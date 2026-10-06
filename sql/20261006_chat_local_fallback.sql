-- NEXUS zero-credit PC chat fallback
-- Public chat remains separate from credit-bearing file/compute jobs.
-- Owner/beta unlimited accounts resolve to deep PC route; ordinary accounts resolve to free local route.

create or replace function public.nexus_create_chat_local_job(
  p_conversation_id uuid,
  p_prompt text
)
returns table(job_id uuid,status text,resolved_level text)
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_user uuid;
  v_job uuid;
  v_active integer;
  v_today integer;
  v_unlimited boolean;
  v_level text;
begin
  v_user := (auth.user_id())::uuid;
  if v_user is null then raise exception 'not_authenticated'; end if;

  if not exists(
    select 1 from public.nexus_conversations c
    where c.id=p_conversation_id and c.user_id=v_user
  ) then raise exception 'conversation_not_owned'; end if;

  if length(trim(coalesce(p_prompt,''))) < 1 then raise exception 'prompt_required'; end if;
  if length(p_prompt) > 12000 then raise exception 'prompt_too_large_12000'; end if;

  select count(*) into v_active
  from public.nexus_jobs j
  where j.user_id=v_user
    and j.input_summary like '[CHAT_LOCAL] %'
    and j.status in ('queued','claimed','running','qa');
  if v_active >= 2 then raise exception 'chat_local_active_limit_2'; end if;

  select count(*) into v_today
  from public.nexus_jobs j
  where j.user_id=v_user
    and j.input_summary like '[CHAT_LOCAL] %'
    and j.created_at > now()-interval '24 hours';

  select coalesce(s.unlimited_qa,false) into v_unlimited
  from public.nexus_staff_accounts s
  where s.user_id=v_user;
  v_unlimited := coalesce(v_unlimited,false);

  if (not v_unlimited and v_today >= 100) or (v_unlimited and v_today >= 1000) then
    raise exception 'chat_local_daily_limit';
  end if;

  v_level := case when v_unlimited then 'deep' else 'free' end;

  -- Use a historically claimable job kind. The worker recognizes the
  -- [CHAT_LOCAL] prefix before generic file processing, so no attachment is required.
  insert into public.nexus_jobs(
    user_id,conversation_id,kind,level,status,priority,
    estimated_credits,charged_credits,input_summary
  )
  values(
    v_user,p_conversation_id,'general_file',v_level,'queued',100,
    0,0,'[CHAT_LOCAL] '||left(p_prompt,11980)
  )
  returning id into v_job;

  return query select v_job,'queued'::text,v_level;
end
$$;
