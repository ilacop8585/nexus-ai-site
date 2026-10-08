-- NEXUS Beta Collaboration / Admin Workspace V1
-- DRAFT ONLY: apply on a temporary Neon branch before production.
-- Separates monitored Beta Workspace from E2EE NEXUS Private.

ALTER TABLE public.nexus_messages
  ADD COLUMN IF NOT EXISTS actor_user_id uuid NULL REFERENCES neon_auth."user"(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.nexus_beta_observations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  beta_user_id uuid NOT NULL REFERENCES neon_auth."user"(id) ON DELETE CASCADE,
  conversation_id uuid NOT NULL REFERENCES public.nexus_conversations(id) ON DELETE CASCADE,
  source_message_id uuid NULL REFERENCES public.nexus_messages(id) ON DELETE SET NULL,
  source_attachment_id uuid NULL REFERENCES public.nexus_attachments(id) ON DELETE SET NULL,
  observation_type text NOT NULL DEFAULT 'unclassified' CHECK (observation_type IN ('unclassified','normal_chat','bug','suggestion','ux','performance','model','other')),
  status text NOT NULL DEFAULT 'NEW' CHECK (status IN ('NEW','CLASSIFYING','TRIAGED','TICKET_LINKED','DISMISSED','FAILED')),
  summary text NULL,
  confidence numeric NULL CHECK (confidence IS NULL OR (confidence>=0 AND confidence<=1)),
  triage_job_id uuid NULL REFERENCES public.nexus_jobs(id) ON DELETE SET NULL,
  linked_ticket_id uuid NULL REFERENCES public.nexus_beta_tickets(id) ON DELETE SET NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS nexus_beta_observations_status_idx ON public.nexus_beta_observations(status,created_at);
CREATE INDEX IF NOT EXISTS nexus_beta_observations_conversation_idx ON public.nexus_beta_observations(conversation_id,created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS nexus_beta_observations_source_message_uidx ON public.nexus_beta_observations(source_message_id) WHERE source_message_id IS NOT NULL;
ALTER TABLE public.nexus_beta_observations ENABLE ROW LEVEL SECURITY;


CREATE OR REPLACE FUNCTION public.nexus_beta_observation_enqueue_internal(p_observation_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_job uuid; v_beta uuid; v_conv uuid; v_msg text; v_title text; v_prompt text;
BEGIN
  SELECT o.beta_user_id,o.conversation_id,m.content,c.title
    INTO v_beta,v_conv,v_msg,v_title
  FROM public.nexus_beta_observations o
  JOIN public.nexus_messages m ON m.id=o.source_message_id
  JOIN public.nexus_conversations c ON c.id=o.conversation_id
  WHERE o.id=p_observation_id;

  IF v_beta IS NULL OR v_msg IS NULL THEN RAISE EXCEPTION 'beta_observation_not_found'; END IF;

  v_prompt:=left(
    '[CHAT_LOCAL] Sei NEXUS Beta Observer. Classifica UN SOLO messaggio di un beta tester.'||E'\n'
    ||'Non rispondere all utente. Restituisci SOLO JSON valido senza markdown:'||E'\n'
    ||'{"action":"ignore|ticket","kind":"bug|suggestion|ux|performance|model|other","title":"max 120","component":"AUTH|CHAT|ROUTING|PC_WORKER|JOBS|UPLOAD|LIBRARY|CREDITS|CONNECTORS|BETA|ADMIN|UI|SEO|OTHER","severity":"LOW|MEDIUM|HIGH|CRITICAL","confidence":0.0,"summary":"max 500"}'||E'\n'
    ||'Usa action=ignore per saluti, conversazione normale, domande informative o richieste che non descrivono un difetto o miglioramento.'||E'\n'
    ||'Usa action=ticket solo per bug, regressioni, problemi di prestazioni/UX/modello o miglioramenti concreti del prodotto.'||E'\n'
    ||'TITOLO CHAT: '||coalesce(v_title,'Chat Beta')||E'\n'
    ||'MESSAGGIO BETA: '||left(v_msg,6000),
    11900
  );

  INSERT INTO public.nexus_jobs(
    user_id,conversation_id,kind,level,status,priority,
    estimated_credits,charged_credits,input_summary,execution_metadata
  ) VALUES(
    v_beta,v_conv,'general_file','free','queued',98,
    0,0,v_prompt,
    jsonb_build_object('internal',true,'internal_type','beta_observer','observation_id',p_observation_id,'credits',0)
  )
  RETURNING id INTO v_job;

  UPDATE public.nexus_beta_observations
     SET status='CLASSIFYING',triage_job_id=v_job,updated_at=now()
   WHERE id=p_observation_id;

  RETURN v_job;
END
$function$;


CREATE OR REPLACE FUNCTION public.nexus_beta_create_ticket_from_observation_internal(
  p_observation_id uuid,
  p_classification jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_beta uuid; v_conv uuid; v_msg text; v_kind text; v_title text; v_component text; v_severity text; v_priority text;
  v_conf numeric; v_fingerprint text; v_ticket uuid; v_code text; v_dup uuid; v_dup_code text;
BEGIN
  SELECT o.beta_user_id,o.conversation_id,m.content
    INTO v_beta,v_conv,v_msg
  FROM public.nexus_beta_observations o
  JOIN public.nexus_messages m ON m.id=o.source_message_id
  WHERE o.id=p_observation_id
  FOR UPDATE OF o;

  IF v_beta IS NULL OR v_msg IS NULL THEN RAISE EXCEPTION 'beta_observation_not_found'; END IF;

  v_kind:=lower(coalesce(p_classification->>'kind','other'));
  IF v_kind NOT IN ('bug','suggestion','ux','performance','model','other') THEN v_kind:='other'; END IF;
  v_component:=upper(coalesce(p_classification->>'component','OTHER'));
  IF v_component NOT IN ('AUTH','CHAT','ROUTING','PC_WORKER','JOBS','UPLOAD','LIBRARY','CREDITS','CONNECTORS','BETA','ADMIN','UI','SEO','OTHER') THEN v_component:='OTHER'; END IF;
  v_severity:=upper(coalesce(p_classification->>'severity','MEDIUM'));
  IF v_severity NOT IN ('LOW','MEDIUM','HIGH','CRITICAL') THEN v_severity:='MEDIUM'; END IF;
  v_priority:=CASE v_severity WHEN 'CRITICAL' THEN 'P0' WHEN 'HIGH' THEN 'P1' WHEN 'MEDIUM' THEN 'P2' ELSE 'P3' END;
  v_title:=left(coalesce(nullif(trim(p_classification->>'title'),''),left(regexp_replace(v_msg,E'[\r\n]+',' ','g'),120)),240);
  BEGIN v_conf:=greatest(0,least(1,(p_classification->>'confidence')::numeric)); EXCEPTION WHEN OTHERS THEN v_conf:=0; END;

  v_fingerprint:=md5(v_component||'|'||v_kind||'|'||lower(regexp_replace(trim(v_title),'\s+',' ','g')));

  SELECT t.id,t.public_code INTO v_dup,v_dup_code
  FROM public.nexus_beta_tickets t
  WHERE t.fingerprint=v_fingerprint AND t.status IN ('APERTO','IN_ANALISI','IN_CORREZIONE','DA_VERIFICARE')
  ORDER BY t.created_at ASC LIMIT 1;

  INSERT INTO public.nexus_beta_tickets(
    user_id,kind,title,description,component,severity,priority,fingerprint,duplicate_of_ticket_id
  ) VALUES(
    v_beta,v_kind,v_title,left(v_msg,12000),v_component,v_severity,v_priority,v_fingerprint,v_dup
  )
  RETURNING id,public_code INTO v_ticket,v_code;

  PERFORM public.nexus_beta_insert_snapshot_internal(
    v_ticket,v_beta,'initial',
    jsonb_build_object('conversation_id',v_conv,'client_route','/beta-workspace','frontend_build_commit','beta-observer-v1')
  );

  INSERT INTO public.nexus_beta_messages(ticket_id,sender_type,content)
  VALUES(v_ticket,'system','NEXUS Beta Observer ha trasformato automaticamente un feedback della chat in questa segnalazione.');

  INSERT INTO public.nexus_beta_events(ticket_id,event_type,to_status,actor_type,metadata)
  VALUES(v_ticket,'ticket_created','APERTO','ai',jsonb_build_object('source','beta_workspace','observation_id',p_observation_id,'confidence',v_conf));

  IF v_dup IS NOT NULL THEN
    INSERT INTO public.nexus_beta_events(ticket_id,event_type,actor_type,metadata)
    VALUES(v_ticket,'duplicate_detected','system',jsonb_build_object('canonical_ticket_id',v_dup,'canonical_public_code',v_dup_code,'method','observer_fingerprint'));
  END IF;

  UPDATE public.nexus_beta_observations
     SET observation_type=v_kind,status='TICKET_LINKED',
         summary=left(coalesce(p_classification->>'summary',''),1200),
         confidence=v_conf,linked_ticket_id=v_ticket,updated_at=now()
   WHERE id=p_observation_id;

  INSERT INTO public.nexus_messages(conversation_id,user_id,role,content,metadata)
  VALUES(
    v_conv,v_beta,'system',
    'NEXUS QA ha rilevato un feedback utile e ha aperto automaticamente '||v_code||'.',
    jsonb_build_object('actor_type','system','visible_label','NEXUS QA','beta_ticket_id',v_ticket,'public_code',v_code)
  );

  BEGIN
    PERFORM public.nexus_beta_enqueue_triage_internal(v_ticket,v_beta);
  EXCEPTION WHEN OTHERS THEN
    UPDATE public.nexus_beta_tickets SET ai_triage_status='failed',ai_updated_at=now() WHERE id=v_ticket;
    INSERT INTO public.nexus_beta_events(ticket_id,event_type,actor_type,metadata)
    VALUES(v_ticket,'triage_failed','system',jsonb_build_object('phase','observer_enqueue'));
  END;

  RETURN v_ticket;
END
$function$;


CREATE OR REPLACE FUNCTION public.nexus_beta_apply_observer_job()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_obs uuid; v_raw text; v_json jsonb; v_action text; v_conf numeric; v_kind text;
BEGIN
  IF coalesce(NEW.execution_metadata->>'internal_type','')<>'beta_observer' THEN RETURN NEW; END IF;
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status NOT IN ('completed','failed') THEN RETURN NEW; END IF;

  BEGIN v_obs:=(NEW.execution_metadata->>'observation_id')::uuid; EXCEPTION WHEN OTHERS THEN RETURN NEW; END;
  IF v_obs IS NULL THEN RETURN NEW; END IF;

  IF NEW.status='failed' THEN
    UPDATE public.nexus_beta_observations
       SET status='FAILED',summary=left(coalesce(NEW.error_code,'observer_worker_failed'),1200),updated_at=now()
     WHERE id=v_obs;
    RETURN NEW;
  END IF;

  v_raw:=trim(coalesce(NEW.output_summary,''));
  v_raw:=regexp_replace(v_raw,'^```json\s*','','i');
  v_raw:=regexp_replace(v_raw,'^```\s*','','i');
  v_raw:=regexp_replace(v_raw,'\s*```$','','i');

  BEGIN
    v_json:=v_raw::jsonb;
  EXCEPTION WHEN OTHERS THEN
    UPDATE public.nexus_beta_observations
       SET status='FAILED',summary='Risposta observer non JSON',updated_at=now(),
           metadata=metadata||jsonb_build_object('job_id',NEW.id,'parse_error',true)
     WHERE id=v_obs;
    RETURN NEW;
  END;

  v_action:=lower(coalesce(v_json->>'action','ignore'));
  v_kind:=lower(coalesce(v_json->>'kind','other'));
  BEGIN v_conf:=greatest(0,least(1,(v_json->>'confidence')::numeric)); EXCEPTION WHEN OTHERS THEN v_conf:=0; END;

  IF v_action='ticket' AND v_conf>=0.65 THEN
    PERFORM public.nexus_beta_create_ticket_from_observation_internal(v_obs,v_json);
  ELSIF v_action='ticket' THEN
    UPDATE public.nexus_beta_observations
       SET observation_type=CASE WHEN v_kind IN ('bug','suggestion','ux','performance','model','other') THEN v_kind ELSE 'other' END,
           status='TRIAGED',summary=left(coalesce(v_json->>'summary','Bassa confidenza: revisione Admin richiesta.'),1200),
           confidence=v_conf,updated_at=now()
     WHERE id=v_obs;
  ELSE
    UPDATE public.nexus_beta_observations
       SET observation_type='normal_chat',status='DISMISSED',
           summary=left(coalesce(v_json->>'summary','Conversazione normale.'),1200),
           confidence=v_conf,updated_at=now()
     WHERE id=v_obs;
  END IF;

  RETURN NEW;
END
$function$;


DROP TRIGGER IF EXISTS nexus_beta_apply_observer_job_trg ON public.nexus_jobs;
CREATE TRIGGER nexus_beta_apply_observer_job_trg
AFTER UPDATE OF status ON public.nexus_jobs
FOR EACH ROW EXECUTE FUNCTION public.nexus_beta_apply_observer_job();


CREATE OR REPLACE FUNCTION public.nexus_beta_capture_message_observation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_role text; v_owner uuid; v_obs uuid;
BEGIN
  IF NEW.role <> 'user' THEN RETURN NEW; END IF;
  IF coalesce(NEW.metadata->>'actor_type','') IN ('ceo','admin','system','nexus_ai') THEN RETURN NEW; END IF;
  SELECT c.user_id INTO v_owner FROM public.nexus_conversations c WHERE c.id=NEW.conversation_id;
  IF v_owner IS NULL OR v_owner<>NEW.user_id THEN RETURN NEW; END IF;
  SELECT s.role INTO v_role FROM public.nexus_staff_accounts s WHERE s.user_id=v_owner;
  IF v_role IS DISTINCT FROM 'beta_tester' THEN RETURN NEW; END IF;
  INSERT INTO public.nexus_beta_observations(beta_user_id,conversation_id,source_message_id,metadata)
  VALUES(v_owner,NEW.conversation_id,NEW.id,jsonb_build_object('source','beta_workspace_chat','content_length',length(coalesce(NEW.content,'')),'has_message',length(trim(coalesce(NEW.content,'')))>0))
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_obs;

  IF v_obs IS NOT NULL THEN
    BEGIN
      PERFORM public.nexus_beta_observation_enqueue_internal(v_obs);
    EXCEPTION WHEN OTHERS THEN
      UPDATE public.nexus_beta_observations
         SET status='FAILED',summary='Impossibile accodare Beta Observer',updated_at=now()
       WHERE id=v_obs;
    END;
  END IF;
  RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS nexus_beta_capture_message_observation_trg ON public.nexus_messages;
CREATE TRIGGER nexus_beta_capture_message_observation_trg AFTER INSERT ON public.nexus_messages FOR EACH ROW EXECUTE FUNCTION public.nexus_beta_capture_message_observation();

CREATE OR REPLACE FUNCTION public.nexus_beta_admin_list_conversations(p_limit integer DEFAULT 100)
RETURNS TABLE(conversation_id uuid,beta_user_id uuid,beta_name text,beta_email text,title text,level text,created_at timestamptz,updated_at timestamptz,message_count bigint,attachment_count bigint,open_observation_count bigint,last_message_at timestamptz,last_message_preview text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_admin uuid; v_limit integer;
BEGIN
  v_admin:=(auth.user_id())::uuid;
  IF v_admin IS NULL OR NOT public.nexus_is_owner(v_admin) THEN RAISE EXCEPTION 'admin_required'; END IF;
  v_limit:=greatest(1,least(coalesce(p_limit,100),300));
  RETURN QUERY
  SELECT c.id,c.user_id,coalesce(p.display_name,u.name,u.email,'Beta tester')::text,u.email::text,c.title,c.level,c.created_at,c.updated_at,
    (SELECT count(*) FROM public.nexus_messages m WHERE m.conversation_id=c.id),
    (SELECT count(*) FROM public.nexus_attachments a WHERE a.conversation_id=c.id AND a.status<>'deleted'),
    (SELECT count(*) FROM public.nexus_beta_observations o WHERE o.conversation_id=c.id AND o.status IN ('NEW','CLASSIFYING','TRIAGED')),
    lm.created_at,left(coalesce(lm.content,''),320)
  FROM public.nexus_conversations c
  JOIN public.nexus_staff_accounts s ON s.user_id=c.user_id AND s.role='beta_tester'
  JOIN neon_auth."user" u ON u.id=c.user_id
  LEFT JOIN public.nexus_profiles p ON p.user_id=c.user_id
  LEFT JOIN LATERAL (SELECT m.content,m.created_at FROM public.nexus_messages m WHERE m.conversation_id=c.id ORDER BY m.created_at DESC,m.id DESC LIMIT 1) lm ON true
  WHERE NOT c.archived
  ORDER BY c.updated_at DESC
  LIMIT v_limit;
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_beta_admin_get_conversation(p_conversation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_admin uuid; v_beta uuid; v_conv jsonb; v_messages jsonb; v_attachments jsonb; v_obs jsonb;
BEGIN
  v_admin:=(auth.user_id())::uuid;
  IF v_admin IS NULL OR NOT public.nexus_is_owner(v_admin) THEN RAISE EXCEPTION 'admin_required'; END IF;
  SELECT c.user_id,jsonb_build_object('id',c.id,'user_id',c.user_id,'title',c.title,'level',c.level,'created_at',c.created_at,'updated_at',c.updated_at,'beta_name',coalesce(p.display_name,u.name,u.email,'Beta tester'),'beta_email',u.email,'privacy_mode','qa_monitored','privacy_notice','Workspace Beta monitorato da NEXUS AI e Owner per finalità QA.')
  INTO v_beta,v_conv
  FROM public.nexus_conversations c
  JOIN public.nexus_staff_accounts s ON s.user_id=c.user_id AND s.role='beta_tester'
  JOIN neon_auth."user" u ON u.id=c.user_id
  LEFT JOIN public.nexus_profiles p ON p.user_id=c.user_id
  WHERE c.id=p_conversation_id;
  IF v_beta IS NULL THEN RAISE EXCEPTION 'beta_conversation_not_found'; END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object('id',m.id,'role',m.role,'content',m.content,'metadata',m.metadata,'created_at',m.created_at,'writer_user_id',coalesce(m.actor_user_id,m.user_id),'actor_type',coalesce(m.metadata->>'actor_type',CASE WHEN m.role='assistant' THEN 'nexus_ai' WHEN m.role='system' THEN 'system' ELSE 'beta' END),'visible_label',coalesce(m.metadata->>'visible_label',CASE WHEN m.role='assistant' THEN 'NEXUS AI' WHEN m.role='system' THEN 'SYSTEM' ELSE 'BETA' END)) ORDER BY m.created_at,m.id),'[]'::jsonb)
  INTO v_messages FROM public.nexus_messages m WHERE m.conversation_id=p_conversation_id;

  SELECT coalesce(jsonb_agg(jsonb_build_object('id',a.id,'filename',a.filename,'mime_type',a.mime_type,'size_bytes',a.size_bytes,'status',a.status,'job_id',a.job_id,'created_at',a.created_at) ORDER BY a.created_at,a.id),'[]'::jsonb)
  INTO v_attachments FROM public.nexus_attachments a WHERE a.conversation_id=p_conversation_id AND a.status<>'deleted';

  SELECT coalesce(jsonb_agg(jsonb_build_object('id',o.id,'source_message_id',o.source_message_id,'source_attachment_id',o.source_attachment_id,'observation_type',o.observation_type,'status',o.status,'summary',o.summary,'confidence',o.confidence,'linked_ticket_id',o.linked_ticket_id,'triage_job_id',o.triage_job_id,'created_at',o.created_at,'updated_at',o.updated_at) ORDER BY o.created_at,o.id),'[]'::jsonb)
  INTO v_obs FROM public.nexus_beta_observations o WHERE o.conversation_id=p_conversation_id;

  RETURN jsonb_build_object('conversation',v_conv,'messages',v_messages,'attachments',v_attachments,'observations',v_obs);
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_beta_admin_intervene(p_conversation_id uuid,p_content text,p_request_ai boolean DEFAULT true)
RETURNS TABLE(message_id uuid,job_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_admin uuid; v_beta uuid; v_level text; v_message uuid; v_job uuid; v_prompt text;
BEGIN
  v_admin:=(auth.user_id())::uuid;
  IF v_admin IS NULL OR NOT public.nexus_is_owner(v_admin) THEN RAISE EXCEPTION 'admin_required'; END IF;
  IF length(trim(coalesce(p_content,'')))<1 THEN RAISE EXCEPTION 'message_required'; END IF;
  IF length(p_content)>12000 THEN RAISE EXCEPTION 'message_too_large_12000'; END IF;
  SELECT c.user_id,c.level INTO v_beta,v_level FROM public.nexus_conversations c JOIN public.nexus_staff_accounts s ON s.user_id=c.user_id AND s.role='beta_tester' WHERE c.id=p_conversation_id AND NOT c.archived;
  IF v_beta IS NULL THEN RAISE EXCEPTION 'beta_conversation_not_found'; END IF;
  INSERT INTO public.nexus_messages(conversation_id,user_id,actor_user_id,role,content,metadata)
  VALUES(p_conversation_id,v_beta,v_admin,'user',left(trim(p_content),12000),jsonb_build_object('actor_type','ceo','visible_label','CEO','admin_intervention',true,'conversation_owner_user_id',v_beta))
  RETURNING id INTO v_message;
  UPDATE public.nexus_conversations SET updated_at=now() WHERE id=p_conversation_id;
  IF coalesce(p_request_ai,true) THEN
    v_prompt:=left('Sei NEXUS AI dentro una conversazione Beta supervisionata. Il CEO è intervenuto nel thread del beta tester. Rispondi al CEO mantenendo il contesto; non impersonare il beta. Se emerge un problema o miglioramento, distingui diagnosi/proposta da una modifica realmente eseguita. MESSAGGIO CEO: '||trim(p_content),11900);
    INSERT INTO public.nexus_jobs(user_id,conversation_id,kind,level,status,priority,estimated_credits,charged_credits,input_summary,execution_metadata)
    VALUES(v_beta,p_conversation_id,'general_file',CASE WHEN v_level='deep' THEN 'deep' ELSE 'free' END,'queued',100,0,0,'[CHAT_LOCAL] '||v_prompt,jsonb_build_object('internal',true,'internal_type','beta_ceo_intervention','admin_user_id',v_admin,'beta_user_id',v_beta,'ceo_message_id',v_message))
    RETURNING id INTO v_job;
  END IF;
  RETURN QUERY SELECT v_message,v_job;
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_beta_apply_ceo_intervention_job()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_beta uuid; v_conv uuid;
BEGIN
  IF coalesce(NEW.execution_metadata->>'internal_type','')<>'beta_ceo_intervention' THEN RETURN NEW; END IF;
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status NOT IN ('completed','failed') THEN RETURN NEW; END IF;
  BEGIN v_beta:=(NEW.execution_metadata->>'beta_user_id')::uuid; EXCEPTION WHEN OTHERS THEN RETURN NEW; END;
  v_conv:=NEW.conversation_id;
  IF v_beta IS NULL OR v_conv IS NULL THEN RETURN NEW; END IF;
  IF NEW.status='completed' AND length(trim(coalesce(NEW.output_summary,'')))>0 THEN
    INSERT INTO public.nexus_messages(conversation_id,user_id,role,content,metadata)
    VALUES(v_conv,v_beta,'assistant',left(NEW.output_summary,20000),jsonb_build_object('actor_type','nexus_ai','visible_label','NEXUS AI','job_id',NEW.id,'source','ceo_intervention'));
    UPDATE public.nexus_conversations SET updated_at=now() WHERE id=v_conv;
  ELSIF NEW.status='failed' THEN
    INSERT INTO public.nexus_messages(conversation_id,user_id,role,content,metadata)
    VALUES(v_conv,v_beta,'system','NEXUS non è riuscita a elaborare l’intervento CEO. Il messaggio CEO resta comunque nel thread.',jsonb_build_object('actor_type','system','visible_label','SYSTEM','job_id',NEW.id,'error_code',NEW.error_code));
    UPDATE public.nexus_conversations SET updated_at=now() WHERE id=v_conv;
  END IF;
  RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS nexus_beta_apply_ceo_intervention_job_trg ON public.nexus_jobs;
CREATE TRIGGER nexus_beta_apply_ceo_intervention_job_trg AFTER UPDATE OF status ON public.nexus_jobs FOR EACH ROW EXECUTE FUNCTION public.nexus_beta_apply_ceo_intervention_job();

-- Do NOT enqueue BETA_OBSERVER jobs until the worker explicitly supports that route.
-- Production Beta Live already supports BETA_TRIAGE for explicit tickets.