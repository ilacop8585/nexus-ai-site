-- NEXUS Private / Secure Beta Messaging V1
-- SCHEMA CANDIDATE ONLY. Do not call the product E2EE until client MLS is verified.
-- Server stores public cryptographic material, ciphertext and delivery metadata only.
-- No message plaintext column exists by design.

CREATE TABLE IF NOT EXISTS public.nexus_secure_devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES neon_auth."user"(id) ON DELETE CASCADE,
  device_label text NOT NULL,
  identity_public_key text NOT NULL,
  identity_fingerprint text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz NULL,
  UNIQUE(user_id, identity_fingerprint)
);

CREATE TABLE IF NOT EXISTS public.nexus_secure_key_packages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id uuid NOT NULL REFERENCES public.nexus_secure_devices(id) ON DELETE CASCADE,
  key_package_ref text NOT NULL,
  key_package text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  consumed_at timestamptz NULL,
  UNIQUE(device_id,key_package_ref)
);

CREATE TABLE IF NOT EXISTS public.nexus_secure_rooms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_type text NOT NULL CHECK (room_type IN ('beta_group','owner_beta_dm')),
  display_name text NOT NULL,
  created_by uuid NOT NULL REFERENCES neon_auth."user"(id) ON DELETE RESTRICT,
  dm_owner_user_id uuid NULL REFERENCES neon_auth."user"(id) ON DELETE CASCADE,
  dm_beta_user_id uuid NULL REFERENCES neon_auth."user"(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  archived_at timestamptz NULL,
  CHECK (
    (room_type='beta_group' AND dm_owner_user_id IS NULL AND dm_beta_user_id IS NULL)
    OR
    (room_type='owner_beta_dm' AND dm_owner_user_id IS NOT NULL AND dm_beta_user_id IS NOT NULL AND dm_owner_user_id<>dm_beta_user_id)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS nexus_secure_single_beta_group_idx
  ON public.nexus_secure_rooms(room_type)
  WHERE room_type='beta_group' AND archived_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS nexus_secure_owner_beta_dm_idx
  ON public.nexus_secure_rooms(dm_owner_user_id,dm_beta_user_id)
  WHERE room_type='owner_beta_dm' AND archived_at IS NULL;

CREATE TABLE IF NOT EXISTS public.nexus_secure_room_members (
  room_id uuid NOT NULL REFERENCES public.nexus_secure_rooms(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES neon_auth."user"(id) ON DELETE CASCADE,
  member_role text NOT NULL DEFAULT 'member' CHECK (member_role IN ('owner','member')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  left_at timestamptz NULL,
  PRIMARY KEY(room_id,user_id)
);

CREATE TABLE IF NOT EXISTS public.nexus_secure_welcomes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id uuid NOT NULL REFERENCES public.nexus_secure_rooms(id) ON DELETE CASCADE,
  recipient_device_id uuid NOT NULL REFERENCES public.nexus_secure_devices(id) ON DELETE CASCADE,
  sender_device_id uuid NOT NULL REFERENCES public.nexus_secure_devices(id) ON DELETE RESTRICT,
  epoch bigint NOT NULL CHECK (epoch>=0),
  welcome_ciphertext text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  consumed_at timestamptz NULL
);

CREATE TABLE IF NOT EXISTS public.nexus_secure_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id uuid NOT NULL REFERENCES public.nexus_secure_rooms(id) ON DELETE CASCADE,
  sender_user_id uuid NOT NULL REFERENCES neon_auth."user"(id) ON DELETE RESTRICT,
  sender_device_id uuid NOT NULL REFERENCES public.nexus_secure_devices(id) ON DELETE RESTRICT,
  client_message_id uuid NOT NULL,
  epoch bigint NOT NULL CHECK (epoch>=0),
  content_type text NOT NULL DEFAULT 'application/vnd.nexus.mls' CHECK (length(content_type)<=120),
  ciphertext text NOT NULL CHECK (length(ciphertext) BETWEEN 1 AND 1400000),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(sender_device_id,client_message_id)
);

CREATE INDEX IF NOT EXISTS nexus_secure_members_user_idx
  ON public.nexus_secure_room_members(user_id,room_id)
  WHERE left_at IS NULL;
CREATE INDEX IF NOT EXISTS nexus_secure_messages_room_created_idx
  ON public.nexus_secure_messages(room_id,created_at,id);
CREATE INDEX IF NOT EXISTS nexus_secure_welcomes_device_created_idx
  ON public.nexus_secure_welcomes(recipient_device_id,created_at)
  WHERE consumed_at IS NULL;
CREATE INDEX IF NOT EXISTS nexus_secure_key_packages_available_idx
  ON public.nexus_secure_key_packages(device_id,created_at)
  WHERE consumed_at IS NULL;

ALTER TABLE public.nexus_secure_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_secure_key_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_secure_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_secure_room_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_secure_welcomes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_secure_messages ENABLE ROW LEVEL SECURITY;

-- No direct RLS policies are intentionally created in V1.
-- Browser access is through the SECURITY DEFINER RPCs below.
-- Private key material must never be passed to any RPC.

CREATE OR REPLACE FUNCTION public.nexus_secure_has_room_access(p_room uuid,p_user uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
  SELECT EXISTS(
    SELECT 1
    FROM public.nexus_secure_room_members m
    WHERE m.room_id=p_room AND m.user_id=p_user AND m.left_at IS NULL
  )
$function$;

CREATE OR REPLACE FUNCTION public.nexus_secure_register_device(
  p_device_label text,
  p_identity_public_key text,
  p_identity_fingerprint text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid; v_id uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT public.nexus_beta_has_access(v_user) THEN RAISE EXCEPTION 'secure_messaging_access_required'; END IF;
  IF length(trim(coalesce(p_device_label,'')))<1 THEN RAISE EXCEPTION 'device_label_required'; END IF;
  IF length(trim(coalesce(p_identity_public_key,'')))<32 THEN RAISE EXCEPTION 'identity_public_key_invalid'; END IF;
  IF length(trim(coalesce(p_identity_fingerprint,'')))<16 THEN RAISE EXCEPTION 'identity_fingerprint_invalid'; END IF;

  INSERT INTO public.nexus_secure_devices(user_id,device_label,identity_public_key,identity_fingerprint,last_seen_at)
  VALUES(v_user,left(trim(p_device_label),160),p_identity_public_key,left(trim(p_identity_fingerprint),256),now())
  ON CONFLICT(user_id,identity_fingerprint)
  DO UPDATE SET device_label=excluded.device_label,last_seen_at=now()
  RETURNING id INTO v_id;
  RETURN v_id;
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_secure_publish_key_package(
  p_device_id uuid,
  p_key_package_ref text,
  p_key_package text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid; v_id uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.nexus_secure_devices d
    WHERE d.id=p_device_id AND d.user_id=v_user AND d.revoked_at IS NULL
  ) THEN RAISE EXCEPTION 'device_not_owned_or_revoked'; END IF;
  IF length(trim(coalesce(p_key_package_ref,'')))<8 OR length(coalesce(p_key_package,''))<32
    THEN RAISE EXCEPTION 'key_package_invalid'; END IF;

  INSERT INTO public.nexus_secure_key_packages(device_id,key_package_ref,key_package)
  VALUES(p_device_id,left(trim(p_key_package_ref),256),p_key_package)
  RETURNING id INTO v_id;
  RETURN v_id;
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_secure_create_beta_group(p_display_name text DEFAULT 'Comitiva Beta')
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_owner uuid; v_id uuid;
BEGIN
  v_owner:=(auth.user_id())::uuid;
  IF v_owner IS NULL OR NOT public.nexus_is_owner(v_owner) THEN RAISE EXCEPTION 'owner_required'; END IF;

  SELECT id INTO v_id FROM public.nexus_secure_rooms
   WHERE room_type='beta_group' AND archived_at IS NULL LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO public.nexus_secure_rooms(room_type,display_name,created_by)
    VALUES('beta_group',left(coalesce(nullif(trim(p_display_name),''),'Comitiva Beta'),160),v_owner)
    RETURNING id INTO v_id;
  END IF;

  INSERT INTO public.nexus_secure_room_members(room_id,user_id,member_role,left_at)
  VALUES(v_id,v_owner,'owner',NULL)
  ON CONFLICT(room_id,user_id) DO UPDATE SET member_role='owner',left_at=NULL;
  RETURN v_id;
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_secure_add_beta_member(p_room_id uuid,p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_owner uuid;
BEGIN
  v_owner:=(auth.user_id())::uuid;
  IF v_owner IS NULL OR NOT public.nexus_is_owner(v_owner) THEN RAISE EXCEPTION 'owner_required'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.nexus_secure_rooms r WHERE r.id=p_room_id AND r.archived_at IS NULL)
    THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF NOT public.nexus_beta_has_access(p_user_id) THEN RAISE EXCEPTION 'target_not_beta_authorized'; END IF;

  INSERT INTO public.nexus_secure_room_members(room_id,user_id,member_role,left_at)
  VALUES(p_room_id,p_user_id,CASE WHEN public.nexus_is_owner(p_user_id) THEN 'owner' ELSE 'member' END,NULL)
  ON CONFLICT(room_id,user_id) DO UPDATE SET left_at=NULL;
  RETURN true;
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_secure_remove_member(p_room_id uuid,p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_owner uuid;
BEGIN
  v_owner:=(auth.user_id())::uuid;
  IF v_owner IS NULL OR NOT public.nexus_is_owner(v_owner) THEN RAISE EXCEPTION 'owner_required'; END IF;
  IF public.nexus_is_owner(p_user_id) THEN RAISE EXCEPTION 'cannot_remove_owner'; END IF;
  UPDATE public.nexus_secure_room_members
     SET left_at=now()
   WHERE room_id=p_room_id AND user_id=p_user_id AND left_at IS NULL;
  RETURN FOUND;
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_secure_create_owner_beta_dm(p_beta_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_owner uuid; v_role text; v_id uuid; v_name text;
BEGIN
  v_owner:=(auth.user_id())::uuid;
  IF v_owner IS NULL OR NOT public.nexus_is_owner(v_owner) THEN RAISE EXCEPTION 'owner_required'; END IF;
  SELECT role INTO v_role FROM public.nexus_staff_accounts WHERE user_id=p_beta_user_id;
  IF v_role IS DISTINCT FROM 'beta_tester' THEN RAISE EXCEPTION 'target_not_beta_tester'; END IF;

  SELECT id INTO v_id FROM public.nexus_secure_rooms
   WHERE room_type='owner_beta_dm' AND dm_owner_user_id=v_owner AND dm_beta_user_id=p_beta_user_id AND archived_at IS NULL
   LIMIT 1;

  IF v_id IS NULL THEN
    SELECT coalesce(p.display_name,u.name,u.email,'Beta tester')
      INTO v_name
      FROM neon_auth."user" u
      LEFT JOIN public.nexus_profiles p ON p.user_id=u.id
     WHERE u.id=p_beta_user_id;
    INSERT INTO public.nexus_secure_rooms(room_type,display_name,created_by,dm_owner_user_id,dm_beta_user_id)
    VALUES('owner_beta_dm','Privato · '||left(coalesce(v_name,'Beta tester'),120),v_owner,v_owner,p_beta_user_id)
    RETURNING id INTO v_id;
  END IF;

  INSERT INTO public.nexus_secure_room_members(room_id,user_id,member_role,left_at)
  VALUES(v_id,v_owner,'owner',NULL)
  ON CONFLICT(room_id,user_id) DO UPDATE SET member_role='owner',left_at=NULL;
  INSERT INTO public.nexus_secure_room_members(room_id,user_id,member_role,left_at)
  VALUES(v_id,p_beta_user_id,'member',NULL)
  ON CONFLICT(room_id,user_id) DO UPDATE SET member_role='member',left_at=NULL;

  RETURN v_id;
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_secure_list_rooms()
RETURNS TABLE(
  id uuid,
  room_type text,
  display_name text,
  created_at timestamptz,
  member_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  RETURN QUERY
  SELECT r.id,r.room_type,r.display_name,r.created_at,
         (SELECT count(*) FROM public.nexus_secure_room_members mm WHERE mm.room_id=r.id AND mm.left_at IS NULL)
  FROM public.nexus_secure_rooms r
  JOIN public.nexus_secure_room_members m ON m.room_id=r.id
  WHERE m.user_id=v_user AND m.left_at IS NULL AND r.archived_at IS NULL
  ORDER BY CASE r.room_type WHEN 'beta_group' THEN 0 ELSE 1 END,r.created_at;
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_secure_send_ciphertext(
  p_room_id uuid,
  p_sender_device_id uuid,
  p_client_message_id uuid,
  p_epoch bigint,
  p_ciphertext text,
  p_content_type text DEFAULT 'application/vnd.nexus.mls'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid; v_id uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT public.nexus_secure_has_room_access(p_room_id,v_user) THEN RAISE EXCEPTION 'room_access_denied'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.nexus_secure_devices d
    WHERE d.id=p_sender_device_id AND d.user_id=v_user AND d.revoked_at IS NULL
  ) THEN RAISE EXCEPTION 'device_not_owned_or_revoked'; END IF;
  IF p_epoch<0 THEN RAISE EXCEPTION 'invalid_epoch'; END IF;
  IF length(coalesce(p_ciphertext,''))<1 OR length(p_ciphertext)>1400000 THEN RAISE EXCEPTION 'ciphertext_size_invalid'; END IF;

  INSERT INTO public.nexus_secure_messages(
    room_id,sender_user_id,sender_device_id,client_message_id,epoch,content_type,ciphertext
  ) VALUES(
    p_room_id,v_user,p_sender_device_id,p_client_message_id,p_epoch,
    left(coalesce(nullif(trim(p_content_type),''),'application/vnd.nexus.mls'),120),p_ciphertext
  )
  ON CONFLICT(sender_device_id,client_message_id)
  DO UPDATE SET client_message_id=excluded.client_message_id
  RETURNING id INTO v_id;
  RETURN v_id;
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_secure_fetch_messages(
  p_room_id uuid,
  p_after timestamptz DEFAULT NULL,
  p_limit integer DEFAULT 200
)
RETURNS TABLE(
  id uuid,
  sender_user_id uuid,
  sender_device_id uuid,
  client_message_id uuid,
  epoch bigint,
  content_type text,
  ciphertext text,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid; v_limit integer;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT public.nexus_secure_has_room_access(p_room_id,v_user) THEN RAISE EXCEPTION 'room_access_denied'; END IF;
  v_limit:=greatest(1,least(coalesce(p_limit,200),500));

  RETURN QUERY
  SELECT m.id,m.sender_user_id,m.sender_device_id,m.client_message_id,m.epoch,m.content_type,m.ciphertext,m.created_at
  FROM public.nexus_secure_messages m
  WHERE m.room_id=p_room_id AND (p_after IS NULL OR m.created_at>p_after)
  ORDER BY m.created_at,m.id
  LIMIT v_limit;
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_secure_store_welcome(
  p_room_id uuid,
  p_recipient_device_id uuid,
  p_sender_device_id uuid,
  p_epoch bigint,
  p_welcome_ciphertext text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid; v_recipient_user uuid; v_id uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT public.nexus_secure_has_room_access(p_room_id,v_user) THEN RAISE EXCEPTION 'room_access_denied'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.nexus_secure_devices d
    WHERE d.id=p_sender_device_id AND d.user_id=v_user AND d.revoked_at IS NULL
  ) THEN RAISE EXCEPTION 'sender_device_invalid'; END IF;
  SELECT user_id INTO v_recipient_user FROM public.nexus_secure_devices
   WHERE id=p_recipient_device_id AND revoked_at IS NULL;
  IF v_recipient_user IS NULL OR NOT public.nexus_secure_has_room_access(p_room_id,v_recipient_user)
    THEN RAISE EXCEPTION 'recipient_not_in_room'; END IF;
  IF length(coalesce(p_welcome_ciphertext,''))<1 OR length(p_welcome_ciphertext)>1400000
    THEN RAISE EXCEPTION 'welcome_size_invalid'; END IF;

  INSERT INTO public.nexus_secure_welcomes(room_id,recipient_device_id,sender_device_id,epoch,welcome_ciphertext)
  VALUES(p_room_id,p_recipient_device_id,p_sender_device_id,p_epoch,p_welcome_ciphertext)
  RETURNING id INTO v_id;
  RETURN v_id;
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_secure_fetch_welcomes(p_device_id uuid)
RETURNS TABLE(
  id uuid,
  room_id uuid,
  sender_device_id uuid,
  epoch bigint,
  welcome_ciphertext text,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.nexus_secure_devices d WHERE d.id=p_device_id AND d.user_id=v_user AND d.revoked_at IS NULL)
    THEN RAISE EXCEPTION 'device_not_owned_or_revoked'; END IF;

  RETURN QUERY
  SELECT w.id,w.room_id,w.sender_device_id,w.epoch,w.welcome_ciphertext,w.created_at
  FROM public.nexus_secure_welcomes w
  WHERE w.recipient_device_id=p_device_id AND w.consumed_at IS NULL
  ORDER BY w.created_at,w.id;
END
$function$;
