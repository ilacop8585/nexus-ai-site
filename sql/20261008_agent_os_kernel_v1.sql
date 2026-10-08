-- NEXUS Agent OS Kernel V1
-- Projects + Agents + Skills + Settings. Additive, backward-compatible with existing nexus_jobs.

CREATE TABLE IF NOT EXISTS public.nexus_projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES neon_auth."user"(id) ON DELETE CASCADE,
  name text NOT NULL CHECK(length(name) BETWEEN 1 AND 160),
  description text NOT NULL DEFAULT '' CHECK(length(description) <= 4000),
  instructions text NOT NULL DEFAULT '' CHECK(length(instructions) <= 20000),
  default_level text NOT NULL DEFAULT 'free' CHECK(default_level IN ('free','smart','deep')),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  archived_at timestamptz NULL
);

CREATE INDEX IF NOT EXISTS nexus_projects_user_updated_idx
  ON public.nexus_projects(user_id,updated_at DESC)
  WHERE archived_at IS NULL;

ALTER TABLE public.nexus_projects ENABLE ROW LEVEL SECURITY;


CREATE TABLE IF NOT EXISTS public.nexus_agents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES neon_auth."user"(id) ON DELETE CASCADE,
  project_id uuid NULL REFERENCES public.nexus_projects(id) ON DELETE SET NULL,
  name text NOT NULL CHECK(length(name) BETWEEN 1 AND 160),
  description text NOT NULL DEFAULT '' CHECK(length(description) <= 4000),
  mission text NOT NULL DEFAULT '' CHECK(length(mission) <= 20000),
  routing_profile text NOT NULL DEFAULT 'local_first'
    CHECK(routing_profile IN ('local_first','balanced','max')),
  autonomy_level text NOT NULL DEFAULT 'supervised'
    CHECK(autonomy_level IN ('assist','supervised','autonomous')),
  approval_policy text NOT NULL DEFAULT 'risk_based'
    CHECK(approval_policy IN ('always_confirm','risk_based','trusted_low_risk')),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  archived_at timestamptz NULL
);

CREATE INDEX IF NOT EXISTS nexus_agents_user_updated_idx
  ON public.nexus_agents(user_id,updated_at DESC)
  WHERE archived_at IS NULL;

ALTER TABLE public.nexus_agents ENABLE ROW LEVEL SECURITY;


CREATE TABLE IF NOT EXISTS public.nexus_skills (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid NOT NULL REFERENCES neon_auth."user"(id) ON DELETE CASCADE,
  name text NOT NULL CHECK(length(name) BETWEEN 1 AND 160),
  slug text NOT NULL CHECK(length(slug) BETWEEN 1 AND 120 AND slug ~ '^[a-z0-9][a-z0-9._-]*$'),
  version text NOT NULL DEFAULT '1.0.0' CHECK(length(version) BETWEEN 1 AND 40),
  description text NOT NULL DEFAULT '' CHECK(length(description) <= 4000),
  instructions text NOT NULL DEFAULT '' CHECK(length(instructions) <= 30000),
  scope text NOT NULL DEFAULT 'personal' CHECK(scope IN ('personal','project','agent')),
  source_type text NOT NULL DEFAULT 'inline'
    CHECK(source_type IN ('inline','upload','github')),
  source_ref text NULL CHECK(source_ref IS NULL OR length(source_ref) <= 2000),
  manifest jsonb NOT NULL DEFAULT '{}'::jsonb,
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  archived_at timestamptz NULL,
  UNIQUE(owner_user_id,slug)
);

CREATE INDEX IF NOT EXISTS nexus_skills_owner_updated_idx
  ON public.nexus_skills(owner_user_id,updated_at DESC)
  WHERE archived_at IS NULL;

ALTER TABLE public.nexus_skills ENABLE ROW LEVEL SECURITY;


CREATE TABLE IF NOT EXISTS public.nexus_project_skills (
  project_id uuid NOT NULL REFERENCES public.nexus_projects(id) ON DELETE CASCADE,
  skill_id uuid NOT NULL REFERENCES public.nexus_skills(id) ON DELETE CASCADE,
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(project_id,skill_id)
);

