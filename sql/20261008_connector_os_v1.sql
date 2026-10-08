-- NEXUS Connector OS V1
-- Metadata and grants only. Secrets must live in the server-side credential vault.

CREATE TABLE IF NOT EXISTS public.nexus_connector_definitions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE CHECK(slug ~ '^[a-z0-9][a-z0-9._-]{0,119}$'),
  display_name text NOT NULL CHECK(length(display_name) BETWEEN 1 AND 160),
  connector_type text NOT NULL CHECK(connector_type IN (
    'builtin','oauth2_builtin','oauth2_generic','api_key','mcp_remote',
    'mcp_local','openapi','webhook','browser_bridge','internal_service'
  )),
  description text NOT NULL DEFAULT '' CHECK(length(description) <= 4000),
  category text NOT NULL DEFAULT 'Other' CHECK(length(category) <= 120),
  manifest jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'development' CHECK(status IN ('development','available','deprecated')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.nexus_connector_instances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES neon_auth."user"(id) ON DELETE CASCADE,
  definition_id uuid NULL REFERENCES public.nexus_connector_definitions(id) ON DELETE SET NULL,
  instance_name text NOT NULL CHECK(length(instance_name) BETWEEN 1 AND 180),
  connector_type text NOT NULL CHECK(connector_type IN (
    'builtin','oauth2_builtin','oauth2_generic','api_key','mcp_remote',
    'mcp_local','openapi','webhook','browser_bridge','internal_service'
  )),
  endpoint_url text NULL CHECK(endpoint_url IS NULL OR length(endpoint_url) <= 2048),
  auth_mode text NOT NULL DEFAULT 'none' CHECK(auth_mode IN (
    'none','oauth2','bearer','api_key','basic','mcp_oauth','local_bridge'
  )),
  vault_ref text NULL CHECK(vault_ref IS NULL OR length(vault_ref) <= 512),
  external_account_label text NULL CHECK(external_account_label IS NULL OR length(external_account_label) <= 320),
  connection_status text NOT NULL DEFAULT 'disconnected' CHECK(connection_status IN (
    'disconnected','connecting','connected','degraded','expired','revoked','error'
  )),
  enabled boolean NOT NULL DEFAULT true,
  is_user_default boolean NOT NULL DEFAULT false,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  last_verified_at timestamptz NULL,
  last_error_code text NULL CHECK(last_error_code IS NULL OR length(last_error_code) <= 160),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz NULL
);

CREATE INDEX IF NOT EXISTS nexus_connector_instances_user_idx
  ON public.nexus_connector_instances(user_id,updated_at DESC)
  WHERE revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS public.nexus_connector_tools (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  connector_instance_id uuid NOT NULL REFERENCES public.nexus_connector_instances(id) ON DELETE CASCADE,
  tool_name text NOT NULL CHECK(length(tool_name) BETWEEN 1 AND 240),
  description text NOT NULL DEFAULT '' CHECK(length(description) <= 8000),
  input_schema jsonb NOT NULL DEFAULT '{}'::jsonb,
  risk_level text NOT NULL DEFAULT 'read' CHECK(risk_level IN (
    'read','write','delete','external_message','publish','financial','production_change'
  )),
  enabled boolean NOT NULL DEFAULT true,
  discovered_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(connector_instance_id,tool_name)
);

CREATE TABLE IF NOT EXISTS public.nexus_project_connectors (
  project_id uuid NOT NULL REFERENCES public.nexus_projects(id) ON DELETE CASCADE,
  connector_instance_id uuid NOT NULL REFERENCES public.nexus_connector_instances(id) ON DELETE CASCADE,
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(project_id,connector_instance_id)
);

CREATE TABLE IF NOT EXISTS public.nexus_agent_connectors (
  agent_id uuid NOT NULL REFERENCES public.nexus_agents(id) ON DELETE CASCADE,
  connector_instance_id uuid NOT NULL REFERENCES public.nexus_connector_instances(id) ON DELETE CASCADE,
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(agent_id,connector_instance_id)
);

