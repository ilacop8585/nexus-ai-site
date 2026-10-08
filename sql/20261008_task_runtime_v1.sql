-- NEXUS Task Runtime V1
-- Append-only task timeline driven by the real nexus_jobs state machine.

CREATE TABLE IF NOT EXISTS public.nexus_task_events (
  id bigserial PRIMARY KEY,
  job_id uuid NOT NULL REFERENCES public.nexus_jobs(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES neon_auth."user"(id) ON DELETE CASCADE,
  event_type text NOT NULL CHECK(length(event_type) BETWEEN 1 AND 80),
  phase text NULL CHECK(phase IS NULL OR length(phase) <= 80),
  title text NOT NULL CHECK(length(title) BETWEEN 1 AND 320),
  detail text NOT NULL DEFAULT '' CHECK(length(detail) <= 4000),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS nexus_task_events_job_created_idx
  ON public.nexus_task_events(job_id,created_at,id);

CREATE INDEX IF NOT EXISTS nexus_task_events_user_created_idx
  ON public.nexus_task_events(user_id,created_at DESC);

ALTER TABLE public.nexus_task_events ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.nexus_task_runtime_job_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_mode text;
  v_plan jsonb;
  v_title text;
  v_detail text;
  v_event text;
  v_phase text;
BEGIN
  IF TG_OP='INSERT' THEN
    v_mode:=coalesce(NEW.execution_metadata->>'execution_mode',
      CASE
        WHEN NEW.kind='code_task' THEN 'code'
        WHEN NEW.input_summary LIKE '[TEXT_TASK WORK] %' THEN 'work'
        WHEN NEW.input_summary LIKE '[TEXT_TASK AGENT] %' THEN 'agent'
        WHEN NEW.input_summary LIKE '[TEXT_TASK CODE] %' THEN 'code'
        ELSE 'task'
      END
    );

    INSERT INTO public.nexus_task_events(
      job_id,user_id,event_type,phase,title,detail,metadata,created_at
    )
    VALUES(
      NEW.id,NEW.user_id,'task_created','plan',
      'Task created',
      'NEXUS accepted the work and created a tracked execution.',
      jsonb_build_object(
        'mode',v_mode,
        'kind',NEW.kind,
        'level',NEW.level,
        'estimated_credits',NEW.estimated_credits
      ),
      NEW.created_at
    );

    v_plan:=jsonb_build_array(
      jsonb_build_object('key','understand','title','Understand request','status','pending'),
      jsonb_build_object('key','execute','title',
        CASE v_mode WHEN 'code' THEN 'Implement / analyse code'
                    WHEN 'work' THEN 'Execute multi-step work'
                    WHEN 'agent' THEN 'Execute agent task'
                    ELSE 'Process task' END,
        'status','pending'),
      jsonb_build_object('key','quality','title','Quality check','status','pending'),
      jsonb_build_object('key','deliver','title','Deliver result','status','pending')
    );

    INSERT INTO public.nexus_task_events(
      job_id,user_id,event_type,phase,title,detail,metadata,created_at
    )
    VALUES(
      NEW.id,NEW.user_id,'plan_created','plan',
      'Execution plan',
      'NEXUS created the initial task plan.',
      jsonb_build_object('steps',v_plan,'mode',v_mode),
      NEW.created_at + interval '1 millisecond'
    );

    RETURN NEW;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    v_event:=CASE NEW.status
      WHEN 'queued' THEN 'task_queued'
      WHEN 'claimed' THEN 'task_claimed'
      WHEN 'running' THEN 'task_running'
      WHEN 'qa' THEN 'task_qa'
      WHEN 'completed' THEN 'task_completed'
      WHEN 'failed' THEN 'task_failed'
      WHEN 'cancelled' THEN 'task_cancelled'
      ELSE 'task_status_changed'
    END;

    v_phase:=CASE NEW.status
      WHEN 'queued' THEN 'queue'
      WHEN 'claimed' THEN 'queue'
      WHEN 'running' THEN 'execute'
      WHEN 'qa' THEN 'quality'
      WHEN 'completed' THEN 'deliver'
      WHEN 'failed' THEN 'error'
      WHEN 'cancelled' THEN 'cancelled'
      ELSE 'status'
    END;

    v_title:=CASE NEW.status
      WHEN 'queued' THEN 'Waiting in queue'
      WHEN 'claimed' THEN 'Worker assigned'
      WHEN 'running' THEN 'Execution started'
      WHEN 'qa' THEN 'Quality check'
      WHEN 'completed' THEN 'Task completed'
      WHEN 'failed' THEN 'Task failed'
      WHEN 'cancelled' THEN 'Task cancelled'
      ELSE 'Status changed to '||NEW.status
    END;

    v_detail:=CASE NEW.status
      WHEN 'queued' THEN 'The task is waiting for compatible compute.'
      WHEN 'claimed' THEN 'A NEXUS worker claimed the task.'
      WHEN 'running' THEN 'NEXUS is actively processing the task.'
      WHEN 'qa' THEN 'The result is undergoing quality checks.'
      WHEN 'completed' THEN 'The task finished and the result is available.'
      WHEN 'failed' THEN coalesce(nullif(NEW.error_code,''),'The task failed during execution.')
      WHEN 'cancelled' THEN 'The task was cancelled.'
      ELSE 'Task state changed.'
    END;

    INSERT INTO public.nexus_task_events(
      job_id,user_id,event_type,phase,title,detail,metadata
    )
    VALUES(
      NEW.id,NEW.user_id,v_event,v_phase,v_title,v_detail,
      jsonb_strip_nulls(jsonb_build_object(
        'from_status',OLD.status,
        'to_status',NEW.status,
        'worker_id',NEW.worker_id,
        'error_code',NEW.error_code,
        'charged_credits',NEW.charged_credits,
        'completed_at',NEW.completed_at
      ))
    );
  END IF;

  RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS nexus_task_runtime_job_insert_trg ON public.nexus_jobs;
CREATE TRIGGER nexus_task_runtime_job_insert_trg
AFTER INSERT ON public.nexus_jobs
FOR EACH ROW EXECUTE FUNCTION public.nexus_task_runtime_job_event();

DROP TRIGGER IF EXISTS nexus_task_runtime_job_status_trg ON public.nexus_jobs;
CREATE TRIGGER nexus_task_runtime_job_status_trg
AFTER UPDATE OF status ON public.nexus_jobs
FOR EACH ROW EXECUTE FUNCTION public.nexus_task_runtime_job_event();

CREATE OR REPLACE FUNCTION public.nexus_task_timeline(p_job_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_user uuid;
  v_job public.nexus_jobs%ROWTYPE;
  v_events jsonb;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO v_job
  FROM public.nexus_jobs
  WHERE id=p_job_id AND user_id=v_user;

  IF v_job.id IS NULL THEN RAISE EXCEPTION 'task_not_found'; END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',e.id,
    'event_type',e.event_type,
    'phase',e.phase,
    'title',e.title,
    'detail',e.detail,
    'metadata',e.metadata,
    'created_at',e.created_at
  ) ORDER BY e.created_at,e.id),'[]'::jsonb)
  INTO v_events
  FROM public.nexus_task_events e
  WHERE e.job_id=v_job.id AND e.user_id=v_user;

  RETURN jsonb_build_object(
    'job',jsonb_build_object(
      'id',v_job.id,
      'conversation_id',v_job.conversation_id,
      'kind',v_job.kind,
      'level',v_job.level,
      'status',v_job.status,
      'estimated_credits',v_job.estimated_credits,
      'charged_credits',v_job.charged_credits,
      'input_summary',regexp_replace(coalesce(v_job.input_summary,''),'^\\[TEXT_TASK (AGENT|WORK|CODE)\\]\\s*','','i'),
      'output_summary',v_job.output_summary,
      'error_code',v_job.error_code,
      'worker_id',v_job.worker_id,
      'project_id',v_job.project_id,
      'agent_id',v_job.agent_id,
      'routing_profile',v_job.routing_profile,
      'approval_policy',v_job.approval_policy,
      'execution_metadata',v_job.execution_metadata,
      'created_at',v_job.created_at,
      'completed_at',v_job.completed_at
    ),
    'events',v_events
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_task_event_emit(
  p_job_id uuid,
  p_event_type text,
  p_phase text,
  p_title text,
  p_detail text DEFAULT '',
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid;v_id bigint;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.nexus_jobs j WHERE j.id=p_job_id AND j.user_id=v_user
  ) THEN RAISE EXCEPTION 'task_not_found'; END IF;

  IF length(trim(coalesce(p_event_type,'')))<1 THEN RAISE EXCEPTION 'event_type_required'; END IF;
  IF length(trim(coalesce(p_title,'')))<1 THEN RAISE EXCEPTION 'event_title_required'; END IF;

  INSERT INTO public.nexus_task_events(
    job_id,user_id,event_type,phase,title,detail,metadata
  )
  VALUES(
    p_job_id,v_user,left(trim(p_event_type),80),left(nullif(trim(coalesce(p_phase,'')),''),80),
    left(trim(p_title),320),left(coalesce(p_detail,''),4000),coalesce(p_metadata,'{}'::jsonb)
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END
$function$;

REVOKE ALL ON TABLE public.nexus_task_events FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_task_timeline(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_task_event_emit(uuid,text,text,text,text,jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.nexus_task_timeline(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_task_event_emit(uuid,text,text,text,text,jsonb) TO authenticated;
