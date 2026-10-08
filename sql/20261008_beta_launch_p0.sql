-- NEXUS Beta Launch P0
-- Real execution modes + paid text tasks. Additive and backward compatible.

CREATE TABLE IF NOT EXISTS public.nexus_user_execution_settings (
  user_id uuid PRIMARY KEY REFERENCES neon_auth."user"(id) ON DELETE CASCADE,
  default_mode text NOT NULL DEFAULT 'auto'
    CHECK(default_mode IN ('auto','chat','agent','work','code')),
  agent_effort text NOT NULL DEFAULT 'smart'
    CHECK(agent_effort IN ('smart','deep')),
  work_effort text NOT NULL DEFAULT 'smart'
    CHECK(work_effort IN ('smart','deep')),
  code_effort text NOT NULL DEFAULT 'smart'
    CHECK(code_effort IN ('smart','deep')),
  auto_escalate boolean NOT NULL DEFAULT true,
  response_style text NOT NULL DEFAULT 'balanced'
    CHECK(response_style IN ('concise','balanced','detailed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.nexus_user_execution_settings ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.nexus_execution_settings_get()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid;v_row public.nexus_user_execution_settings%ROWTYPE;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  INSERT INTO public.nexus_user_execution_settings(user_id)
  VALUES(v_user)
  ON CONFLICT(user_id) DO NOTHING;

  SELECT * INTO v_row
  FROM public.nexus_user_execution_settings
  WHERE user_id=v_user;

  RETURN to_jsonb(v_row)-'user_id';
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_execution_settings_save(
  p_default_mode text,
  p_agent_effort text,
  p_work_effort text,
  p_code_effort text,
  p_auto_escalate boolean,
  p_response_style text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid;v_row public.nexus_user_execution_settings%ROWTYPE;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  IF p_default_mode NOT IN ('auto','chat','agent','work','code') THEN RAISE EXCEPTION 'invalid_default_mode'; END IF;
  IF p_agent_effort NOT IN ('smart','deep') THEN RAISE EXCEPTION 'invalid_agent_effort'; END IF;
  IF p_work_effort NOT IN ('smart','deep') THEN RAISE EXCEPTION 'invalid_work_effort'; END IF;
  IF p_code_effort NOT IN ('smart','deep') THEN RAISE EXCEPTION 'invalid_code_effort'; END IF;
  IF p_response_style NOT IN ('concise','balanced','detailed') THEN RAISE EXCEPTION 'invalid_response_style'; END IF;

  INSERT INTO public.nexus_user_execution_settings(
    user_id,default_mode,agent_effort,work_effort,code_effort,auto_escalate,response_style,updated_at
  )
  VALUES(
    v_user,p_default_mode,p_agent_effort,p_work_effort,p_code_effort,coalesce(p_auto_escalate,true),p_response_style,now()
  )
  ON CONFLICT(user_id) DO UPDATE SET
    default_mode=excluded.default_mode,
    agent_effort=excluded.agent_effort,
    work_effort=excluded.work_effort,
    code_effort=excluded.code_effort,
    auto_escalate=excluded.auto_escalate,
    response_style=excluded.response_style,
    updated_at=now()
  RETURNING * INTO v_row;

  RETURN to_jsonb(v_row)-'user_id';
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_quote_text_task_credits(p_mode text,p_level text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT public.nexus_quote_job_credits(
    CASE WHEN p_mode='code' THEN 'code_task' ELSE 'general_file' END,
    CASE WHEN p_level='deep' THEN 'deep' ELSE 'smart' END,
    0,
    1
  )
$function$;

CREATE OR REPLACE FUNCTION public.nexus_create_text_task(
  p_conversation_id uuid,
  p_mode text,
  p_level text,
  p_prompt text
)
RETURNS TABLE(job_id uuid,status text,estimated_credits integer,resolved_level text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_user uuid;
  v_job uuid;
  v_mode text;
  v_level text;
  v_kind text;
  v_est integer;
  v_balance integer;
  v_internal boolean;
  v_active integer;
  v_today integer;
  v_active_limit integer;
  v_daily_limit integer;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  IF NOT EXISTS(
    SELECT 1 FROM public.nexus_conversations c
    WHERE c.id=p_conversation_id AND c.user_id=v_user
  ) THEN RAISE EXCEPTION 'conversation_not_owned'; END IF;

  v_mode:=lower(trim(coalesce(p_mode,'')));
  IF v_mode NOT IN ('agent','work','code') THEN RAISE EXCEPTION 'invalid_text_task_mode'; END IF;

  v_level:=CASE WHEN p_level='deep' THEN 'deep' ELSE 'smart' END;
  v_kind:=CASE WHEN v_mode='code' THEN 'code_task' ELSE 'general_file' END;

  IF length(trim(coalesce(p_prompt,'')))<1 THEN RAISE EXCEPTION 'prompt_required'; END IF;
  IF length(p_prompt)>12000 THEN RAISE EXCEPTION 'prompt_too_large_12000'; END IF;

  v_internal:=public.nexus_is_internal_qa(v_user);
  v_active_limit:=CASE WHEN v_internal THEN 10 ELSE 3 END;
  v_daily_limit:=CASE WHEN v_internal THEN 100 ELSE 20 END;

  SELECT count(*) INTO v_active
  FROM public.nexus_jobs j
  WHERE j.user_id=v_user AND j.status IN ('queued','claimed','running','qa');
  IF v_active>=v_active_limit THEN RAISE EXCEPTION 'active_job_limit_%',v_active_limit; END IF;

  SELECT count(*) INTO v_today
  FROM public.nexus_jobs j
  WHERE j.user_id=v_user AND j.created_at>now()-interval '24 hours';
  IF v_today>=v_daily_limit THEN RAISE EXCEPTION 'daily_job_limit_%',v_daily_limit; END IF;

  v_est:=public.nexus_quote_text_task_credits(v_mode,v_level);

  SELECT p.credits_balance INTO v_balance
  FROM public.nexus_profiles p
  WHERE p.user_id=v_user
  FOR UPDATE;
  IF v_balance IS NULL THEN RAISE EXCEPTION 'profile_not_found'; END IF;
  IF NOT v_internal AND v_balance<v_est THEN RAISE EXCEPTION 'insufficient_credits'; END IF;

  INSERT INTO public.nexus_jobs(
    user_id,conversation_id,kind,level,status,priority,
    estimated_credits,charged_credits,input_summary,execution_metadata
  )
  VALUES(
    v_user,p_conversation_id,v_kind,v_level,'queued',
    CASE WHEN v_internal THEN 95 ELSE 80 END,
    v_est,CASE WHEN v_internal THEN 0 ELSE v_est END,
    '[TEXT_TASK '||upper(v_mode)||'] '||left(p_prompt,11950),
    jsonb_build_object('execution_mode',v_mode,'billing_class','text_task')
  )
  RETURNING id INTO v_job;

  IF v_internal THEN
    INSERT INTO public.nexus_credit_ledger(user_id,delta,reason,job_id,balance_after)
    VALUES(v_user,0,'qa_unlimited:text_task_reserve',v_job,v_balance);
  ELSE
    UPDATE public.nexus_profiles
    SET credits_balance=credits_balance-v_est,updated_at=now()
    WHERE user_id=v_user;

    INSERT INTO public.nexus_credit_ledger(user_id,delta,reason,job_id,balance_after)
    VALUES(v_user,-v_est,'text_task_reserve',v_job,v_balance-v_est);
  END IF;

  RETURN QUERY SELECT v_job,'queued'::text,v_est,v_level;
END
$function$;

REVOKE ALL ON TABLE public.nexus_user_execution_settings FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_execution_settings_get() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_execution_settings_save(text,text,text,text,boolean,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_create_text_task(uuid,text,text,text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.nexus_execution_settings_get() TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_execution_settings_save(text,text,text,text,boolean,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_create_text_task(uuid,text,text,text) TO authenticated;
