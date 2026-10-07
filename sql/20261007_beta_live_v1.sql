-- NEXUS Beta Live V1
-- Production-compatible, additive migration.
-- Applied live on 2026-10-07 after validation on a Neon child branch.
-- Current state remains in nexus_beta_tickets; nexus_beta_events is append-only audit history.

CREATE SEQUENCE IF NOT EXISTS public.nexus_beta_ticket_seq START WITH 1 INCREMENT BY 1;

CREATE TABLE IF NOT EXISTS public.nexus_beta_tickets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  public_code text NOT NULL UNIQUE DEFAULT ('BUG-' || lpad(nextval('public.nexus_beta_ticket_seq')::text,6,'0')),
  user_id uuid NOT NULL REFERENCES neon_auth."user"(id) ON DELETE CASCADE,
  kind text NOT NULL DEFAULT 'bug' CHECK (kind IN ('bug','suggestion','ux','performance','model','other')),
  title text NOT NULL,
  description text NOT NULL,
  repro_steps text NULL,
  expected_result text NULL,
  actual_result text NULL,
  component text NOT NULL DEFAULT 'OTHER' CHECK (component IN ('AUTH','CHAT','ROUTING','PC_WORKER','JOBS','UPLOAD','LIBRARY','CREDITS','CONNECTORS','BETA','ADMIN','UI','SEO','OTHER')),
  status text NOT NULL DEFAULT 'APERTO' CHECK (status IN ('APERTO','IN_ANALISI','IN_CORREZIONE','DA_VERIFICARE','RISOLTO','CHIUSO')),
  severity text NOT NULL DEFAULT 'MEDIUM' CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
  priority text NOT NULL DEFAULT 'P2' CHECK (priority IN ('P0','P1','P2','P3')),
  duplicate_of_ticket_id uuid NULL REFERENCES public.nexus_beta_tickets(id) ON DELETE SET NULL,
  regression_of_ticket_id uuid NULL REFERENCES public.nexus_beta_tickets(id) ON DELETE SET NULL,
  fingerprint text NOT NULL,
  fingerprint_version integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (duplicate_of_ticket_id IS NULL OR duplicate_of_ticket_id <> id),
  CHECK (regression_of_ticket_id IS NULL OR regression_of_ticket_id <> id)
);

CREATE TABLE IF NOT EXISTS public.nexus_beta_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES public.nexus_beta_tickets(id) ON DELETE CASCADE,
  snapshot_type text NOT NULL CHECK (snapshot_type IN ('initial','retest','regression','manual')),
  client_route text NULL,
  tab_session_id text NULL,
  user_agent text NULL,
  viewport text NULL,
  conversation_id uuid NULL REFERENCES public.nexus_conversations(id) ON DELETE SET NULL,
  job_id uuid NULL REFERENCES public.nexus_jobs(id) ON DELETE SET NULL,
  job_kind text NULL,
  job_status_at_capture text NULL,
  job_charged_credits integer NULL,
  provider_expected text NULL,
  model_expected text NULL,
  orchestration_route text NULL,
  provider_used text NULL,
  model_used text NULL,
  worker_id text NULL,
  queued_at timestamptz NULL,
  claimed_at timestamptz NULL,
  model_started_at timestamptz NULL,
  completed_at timestamptz NULL,
  frontend_build_commit text NULL,
  worker_version text NULL,
  worker_build_id text NULL,
  schema_version text NULL,
  error_code text NULL,
  execution_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  diagnostic_buffer jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.nexus_beta_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES public.nexus_beta_tickets(id) ON DELETE CASCADE,
  sender_type text NOT NULL CHECK (sender_type IN ('tester','admin','system','ai')),
  sender_user_id uuid NULL REFERENCES neon_auth."user"(id) ON DELETE SET NULL,
  content text NOT NULL,
  is_internal boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((sender_type IN ('tester','admin') AND sender_user_id IS NOT NULL) OR sender_type IN ('system','ai'))
);

