-- NEXUS Private MLS V1
-- RFC 9420 relay/storage schema. Server stores MLS ciphertext/public bootstrap material only.
-- Plaintext and MLS private state MUST remain client-side.

CREATE TABLE IF NOT EXISTS public.nexus_secure_devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES neon_auth."user"(id) ON DELETE CASCADE,
  device_label text NOT NULL,
  identity_public_key text NOT NULL,
  identity_fingerprint text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz NULL,
  UNIQUE(user_id,identity_fingerprint)
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
  room_type text NOT NULL CHECK(room_type IN ('beta_group','owner_beta_dm')),
  display_name text NOT NULL,
  created_by uuid NOT NULL REFERENCES neon_auth."user"(id) ON DELETE RESTRICT,
  dm_owner_user_id uuid NULL REFERENCES neon_auth."user"(id) ON DELETE CASCADE,
  dm_beta_user_id uuid NULL REFERENCES neon_auth."user"(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  archived_at timestamptz NULL,
  CHECK(
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
  member_role text NOT NULL DEFAULT 'member' CHECK(member_role IN ('owner','member')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  left_at timestamptz NULL,
  PRIMARY KEY(room_id,user_id)
);

CREATE TABLE IF NOT EXISTS public.nexus_secure_room_devices (
  room_id uuid NOT NULL REFERENCES public.nexus_secure_rooms(id) ON DELETE CASCADE,
  device_id uuid NOT NULL REFERENCES public.nexus_secure_devices(id) ON DELETE CASCADE,
  joined_epoch bigint NOT NULL CHECK(joined_epoch>=0),
  joined_at timestamptz NOT NULL DEFAULT now(),
  left_at timestamptz NULL,
  PRIMARY KEY(room_id,device_id)
);

CREATE TABLE IF NOT EXISTS public.nexus_secure_welcomes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id uuid NOT NULL REFERENCES public.nexus_secure_rooms(id) ON DELETE CASCADE,
  recipient_device_id uuid NOT NULL REFERENCES public.nexus_secure_devices(id) ON DELETE CASCADE,
  sender_device_id uuid NOT NULL REFERENCES public.nexus_secure_devices(id) ON DELETE RESTRICT,
  key_package_ref text NOT NULL,
  epoch bigint NOT NULL CHECK(epoch>=0),
  welcome_ciphertext text NOT NULL CHECK(length(welcome_ciphertext) BETWEEN 1 AND 1400000),
  created_at timestamptz NOT NULL DEFAULT now(),
  consumed_at timestamptz NULL
);

CREATE TABLE IF NOT EXISTS public.nexus_secure_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id uuid NOT NULL REFERENCES public.nexus_secure_rooms(id) ON DELETE CASCADE,
  sender_user_id uuid NOT NULL REFERENCES neon_auth."user"(id) ON DELETE RESTRICT,
  sender_device_id uuid NOT NULL REFERENCES public.nexus_secure_devices(id) ON DELETE RESTRICT,
  client_message_id uuid NOT NULL,
  epoch bigint NOT NULL CHECK(epoch>=0),
  content_type text NOT NULL DEFAULT 'application/vnd.nexus.mls' CHECK(length(content_type)<=120),
  ciphertext text NOT NULL CHECK(length(ciphertext) BETWEEN 1 AND 1400000),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(sender_device_id,client_message_id)
);

CREATE INDEX IF NOT EXISTS nexus_secure_members_user_idx ON public.nexus_secure_room_members(user_id,room_id) WHERE left_at IS NULL;
CREATE INDEX IF NOT EXISTS nexus_secure_room_devices_device_idx ON public.nexus_secure_room_devices(device_id,room_id) WHERE left_at IS NULL;
CREATE INDEX IF NOT EXISTS nexus_secure_messages_room_created_idx ON public.nexus_secure_messages(room_id,created_at,id);
CREATE INDEX IF NOT EXISTS nexus_secure_welcomes_device_created_idx ON public.nexus_secure_welcomes(recipient_device_id,created_at) WHERE consumed_at IS NULL;
CREATE INDEX IF NOT EXISTS nexus_secure_key_packages_available_idx ON public.nexus_secure_key_packages(device_id,created_at) WHERE consumed_at IS NULL;

