-- NEXUS Project Workspace V2
-- Read-only workspace aggregation over real Project-owned objects.

CREATE OR REPLACE FUNCTION public.nexus_project_workspace(p_project_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_user uuid;
  v_project public.nexus_projects%ROWTYPE;
  v_chats jsonb;
  v_tasks jsonb;
  v_files jsonb;
  v_agents jsonb;
  v_skills jsonb;
BEGIN
  v_user:=(auth.user_id())::uuid;
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO v_project
  FROM public.nexus_projects
  WHERE id=p_project_id AND user_id=v_user AND archived_at IS NULL;

  IF v_project.id IS NULL THEN RAISE EXCEPTION 'project_not_found'; END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,'title',c.title,'level',c.level,'agent_id',c.agent_id,
    'created_at',c.created_at,'updated_at',c.updated_at
  ) ORDER BY c.updated_at DESC,c.id),'[]'::jsonb)
  INTO v_chats
  FROM public.nexus_conversations c
  WHERE c.user_id=v_user AND c.project_id=v_project.id AND NOT c.archived;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',j.id,'conversation_id',j.conversation_id,'kind',j.kind,'level',j.level,
    'status',j.status,'estimated_credits',j.estimated_credits,'charged_credits',j.charged_credits,
    'input_summary',regexp_replace(coalesce(j.input_summary,''),'^\[TEXT_TASK (AGENT|WORK|CODE)\]\s*','','i'),
    'output_summary',j.output_summary,'error_code',j.error_code,'worker_id',j.worker_id,
    'agent_id',j.agent_id,'execution_metadata',j.execution_metadata,
    'created_at',j.created_at,'completed_at',j.completed_at
  ) ORDER BY j.created_at DESC,j.id),'[]'::jsonb)
  INTO v_tasks
  FROM public.nexus_jobs j
  WHERE j.user_id=v_user AND j.project_id=v_project.id
    AND upper(trim(coalesce(j.input_summary,''))) NOT LIKE 'INTERNAL%'
    AND upper(trim(coalesce(j.input_summary,''))) NOT LIKE '[CHAT_LOCAL]%'
    AND upper(trim(coalesce(j.input_summary,''))) NOT LIKE '[BETA_TRIAGE]%';

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',a.id,'filename',a.filename,'mime_type',a.mime_type,'size_bytes',a.size_bytes,
    'status',a.status,'conversation_id',a.conversation_id,'job_id',a.job_id,'created_at',a.created_at
  ) ORDER BY a.created_at DESC,a.id),'[]'::jsonb)
  INTO v_files
  FROM public.nexus_attachments a
  WHERE a.user_id=v_user
    AND a.status<>'deleted'
    AND (
      EXISTS(
        SELECT 1 FROM public.nexus_conversations c
        WHERE c.id=a.conversation_id AND c.user_id=v_user AND c.project_id=v_project.id
      )
      OR EXISTS(
        SELECT 1 FROM public.nexus_jobs j
        WHERE j.id=a.job_id AND j.user_id=v_user AND j.project_id=v_project.id
      )
    );

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',a.id,'name',a.name,'description',a.description,'mission',a.mission,
    'routing_profile',a.routing_profile,'autonomy_level',a.autonomy_level,
    'approval_policy',a.approval_policy,'updated_at',a.updated_at
  ) ORDER BY a.updated_at DESC,a.id),'[]'::jsonb)
  INTO v_agents
  FROM public.nexus_agents a
  WHERE a.user_id=v_user AND a.project_id=v_project.id AND a.archived_at IS NULL;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,'name',s.name,'slug',s.slug,'version',s.version,
    'description',s.description,'scope',s.scope,'enabled',s.enabled,'updated_at',s.updated_at
  ) ORDER BY s.name,s.id),'[]'::jsonb)
  INTO v_skills
  FROM public.nexus_project_skills ps
  JOIN public.nexus_skills s ON s.id=ps.skill_id
  WHERE ps.project_id=v_project.id AND ps.enabled
    AND s.owner_user_id=v_user AND s.archived_at IS NULL;

  RETURN jsonb_build_object(
    'project',jsonb_build_object(
      'id',v_project.id,
      'name',v_project.name,
      'description',v_project.description,
      'instructions',v_project.instructions,
      'default_level',v_project.default_level,
      'created_at',v_project.created_at,
      'updated_at',v_project.updated_at
    ),
    'counts',jsonb_build_object(
      'chats',jsonb_array_length(v_chats),
      'tasks',jsonb_array_length(v_tasks),
      'files',jsonb_array_length(v_files),
      'agents',jsonb_array_length(v_agents),
      'skills',jsonb_array_length(v_skills)
    ),
    'chats',v_chats,
    'tasks',v_tasks,
    'files',v_files,
    'agents',v_agents,
    'skills',v_skills
  );
END
$function$;

REVOKE ALL ON FUNCTION public.nexus_project_workspace(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nexus_project_workspace(uuid) TO authenticated;
