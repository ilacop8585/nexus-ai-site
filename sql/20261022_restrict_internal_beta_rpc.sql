-- 2026-10-22: restrict internal Beta Observer RPC entry points.
-- These SECURITY DEFINER functions are invoked internally by database
-- triggers/functions. They must not be callable directly by web roles.
-- Authorization was not yet verifiable in production: Neon quota blocked
-- database inspection. Apply only after a backup and inspect current ACLs.
--
-- Non-destructive: changes function EXECUTE permissions only.
-- Does not modify user records, credits, job status, or other data.
BEGIN;

REVOKE ALL ON FUNCTION public.nexus_beta_observation_enqueue_internal(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_beta_create_ticket_from_observation_internal(uuid,jsonb) FROM PUBLIC;

DO $restrict_web_roles$
DECLARE
  r text;
BEGIN
  FOR r IN
    SELECT rolname
    FROM pg_roles
    WHERE rolname IN ('authenticated','anon','anonymous')
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.nexus_beta_observation_enqueue_internal(uuid) FROM %I',r);
    EXECUTE format('REVOKE ALL ON FUNCTION public.nexus_beta_create_ticket_from_observation_internal(uuid,jsonb) FROM %I',r);
  END LOOP;
END;
$restrict_web_roles$;

COMMIT;

-- Production verification after applying (read-only):
-- SELECT p.proname,
--        p.proacl,
--        has_function_privilege('authenticated',p.oid,'EXECUTE') AS auth_can_execute
-- FROM pg_proc p
-- JOIN pg_namespace n ON n.oid=p.pronamespace
-- WHERE n.nspname='public'
--   AND p.proname IN (
--     'nexus_beta_observation_enqueue_internal',
--     'nexus_beta_create_ticket_from_observation_internal'
--   );
-- A negative auth_can_execute result is required for the web role.