ALTER TABLE public.nexus_project_skills ENABLE ROW LEVEL SECURITY;


CREATE TABLE IF NOT EXISTS public.nexus_agent_skills (
  agent_id uuid NOT NULL REFERENCES public.nexus_agents(id) ON DELETE CASCADE,
  skill_id uuid NOT NULL REFERENCES public.nexus_skills(id) ON DELETE CASCADE,
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(agent_id,skill_id)
);

ALTER TABLE public.nexus_agent_skills ENABLE ROW LEVEL SECURITY;


CREATE TABLE IF NOT EXISTS public.nexus_user_settings (
  user_id uuid PRIMARY KEY REFERENCES neon_auth."user"(id) ON DELETE CASCADE,
  default_project_id uuid NULL REFERENCES public.nexus_projects(id) ON DELETE SET NULL,
  default_agent_id uuid NULL REFERENCES public.nexus_agents(id) ON DELETE SET NULL,
  routing_profile text NOT NULL DEFAULT 'local_first'
    CHECK(routing_profile IN ('local_first','balanced','max')),
  autonomy_level text NOT NULL DEFAULT 'supervised'
    CHECK(autonomy_level IN ('assist','supervised','autonomous')),
  approval_policy text NOT NULL DEFAULT 'risk_based'
    CHECK(approval_policy IN ('always_confirm','risk_based','trusted_low_risk')),
  timezone text NOT NULL DEFAULT 'UTC' CHECK(length(timezone) BETWEEN 1 AND 100),
  language text NOT NULL DEFAULT 'it' CHECK(length(language) BETWEEN 2 AND 16),
  notifications_in_app boolean NOT NULL DEFAULT true,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.nexus_user_settings ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.nexus_conversations
  ADD COLUMN IF NOT EXISTS project_id uuid NULL REFERENCES public.nexus_projects(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS agent_id uuid NULL REFERENCES public.nexus_agents(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS nexus_conversations_project_updated_idx
  ON public.nexus_conversations(project_id,updated_at DESC)
  WHERE project_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS nexus_conversations_agent_updated_idx
  ON public.nexus_conversations(agent_id,updated_at DESC)
  WHERE agent_id IS NOT NULL;


ALTER TABLE public.nexus_jobs
  ADD COLUMN IF NOT EXISTS project_id uuid NULL REFERENCES public.nexus_projects(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS agent_id uuid NULL REFERENCES public.nexus_agents(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS parent_job_id uuid NULL REFERENCES public.nexus_jobs(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS root_job_id uuid NULL REFERENCES public.nexus_jobs(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS routing_profile text NULL
    CHECK(routing_profile IS NULL OR routing_profile IN ('local_first','balanced','max')),
  ADD COLUMN IF NOT EXISTS approval_policy text NULL
    CHECK(approval_policy IS NULL OR approval_policy IN ('always_confirm','risk_based','trusted_low_risk')),
  ADD COLUMN IF NOT EXISTS structured_output_schema jsonb NULL,
  ADD COLUMN IF NOT EXISTS structured_output_result jsonb NULL;

CREATE INDEX IF NOT EXISTS nexus_jobs_project_created_idx
  ON public.nexus_jobs(project_id,created_at DESC)
  WHERE project_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS nexus_jobs_agent_created_idx
  ON public.nexus_jobs(agent_id,created_at DESC)
  WHERE agent_id IS NOT NULL;


CREATE OR REPLACE FUNCTION public.nexus_workspace_bootstrap()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_user uuid;
  v_settings jsonb;
  v_projects jsonb;
  v_agents jsonb;
  v_skills jsonb;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  INSERT INTO public.nexus_user_settings(user_id)
  VALUES(v_user)
  ON CONFLICT(user_id) DO NOTHING;

  SELECT to_jsonb(s) - 'metadata'
    INTO v_settings
  FROM public.nexus_user_settings s
  WHERE s.user_id=v_user;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',p.id,
    'name',p.name,
    'description',p.description,
    'instructions',p.instructions,
    'default_level',p.default_level,
    'created_at',p.created_at,
    'updated_at',p.updated_at
  ) ORDER BY p.updated_at DESC,p.id),'[]'::jsonb)
  INTO v_projects
  FROM public.nexus_projects p
  WHERE p.user_id=v_user AND p.archived_at IS NULL;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',a.id,
    'project_id',a.project_id,
    'name',a.name,
    'description',a.description,
    'mission',a.mission,
    'routing_profile',a.routing_profile,
    'autonomy_level',a.autonomy_level,
    'approval_policy',a.approval_policy,
    'created_at',a.created_at,
    'updated_at',a.updated_at,
    'skill_ids',coalesce((
      SELECT jsonb_agg(x.skill_id ORDER BY x.created_at)
      FROM public.nexus_agent_skills x
      JOIN public.nexus_skills sk ON sk.id=x.skill_id
      WHERE x.agent_id=a.id AND x.enabled AND sk.archived_at IS NULL
    ),'[]'::jsonb)
  ) ORDER BY a.updated_at DESC,a.id),'[]'::jsonb)
  INTO v_agents
  FROM public.nexus_agents a
  WHERE a.user_id=v_user AND a.archived_at IS NULL;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,
    'name',s.name,
    'slug',s.slug,
    'version',s.version,
    'description',s.description,
    'instructions',s.instructions,
    'scope',s.scope,
    'source_type',s.source_type,
    'source_ref',s.source_ref,
    'enabled',s.enabled,
    'created_at',s.created_at,
    'updated_at',s.updated_at,
    'project_ids',coalesce((
      SELECT jsonb_agg(ps.project_id ORDER BY ps.created_at)
      FROM public.nexus_project_skills ps
      JOIN public.nexus_projects p ON p.id=ps.project_id
      WHERE ps.skill_id=s.id AND ps.enabled AND p.user_id=v_user AND p.archived_at IS NULL
    ),'[]'::jsonb),
    'agent_ids',coalesce((
      SELECT jsonb_agg(ask.agent_id ORDER BY ask.created_at)
      FROM public.nexus_agent_skills ask
      JOIN public.nexus_agents a ON a.id=ask.agent_id
      WHERE ask.skill_id=s.id AND ask.enabled AND a.user_id=v_user AND a.archived_at IS NULL
    ),'[]'::jsonb)
  ) ORDER BY s.updated_at DESC,s.id),'[]'::jsonb)
  INTO v_skills
  FROM public.nexus_skills s
  WHERE s.owner_user_id=v_user AND s.archived_at IS NULL;

  RETURN jsonb_build_object(
    'settings',coalesce(v_settings,'{}'::jsonb),
    'projects',v_projects,
    'agents',v_agents,
    'skills',v_skills
  );
