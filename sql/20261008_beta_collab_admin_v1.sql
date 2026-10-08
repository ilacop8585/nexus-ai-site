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

CREATE OR REPLACE FUNCTION public.nexus_beta_capture_message_observation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_role text; v_owner uuid;
BEGIN
  IF NEW.role <> 'user' THEN RETURN NEW; END IF;
  IF coalesce(NEW.metadata->>'actor_type','') IN ('ceo','admin','system','nexus_ai') THEN RETURN NEW; END IF;
  SELECT c.user_id INTO v_owner FROM public.nexus_conversations c WHERE c.id=NEW.conversation_id;
  IF v_owner IS NULL OR v_owner<>NEW.user_id THEN RETURN NEW; END IF;
  SELECT s.role INTO v_role FROM public.nexus_staff_accounts s WHERE s.user_id=v_owner;
  IF v_role IS DISTINCT FROM 'beta_tester' THEN RETURN NEW; END IF;
  INSERT INTO public.nexus_beta_observations(beta_user_id,conversation_id,source_message_id,metadata)
  VALUES(v_owner,NEW.conversation_id,NEW.id,jsonb_build_object('source','beta_workspace_chat','content_length',length(coalesce(NEW.content,'')),'has_message',length(trim(coalesce(NEW.content,'')))>0))
  ON CONFLICT DO NOTHING;
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