CREATE TABLE IF NOT EXISTS public.nexus_connector_audit (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES neon_auth."user"(id) ON DELETE CASCADE,
  connector_instance_id uuid NULL REFERENCES public.nexus_connector_instances(id) ON DELETE SET NULL,
  tool_name text NULL,
  action text NOT NULL CHECK(length(action) BETWEEN 1 AND 120),
  outcome text NOT NULL CHECK(outcome IN ('allowed','denied','success','error','cancelled')),
  risk_level text NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS nexus_connector_audit_user_created_idx
  ON public.nexus_connector_audit(user_id,created_at DESC);

ALTER TABLE public.nexus_connector_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_connector_instances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_connector_tools ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_project_connectors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_agent_connectors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nexus_connector_audit ENABLE ROW LEVEL SECURITY;

-- This branch deliberately does NOT create secret-storage RPCs.
-- Credential writes must terminate at the hardened connector bridge/vault.

CREATE OR REPLACE FUNCTION public.nexus_connector_os_list()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid;v_instances jsonb;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',i.id,
    'definition_id',i.definition_id,
    'instance_name',i.instance_name,
    'connector_type',i.connector_type,
    'endpoint_url',i.endpoint_url,
    'auth_mode',i.auth_mode,
    'external_account_label',i.external_account_label,
    'connection_status',i.connection_status,
    'enabled',i.enabled,
    'is_user_default',i.is_user_default,
    'last_verified_at',i.last_verified_at,
    'last_error_code',i.last_error_code,
    'created_at',i.created_at,
    'updated_at',i.updated_at,
    'tool_count',(select count(*) from public.nexus_connector_tools t where t.connector_instance_id=i.id and t.enabled)
  ) order by i.updated_at desc),'[]'::jsonb)
  INTO v_instances
  FROM public.nexus_connector_instances i
  WHERE i.user_id=v_user AND i.revoked_at IS NULL;

  RETURN jsonb_build_object('instances',v_instances);
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_connector_project_set(
  p_project_id uuid,p_connector_instance_id uuid,p_enabled boolean DEFAULT true
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT EXISTS(select 1 from public.nexus_projects p where p.id=p_project_id and p.user_id=v_user and p.archived_at is null)
    THEN RAISE EXCEPTION 'project_not_found'; END IF;
  IF NOT EXISTS(select 1 from public.nexus_connector_instances i where i.id=p_connector_instance_id and i.user_id=v_user and i.revoked_at is null)
    THEN RAISE EXCEPTION 'connector_not_found'; END IF;

  INSERT INTO public.nexus_project_connectors(project_id,connector_instance_id,enabled)
  VALUES(p_project_id,p_connector_instance_id,coalesce(p_enabled,true))
  ON CONFLICT(project_id,connector_instance_id) DO UPDATE SET enabled=excluded.enabled;
  RETURN true;
END
$function$;

CREATE OR REPLACE FUNCTION public.nexus_connector_agent_set(
  p_agent_id uuid,p_connector_instance_id uuid,p_enabled boolean DEFAULT true
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT EXISTS(select 1 from public.nexus_agents a where a.id=p_agent_id and a.user_id=v_user and a.archived_at is null)
    THEN RAISE EXCEPTION 'agent_not_found'; END IF;
  IF NOT EXISTS(select 1 from public.nexus_connector_instances i where i.id=p_connector_instance_id and i.user_id=v_user and i.revoked_at is null)
    THEN RAISE EXCEPTION 'connector_not_found'; END IF;

  INSERT INTO public.nexus_agent_connectors(agent_id,connector_instance_id,enabled)
  VALUES(p_agent_id,p_connector_instance_id,coalesce(p_enabled,true))
  ON CONFLICT(agent_id,connector_instance_id) DO UPDATE SET enabled=excluded.enabled;
  RETURN true;
END
$function$;

REVOKE ALL ON TABLE public.nexus_connector_instances FROM PUBLIC;
REVOKE ALL ON TABLE public.nexus_connector_tools FROM PUBLIC;
REVOKE ALL ON TABLE public.nexus_project_connectors FROM PUBLIC;
REVOKE ALL ON TABLE public.nexus_agent_connectors FROM PUBLIC;
REVOKE ALL ON TABLE public.nexus_connector_audit FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_connector_os_list() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_connector_project_set(uuid,uuid,boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_connector_agent_set(uuid,uuid,boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.nexus_connector_os_list() TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_connector_project_set(uuid,uuid,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_connector_agent_set(uuid,uuid,boolean) TO authenticated;