END
$function$;


CREATE OR REPLACE FUNCTION public.nexus_project_save(
  p_id uuid,
  p_name text,
  p_description text DEFAULT '',
  p_instructions text DEFAULT '',
  p_default_level text DEFAULT 'free'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid;v_id uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF length(trim(coalesce(p_name,'')))<1 THEN RAISE EXCEPTION 'project_name_required'; END IF;
  IF p_default_level NOT IN ('free','smart','deep') THEN RAISE EXCEPTION 'invalid_default_level'; END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.nexus_projects(user_id,name,description,instructions,default_level)
    VALUES(v_user,left(trim(p_name),160),left(coalesce(p_description,''),4000),left(coalesce(p_instructions,''),20000),p_default_level)
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.nexus_projects
    SET name=left(trim(p_name),160),
        description=left(coalesce(p_description,''),4000),
        instructions=left(coalesce(p_instructions,''),20000),
        default_level=p_default_level,
        updated_at=now()
    WHERE id=p_id AND user_id=v_user AND archived_at IS NULL
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'project_not_found'; END IF;
  END IF;
  RETURN v_id;
END
$function$;


CREATE OR REPLACE FUNCTION public.nexus_project_archive(p_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  UPDATE public.nexus_projects SET archived_at=now(),updated_at=now()
  WHERE id=p_id AND user_id=v_user AND archived_at IS NULL;
  IF FOUND THEN
    UPDATE public.nexus_user_settings
      SET default_project_id=NULL,updated_at=now()
      WHERE user_id=v_user AND default_project_id=p_id;
    RETURN true;
  END IF;
  RETURN false;
END
$function$;


CREATE OR REPLACE FUNCTION public.nexus_agent_save(
  p_id uuid,
  p_project_id uuid,
  p_name text,
  p_description text DEFAULT '',
  p_mission text DEFAULT '',
  p_routing_profile text DEFAULT 'local_first',
  p_autonomy_level text DEFAULT 'supervised',
  p_approval_policy text DEFAULT 'risk_based'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid;v_id uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF length(trim(coalesce(p_name,'')))<1 THEN RAISE EXCEPTION 'agent_name_required'; END IF;
  IF p_routing_profile NOT IN ('local_first','balanced','max') THEN RAISE EXCEPTION 'invalid_routing_profile'; END IF;
  IF p_autonomy_level NOT IN ('assist','supervised','autonomous') THEN RAISE EXCEPTION 'invalid_autonomy_level'; END IF;
  IF p_approval_policy NOT IN ('always_confirm','risk_based','trusted_low_risk') THEN RAISE EXCEPTION 'invalid_approval_policy'; END IF;
  IF p_project_id IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM public.nexus_projects p WHERE p.id=p_project_id AND p.user_id=v_user AND p.archived_at IS NULL
  ) THEN RAISE EXCEPTION 'project_not_found'; END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.nexus_agents(user_id,project_id,name,description,mission,routing_profile,autonomy_level,approval_policy)
    VALUES(v_user,p_project_id,left(trim(p_name),160),left(coalesce(p_description,''),4000),left(coalesce(p_mission,''),20000),p_routing_profile,p_autonomy_level,p_approval_policy)
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.nexus_agents
    SET project_id=p_project_id,
        name=left(trim(p_name),160),
        description=left(coalesce(p_description,''),4000),
        mission=left(coalesce(p_mission,''),20000),
        routing_profile=p_routing_profile,
        autonomy_level=p_autonomy_level,
        approval_policy=p_approval_policy,
        updated_at=now()
    WHERE id=p_id AND user_id=v_user AND archived_at IS NULL
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'agent_not_found'; END IF;
  END IF;
  RETURN v_id;
END
$function$;


CREATE OR REPLACE FUNCTION public.nexus_agent_archive(p_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  UPDATE public.nexus_agents SET archived_at=now(),updated_at=now()
  WHERE id=p_id AND user_id=v_user AND archived_at IS NULL;
  IF FOUND THEN
    UPDATE public.nexus_user_settings
      SET default_agent_id=NULL,updated_at=now()
      WHERE user_id=v_user AND default_agent_id=p_id;
    RETURN true;
  END IF;
  RETURN false;
END
$function$;


CREATE OR REPLACE FUNCTION public.nexus_skill_save(
  p_id uuid,
  p_name text,
  p_slug text,
  p_version text DEFAULT '1.0.0',
  p_description text DEFAULT '',
  p_instructions text DEFAULT '',
  p_scope text DEFAULT 'personal',
  p_source_type text DEFAULT 'inline',
  p_source_ref text DEFAULT NULL,
  p_enabled boolean DEFAULT true
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid;v_id uuid;v_slug text;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF length(trim(coalesce(p_name,'')))<1 THEN RAISE EXCEPTION 'skill_name_required'; END IF;
  v_slug:=lower(trim(coalesce(p_slug,'')));
  IF v_slug !~ '^[a-z0-9][a-z0-9._-]{0,119}$' THEN RAISE EXCEPTION 'invalid_skill_slug'; END IF;
  IF p_scope NOT IN ('personal','project','agent') THEN RAISE EXCEPTION 'invalid_skill_scope'; END IF;
  IF p_source_type NOT IN ('inline','upload','github') THEN RAISE EXCEPTION 'invalid_skill_source_type'; END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.nexus_skills(owner_user_id,name,slug,version,description,instructions,scope,source_type,source_ref,enabled)
    VALUES(v_user,left(trim(p_name),160),v_slug,left(coalesce(nullif(trim(p_version),''),'1.0.0'),40),left(coalesce(p_description,''),4000),left(coalesce(p_instructions,''),30000),p_scope,p_source_type,left(p_source_ref,2000),coalesce(p_enabled,true))
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.nexus_skills
    SET name=left(trim(p_name),160),
        slug=v_slug,
        version=left(coalesce(nullif(trim(p_version),''),'1.0.0'),40),
        description=left(coalesce(p_description,''),4000),
        instructions=left(coalesce(p_instructions,''),30000),
        scope=p_scope,
        source_type=p_source_type,
        source_ref=left(p_source_ref,2000),
        enabled=coalesce(p_enabled,true),
        updated_at=now()
    WHERE id=p_id AND owner_user_id=v_user AND archived_at IS NULL
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'skill_not_found'; END IF;
  END IF;
  RETURN v_id;
EXCEPTION
  WHEN unique_violation THEN RAISE EXCEPTION 'skill_slug_already_exists';
END
$function$;


CREATE OR REPLACE FUNCTION public.nexus_skill_archive(p_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  UPDATE public.nexus_skills SET archived_at=now(),updated_at=now()
  WHERE id=p_id AND owner_user_id=v_user AND archived_at IS NULL;
  RETURN FOUND;
END
$function$;


CREATE OR REPLACE FUNCTION public.nexus_project_skill_set(p_project_id uuid,p_skill_id uuid,p_enabled boolean DEFAULT true)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.nexus_projects WHERE id=p_project_id AND user_id=v_user AND archived_at IS NULL)
    THEN RAISE EXCEPTION 'project_not_found'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.nexus_skills WHERE id=p_skill_id AND owner_user_id=v_user AND archived_at IS NULL)
    THEN RAISE EXCEPTION 'skill_not_found'; END IF;

  INSERT INTO public.nexus_project_skills(project_id,skill_id,enabled)
  VALUES(p_project_id,p_skill_id,coalesce(p_enabled,true))
  ON CONFLICT(project_id,skill_id) DO UPDATE SET enabled=excluded.enabled;
  RETURN true;
END
$function$;


CREATE OR REPLACE FUNCTION public.nexus_agent_skill_set(p_agent_id uuid,p_skill_id uuid,p_enabled boolean DEFAULT true)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.nexus_agents WHERE id=p_agent_id AND user_id=v_user AND archived_at IS NULL)
    THEN RAISE EXCEPTION 'agent_not_found'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.nexus_skills WHERE id=p_skill_id AND owner_user_id=v_user AND archived_at IS NULL)
    THEN RAISE EXCEPTION 'skill_not_found'; END IF;

  INSERT INTO public.nexus_agent_skills(agent_id,skill_id,enabled)
  VALUES(p_agent_id,p_skill_id,coalesce(p_enabled,true))
  ON CONFLICT(agent_id,skill_id) DO UPDATE SET enabled=excluded.enabled;
  RETURN true;
END
$function$;


CREATE OR REPLACE FUNCTION public.nexus_settings_save(
  p_default_project_id uuid,
  p_default_agent_id uuid,
  p_routing_profile text,
  p_autonomy_level text,
  p_approval_policy text,
  p_timezone text,
  p_language text,
  p_notifications_in_app boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE v_user uuid;v_row public.nexus_user_settings%ROWTYPE;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_routing_profile NOT IN ('local_first','balanced','max') THEN RAISE EXCEPTION 'invalid_routing_profile'; END IF;
  IF p_autonomy_level NOT IN ('assist','supervised','autonomous') THEN RAISE EXCEPTION 'invalid_autonomy_level'; END IF;
  IF p_approval_policy NOT IN ('always_confirm','risk_based','trusted_low_risk') THEN RAISE EXCEPTION 'invalid_approval_policy'; END IF;
  IF p_default_project_id IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM public.nexus_projects WHERE id=p_default_project_id AND user_id=v_user AND archived_at IS NULL
  ) THEN RAISE EXCEPTION 'project_not_found'; END IF;
  IF p_default_agent_id IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM public.nexus_agents WHERE id=p_default_agent_id AND user_id=v_user AND archived_at IS NULL
  ) THEN RAISE EXCEPTION 'agent_not_found'; END IF;

  INSERT INTO public.nexus_user_settings(
    user_id,default_project_id,default_agent_id,routing_profile,autonomy_level,approval_policy,timezone,language,notifications_in_app,updated_at
  )
  VALUES(
    v_user,p_default_project_id,p_default_agent_id,p_routing_profile,p_autonomy_level,p_approval_policy,
    left(coalesce(nullif(trim(p_timezone),''),'UTC'),100),
    left(coalesce(nullif(trim(p_language),''),'it'),16),
    coalesce(p_notifications_in_app,true),now()
  )
  ON CONFLICT(user_id) DO UPDATE SET
    default_project_id=excluded.default_project_id,
    default_agent_id=excluded.default_agent_id,
    routing_profile=excluded.routing_profile,
    autonomy_level=excluded.autonomy_level,
    approval_policy=excluded.approval_policy,
    timezone=excluded.timezone,
    language=excluded.language,
    notifications_in_app=excluded.notifications_in_app,
    updated_at=now()
  RETURNING * INTO v_row;

  RETURN to_jsonb(v_row)-'metadata';