ALTER TABLE public.nexus_secure_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_secure_key_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_secure_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_secure_room_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_secure_room_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_secure_welcomes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_secure_messages ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.nexus_secure_has_room_access(p_room uuid,p_user uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $f$
  SELECT EXISTS(
    SELECT 1 FROM public.nexus_secure_room_members m
    JOIN public.nexus_secure_rooms r ON r.id=m.room_id
    WHERE m.room_id=p_room AND m.user_id=p_user AND m.left_at IS NULL AND r.archived_at IS NULL
  )
$f$;

CREATE OR REPLACE FUNCTION public.nexus_secure_register_device(
  p_device_label text,p_identity_public_key text,p_identity_fingerprint text
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $f$
DECLARE v_user uuid;v_id uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT public.nexus_beta_has_access(v_user) THEN RAISE EXCEPTION 'secure_messaging_access_required'; END IF;
  IF length(trim(coalesce(p_device_label,'')))<1 THEN RAISE EXCEPTION 'device_label_required'; END IF;
  IF length(trim(coalesce(p_identity_public_key,'')))<32 THEN RAISE EXCEPTION 'identity_public_key_invalid'; END IF;
  IF length(trim(coalesce(p_identity_fingerprint,'')))<16 THEN RAISE EXCEPTION 'identity_fingerprint_invalid'; END IF;

  INSERT INTO public.nexus_secure_devices(user_id,device_label,identity_public_key,identity_fingerprint,last_seen_at)
  VALUES(v_user,left(trim(p_device_label),160),p_identity_public_key,left(trim(p_identity_fingerprint),256),now())
  ON CONFLICT(user_id,identity_fingerprint) DO UPDATE
    SET device_label=excluded.device_label,last_seen_at=now()
  RETURNING id INTO v_id;

  IF EXISTS(SELECT 1 FROM public.nexus_secure_devices WHERE id=v_id AND revoked_at IS NOT NULL)
    THEN RAISE EXCEPTION 'device_revoked'; END IF;
  RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.nexus_secure_publish_key_package(
  p_device_id uuid,p_key_package_ref text,p_key_package text
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $f$
DECLARE v_user uuid;v_id uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.nexus_secure_devices d WHERE d.id=p_device_id AND d.user_id=v_user AND d.revoked_at IS NULL)
    THEN RAISE EXCEPTION 'device_not_owned_or_revoked'; END IF;
  IF length(trim(coalesce(p_key_package_ref,'')))<8 OR length(coalesce(p_key_package,''))<32
    THEN RAISE EXCEPTION 'key_package_invalid'; END IF;

  INSERT INTO public.nexus_secure_key_packages(device_id,key_package_ref,key_package)
  VALUES(p_device_id,left(trim(p_key_package_ref),256),p_key_package)
  ON CONFLICT(device_id,key_package_ref) DO UPDATE SET key_package=excluded.key_package
  RETURNING id INTO v_id;
  RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.nexus_secure_key_package_available(p_device_id uuid,p_key_package_ref text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $f$
DECLARE v_user uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RETURN false; END IF;
  RETURN EXISTS(
    SELECT 1 FROM public.nexus_secure_key_packages k
    JOIN public.nexus_secure_devices d ON d.id=k.device_id
    WHERE k.device_id=p_device_id AND k.key_package_ref=p_key_package_ref
      AND k.consumed_at IS NULL AND d.user_id=v_user AND d.revoked_at IS NULL
  );
END
$f$;

CREATE OR REPLACE FUNCTION public.nexus_secure_create_beta_group(p_display_name text DEFAULT 'Comitiva Beta')
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $f$
DECLARE v_owner uuid;v_id uuid;
BEGIN
  v_owner:=(auth.user_id())::uuid;
  IF v_owner IS NULL OR NOT public.nexus_is_owner(v_owner) THEN RAISE EXCEPTION 'owner_required'; END IF;
  SELECT id INTO v_id FROM public.nexus_secure_rooms WHERE room_type='beta_group' AND archived_at IS NULL LIMIT 1;
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
$f$;

CREATE OR REPLACE FUNCTION public.nexus_secure_create_owner_beta_dm(p_beta_user_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $f$
DECLARE v_owner uuid;v_id uuid;v_name text;
BEGIN
  v_owner:=(auth.user_id())::uuid;
  IF v_owner IS NULL OR NOT public.nexus_is_owner(v_owner) THEN RAISE EXCEPTION 'owner_required'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.nexus_staff_accounts s WHERE s.user_id=p_beta_user_id AND s.role='beta_tester')
    THEN RAISE EXCEPTION 'target_not_beta_tester'; END IF;

  SELECT id INTO v_id FROM public.nexus_secure_rooms
  WHERE room_type='owner_beta_dm' AND dm_owner_user_id=v_owner AND dm_beta_user_id=p_beta_user_id AND archived_at IS NULL LIMIT 1;

  IF v_id IS NULL THEN
    SELECT coalesce(p.display_name,u.name,u.email,'Beta tester') INTO v_name
    FROM neon_auth."user" u LEFT JOIN public.nexus_profiles p ON p.user_id=u.id WHERE u.id=p_beta_user_id;
    INSERT INTO public.nexus_secure_rooms(room_type,display_name,created_by,dm_owner_user_id,dm_beta_user_id)
    VALUES('owner_beta_dm','Privato · '||left(coalesce(v_name,'Beta tester'),120),v_owner,v_owner,p_beta_user_id)
    RETURNING id INTO v_id;
  END IF;

  INSERT INTO public.nexus_secure_room_members(room_id,user_id,member_role,left_at)
  VALUES(v_id,v_owner,'owner',NULL)
  ON CONFLICT(room_id,user_id) DO UPDATE SET member_role='owner',left_at=NULL;
  RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.nexus_secure_bind_owner_device(p_room_id uuid,p_device_id uuid,p_epoch bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $f$
DECLARE v_owner uuid;
BEGIN
  v_owner:=(auth.user_id())::uuid;
  IF v_owner IS NULL OR NOT public.nexus_is_owner(v_owner) THEN RAISE EXCEPTION 'owner_required'; END IF;
  IF NOT public.nexus_secure_has_room_access(p_room_id,v_owner) THEN RAISE EXCEPTION 'room_access_denied'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.nexus_secure_devices d WHERE d.id=p_device_id AND d.user_id=v_owner AND d.revoked_at IS NULL)
    THEN RAISE EXCEPTION 'device_not_owned_or_revoked'; END IF;
  IF EXISTS(
    SELECT 1 FROM public.nexus_secure_room_devices rd
    JOIN public.nexus_secure_devices d ON d.id=rd.device_id
    WHERE rd.room_id=p_room_id AND rd.left_at IS NULL AND d.user_id=v_owner AND rd.device_id<>p_device_id
  ) THEN RAISE EXCEPTION 'owner_device_already_bound'; END IF;

  INSERT INTO public.nexus_secure_room_devices(room_id,device_id,joined_epoch,left_at)
  VALUES(p_room_id,p_device_id,greatest(0,p_epoch),NULL)
  ON CONFLICT(room_id,device_id) DO UPDATE SET left_at=NULL;
  RETURN true;
END
$f$;

CREATE OR REPLACE FUNCTION public.nexus_secure_list_rooms()
RETURNS TABLE(id uuid,room_type text,display_name text,created_at timestamptz,member_count bigint,enrolled_device_count bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $f$
DECLARE v_user uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  RETURN QUERY
  SELECT r.id,r.room_type,r.display_name,r.created_at,
    (SELECT count(*) FROM public.nexus_secure_room_members x WHERE x.room_id=r.id AND x.left_at IS NULL),
    (SELECT count(*) FROM public.nexus_secure_room_devices d WHERE d.room_id=r.id AND d.left_at IS NULL)
  FROM public.nexus_secure_rooms r
  JOIN public.nexus_secure_room_members m ON m.room_id=r.id
  WHERE m.user_id=v_user AND m.left_at IS NULL AND r.archived_at IS NULL
  ORDER BY CASE r.room_type WHEN 'beta_group' THEN 0 ELSE 1 END,r.created_at;
END
$f$;

CREATE OR REPLACE FUNCTION public.nexus_secure_list_beta_candidates()
RETURNS TABLE(user_id uuid,display_name text,active_device_count bigint,available_key_package_count bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $f$
DECLARE v_owner uuid;
BEGIN
  v_owner:=(auth.user_id())::uuid;
  IF v_owner IS NULL OR NOT public.nexus_is_owner(v_owner) THEN RAISE EXCEPTION 'owner_required'; END IF;
  RETURN QUERY
  SELECT s.user_id,coalesce(p.display_name,u.name,u.email,'Beta tester')::text,
    (SELECT count(*) FROM public.nexus_secure_devices d WHERE d.user_id=s.user_id AND d.revoked_at IS NULL),
    (SELECT count(*) FROM public.nexus_secure_key_packages k JOIN public.nexus_secure_devices d ON d.id=k.device_id
      WHERE d.user_id=s.user_id AND d.revoked_at IS NULL AND k.consumed_at IS NULL)
  FROM public.nexus_staff_accounts s
  JOIN neon_auth."user" u ON u.id=s.user_id
  LEFT JOIN public.nexus_profiles p ON p.user_id=s.user_id
  WHERE s.role='beta_tester'
  ORDER BY coalesce(p.display_name,u.name,u.email,'Beta tester'),s.user_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.nexus_secure_list_room_members(p_room_id uuid)
RETURNS TABLE(user_id uuid,display_name text,member_role text,joined_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $f$
DECLARE v_user uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL OR NOT public.nexus_secure_has_room_access(p_room_id,v_user) THEN RAISE EXCEPTION 'room_access_denied'; END IF;
  RETURN QUERY
  SELECT m.user_id,coalesce(p.display_name,u.name,u.email,'NEXUS user')::text,m.member_role,m.joined_at
  FROM public.nexus_secure_room_members m
  JOIN neon_auth."user" u ON u.id=m.user_id
  LEFT JOIN public.nexus_profiles p ON p.user_id=m.user_id
  WHERE m.room_id=p_room_id AND m.left_at IS NULL
  ORDER BY CASE m.member_role WHEN 'owner' THEN 0 ELSE 1 END,m.joined_at,m.user_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.nexus_secure_list_member_devices(p_room_id uuid)
RETURNS TABLE(device_id uuid,user_id uuid,display_name text,device_label text,identity_public_key text,identity_fingerprint text,joined_epoch bigint,created_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $f$
DECLARE v_user uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL OR NOT public.nexus_secure_has_room_access(p_room_id,v_user) THEN RAISE EXCEPTION 'room_access_denied'; END IF;
  RETURN QUERY
  SELECT d.id,d.user_id,coalesce(p.display_name,u.name,u.email,'NEXUS user')::text,d.device_label,d.identity_public_key,d.identity_fingerprint,rd.joined_epoch,d.created_at
  FROM public.nexus_secure_room_devices rd
  JOIN public.nexus_secure_devices d ON d.id=rd.device_id
  JOIN neon_auth."user" u ON u.id=d.user_id
  LEFT JOIN public.nexus_profiles p ON p.user_id=d.user_id
  WHERE rd.room_id=p_room_id AND rd.left_at IS NULL AND d.revoked_at IS NULL
  ORDER BY rd.joined_at,d.id;
END
$f$;

CREATE OR REPLACE FUNCTION public.nexus_secure_validate_credential(p_identity text,p_signature_public_key text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $f$
DECLARE v_caller uuid;v_identity uuid;
BEGIN
  v_caller:=(auth.user_id())::uuid;
  IF v_caller IS NULL OR NOT public.nexus_beta_has_access(v_caller) THEN RETURN false; END IF;
  BEGIN v_identity:=p_identity::uuid; EXCEPTION WHEN OTHERS THEN RETURN false; END;
  IF NOT public.nexus_beta_has_access(v_identity) THEN RETURN false; END IF;
  RETURN EXISTS(
    SELECT 1 FROM public.nexus_secure_devices d
    WHERE d.user_id=v_identity AND d.revoked_at IS NULL AND d.identity_public_key=p_signature_public_key
  );
END
$f$;

CREATE OR REPLACE FUNCTION public.nexus_secure_owner_take_beta_key_package(p_room_id uuid,p_beta_user_id uuid)
RETURNS TABLE(device_id uuid,key_package_ref text,key_package text,identity_fingerprint text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $f$
DECLARE v_owner uuid;v_id uuid;v_device uuid;v_ref text;v_package text;v_fp text;
BEGIN
  v_owner:=(auth.user_id())::uuid;
  IF v_owner IS NULL OR NOT public.nexus_is_owner(v_owner) THEN RAISE EXCEPTION 'owner_required'; END IF;
  IF NOT public.nexus_secure_has_room_access(p_room_id,v_owner) THEN RAISE EXCEPTION 'room_owner_required'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.nexus_staff_accounts s WHERE s.user_id=p_beta_user_id AND s.role='beta_tester')
    THEN RAISE EXCEPTION 'target_not_beta_tester'; END IF;

  SELECT k.id,k.device_id,k.key_package_ref,k.key_package,d.identity_fingerprint
    INTO v_id,v_device,v_ref,v_package,v_fp
  FROM public.nexus_secure_key_packages k
  JOIN public.nexus_secure_devices d ON d.id=k.device_id
  WHERE d.user_id=p_beta_user_id AND d.revoked_at IS NULL AND k.consumed_at IS NULL
    AND NOT EXISTS(
      SELECT 1 FROM public.nexus_secure_room_devices rd
      WHERE rd.room_id=p_room_id AND rd.device_id=d.id AND rd.left_at IS NULL
    )
  ORDER BY k.created_at,k.id
  FOR UPDATE OF k SKIP LOCKED
  LIMIT 1;

  IF v_id IS NULL THEN RAISE EXCEPTION 'no_beta_key_package_available'; END IF;
  UPDATE public.nexus_secure_key_packages SET consumed_at=now() WHERE id=v_id;
  RETURN QUERY SELECT v_device,v_ref,v_package,v_fp;
END
$f$;

CREATE OR REPLACE FUNCTION public.nexus_secure_owner_finalize_add(
  p_room_id uuid,p_beta_user_id uuid,p_recipient_device_id uuid,p_sender_device_id uuid,
  p_key_package_ref text,p_epoch bigint,p_commit_ciphertext text,p_welcome_ciphertext text
)
RETURNS TABLE(commit_message_id uuid,welcome_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $f$
DECLARE v_owner uuid;v_commit uuid;v_welcome uuid;
BEGIN
  v_owner:=(auth.user_id())::uuid;
  IF v_owner IS NULL OR NOT public.nexus_is_owner(v_owner) THEN RAISE EXCEPTION 'owner_required'; END IF;
  IF NOT public.nexus_secure_has_room_access(p_room_id,v_owner) THEN RAISE EXCEPTION 'room_owner_required'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.nexus_secure_room_devices rd JOIN public.nexus_secure_devices d ON d.id=rd.device_id
    WHERE rd.room_id=p_room_id AND rd.device_id=p_sender_device_id AND rd.left_at IS NULL
      AND d.user_id=v_owner AND d.revoked_at IS NULL
  ) THEN RAISE EXCEPTION 'sender_device_not_enrolled'; END IF;
  IF EXISTS(SELECT 1 FROM public.nexus_secure_room_devices rd WHERE rd.room_id=p_room_id AND rd.device_id=p_recipient_device_id AND rd.left_at IS NULL)
    THEN RAISE EXCEPTION 'recipient_device_already_enrolled'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.nexus_secure_key_packages k JOIN public.nexus_secure_devices d ON d.id=k.device_id
    WHERE k.device_id=p_recipient_device_id AND d.user_id=p_beta_user_id AND d.revoked_at IS NULL
      AND k.key_package_ref=p_key_package_ref AND k.consumed_at IS NOT NULL
  ) THEN RAISE EXCEPTION 'recipient_key_package_not_taken'; END IF;

  INSERT INTO public.nexus_secure_room_members(room_id,user_id,member_role,left_at)
  VALUES(p_room_id,p_beta_user_id,'member',NULL)
  ON CONFLICT(room_id,user_id) DO UPDATE SET member_role='member',left_at=NULL;

  INSERT INTO public.nexus_secure_room_devices(room_id,device_id,joined_epoch,left_at)
  VALUES(p_room_id,p_recipient_device_id,p_epoch,NULL)
  ON CONFLICT(room_id,device_id) DO UPDATE SET joined_epoch=excluded.joined_epoch,left_at=NULL;

  INSERT INTO public.nexus_secure_messages(room_id,sender_user_id,sender_device_id,client_message_id,epoch,content_type,ciphertext)
  VALUES(p_room_id,v_owner,p_sender_device_id,gen_random_uuid(),p_epoch,'application/vnd.nexus.mls-commit',p_commit_ciphertext)
  RETURNING id INTO v_commit;

  INSERT INTO public.nexus_secure_welcomes(room_id,recipient_device_id,sender_device_id,key_package_ref,epoch,welcome_ciphertext)
  VALUES(p_room_id,p_recipient_device_id,p_sender_device_id,left(p_key_package_ref,256),p_epoch,p_welcome_ciphertext)
  RETURNING id INTO v_welcome;

  RETURN QUERY SELECT v_commit,v_welcome;
END
$f$;

CREATE OR REPLACE FUNCTION public.nexus_secure_fetch_welcomes(p_device_id uuid)
RETURNS TABLE(id uuid,room_id uuid,sender_device_id uuid,key_package_ref text,epoch bigint,welcome_ciphertext text,created_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $f$
DECLARE v_user uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.nexus_secure_devices d WHERE d.id=p_device_id AND d.user_id=v_user AND d.revoked_at IS NULL)
    THEN RAISE EXCEPTION 'device_not_owned_or_revoked'; END IF;
  RETURN QUERY
  SELECT w.id,w.room_id,w.sender_device_id,w.key_package_ref,w.epoch,w.welcome_ciphertext,w.created_at
  FROM public.nexus_secure_welcomes w
  WHERE w.recipient_device_id=p_device_id AND w.consumed_at IS NULL
  ORDER BY w.created_at,w.id;
END
$f$;

CREATE OR REPLACE FUNCTION public.nexus_secure_mark_welcome_consumed(p_welcome_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $f$
DECLARE v_user uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  UPDATE public.nexus_secure_welcomes w SET consumed_at=coalesce(w.consumed_at,now())
  WHERE w.id=p_welcome_id AND EXISTS(
    SELECT 1 FROM public.nexus_secure_devices d
    WHERE d.id=w.recipient_device_id AND d.user_id=v_user AND d.revoked_at IS NULL
  );
  RETURN FOUND;
END
$f$;

CREATE OR REPLACE FUNCTION public.nexus_secure_send_ciphertext(
  p_room_id uuid,p_sender_device_id uuid,p_client_message_id uuid,p_epoch bigint,
  p_ciphertext text,p_content_type text DEFAULT 'application/vnd.nexus.mls'
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $f$
DECLARE v_user uuid;v_id uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.nexus_secure_room_devices rd
    JOIN public.nexus_secure_devices d ON d.id=rd.device_id
    WHERE rd.room_id=p_room_id AND rd.device_id=p_sender_device_id AND rd.left_at IS NULL
      AND d.user_id=v_user AND d.revoked_at IS NULL
  ) THEN RAISE EXCEPTION 'sender_device_not_enrolled'; END IF;
  IF p_epoch<0 THEN RAISE EXCEPTION 'invalid_epoch'; END IF;
  IF length(coalesce(p_ciphertext,''))<1 OR length(p_ciphertext)>1400000 THEN RAISE EXCEPTION 'ciphertext_size_invalid'; END IF;

  INSERT INTO public.nexus_secure_messages(room_id,sender_user_id,sender_device_id,client_message_id,epoch,content_type,ciphertext)
  VALUES(p_room_id,v_user,p_sender_device_id,p_client_message_id,p_epoch,left(coalesce(nullif(trim(p_content_type),''),'application/vnd.nexus.mls'),120),p_ciphertext)
  ON CONFLICT(sender_device_id,client_message_id) DO UPDATE SET client_message_id=excluded.client_message_id
  RETURNING id INTO v_id;
  RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.nexus_secure_fetch_messages(
  p_room_id uuid,p_device_id uuid,p_after timestamptz DEFAULT NULL,p_limit integer DEFAULT 200
)
RETURNS TABLE(id uuid,sender_user_id uuid,sender_device_id uuid,client_message_id uuid,epoch bigint,content_type text,ciphertext text,created_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $f$
DECLARE v_user uuid;v_limit integer;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.nexus_secure_room_devices rd JOIN public.nexus_secure_devices d ON d.id=rd.device_id
    WHERE rd.room_id=p_room_id AND rd.device_id=p_device_id AND rd.left_at IS NULL
      AND d.user_id=v_user AND d.revoked_at IS NULL
  ) THEN RAISE EXCEPTION 'device_not_enrolled'; END IF;
  v_limit:=greatest(1,least(coalesce(p_limit,200),500));
  RETURN QUERY
  SELECT m.id,m.sender_user_id,m.sender_device_id,m.client_message_id,m.epoch,m.content_type,m.ciphertext,m.created_at
  FROM public.nexus_secure_messages m
  WHERE m.room_id=p_room_id AND (p_after IS NULL OR m.created_at>p_after)
  ORDER BY m.created_at,m.id
  LIMIT v_limit;
END
$f$;

CREATE OR REPLACE FUNCTION public.nexus_secure_revoke_device(p_device_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $f$
DECLARE v_user uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  UPDATE public.nexus_secure_devices SET revoked_at=coalesce(revoked_at,now()),last_seen_at=now()
  WHERE id=p_device_id AND user_id=v_user;
  IF FOUND THEN
    UPDATE public.nexus_secure_room_devices SET left_at=coalesce(left_at,now()) WHERE device_id=p_device_id AND left_at IS NULL;
    RETURN true;
  END IF;
  RETURN false;
END
$f$;