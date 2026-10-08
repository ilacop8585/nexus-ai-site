-- Server-enforced price confirmation is live on the website.
-- Disable the obsolete direct file-job reservation API for regular users.
-- Privileged worker / function owner keeps access through SECURITY DEFINER.
-- Older cached browser tabs must refresh before submitting a file job.
REVOKE EXECUTE ON FUNCTION public.nexus_create_job(uuid,text,text,uuid[],text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.nexus_create_job(uuid,text,text,uuid[],text) FROM authenticated;
