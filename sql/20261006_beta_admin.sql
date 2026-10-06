-- NEXUS Beta/Admin controls and upload-policy alignment
-- Applied to production Neon on 2026-10-06.
-- This migration is generic: no tester email, password, token or private credential is embedded.

create table if not exists public.nexus_beta_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references neon_auth."user"(id) on delete cascade,
  conversation_id uuid null references public.nexus_conversations(id) on delete set null,
  kind text not null default 'bug' check (kind in ('bug','suggestion','ux','performance','model','other')),
  severity text not null default 'medium' check (severity in ('critical','high','medium','low')),
  title text not null,
  description text not null,
  repro_steps text null,
  expected_result text null,
  actual_result text null,
  page_url text null,
  client_info jsonb not null default '{}'::jsonb,
  status text not null default 'new' check (status in ('new','triaged','in_progress','fixed','verified','closed','wont_fix')),
  admin_note text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists nexus_beta_feedback_user_created_idx on public.nexus_beta_feedback(user_id,created_at desc);
create index if not exists nexus_beta_feedback_status_created_idx on public.nexus_beta_feedback(status,created_at desc);
alter table public.nexus_beta_feedback enable row level security;

create table if not exists public.nexus_admin_audit (
  id bigserial primary key,
  admin_user_id uuid not null references neon_auth."user"(id) on delete restrict,
  target_user_id uuid null references neon_auth."user"(id) on delete set null,
  action text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists nexus_admin_audit_created_idx on public.nexus_admin_audit(created_at desc);
alter table public.nexus_admin_audit enable row level security;

create or replace function public.nexus_is_owner(p_user uuid)
returns boolean language sql security definer set search_path=public,pg_temp
as $$
  select coalesce((select role in ('owner','admin') from public.nexus_staff_accounts where user_id=p_user),false)
$$;

create or replace function public.nexus_get_my_access()
returns table(user_id uuid,display_name text,staff_role text,unlimited boolean,plan text,credits integer,is_beta boolean,is_admin boolean)
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_user uuid;
begin
  v_user := (auth.user_id())::uuid;
  if v_user is null then raise exception 'not_authenticated'; end if;
  return query
  select p.user_id,p.display_name,s.role,coalesce(s.unlimited_qa,false),p.plan,p.credits_balance,
         coalesce(s.role='beta_tester',false),
         coalesce(s.role in ('owner','admin'),false)
  from public.nexus_profiles p
  left join public.nexus_staff_accounts s on s.user_id=p.user_id
  where p.user_id=v_user;
end
$$;

create or replace function public.nexus_submit_beta_feedback(
  p_kind text,p_severity text,p_title text,p_description text,
  p_repro_steps text default null,p_expected_result text default null,p_actual_result text default null,
  p_page_url text default null,p_conversation_id uuid default null,p_client_info jsonb default '{}'::jsonb
)
returns uuid language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_user uuid; v_id uuid; v_role text;
begin
  v_user := (auth.user_id())::uuid;
  if v_user is null then raise exception 'not_authenticated'; end if;
  select role into v_role from public.nexus_staff_accounts where user_id=v_user;
  if coalesce(v_role,'') not in ('beta_tester','owner','admin','qa') then raise exception 'beta_access_required'; end if;
  if p_kind not in ('bug','suggestion','ux','performance','model','other') then raise exception 'invalid_kind'; end if;
  if p_severity not in ('critical','high','medium','low') then raise exception 'invalid_severity'; end if;
  if length(trim(coalesce(p_title,''))) < 3 then raise exception 'title_required'; end if;
  if length(trim(coalesce(p_description,''))) < 3 then raise exception 'description_required'; end if;
  if p_conversation_id is not null and not exists(
    select 1 from public.nexus_conversations c where c.id=p_conversation_id and c.user_id=v_user
  ) then raise exception 'conversation_not_owned'; end if;
  insert into public.nexus_beta_feedback(
    user_id,conversation_id,kind,severity,title,description,repro_steps,expected_result,actual_result,page_url,client_info
  ) values(
    v_user,p_conversation_id,p_kind,p_severity,left(trim(p_title),240),left(trim(p_description),12000),
    left(p_repro_steps,12000),left(p_expected_result,8000),left(p_actual_result,8000),left(p_page_url,1200),coalesce(p_client_info,'{}'::jsonb)
  ) returning id into v_id;
  return v_id;
end
$$;

create or replace function public.nexus_admin_list_users()
returns table(user_id uuid,email text,name text,display_name text,staff_role text,unlimited boolean,plan text,credits integer,email_verified boolean,created_at timestamptz)
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_admin uuid;
begin
  v_admin := (auth.user_id())::uuid;
  if not public.nexus_is_owner(v_admin) then raise exception 'admin_required'; end if;
  return query
  select u.id,u.email,u.name,p.display_name,s.role,coalesce(s.unlimited_qa,false),p.plan,p.credits_balance,u."emailVerified",u."createdAt"
  from neon_auth."user" u
  left join public.nexus_profiles p on p.user_id=u.id
  left join public.nexus_staff_accounts s on s.user_id=u.id
  order by u."createdAt" desc;
end
$$;

create or replace function public.nexus_admin_grant_credits(p_target uuid,p_amount integer,p_reason text default 'admin_grant')
returns table(user_id uuid,balance integer)
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_admin uuid; v_balance integer;
begin
  v_admin := (auth.user_id())::uuid;
  if not public.nexus_is_owner(v_admin) then raise exception 'admin_required'; end if;
  if p_amount is null or p_amount < 1 or p_amount > 1000000 then raise exception 'invalid_amount'; end if;
  update public.nexus_profiles set credits_balance=credits_balance+p_amount,updated_at=now()
   where nexus_profiles.user_id=p_target returning credits_balance into v_balance;
  if v_balance is null then raise exception 'target_profile_not_found'; end if;
  insert into public.nexus_credit_ledger(user_id,delta,reason,balance_after)
   values(p_target,p_amount,'admin:'||coalesce(nullif(trim(p_reason),''),'grant'),v_balance);
  insert into public.nexus_admin_audit(admin_user_id,target_user_id,action,details)
   values(v_admin,p_target,'grant_credits',jsonb_build_object('amount',p_amount,'reason',p_reason,'balance_after',v_balance));
  return query select p_target,v_balance;
end
$$;

create or replace function public.nexus_admin_set_unlimited(p_target uuid,p_unlimited boolean)
returns table(user_id uuid,staff_role text,unlimited boolean)
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_admin uuid; v_role text;
begin
  v_admin := (auth.user_id())::uuid;
  if not public.nexus_is_owner(v_admin) then raise exception 'admin_required'; end if;
  select role into v_role from public.nexus_staff_accounts where user_id=p_target;
  if v_role='owner' and not coalesce(p_unlimited,false) then raise exception 'owner_must_remain_unlimited'; end if;
  if v_role is null then
    if coalesce(p_unlimited,false) then
      insert into public.nexus_staff_accounts(user_id,role,unlimited_qa) values(p_target,'unlimited_user',true);
      v_role := 'unlimited_user';
    else
      return query select p_target,null::text,false; return;
    end if;
  else
    update public.nexus_staff_accounts set unlimited_qa=coalesce(p_unlimited,false) where user_id=p_target;
  end if;
  insert into public.nexus_admin_audit(admin_user_id,target_user_id,action,details)
    values(v_admin,p_target,'set_unlimited',jsonb_build_object('enabled',coalesce(p_unlimited,false),'role',v_role));
  return query select p_target,v_role,coalesce(p_unlimited,false);
end
$$;

create or replace function public.nexus_admin_set_beta(p_target uuid,p_enabled boolean)
returns table(user_id uuid,staff_role text,unlimited boolean)
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_admin uuid; v_role text; v_unlimited boolean;
begin
  v_admin := (auth.user_id())::uuid;
  if not public.nexus_is_owner(v_admin) then raise exception 'admin_required'; end if;
  select role,unlimited_qa into v_role,v_unlimited from public.nexus_staff_accounts where user_id=p_target;
  if v_role='owner' then raise exception 'owner_role_protected'; end if;
  if coalesce(p_enabled,false) then
    insert into public.nexus_staff_accounts(user_id,role,unlimited_qa)
      values(p_target,'beta_tester',true)
      on conflict(user_id) do update set role='beta_tester',unlimited_qa=true;
    v_role:='beta_tester'; v_unlimited:=true;
  elsif v_role='beta_tester' then
    delete from public.nexus_staff_accounts where user_id=p_target;
    v_role:=null; v_unlimited:=false;
  end if;
  insert into public.nexus_admin_audit(admin_user_id,target_user_id,action,details)
    values(v_admin,p_target,'set_beta',jsonb_build_object('enabled',coalesce(p_enabled,false),'role',v_role,'unlimited',coalesce(v_unlimited,false)));
  return query select p_target,v_role,coalesce(v_unlimited,false);
end
$$;

create or replace function public.nexus_admin_set_display_name(p_target uuid,p_display_name text)
returns text language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_admin uuid; v_name text;
begin
  v_admin := (auth.user_id())::uuid;
  if not public.nexus_is_owner(v_admin) then raise exception 'admin_required'; end if;
  v_name:=left(trim(coalesce(p_display_name,'')),120);
  if length(v_name)<2 then raise exception 'invalid_display_name'; end if;
  update public.nexus_profiles set display_name=v_name,updated_at=now() where user_id=p_target;
  if not found then raise exception 'target_profile_not_found'; end if;
  insert into public.nexus_admin_audit(admin_user_id,target_user_id,action,details)
    values(v_admin,p_target,'set_display_name',jsonb_build_object('display_name',v_name));
  return v_name;
end
$$;

create or replace function public.nexus_admin_list_beta_feedback()
returns table(id uuid,user_id uuid,email text,name text,kind text,severity text,title text,description text,repro_steps text,expected_result text,actual_result text,page_url text,status text,admin_note text,created_at timestamptz,updated_at timestamptz)
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_admin uuid;
begin
  v_admin := (auth.user_id())::uuid;
  if not public.nexus_is_owner(v_admin) then raise exception 'admin_required'; end if;
  return query
  select f.id,f.user_id,u.email,u.name,f.kind,f.severity,f.title,f.description,f.repro_steps,f.expected_result,f.actual_result,f.page_url,f.status,f.admin_note,f.created_at,f.updated_at
  from public.nexus_beta_feedback f join neon_auth."user" u on u.id=f.user_id
  order by case f.severity when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end,f.created_at desc;
end
$$;

create or replace function public.nexus_admin_update_beta_feedback(p_id uuid,p_status text,p_admin_note text default null)
returns boolean language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_admin uuid;
begin
  v_admin := (auth.user_id())::uuid;
  if not public.nexus_is_owner(v_admin) then raise exception 'admin_required'; end if;
  if p_status not in ('new','triaged','in_progress','fixed','verified','closed','wont_fix') then raise exception 'invalid_status'; end if;
  update public.nexus_beta_feedback set status=p_status,admin_note=left(p_admin_note,8000),updated_at=now() where id=p_id;
  if not found then raise exception 'feedback_not_found'; end if;
  insert into public.nexus_admin_audit(admin_user_id,action,details)
    values(v_admin,'update_beta_feedback',jsonb_build_object('feedback_id',p_id,'status',p_status));
  return true;
end
$$;

-- Align upload ticket policy with the existing 250 MiB table constraint.
create or replace function public.nexus_create_upload_ticket(p_conversation_id uuid, p_filename text, p_mime text, p_size bigint)
returns table(ticket_id uuid, object_key text, expires_at timestamp with time zone)
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_user uuid; v_ticket uuid; v_key text; v_name text; v_exp timestamptz; v_recent integer;
begin
  v_user := (auth.user_id())::uuid;
  if v_user is null then raise exception 'not_authenticated'; end if;
  if not exists(select 1 from public.nexus_conversations where id=p_conversation_id and user_id=v_user)
    then raise exception 'conversation_not_owned'; end if;
  if p_size is null or p_size <= 0 or p_size > 262144000
    then raise exception 'file_size_not_allowed_250mb'; end if;
  select count(*) into v_recent from public.nexus_upload_tickets
   where user_id=v_user and created_at > now()-interval '1 hour';
  if v_recent >= 20 then raise exception 'upload_rate_limit'; end if;
  v_name := left(regexp_replace(coalesce(nullif(trim(p_filename),''),'file'),'[^A-Za-z0-9._-]+','_','g'),180);
  v_ticket := gen_random_uuid();
  v_key := v_user::text||'/'||v_ticket::text||'/'||v_name;
  v_exp := now()+interval '15 minutes';
  insert into public.nexus_upload_tickets(ticket_id,user_id,conversation_id,object_key,filename,mime_type,size_bytes,expires_at)
  values(v_ticket,v_user,p_conversation_id,v_key,left(p_filename,255),left(coalesce(p_mime,''),160),p_size,v_exp);
  return query select v_ticket,v_key,v_exp;
end
$$;
