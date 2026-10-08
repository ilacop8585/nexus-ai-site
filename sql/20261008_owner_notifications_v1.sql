-- NEXUS Owner Notifications V1
-- Persistent Owner-only notifications sourced from append-only Beta Live events.

CREATE TABLE IF NOT EXISTS public.nexus_owner_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid NOT NULL REFERENCES neon_auth."user"(id) ON DELETE CASCADE,
  ticket_id uuid NULL REFERENCES public.nexus_beta_tickets(id) ON DELETE CASCADE,
  event_id uuid NULL REFERENCES public.nexus_beta_events(id) ON DELETE CASCADE,
  notification_type text NOT NULL,
  title text NOT NULL,
  body text NULL,
  severity text NOT NULL DEFAULT 'info'
    CHECK (severity IN ('info','success','warning','critical')),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz NULL,
  UNIQUE(owner_user_id,event_id)
);

CREATE INDEX IF NOT EXISTS nexus_owner_notifications_owner_unread_idx
  ON public.nexus_owner_notifications(owner_user_id,created_at DESC)
  WHERE read_at IS NULL;

CREATE INDEX IF NOT EXISTS nexus_owner_notifications_owner_created_idx
  ON public.nexus_owner_notifications(owner_user_id,created_at DESC);

ALTER TABLE public.nexus_owner_notifications ENABLE ROW LEVEL SECURITY;


CREATE OR REPLACE FUNCTION public.nexus_owner_notify_from_beta_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_code text;
  v_title text;
  v_ticket_title text;
  v_beta_name text;
  v_type text;
  v_n_title text;
  v_body text;
  v_severity text:='info';
  v_owner record;
BEGIN
  IF NEW.event_type NOT IN (
    'ticket_created',
    'ai_triage_completed',
    'triage_failed',
    'fix_linked',
    'retest_requested',
    'tester_confirmed',
    'tester_rejected_fix',
    'ticket_closed'
  ) THEN
    RETURN NEW;
  END IF;

  SELECT
    t.public_code,
    t.title,
    coalesce(p.display_name,u.name,u.email,'Beta tester')
  INTO v_code,v_ticket_title,v_beta_name
  FROM public.nexus_beta_tickets t
  JOIN neon_auth."user" u ON u.id=t.user_id
  LEFT JOIN public.nexus_profiles p ON p.user_id=t.user_id
  WHERE t.id=NEW.ticket_id;

  IF v_code IS NULL THEN RETURN NEW; END IF;

  CASE NEW.event_type
    WHEN 'ticket_created' THEN
      v_type:='new_beta_ticket';
      v_n_title:=v_beta_name||' ha aperto '||v_code;
      v_body:=coalesce(v_ticket_title,'Nuova segnalazione Beta');
      v_severity:='warning';

    WHEN 'ai_triage_completed' THEN
      v_type:='ai_triage_completed';
      v_n_title:='IA ha finito il triage di '||v_code;
      v_body:=trim(concat_ws(' · ',
        nullif(NEW.metadata->>'component',''),
        nullif(NEW.metadata->>'severity',''),
        CASE
          WHEN NEW.metadata ? 'confidence'
          THEN 'confidenza '||round(((NEW.metadata->>'confidence')::numeric)*100)||'%'
          ELSE NULL
        END
      ));
      IF v_body='' THEN v_body:='Analisi automatica completata.'; END IF;
      v_severity:='success';

    WHEN 'triage_failed' THEN
      v_type:='ai_triage_failed';
      v_n_title:='Triage IA fallito su '||v_code;
      v_body:=coalesce(NEW.metadata->>'error_code',NEW.metadata->>'reason','Il triage automatico richiede attenzione.');
      v_severity:='critical';

    WHEN 'fix_linked' THEN
      v_type:='fix_ready';
      v_n_title:='Fix pronto per '||v_code;
      v_body:=trim(concat_ws(' · ',
        nullif(NEW.metadata->>'fix_type',''),
        nullif(NEW.metadata->>'reference','')
      ));
      IF v_body='' THEN v_body:='Una correzione è stata collegata al ticket.'; END IF;
      v_severity:='success';

    WHEN 'retest_requested' THEN
      v_type:='beta_retest_requested';
      v_n_title:=v_beta_name||' deve verificare '||v_code;
      v_body:='La correzione è pronta per il retest del beta tester.';
      v_severity:='warning';

    WHEN 'tester_confirmed' THEN
      v_type:='beta_confirmed';
      v_n_title:=v_beta_name||' ha confermato '||v_code;
      v_body:='Il beta tester conferma che il problema è risolto.';
      v_severity:='success';

    WHEN 'tester_rejected_fix' THEN
      v_type:='beta_rejected_fix';
      v_n_title:=v_beta_name||' segnala che '||v_code||' è ancora presente';
      v_body:='Il ticket è tornato in analisi.';
      v_severity:='critical';

    WHEN 'ticket_closed' THEN
      v_type:='ticket_closed';
      v_n_title:=v_code||' è stato chiuso';
      v_body:=coalesce(v_ticket_title,'Ticket Beta chiuso.');
      v_severity:='info';

    ELSE
      RETURN NEW;
  END CASE;

  FOR v_owner IN
    SELECT s.user_id
    FROM public.nexus_staff_accounts s
    WHERE s.role='owner'
  LOOP
    INSERT INTO public.nexus_owner_notifications(
      owner_user_id,ticket_id,event_id,notification_type,title,body,severity,metadata
    )
    VALUES(
      v_owner.user_id,NEW.ticket_id,NEW.id,v_type,
      left(v_n_title,320),left(v_body,1600),v_severity,
      jsonb_build_object(
        'beta_event_type',NEW.event_type,
        'public_code',v_code,
        'beta_name',v_beta_name,
        'from_status',NEW.from_status,
        'to_status',NEW.to_status
      ) || coalesce(NEW.metadata,'{}'::jsonb)
    )
    ON CONFLICT(owner_user_id,event_id) DO NOTHING;
  END LOOP;

  RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS nexus_owner_notify_from_beta_event_trg ON public.nexus_beta_events;
