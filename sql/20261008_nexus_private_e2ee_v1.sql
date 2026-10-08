-- NEXUS Private E2EE V1
-- Browser-native protocol:
-- ECDH P-256 + HKDF-SHA-256 + AES-256-GCM + ECDSA P-256/SHA-256.
-- Neon stores ciphertext, public keys, wrapped per-device content keys and delivery metadata only.

CREATE TABLE IF NOT EXISTS public.nexus_secure_devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES neon_auth."user"(id) ON DELETE CASCADE,
  device_label text NOT NULL,
  ecdh_public_jwk jsonb NOT NULL,
  signing_public_jwk jsonb NOT NULL,
  identity_fingerprint text NOT NULL,
  protocol_version text NOT NULL DEFAULT 'NEXUS-E2EE-v1',
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz NULL,
  UNIQUE(user_id,identity_fingerprint)
);

CREATE TABLE IF NOT EXISTS public.nexus_secure_rooms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_type text NOT NULL CHECK (room_type IN ('beta_group','owner_beta_dm')),
  display_name text NOT NULL,
  created_by uuid NOT NULL REFERENCES neon_auth."user"(id) ON DELETE RESTRICT,
  dm_owner_user_id uuid NULL REFERENCES neon_auth."user"(id) ON DELETE CASCADE,
  dm_beta_user_id uuid NULL REFERENCES neon_auth."user"(id) ON DELETE CASCADE,
  membership_version bigint NOT NULL DEFAULT 1 CHECK (membership_version>0),
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

CREATE TABLE IF NOT EXISTS public.nexus_secure_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id uuid NOT NULL REFERENCES public.nexus_secure_rooms(id) ON DELETE CASCADE,
  sender_user_id uuid NOT NULL REFERENCES neon_auth."user"(id) ON DELETE RESTRICT,
  sender_device_id uuid NOT NULL REFERENCES public.nexus_secure_devices(id) ON DELETE RESTRICT,
  client_message_id uuid NOT NULL,
  membership_version bigint NOT NULL CHECK (membership_version>0),
  protocol_version text NOT NULL DEFAULT 'NEXUS-E2EE-v1',
  payload_iv text NOT NULL CHECK (length(payload_iv) BETWEEN 8 AND 128),
  salt text NOT NULL CHECK (length(salt) BETWEEN 16 AND 256),
  ephemeral_public_jwk jsonb NOT NULL,
  ciphertext text NOT NULL CHECK (length(ciphertext) BETWEEN 1 AND 1400000),
  signature text NOT NULL CHECK (length(signature) BETWEEN 16 AND 4096),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(sender_device_id,client_message_id)
);

CREATE TABLE IF NOT EXISTS public.nexus_secure_message_keys (
  message_id uuid NOT NULL REFERENCES public.nexus_secure_messages(id) ON DELETE CASCADE,
  recipient_device_id uuid NOT NULL REFERENCES public.nexus_secure_devices(id) ON DELETE CASCADE,
  wrap_iv text NOT NULL CHECK (length(wrap_iv) BETWEEN 8 AND 128),
  wrapped_key text NOT NULL CHECK (length(wrapped_key) BETWEEN 16 AND 4096),
  PRIMARY KEY(message_id,recipient_device_id)
);

CREATE INDEX IF NOT EXISTS nexus_secure_members_user_idx
  ON public.nexus_secure_room_members(user_id,room_id)
  WHERE left_at IS NULL;
CREATE INDEX IF NOT EXISTS nexus_secure_messages_room_created_idx
  ON public.nexus_secure_messages(room_id,created_at,id);
CREATE INDEX IF NOT EXISTS nexus_secure_message_keys_device_idx
  ON public.nexus_secure_message_keys(recipient_device_id,message_id);
CREATE INDEX IF NOT EXISTS nexus_secure_devices_user_active_idx
  ON public.nexus_secure_devices(user_id,created_at)
  WHERE revoked_at IS NULL;