END
$function$;


CREATE OR REPLACE FUNCTION public.nexus_agent_os_context()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_user uuid;
  v_settings public.nexus_user_settings%ROWTYPE;
  v_project public.nexus_projects%ROWTYPE;
  v_agent public.nexus_agents%ROWTYPE;
  v_skills jsonb;
  v_prompt text:='';
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  INSERT INTO public.nexus_user_settings(user_id)
  VALUES(v_user)
  ON CONFLICT(user_id) DO NOTHING;

  SELECT * INTO v_settings FROM public.nexus_user_settings WHERE user_id=v_user;

  IF v_settings.default_project_id IS NOT NULL THEN
    SELECT * INTO v_project
    FROM public.nexus_projects
    WHERE id=v_settings.default_project_id AND user_id=v_user AND archived_at IS NULL;
  END IF;

  IF v_settings.default_agent_id IS NOT NULL THEN
    SELECT * INTO v_agent
    FROM public.nexus_agents
    WHERE id=v_settings.default_agent_id AND user_id=v_user AND archived_at IS NULL;
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,'name',s.name,'version',s.version,'instructions',s.instructions
  ) ORDER BY s.name),'[]'::jsonb)
  INTO v_skills
  FROM public.nexus_skills s
  WHERE s.owner_user_id=v_user
    AND s.archived_at IS NULL
    AND s.enabled
    AND (
      s.scope='personal'
      OR EXISTS(
        SELECT 1 FROM public.nexus_project_skills ps
        WHERE ps.skill_id=s.id AND ps.enabled AND ps.project_id=v_project.id
      )
      OR EXISTS(
        SELECT 1 FROM public.nexus_agent_skills ask
        WHERE ask.skill_id=s.id AND ask.enabled AND ask.agent_id=v_agent.id
      )
    );

  IF v_project.id IS NOT NULL AND length(trim(v_project.instructions))>0 THEN
    v_prompt:=v_prompt||E'PROJECT: '||v_project.name||E'\nPROJECT INSTRUCTIONS:\n'||v_project.instructions||E'\n\n';
  END IF;
  IF v_agent.id IS NOT NULL THEN
    v_prompt:=v_prompt||E'AGENT: '||v_agent.name||E'\n';
    IF length(trim(v_agent.mission))>0 THEN
      v_prompt:=v_prompt||E'AGENT MISSION:\n'||v_agent.mission||E'\n';
    END IF;
    v_prompt:=v_prompt||E'ROUTING PROFILE: '||v_agent.routing_profile||E'\nAUTONOMY: '||v_agent.autonomy_level||E'\nAPPROVAL POLICY: '||v_agent.approval_policy||E'\n\n';
  END IF;

  IF jsonb_array_length(v_skills)>0 THEN
    v_prompt:=v_prompt||E'ACTIVE SKILLS:\n';
    v_prompt:=v_prompt||(
      SELECT string_agg(
        '- '||(x->>'name')||' v'||(x->>'version')||
        CASE WHEN length(trim(coalesce(x->>'instructions','')))>0 THEN E':\n'||(x->>'instructions') ELSE '' END,
        E'\n'
      )
      FROM jsonb_array_elements(v_skills) x
    )||E'\n\n';
  END IF;

  RETURN jsonb_build_object(
    'project_id',v_project.id,
    'project_name',v_project.name,
    'agent_id',v_agent.id,
    'agent_name',v_agent.name,
    'routing_profile',coalesce(v_agent.routing_profile,v_settings.routing_profile),
    'autonomy_level',coalesce(v_agent.autonomy_level,v_settings.autonomy_level),
    'approval_policy',coalesce(v_agent.approval_policy,v_settings.approval_policy),
    'skills',v_skills,
    'prompt_prefix',left(v_prompt,18000)
  );
