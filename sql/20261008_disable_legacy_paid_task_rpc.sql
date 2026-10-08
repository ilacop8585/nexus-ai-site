-- Security follow-up after NEXUS guarded text-task RPC shipped.
-- Older cached clients must refresh before purchasing a text task.
-- Reject unapproved text-task reservations rather than charge against a missing/failed quote.
-- SECURITY DEFINER public.nexus_create_text_task_checked remains callable by authenticated
-- and internally invokes nexus_create_text_task using the privileged function owner.
REVOKE EXECUTE ON FUNCTION public.nexus_create_text_task(uuid,text,text,text) FROM authenticated;