CREATE TABLE IF NOT EXISTS public.nexus_beta_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES public.nexus_beta_tickets(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  from_status text NULL,
  to_status text NULL,
  actor_type text NOT NULL CHECK (actor_type IN ('tester','admin','system','ai','worker')),
  actor_user_id uuid NULL REFERENCES neon_auth."user"(id) ON DELETE SET NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.nexus_beta_fixes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES public.nexus_beta_tickets(id) ON DELETE CASCADE,
  fix_type text NOT NULL CHECK (fix_type IN ('frontend_commit','worker_change','database_migration','deployment','configuration')),
  reference text NOT NULL,
  environment text NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid NULL REFERENCES neon_auth."user"(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS nexus_beta_tickets_user_created_idx ON public.nexus_beta_tickets(user_id,created_at DESC);
CREATE INDEX IF NOT EXISTS nexus_beta_tickets_status_priority_idx ON public.nexus_beta_tickets(status,priority,updated_at DESC);
CREATE INDEX IF NOT EXISTS nexus_beta_tickets_component_status_idx ON public.nexus_beta_tickets(component,status);
CREATE INDEX IF NOT EXISTS nexus_beta_tickets_fingerprint_idx ON public.nexus_beta_tickets(fingerprint);
CREATE INDEX IF NOT EXISTS nexus_beta_snapshots_ticket_created_idx ON public.nexus_beta_snapshots(ticket_id,created_at);
CREATE INDEX IF NOT EXISTS nexus_beta_messages_ticket_created_idx ON public.nexus_beta_messages(ticket_id,created_at);
CREATE INDEX IF NOT EXISTS nexus_beta_events_ticket_created_idx ON public.nexus_beta_events(ticket_id,created_at);
CREATE INDEX IF NOT EXISTS nexus_beta_fixes_ticket_created_idx ON public.nexus_beta_fixes(ticket_id,created_at);

ALTER TABLE public.nexus_beta_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_beta_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_beta_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_beta_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_beta_fixes ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.nexus_jobs
  ADD COLUMN IF NOT EXISTS provider_used text NULL,
  ADD COLUMN IF NOT EXISTS model_used text NULL,
  ADD COLUMN IF NOT EXISTS orchestration_route text NULL,
  ADD COLUMN IF NOT EXISTS model_started_at timestamptz NULL,
  ADD COLUMN IF NOT EXISTS execution_metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE OR REPLACE FUNCTION public.nexus_beta_touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$ BEGIN NEW.updated_at:=now(); RETURN NEW; END $function$


CREATE OR REPLACE FUNCTION public.nexus_beta_has_access(p_user uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ SELECT COALESCE((SELECT role IN ('beta_tester','owner','admin','qa') FROM public.nexus_staff_accounts WHERE user_id=p_user),false) $function$


CREATE OR REPLACE FUNCTION public.nexus_beta_sanitize_diagnostic(p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
 DECLARE v_out jsonb:='[]'::jsonb; v_item jsonb; v_safe jsonb; v_candidate jsonb; v_n integer:=0;
 BEGIN
   IF p_data IS NULL OR jsonb_typeof(p_data)<>'array' THEN RETURN '[]'::jsonb; END IF;
   FOR v_item IN SELECT value FROM jsonb_array_elements(p_data) LOOP
     EXIT WHEN v_n>=100;
     v_safe:=jsonb_strip_nulls(jsonb_build_object(
       'timestamp',left(v_item->>'timestamp',64),'event_name',left(v_item->>'event_name',80),
       'component',left(v_item->>'component',40),'severity',left(v_item->>'severity',20),
       'safe_metadata',jsonb_strip_nulls(jsonb_build_object(
         'status',left(v_item#>>'{safe_metadata,status}',80),'code',left(v_item#>>'{safe_metadata,code}',120),
         'job_id',left(v_item#>>'{safe_metadata,job_id}',64),'kind',left(v_item#>>'{safe_metadata,kind}',80),
         'duration_ms',left(v_item#>>'{safe_metadata,duration_ms}',32),'phase',left(v_item#>>'{safe_metadata,phase}',80),
         'route',left(v_item#>>'{safe_metadata,route}',160)
       ))
     ));
     v_candidate:=v_out||jsonb_build_array(v_safe);
     EXIT WHEN octet_length(v_candidate::text)>65536;
     v_out:=v_candidate; v_n:=v_n+1;
   END LOOP;
   RETURN v_out;
 END $function$


CREATE OR REPLACE FUNCTION public.nexus_beta_insert_snapshot_internal(p_ticket_id uuid, p_user uuid, p_snapshot_type text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
 DECLARE
   v_id uuid; v_job uuid; v_conv uuid; v_job_found boolean:=false;
   v_kind text; v_status text; v_worker text; v_created timestamptz; v_started timestamptz; v_model_started timestamptz; v_completed timestamptz;
   v_error text; v_charged integer; v_provider text; v_model text; v_route text; v_exec jsonb;
 BEGIN
   IF p_snapshot_type NOT IN ('initial','retest','regression','manual') THEN RAISE EXCEPTION 'invalid_snapshot_type'; END IF;
   p_data:=coalesce(p_data,'{}'::jsonb);
   IF nullif(p_data->>'conversation_id','') IS NOT NULL THEN
     BEGIN v_conv:=(p_data->>'conversation_id')::uuid; EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'invalid_conversation_id'; END;
     IF NOT EXISTS(SELECT 1 FROM public.nexus_conversations c WHERE c.id=v_conv AND c.user_id=p_user) THEN RAISE EXCEPTION 'conversation_not_owned'; END IF;
   END IF;
   IF nullif(p_data->>'job_id','') IS NOT NULL THEN
     BEGIN v_job:=(p_data->>'job_id')::uuid; EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'invalid_job_id'; END;
     SELECT true,j.kind,j.status,j.worker_id,j.created_at,j.started_at,j.model_started_at,j.completed_at,j.error_code,j.charged_credits,
            j.provider_used,j.model_used,j.orchestration_route,j.execution_metadata
       INTO v_job_found,v_kind,v_status,v_worker,v_created,v_started,v_model_started,v_completed,v_error,v_charged,v_provider,v_model,v_route,v_exec
       FROM public.nexus_jobs j WHERE j.id=v_job AND j.user_id=p_user;
     IF NOT coalesce(v_job_found,false) THEN RAISE EXCEPTION 'job_not_owned'; END IF;
   END IF;
   INSERT INTO public.nexus_beta_snapshots(
     ticket_id,snapshot_type,client_route,tab_session_id,user_agent,viewport,conversation_id,job_id,
     job_kind,job_status_at_capture,job_charged_credits,provider_expected,model_expected,
     orchestration_route,provider_used,model_used,worker_id,queued_at,claimed_at,model_started_at,completed_at,
     frontend_build_commit,worker_version,worker_build_id,schema_version,error_code,execution_metadata,diagnostic_buffer
   ) VALUES(
     p_ticket_id,p_snapshot_type,left(p_data->>'client_route',1200),left(p_data->>'tab_session_id',120),
     left(p_data->>'user_agent',1200),left(p_data->>'viewport',120),v_conv,v_job,v_kind,v_status,v_charged,
     left(p_data->>'provider_expected',160),left(p_data->>'model_expected',200),
     left(v_route,1200),left(v_provider,160),left(v_model,200),left(v_worker,240),
     v_created,v_started,v_model_started,v_completed,left(p_data->>'frontend_build_commit',120),
     left(coalesce(v_exec->>'worker_version',p_data->>'worker_version'),120),
     left(coalesce(v_exec->>'worker_build_id',p_data->>'worker_build_id'),160),
     'beta-live-v1',coalesce(v_error,left(p_data->>'error_code',240)),coalesce(v_exec,'{}'::jsonb),
     public.nexus_beta_sanitize_diagnostic(p_data->'diagnostic_buffer')
   ) RETURNING id INTO v_id;
   RETURN v_id;
 END $function$


CREATE OR REPLACE FUNCTION public.nexus_beta_create_ticket(p_kind text, p_severity text, p_title text, p_description text, p_repro_steps text DEFAULT NULL::text, p_expected_result text DEFAULT NULL::text, p_actual_result text DEFAULT NULL::text, p_component text DEFAULT 'OTHER'::text, p_snapshot_data jsonb DEFAULT '{}'::jsonb)
 RETURNS TABLE(ticket_id uuid, public_code text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
 DECLARE v_user uuid; v_id uuid; v_code text; v_kind text; v_severity text; v_component text; v_priority text; v_fingerprint text;
 BEGIN
   v_user:=(auth.user_id())::uuid;
   IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
   IF NOT public.nexus_beta_has_access(v_user) THEN RAISE EXCEPTION 'beta_access_required'; END IF;
   v_kind:=lower(trim(coalesce(p_kind,'bug'))); v_severity:=upper(trim(coalesce(p_severity,'MEDIUM')));
   v_component:=upper(trim(coalesce(nullif(p_component,''),'OTHER')));
   IF v_kind NOT IN ('bug','suggestion','ux','performance','model','other') THEN RAISE EXCEPTION 'invalid_kind'; END IF;
   IF v_severity NOT IN ('LOW','MEDIUM','HIGH','CRITICAL') THEN RAISE EXCEPTION 'invalid_severity'; END IF;
   IF v_component NOT IN ('AUTH','CHAT','ROUTING','PC_WORKER','JOBS','UPLOAD','LIBRARY','CREDITS','CONNECTORS','BETA','ADMIN','UI','SEO','OTHER') THEN RAISE EXCEPTION 'invalid_component'; END IF;
   IF length(trim(coalesce(p_title,'')))<3 THEN RAISE EXCEPTION 'title_required'; END IF;
   IF length(trim(coalesce(p_description,'')))<3 THEN RAISE EXCEPTION 'description_required'; END IF;
   v_priority:=CASE v_severity WHEN 'CRITICAL' THEN 'P0' WHEN 'HIGH' THEN 'P1' WHEN 'MEDIUM' THEN 'P2' ELSE 'P3' END;
   v_fingerprint:=md5(v_component||'|'||coalesce(p_snapshot_data->>'error_code','')||'|'||v_kind||'|'||lower(regexp_replace(trim(p_title),'\s+',' ','g')));
   INSERT INTO public.nexus_beta_tickets(user_id,kind,title,description,repro_steps,expected_result,actual_result,component,severity,priority,fingerprint)
   VALUES(v_user,v_kind,left(trim(p_title),240),left(trim(p_description),12000),left(p_repro_steps,12000),
          left(p_expected_result,8000),left(p_actual_result,8000),v_component,v_severity,v_priority,v_fingerprint)
   RETURNING id,nexus_beta_tickets.public_code INTO v_id,v_code;
   PERFORM public.nexus_beta_insert_snapshot_internal(v_id,v_user,'initial',coalesce(p_snapshot_data,'{}'::jsonb));
   INSERT INTO public.nexus_beta_messages(ticket_id,sender_type,content)
     VALUES(v_id,'system','Segnalazione ricevuta. NEXUS ha acquisito il contesto diagnostico disponibile.');
   INSERT INTO public.nexus_beta_events(ticket_id,event_type,to_status,actor_type,actor_user_id,metadata)
     VALUES(v_id,'ticket_created','APERTO','tester',v_user,jsonb_build_object('fingerprint_version',1));
   RETURN QUERY SELECT v_id,v_code;
 END $function$


CREATE OR REPLACE FUNCTION public.nexus_beta_list_my_tickets()
 RETURNS TABLE(id uuid, public_code text, title text, kind text, component text, status text, severity text, priority text, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
 DECLARE v_user uuid;
 BEGIN
   v_user:=(auth.user_id())::uuid;
   IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
   IF NOT public.nexus_beta_has_access(v_user) THEN RAISE EXCEPTION 'beta_access_required'; END IF;
   RETURN QUERY SELECT t.id,t.public_code,t.title,t.kind,t.component,t.status,t.severity,t.priority,t.created_at,t.updated_at
   FROM public.nexus_beta_tickets t WHERE t.user_id=v_user ORDER BY t.updated_at DESC;
 END $function$


CREATE OR REPLACE FUNCTION public.nexus_beta_get_ticket(p_ticket_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
 DECLARE v_user uuid; v_admin boolean; v_ticket public.nexus_beta_tickets%ROWTYPE;
         v_messages jsonb; v_events jsonb; v_snapshots jsonb; v_fixes jsonb;
 BEGIN
   v_user:=(auth.user_id())::uuid;
   IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
   v_admin:=public.nexus_is_owner(v_user);
   SELECT * INTO v_ticket FROM public.nexus_beta_tickets t WHERE t.id=p_ticket_id AND (t.user_id=v_user OR v_admin);
   IF NOT FOUND THEN RAISE EXCEPTION 'ticket_not_found'; END IF;
   SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id',m.id,'sender_type',m.sender_type,'sender_user_id',m.sender_user_id,
      'sender_name',coalesce(p.display_name,u.name,u.email,m.sender_type),
      'content',m.content,'is_internal',m.is_internal,'created_at',m.created_at
    ) ORDER BY m.created_at),'[]'::jsonb)
   INTO v_messages
   FROM public.nexus_beta_messages m
   LEFT JOIN neon_auth."user" u ON u.id=m.sender_user_id
   LEFT JOIN public.nexus_profiles p ON p.user_id=m.sender_user_id
   WHERE m.ticket_id=p_ticket_id AND (v_admin OR NOT m.is_internal);
   SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id',e.id,'event_type',e.event_type,'from_status',e.from_status,'to_status',e.to_status,
      'actor_type',e.actor_type,'created_at',e.created_at,'metadata',CASE WHEN v_admin THEN e.metadata ELSE '{}'::jsonb END
    ) ORDER BY e.created_at),'[]'::jsonb)
   INTO v_events
   FROM public.nexus_beta_events e
   WHERE e.ticket_id=p_ticket_id AND (v_admin OR e.event_type IN ('ticket_created','status_changed','retest_requested','tester_confirmed','tester_rejected_fix','ticket_closed'));
   IF v_admin THEN
     SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY s.created_at),'[]'::jsonb) INTO v_snapshots
       FROM public.nexus_beta_snapshots s WHERE s.ticket_id=p_ticket_id;
     SELECT coalesce(jsonb_agg(to_jsonb(f) ORDER BY f.created_at),'[]'::jsonb) INTO v_fixes
       FROM public.nexus_beta_fixes f WHERE f.ticket_id=p_ticket_id;
   ELSE
     v_snapshots:='[]'::jsonb; v_fixes:='[]'::jsonb;
   END IF;
   RETURN jsonb_build_object('ticket',to_jsonb(v_ticket),'messages',v_messages,'events',v_events,'snapshots',v_snapshots,'fixes',v_fixes,'is_admin',v_admin);
 END $function$


CREATE OR REPLACE FUNCTION public.nexus_beta_add_message(p_ticket_id uuid, p_content text, p_is_internal boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
 DECLARE v_user uuid; v_admin boolean; v_owner uuid; v_id uuid; v_sender text;
 BEGIN
   v_user:=(auth.user_id())::uuid; IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
   SELECT user_id INTO v_owner FROM public.nexus_beta_tickets WHERE id=p_ticket_id;
   IF v_owner IS NULL THEN RAISE EXCEPTION 'ticket_not_found'; END IF;
   v_admin:=public.nexus_is_owner(v_user);
   IF NOT v_admin AND v_owner<>v_user THEN RAISE EXCEPTION 'ticket_not_owned'; END IF;
   IF NOT v_admin AND coalesce(p_is_internal,false) THEN RAISE EXCEPTION 'internal_message_forbidden'; END IF;
   IF length(trim(coalesce(p_content,'')))<1 THEN RAISE EXCEPTION 'message_required'; END IF;
   v_sender:=CASE WHEN v_admin THEN 'admin' ELSE 'tester' END;
   INSERT INTO public.nexus_beta_messages(ticket_id,sender_type,sender_user_id,content,is_internal)
     VALUES(p_ticket_id,v_sender,v_user,left(trim(p_content),12000),coalesce(p_is_internal,false)) RETURNING id INTO v_id;
   INSERT INTO public.nexus_beta_events(ticket_id,event_type,actor_type,actor_user_id,metadata)
     VALUES(p_ticket_id,'message_added',v_sender,v_user,jsonb_build_object('internal',coalesce(p_is_internal,false)));
   UPDATE public.nexus_beta_tickets SET updated_at=now() WHERE id=p_ticket_id;
   RETURN v_id;
 END $function$


CREATE OR REPLACE FUNCTION public.nexus_beta_confirm_resolved(p_ticket_id uuid, p_snapshot_data jsonb DEFAULT '{}'::jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
 DECLARE v_user uuid; v_status text; v_owner uuid;
 BEGIN
   v_user:=(auth.user_id())::uuid; IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
   SELECT user_id,status INTO v_owner,v_status FROM public.nexus_beta_tickets WHERE id=p_ticket_id FOR UPDATE;
   IF v_owner IS NULL THEN RAISE EXCEPTION 'ticket_not_found'; END IF;
   IF v_owner<>v_user THEN RAISE EXCEPTION 'ticket_not_owned'; END IF;
   IF v_status<>'DA_VERIFICARE' THEN RAISE EXCEPTION 'invalid_transition'; END IF;
   PERFORM public.nexus_beta_insert_snapshot_internal(p_ticket_id,v_user,'retest',coalesce(p_snapshot_data,'{}'::jsonb));
   UPDATE public.nexus_beta_tickets SET status='RISOLTO' WHERE id=p_ticket_id;
   INSERT INTO public.nexus_beta_events(ticket_id,event_type,from_status,to_status,actor_type,actor_user_id)
     VALUES(p_ticket_id,'tester_confirmed','DA_VERIFICARE','RISOLTO','tester',v_user);
   INSERT INTO public.nexus_beta_messages(ticket_id,sender_type,content)
     VALUES(p_ticket_id,'system','Il tester ha confermato che il problema è risolto.');
   RETURN true;
 END $function$


CREATE OR REPLACE FUNCTION public.nexus_beta_report_still_present(p_ticket_id uuid, p_snapshot_data jsonb DEFAULT '{}'::jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
 DECLARE v_user uuid; v_status text; v_owner uuid;
 BEGIN
   v_user:=(auth.user_id())::uuid; IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
   SELECT user_id,status INTO v_owner,v_status FROM public.nexus_beta_tickets WHERE id=p_ticket_id FOR UPDATE;
   IF v_owner IS NULL THEN RAISE EXCEPTION 'ticket_not_found'; END IF;
   IF v_owner<>v_user THEN RAISE EXCEPTION 'ticket_not_owned'; END IF;
   IF v_status<>'DA_VERIFICARE' THEN RAISE EXCEPTION 'invalid_transition'; END IF;
   PERFORM public.nexus_beta_insert_snapshot_internal(p_ticket_id,v_user,'retest',coalesce(p_snapshot_data,'{}'::jsonb));
   UPDATE public.nexus_beta_tickets SET status='IN_ANALISI' WHERE id=p_ticket_id;
   INSERT INTO public.nexus_beta_events(ticket_id,event_type,from_status,to_status,actor_type,actor_user_id)
     VALUES(p_ticket_id,'tester_rejected_fix','DA_VERIFICARE','IN_ANALISI','tester',v_user);
   INSERT INTO public.nexus_beta_messages(ticket_id,sender_type,content)
     VALUES(p_ticket_id,'system','Il tester segnala che il problema è ancora presente. Il ticket torna in analisi.');
   RETURN true;
 END $function$


CREATE OR REPLACE FUNCTION public.nexus_beta_admin_transition(p_ticket_id uuid, p_new_status text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
 DECLARE v_admin uuid; v_old text; v_new text; v_ok boolean:=false; v_event text:='status_changed';
 BEGIN
   v_admin:=(auth.user_id())::uuid; IF NOT public.nexus_is_owner(v_admin) THEN RAISE EXCEPTION 'admin_required'; END IF;
   v_new:=upper(trim(coalesce(p_new_status,'')));
   SELECT status INTO v_old FROM public.nexus_beta_tickets WHERE id=p_ticket_id FOR UPDATE;
   IF v_old IS NULL THEN RAISE EXCEPTION 'ticket_not_found'; END IF;
   v_ok:=CASE
     WHEN v_old='APERTO' AND v_new IN ('IN_ANALISI','CHIUSO') THEN true
     WHEN v_old='IN_ANALISI' AND v_new IN ('IN_CORREZIONE','CHIUSO') THEN true
     WHEN v_old='IN_CORREZIONE' AND v_new IN ('DA_VERIFICARE','IN_ANALISI') THEN true
     WHEN v_old='DA_VERIFICARE' AND v_new IN ('IN_ANALISI','RISOLTO') THEN true
     WHEN v_old='RISOLTO' AND v_new IN ('CHIUSO','IN_ANALISI') THEN true
     ELSE false END;
   IF NOT v_ok THEN RAISE EXCEPTION 'invalid_transition:%->%',v_old,v_new; END IF;
   UPDATE public.nexus_beta_tickets SET status=v_new WHERE id=p_ticket_id;
   IF v_new='DA_VERIFICARE' THEN v_event:='retest_requested'; ELSIF v_new='CHIUSO' THEN v_event:='ticket_closed'; END IF;
   INSERT INTO public.nexus_beta_events(ticket_id,event_type,from_status,to_status,actor_type,actor_user_id,metadata)
     VALUES(p_ticket_id,v_event,v_old,v_new,'admin',v_admin,coalesce(p_metadata,'{}'::jsonb));
   IF v_new='DA_VERIFICARE' THEN
     INSERT INTO public.nexus_beta_messages(ticket_id,sender_type,content)
       VALUES(p_ticket_id,'system','Una correzione è pronta. Riproduci il problema e conferma se è risolto oppure ancora presente.');
   ELSIF v_new='CHIUSO' THEN
     INSERT INTO public.nexus_beta_messages(ticket_id,sender_type,content) VALUES(p_ticket_id,'system','Ticket chiuso dall’amministratore.');
   END IF;
   RETURN true;
 END $function$


CREATE OR REPLACE FUNCTION public.nexus_beta_admin_link_fix(p_ticket_id uuid, p_fix_type text, p_reference text, p_environment text DEFAULT 'production'::text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
 DECLARE v_admin uuid; v_id uuid; v_type text;
 BEGIN
   v_admin:=(auth.user_id())::uuid; IF NOT public.nexus_is_owner(v_admin) THEN RAISE EXCEPTION 'admin_required'; END IF;
   IF NOT EXISTS(SELECT 1 FROM public.nexus_beta_tickets WHERE id=p_ticket_id) THEN RAISE EXCEPTION 'ticket_not_found'; END IF;
   v_type:=lower(trim(coalesce(p_fix_type,'')));
   IF v_type NOT IN ('frontend_commit','worker_change','database_migration','deployment','configuration') THEN RAISE EXCEPTION 'invalid_fix_type'; END IF;
   IF length(trim(coalesce(p_reference,'')))<2 THEN RAISE EXCEPTION 'reference_required'; END IF;
   INSERT INTO public.nexus_beta_fixes(ticket_id,fix_type,reference,environment,metadata,created_by)
     VALUES(p_ticket_id,v_type,left(trim(p_reference),500),left(trim(coalesce(p_environment,'production')),120),coalesce(p_metadata,'{}'::jsonb),v_admin)
     RETURNING id INTO v_id;
   INSERT INTO public.nexus_beta_events(ticket_id,event_type,actor_type,actor_user_id,metadata)
     VALUES(p_ticket_id,'fix_linked','admin',v_admin,jsonb_build_object('fix_id',v_id,'fix_type',v_type,'reference',left(trim(p_reference),500)));
   UPDATE public.nexus_beta_tickets SET updated_at=now() WHERE id=p_ticket_id;
   RETURN v_id;
 END $function$


CREATE OR REPLACE FUNCTION public.nexus_beta_admin_list_tickets()
 RETURNS TABLE(id uuid, public_code text, user_id uuid, email text, name text, title text, kind text, component text, status text, severity text, priority text, duplicate_of_ticket_id uuid, regression_of_ticket_id uuid, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
 DECLARE v_admin uuid;
 BEGIN
   v_admin:=(auth.user_id())::uuid; IF NOT public.nexus_is_owner(v_admin) THEN RAISE EXCEPTION 'admin_required'; END IF;
   RETURN QUERY SELECT t.id,t.public_code,t.user_id,u.email,coalesce(p.display_name,u.name,u.email),t.title,t.kind,t.component,t.status,t.severity,t.priority,
          t.duplicate_of_ticket_id,t.regression_of_ticket_id,t.created_at,t.updated_at
   FROM public.nexus_beta_tickets t JOIN neon_auth."user" u ON u.id=t.user_id LEFT JOIN public.nexus_profiles p ON p.user_id=t.user_id
   ORDER BY CASE t.priority WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 ELSE 3 END,t.updated_at DESC;
 END $function$


DROP TRIGGER IF EXISTS nexus_beta_tickets_touch_updated_at ON public.nexus_beta_tickets;
CREATE TRIGGER nexus_beta_tickets_touch_updated_at
BEFORE UPDATE ON public.nexus_beta_tickets
FOR EACH ROW EXECUTE FUNCTION public.nexus_beta_touch_updated_at();

REVOKE ALL ON FUNCTION public.nexus_beta_insert_snapshot_internal(uuid,uuid,text,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_beta_insert_snapshot_internal(uuid,uuid,text,jsonb) FROM authenticated;

REVOKE ALL ON FUNCTION public.nexus_beta_create_ticket(text,text,text,text,text,text,text,text,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_beta_list_my_tickets() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_beta_get_ticket(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_beta_add_message(uuid,text,boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_beta_confirm_resolved(uuid,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_beta_report_still_present(uuid,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_beta_admin_transition(uuid,text,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_beta_admin_link_fix(uuid,text,text,text,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_beta_admin_list_tickets() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.nexus_beta_create_ticket(text,text,text,text,text,text,text,text,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_beta_list_my_tickets() TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_beta_get_ticket(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_beta_add_message(uuid,text,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_beta_confirm_resolved(uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_beta_report_still_present(uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_beta_admin_transition(uuid,text,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_beta_admin_link_fix(uuid,text,text,text,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_beta_admin_list_tickets() TO authenticated;