END
$function$;


CREATE OR REPLACE FUNCTION public.nexus_job_bind_context(
  p_job_id uuid,
  p_project_id uuid,
  p_agent_id uuid,
  p_routing_profile text,
  p_approval_policy text
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

  IF p_project_id IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM public.nexus_projects p
    WHERE p.id=p_project_id AND p.user_id=v_user AND p.archived_at IS NULL
  ) THEN RAISE EXCEPTION 'project_not_found'; END IF;

  IF p_agent_id IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM public.nexus_agents a
    WHERE a.id=p_agent_id AND a.user_id=v_user AND a.archived_at IS NULL
  ) THEN RAISE EXCEPTION 'agent_not_found'; END IF;

  UPDATE public.nexus_jobs
  SET project_id=p_project_id,
      agent_id=p_agent_id,
      routing_profile=CASE WHEN p_routing_profile IN ('local_first','balanced','max') THEN p_routing_profile ELSE routing_profile END,
      approval_policy=CASE WHEN p_approval_policy IN ('always_confirm','risk_based','trusted_low_risk') THEN p_approval_policy ELSE approval_policy END,
      execution_metadata=coalesce(execution_metadata,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object(
        'agent_os_project_id',p_project_id,
        'agent_os_agent_id',p_agent_id,
        'agent_os_routing_profile',p_routing_profile,
        'agent_os_approval_policy',p_approval_policy
      ))
  WHERE id=p_job_id AND user_id=v_user;

  RETURN FOUND;
