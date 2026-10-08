-- User-approved file/job reservations, compatible with existing NEXUS job system.
-- Quote is recalculated from actually uploaded, account-owned attachment sizes.
-- No purchase on missing or mismatched approval.
CREATE OR REPLACE FUNCTION public.nexus_create_job_checked(
  p_conversation_id uuid,
  p_kind text,
  p_level text,
  p_attachment_ids uuid[],
  p_summary text,
  p_approved_credits integer
)
RETURNS TABLE(job_id uuid,status text,estimated_credits integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_user uuid;
  v_internal boolean;
  v_expected integer;
  v_owned integer;
  v_total_bytes bigint;
  v_kind text;
  v_level text;
  v_quote integer;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.nexus_conversations c
    WHERE c.id=p_conversation_id AND c.user_id=v_user
  ) THEN RAISE EXCEPTION 'conversation_not_owned'; END IF;

  v_expected:=coalesce(array_length(p_attachment_ids,1),0);
  IF v_expected>5 OR (v_expected<1 AND p_kind<>'foundry_build')
    THEN RAISE EXCEPTION 'attachments_required_or_invalid'; END IF;

  SELECT count(*),coalesce(sum(a.size_bytes),0)
  INTO v_owned,v_total_bytes
  FROM public.nexus_attachments a
  WHERE a.id=ANY(p_attachment_ids)
    AND a.user_id=v_user AND a.status='uploaded' AND a.job_id IS NULL;
  IF v_owned<>v_expected THEN RAISE EXCEPTION 'attachment_not_owned_or_unavailable'; END IF;

  v_kind:=CASE
    WHEN p_kind='foundry_build' THEN 'foundry_build'
    WHEN p_kind IN ('image_edit','video_edit','audio_task','document_task','code_task','archive_task','general_file') THEN p_kind
    ELSE 'general_file'
  END;
  v_level:=CASE WHEN p_level IN ('free','smart','deep') THEN p_level ELSE 'free' END;
  v_quote:=public.nexus_quote_job_credits(v_kind,v_level,v_total_bytes,v_expected);
  IF v_quote IS NULL OR v_quote<=0 THEN RAISE EXCEPTION 'quote_unavailable'; END IF;

  v_internal:=public.nexus_is_internal_qa(v_user);
  IF v_internal THEN
    IF p_approved_credits IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'quote_changed_retry'; END IF;
  ELSE
    IF p_approved_credits IS DISTINCT FROM v_quote THEN RAISE EXCEPTION 'quote_changed_retry'; END IF;
  END IF;

  RETURN QUERY
  SELECT j.job_id,j.status,j.estimated_credits
  FROM public.nexus_create_job(
    p_conversation_id,p_kind,p_level,p_attachment_ids,p_summary
  ) j;
END
$function$;

REVOKE ALL ON FUNCTION public.nexus_create_job_checked(uuid,text,text,uuid[],text,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nexus_create_job_checked(uuid,text,text,uuid[],text,integer) TO authenticated;