ALTER TABLE public.nexus_secure_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_secure_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_secure_room_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_secure_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_secure_message_keys ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.nexus_secure_has_room_access(p_room uuid,p_user uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
  SELECT EXISTS(
    SELECT 1
    FROM public.nexus_secure_room_members m
    JOIN public.nexus_secure_rooms r ON r.id=m.room_id
    WHERE m.room_id=p_room AND m.user_id=p_user AND m.left_at IS NULL AND r.archived_at IS NULL
  )
$function$;

CREATE OR REPLACE FUNCTION public.nexus_secure_register_device(
  p_device_label text,
  p_ecdh_public_jwk jsonb,
  p_signing_public_jwk jsonb,
  p_identity_fingerprint text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid; v_id uuid; v_revoked timestamptz;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT public.nexus_beta_has_access(v_user) THEN RAISE EXCEPTION 'secure_messaging_access_required'; END IF;
  IF length(trim(coalesce(p_device_label,'')))<1 THEN RAISE EXCEPTION 'device_label_required'; END IF;
  IF jsonb_typeof(p_ecdh_public_jwk)<>'object' OR jsonb_typeof(p_signing_public_jwk)<>'object'
    THEN RAISE EXCEPTION 'public_key_invalid'; END IF;
  IF length(trim(coalesce(p_identity_fingerprint,'')))<32 THEN RAISE EXCEPTION 'fingerprint_invalid'; END IF;

  SELECT id,revoked_at INTO v_id,v_revoked
  FROM public.nexus_secure_devices
  WHERE user_id=v_user AND identity_fingerprint=left(trim(p_identity_fingerprint),256);

  IF v_id IS NOT NULL THEN
    IF v_revoked IS NOT NULL THEN RAISE EXCEPTION 'device_revoked'; END IF;
    UPDATE public.nexus_secure_devices
       SET device_label=left(trim(p_device_label),160),
           ecdh_public_jwk=p_ecdh_public_jwk,
           signing_public_jwk=p_signing_public_jwk,
           last_seen_at=now()
     WHERE id=v_id;
    RETURN v_id;
  END IF;

  INSERT INTO public.nexus_secure_devices(
    user_id,device_label,ecdh_public_jwk,signing_public_jwk,identity_fingerprint
  ) VALUES(
    v_user,left(trim(p_device_label),160),p_ecdh_public_jwk,p_signing_public_jwk,left(trim(p_identity_fingerprint),256)
  ) RETURNING id INTO v_id;
  RETURN v_id;
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_secure_revoke_device(p_device_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  UPDATE public.nexus_secure_devices
     SET revoked_at=coalesce(revoked_at,now()),last_seen_at=now()
   WHERE id=p_device_id AND user_id=v_user;
  RETURN FOUND;
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_secure_sync_beta_group(p_display_name text DEFAULT 'Comitiva Beta')
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_owner uuid; v_room uuid;
BEGIN
  v_owner:=(auth.user_id())::uuid;
  IF v_owner IS NULL OR NOT public.nexus_is_owner(v_owner) THEN RAISE EXCEPTION 'owner_required'; END IF;

  SELECT id INTO v_room
  FROM public.nexus_secure_rooms
  WHERE room_type='beta_group' AND archived_at IS NULL
  LIMIT 1;

  IF v_room IS NULL THEN
    INSERT INTO public.nexus_secure_rooms(room_type,display_name,created_by)
    VALUES('beta_group',left(coalesce(nullif(trim(p_display_name),''),'Comitiva Beta'),160),v_owner)
    RETURNING id INTO v_room;
  ELSE
    UPDATE public.nexus_secure_rooms
       SET display_name=left(coalesce(nullif(trim(p_display_name),''),display_name),160),
           membership_version=membership_version+1
     WHERE id=v_room;
  END IF;

  INSERT INTO public.nexus_secure_room_members(room_id,user_id,member_role,left_at)
  VALUES(v_room,v_owner,'owner',NULL)
  ON CONFLICT(room_id,user_id) DO UPDATE SET member_role='owner',left_at=NULL;

  INSERT INTO public.nexus_secure_room_members(room_id,user_id,member_role,left_at)
  SELECT v_room,s.user_id,'member',NULL
  FROM public.nexus_staff_accounts s
  WHERE s.role='beta_tester'
  ON CONFLICT(room_id,user_id) DO UPDATE SET member_role='member',left_at=NULL;

  UPDATE public.nexus_secure_room_members m
     SET left_at=now()
   WHERE m.room_id=v_room
     AND m.user_id<>v_owner
     AND m.left_at IS NULL
     AND NOT EXISTS(
       SELECT 1 FROM public.nexus_staff_accounts s
       WHERE s.user_id=m.user_id AND s.role='beta_tester'
     );

  RETURN v_room;
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_secure_create_owner_beta_dm(p_beta_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_owner uuid; v_room uuid; v_name text;
BEGIN
  v_owner:=(auth.user_id())::uuid;
  IF v_owner IS NULL OR NOT public.nexus_is_owner(v_owner) THEN RAISE EXCEPTION 'owner_required'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.nexus_staff_accounts s WHERE s.user_id=p_beta_user_id AND s.role='beta_tester')
    THEN RAISE EXCEPTION 'target_not_beta_tester'; END IF;

  SELECT id INTO v_room
  FROM public.nexus_secure_rooms
  WHERE room_type='owner_beta_dm' AND dm_owner_user_id=v_owner AND dm_beta_user_id=p_beta_user_id AND archived_at IS NULL
  LIMIT 1;

  IF v_room IS NULL THEN
    SELECT coalesce(p.display_name,u.name,u.email,'Beta tester')
      INTO v_name
      FROM neon_auth."user" u
      LEFT JOIN public.nexus_profiles p ON p.user_id=u.id
     WHERE u.id=p_beta_user_id;

    INSERT INTO public.nexus_secure_rooms(room_type,display_name,created_by,dm_owner_user_id,dm_beta_user_id)
    VALUES('owner_beta_dm','Privato · '||left(coalesce(v_name,'Beta tester'),120),v_owner,v_owner,p_beta_user_id)
    RETURNING id INTO v_room;
  END IF;

  INSERT INTO public.nexus_secure_room_members(room_id,user_id,member_role,left_at)
  VALUES(v_room,v_owner,'owner',NULL)
  ON CONFLICT(room_id,user_id) DO UPDATE SET member_role='owner',left_at=NULL;

  INSERT INTO public.nexus_secure_room_members(room_id,user_id,member_role,left_at)
  VALUES(v_room,p_beta_user_id,'member',NULL)
  ON CONFLICT(room_id,user_id) DO UPDATE SET member_role='member',left_at=NULL;

  RETURN v_room;
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_secure_open_owner_dm()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid; v_owner uuid; v_room uuid; v_name text;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.nexus_staff_accounts s WHERE s.user_id=v_user AND s.role='beta_tester')
    THEN RAISE EXCEPTION 'beta_tester_required'; END IF;

  SELECT s.user_id INTO v_owner FROM public.nexus_staff_accounts s WHERE s.role='owner' LIMIT 1;
  IF v_owner IS NULL THEN RAISE EXCEPTION 'owner_not_configured'; END IF;

  SELECT id INTO v_room
  FROM public.nexus_secure_rooms
  WHERE room_type='owner_beta_dm' AND dm_owner_user_id=v_owner AND dm_beta_user_id=v_user AND archived_at IS NULL
  LIMIT 1;

  IF v_room IS NULL THEN
    SELECT coalesce(p.display_name,u.name,u.email,'Beta tester')
      INTO v_name
      FROM neon_auth."user" u
      LEFT JOIN public.nexus_profiles p ON p.user_id=u.id
     WHERE u.id=v_user;

    INSERT INTO public.nexus_secure_rooms(room_type,display_name,created_by,dm_owner_user_id,dm_beta_user_id)
    VALUES('owner_beta_dm','Privato · '||left(coalesce(v_name,'Beta tester'),120),v_owner,v_owner,v_user)
    RETURNING id INTO v_room;
  END IF;

  INSERT INTO public.nexus_secure_room_members(room_id,user_id,member_role,left_at)
  VALUES(v_room,v_owner,'owner',NULL)
  ON CONFLICT(room_id,user_id) DO UPDATE SET member_role='owner',left_at=NULL;

  INSERT INTO public.nexus_secure_room_members(room_id,user_id,member_role,left_at)
  VALUES(v_room,v_user,'member',NULL)
  ON CONFLICT(room_id,user_id) DO UPDATE SET member_role='member',left_at=NULL;

  RETURN v_room;
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_secure_list_rooms()
RETURNS TABLE(
  id uuid,
  room_type text,
  display_name text,
  membership_version bigint,
  created_at timestamptz,
  member_count bigint,
  active_device_count bigint
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
  SELECT r.id,r.room_type,r.display_name,r.membership_version,r.created_at,
         (SELECT count(*) FROM public.nexus_secure_room_members mm WHERE mm.room_id=r.id AND mm.left_at IS NULL),
         (
           SELECT count(*)
           FROM public.nexus_secure_devices d
           JOIN public.nexus_secure_room_members mm ON mm.user_id=d.user_id
           WHERE mm.room_id=r.id AND mm.left_at IS NULL AND d.revoked_at IS NULL
         )
  FROM public.nexus_secure_rooms r
  JOIN public.nexus_secure_room_members m ON m.room_id=r.id
  WHERE m.user_id=v_user AND m.left_at IS NULL AND r.archived_at IS NULL
  ORDER BY CASE r.room_type WHEN 'beta_group' THEN 0 ELSE 1 END,r.created_at,r.id;
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_secure_list_member_devices(p_room_id uuid)
RETURNS TABLE(
  device_id uuid,
  user_id uuid,
  device_label text,
  ecdh_public_jwk jsonb,
  signing_public_jwk jsonb,
  identity_fingerprint text,
  protocol_version text,
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
  IF NOT public.nexus_secure_has_room_access(p_room_id,v_user) THEN RAISE EXCEPTION 'room_access_denied'; END IF;

  RETURN QUERY
  SELECT d.id,d.user_id,d.device_label,d.ecdh_public_jwk,d.signing_public_jwk,
         d.identity_fingerprint,d.protocol_version,d.created_at
  FROM public.nexus_secure_devices d
  JOIN public.nexus_secure_room_members m ON m.user_id=d.user_id
  WHERE m.room_id=p_room_id AND m.left_at IS NULL AND d.revoked_at IS NULL
  ORDER BY d.user_id,d.created_at,d.id;
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_secure_send_envelope(
  p_room_id uuid,
  p_sender_device_id uuid,
  p_client_message_id uuid,
  p_membership_version bigint,
  p_payload_iv text,
  p_salt text,
  p_ephemeral_public_jwk jsonb,
  p_ciphertext text,
  p_signature text,
  p_recipient_keys jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_user uuid; v_message uuid; v_expected integer; v_given integer; v_current_version bigint;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT public.nexus_secure_has_room_access(p_room_id,v_user) THEN RAISE EXCEPTION 'room_access_denied'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.nexus_secure_devices d
    WHERE d.id=p_sender_device_id AND d.user_id=v_user AND d.revoked_at IS NULL
  ) THEN RAISE EXCEPTION 'sender_device_invalid'; END IF;

  SELECT membership_version INTO v_current_version
  FROM public.nexus_secure_rooms
  WHERE id=p_room_id AND archived_at IS NULL;
  IF v_current_version IS NULL THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF p_membership_version<>v_current_version THEN RAISE EXCEPTION 'membership_changed_refresh_room'; END IF;

  IF jsonb_typeof(p_recipient_keys)<>'array' THEN RAISE EXCEPTION 'recipient_keys_array_required'; END IF;
  IF jsonb_typeof(p_ephemeral_public_jwk)<>'object' THEN RAISE EXCEPTION 'ephemeral_public_key_invalid'; END IF;
  IF length(coalesce(p_ciphertext,''))<1 OR length(p_ciphertext)>1400000 THEN RAISE EXCEPTION 'ciphertext_size_invalid'; END IF;
  IF length(coalesce(p_signature,''))<16 OR length(p_signature)>4096 THEN RAISE EXCEPTION 'signature_invalid'; END IF;

  SELECT count(*) INTO v_expected
  FROM public.nexus_secure_devices d
  JOIN public.nexus_secure_room_members m ON m.user_id=d.user_id
  WHERE m.room_id=p_room_id AND m.left_at IS NULL AND d.revoked_at IS NULL;

  SELECT count(DISTINCT (x->>'device_id')::uuid) INTO v_given
  FROM jsonb_array_elements(p_recipient_keys) x
  WHERE x ? 'device_id' AND x ? 'wrap_iv' AND x ? 'wrapped_key';

  IF v_expected<1 OR v_given<>v_expected THEN RAISE EXCEPTION 'recipient_device_set_incomplete'; END IF;

  IF EXISTS(
    SELECT 1
    FROM jsonb_array_elements(p_recipient_keys) x
    LEFT JOIN public.nexus_secure_devices d ON d.id=(x->>'device_id')::uuid AND d.revoked_at IS NULL
    LEFT JOIN public.nexus_secure_room_members m ON m.user_id=d.user_id AND m.room_id=p_room_id AND m.left_at IS NULL
    WHERE d.id IS NULL OR m.room_id IS NULL
  ) THEN RAISE EXCEPTION 'recipient_device_not_in_room'; END IF;

  INSERT INTO public.nexus_secure_messages(
    room_id,sender_user_id,sender_device_id,client_message_id,membership_version,
    payload_iv,salt,ephemeral_public_jwk,ciphertext,signature
  ) VALUES(
    p_room_id,v_user,p_sender_device_id,p_client_message_id,p_membership_version,
    left(p_payload_iv,128),left(p_salt,256),p_ephemeral_public_jwk,p_ciphertext,left(p_signature,4096)
  )
  ON CONFLICT(sender_device_id,client_message_id)
  DO UPDATE SET client_message_id=excluded.client_message_id
  RETURNING id INTO v_message;

  INSERT INTO public.nexus_secure_message_keys(message_id,recipient_device_id,wrap_iv,wrapped_key)
  SELECT v_message,(x->>'device_id')::uuid,left(x->>'wrap_iv',128),left(x->>'wrapped_key',4096)
  FROM jsonb_array_elements(p_recipient_keys) x
  ON CONFLICT(message_id,recipient_device_id)
  DO UPDATE SET wrap_iv=excluded.wrap_iv,wrapped_key=excluded.wrapped_key;

  RETURN v_message;
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_secure_fetch_messages(
  p_room_id uuid,
  p_device_id uuid,
  p_after timestamptz DEFAULT NULL,
  p_limit integer DEFAULT 200
)
RETURNS TABLE(
  id uuid,
  sender_user_id uuid,
  sender_device_id uuid,
  sender_device_label text,
  sender_fingerprint text,
  sender_signing_public_jwk jsonb,
  client_message_id uuid,
  membership_version bigint,
  protocol_version text,
  payload_iv text,
  salt text,
  ephemeral_public_jwk jsonb,
  ciphertext text,
  signature text,
  wrap_iv text,
  wrapped_key text,
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
  IF NOT EXISTS(
    SELECT 1 FROM public.nexus_secure_devices d
    WHERE d.id=p_device_id AND d.user_id=v_user AND d.revoked_at IS NULL
  ) THEN RAISE EXCEPTION 'device_not_owned_or_revoked'; END IF;

  v_limit:=greatest(1,least(coalesce(p_limit,200),500));

  RETURN QUERY
  SELECT m.id,m.sender_user_id,m.sender_device_id,sd.device_label,sd.identity_fingerprint,sd.signing_public_jwk,
         m.client_message_id,m.membership_version,m.protocol_version,m.payload_iv,m.salt,
         m.ephemeral_public_jwk,m.ciphertext,m.signature,k.wrap_iv,k.wrapped_key,m.created_at
  FROM public.nexus_secure_messages m
  JOIN public.nexus_secure_message_keys k ON k.message_id=m.id AND k.recipient_device_id=p_device_id
  JOIN public.nexus_secure_devices sd ON sd.id=m.sender_device_id
  WHERE m.room_id=p_room_id AND (p_after IS NULL OR m.created_at>p_after)
  ORDER BY m.created_at,m.id
  LIMIT v_limit;
END
$function$;