END
$function$;


REVOKE ALL ON TABLE public.nexus_projects FROM PUBLIC;
REVOKE ALL ON TABLE public.nexus_agents FROM PUBLIC;
REVOKE ALL ON TABLE public.nexus_skills FROM PUBLIC;
REVOKE ALL ON TABLE public.nexus_project_skills FROM PUBLIC;
REVOKE ALL ON TABLE public.nexus_agent_skills FROM PUBLIC;
REVOKE ALL ON TABLE public.nexus_user_settings FROM PUBLIC;

REVOKE ALL ON FUNCTION public.nexus_workspace_bootstrap() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_agent_os_context() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_job_bind_context(uuid,uuid,uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_project_save(uuid,text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_project_archive(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_agent_save(uuid,uuid,text,text,text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_agent_archive(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_skill_save(uuid,text,text,text,text,text,text,text,text,boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_skill_archive(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_project_skill_set(uuid,uuid,boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_agent_skill_set(uuid,uuid,boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nexus_settings_save(uuid,uuid,text,text,text,text,text,boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.nexus_workspace_bootstrap() TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_agent_os_context() TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_job_bind_context(uuid,uuid,uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_project_save(uuid,text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_project_archive(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_agent_save(uuid,uuid,text,text,text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_agent_archive(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_skill_save(uuid,text,text,text,text,text,text,text,text,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_skill_archive(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_project_skill_set(uuid,uuid,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_agent_skill_set(uuid,uuid,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nexus_settings_save(uuid,uuid,text,text,text,text,text,boolean) TO authenticated;
