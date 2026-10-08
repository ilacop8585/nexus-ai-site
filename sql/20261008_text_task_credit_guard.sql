-- NEXUS P0: fail-closed credit reservation; additive guarded task RPC.
-- Client supplies the exact approved credit estimate, or zero for server-verified unlimited QA.
-- Never charge when a quote is missing, stale or inconsistent.
CREATE OR REPLACE FUNCTION public.nexus_create_text_task_checked(
  p_conversation_id uuid,
  p_mode text,
  p_level text,
  p_prompt text,
  p_approved_credits integer
)
RETURNS TABLE(job_id uuid,status text,estimated_credits integer,resolved_level text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_user uuid;
  v_quote integer;
  v_internal boolean;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_mode NOT IN ('agent','work','code') THEN RAISE EXCEPTION 'invalid_text_task_mode'; END IF;
  IF p_level NOT IN ('smart','deep') THEN RAISE EXCEPTION 'invalid_text_task_level'; END IF;
  v_quote:=public.nexus_quote_text_task_credits(p_mode,p_level);
  IF v_quote IS NULL OR v_quote<=0 THEN RAISE EXCEPTION 'quote_unavailable'; END IF;

  v_internal:=public.nexus_is_internal_qa(v_user);
  IF v_internal THEN
    IF p_approved_credits IS DISTINCT FROM 0
      THEN RAISE EXCEPTION 'quote_changed_retry'; END IF;
  ELSE
    IF p_approved_credits IS DISTINCT FROM v_quote
      THEN RAISE EXCEPTION 'quote_changed_retry'; END IF;
  END IF;

  RETURN QUERY
  SELECT t.job_id,t.status,t.estimated_credits,t.resolved_level
  FROM public.nexus_create_text_task(
    p_conversation_id,p_mode,p_level,p_prompt
  ) t;
END
$function$;

REVOKE ALL ON FUNCTION public.nexus_create_text_task_checked(uuid,text,text,text,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nexus_create_text_task_checked(uuid,text,text,text,integer) TO authenticated;