CREATE TRIGGER nexus_owner_notify_from_beta_event_trg
AFTER INSERT ON public.nexus_beta_events
FOR EACH ROW EXECUTE FUNCTION public.nexus_owner_notify_from_beta_event();


CREATE OR REPLACE FUNCTION public.nexus_owner_notifications_list(p_limit integer DEFAULT 100)
RETURNS TABLE(
  id uuid,
  ticket_id uuid,
  notification_type text,
  title text,
  body text,
  severity text,
  metadata jsonb,
  created_at timestamptz,
  read_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_owner uuid; v_limit integer;
BEGIN
  v_owner:=(auth.user_id())::uuid;
  IF v_owner IS NULL OR NOT public.nexus_is_owner(v_owner) THEN
    RAISE EXCEPTION 'owner_required';
  END IF;

  v_limit:=greatest(1,least(coalesce(p_limit,100),300));

  RETURN QUERY
  SELECT n.id,n.ticket_id,n.notification_type,n.title,n.body,n.severity,n.metadata,n.created_at,n.read_at
  FROM public.nexus_owner_notifications n
  WHERE n.owner_user_id=v_owner
  ORDER BY (n.read_at IS NULL) DESC,n.created_at DESC
  LIMIT v_limit;
END
$function$;


CREATE OR REPLACE FUNCTION public.nexus_owner_notifications_unread_count()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_owner uuid; v_count bigint;
BEGIN
  v_owner:=(auth.user_id())::uuid;
  IF v_owner IS NULL OR NOT public.nexus_is_owner(v_owner) THEN
    RAISE EXCEPTION 'owner_required';
  END IF;

  SELECT count(*) INTO v_count
  FROM public.nexus_owner_notifications n
  WHERE n.owner_user_id=v_owner AND n.read_at IS NULL;

  RETURN v_count;
END
$function$;


CREATE OR REPLACE FUNCTION public.nexus_owner_notifications_mark_read(p_notification_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_owner uuid;
BEGIN
  v_owner:=(auth.user_id())::uuid;
  IF v_owner IS NULL OR NOT public.nexus_is_owner(v_owner) THEN
    RAISE EXCEPTION 'owner_required';
  END IF;

  UPDATE public.nexus_owner_notifications
  SET read_at=coalesce(read_at,now())
  WHERE id=p_notification_id AND owner_user_id=v_owner;

  RETURN FOUND;
END
$function$;


CREATE OR REPLACE FUNCTION public.nexus_owner_notifications_mark_all_read()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_owner uuid; v_count bigint;
BEGIN
  v_owner:=(auth.user_id())::uuid;
  IF v_owner IS NULL OR NOT public.nexus_is_owner(v_owner) THEN
    RAISE EXCEPTION 'owner_required';
  END IF;

  WITH changed AS (
    UPDATE public.nexus_owner_notifications
    SET read_at=now()
    WHERE owner_user_id=v_owner AND read_at IS NULL
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM changed;

  RETURN v_count;
END
$function$;

REVOKE ALL ON TABLE public.nexus_owner_notifications FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_owner_notifications_list(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_owner_notifications_unread_count() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_owner_notifications_mark_read(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_owner_notifications_mark_all_read() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.nexus_owner_notifications_list(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_owner_notifications_unread_count() TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_owner_notifications_mark_read(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_owner_notifications_mark_all_read() TO authenticated;
