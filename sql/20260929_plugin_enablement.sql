-- NEXUS AI per-user plugin enablement
-- Applied to Neon project NEXUS AI on 2026-09-29.
-- No third-party credentials are stored in this table.

create table if not exists public.nexus_user_plugins (
  user_id uuid not null references neon_auth."user"(id) on delete cascade,
  plugin_id text not null,
  enabled boolean not null default true,
  connection_status text not null default 'disconnected',
  preferences jsonb not null default '{}'::jsonb,
  enabled_at timestamptz,
  disabled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, plugin_id),
  constraint nexus_user_plugins_plugin_id_check
    check (length(plugin_id) between 1 and 120 and plugin_id ~ '^[a-z0-9][a-z0-9._-]*$'),
  constraint nexus_user_plugins_connection_status_check
    check (connection_status in ('not_required','disconnected','pending','connected','error'))
);

alter table public.nexus_user_plugins enable row level security;

drop policy if exists nexus_user_plugins_own on public.nexus_user_plugins;
create policy nexus_user_plugins_own
on public.nexus_user_plugins
for all
to authenticated
using (auth.user_id() = user_id::text)
with check (auth.user_id() = user_id::text);

grant select, insert, update, delete
on public.nexus_user_plugins
to authenticated;

create or replace function public.nexus_set_plugin_enabled(
  p_plugin_id text,
  p_enabled boolean,
  p_connection_required boolean default true
)
returns table(
  plugin_id text,
  enabled boolean,
  connection_status text,
  enabled_at timestamptz,
  disabled_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid;
  v_connection_status text;
begin
  v_user := nullif(auth.user_id(),'')::uuid;
  if v_user is null then
    raise exception 'authentication_required';
  end if;

  if p_plugin_id is null
     or length(p_plugin_id) < 1
     or length(p_plugin_id) > 120
     or p_plugin_id !~ '^[a-z0-9][a-z0-9._-]*$' then
    raise exception 'invalid_plugin_id';
  end if;

  v_connection_status :=
    case when p_connection_required then 'disconnected' else 'not_required' end;

  insert into public.nexus_user_plugins(
    user_id, plugin_id, enabled, connection_status,
    enabled_at, disabled_at, updated_at
  )
  values(
    v_user, p_plugin_id, p_enabled, v_connection_status,
    case when p_enabled then now() else null end,
    case when p_enabled then null else now() end,
    now()
  )
  on conflict (user_id, plugin_id) do update
  set enabled = excluded.enabled,
      connection_status = case
        when excluded.enabled = false then public.nexus_user_plugins.connection_status
        when public.nexus_user_plugins.connection_status = 'connected' then 'connected'
        else excluded.connection_status
      end,
      enabled_at = case
        when excluded.enabled then coalesce(public.nexus_user_plugins.enabled_at, now())
        else public.nexus_user_plugins.enabled_at
      end,
      disabled_at = case when excluded.enabled then null else now() end,
      updated_at = now();

  return query
  select p.plugin_id, p.enabled, p.connection_status, p.enabled_at, p.disabled_at
  from public.nexus_user_plugins p
  where p.user_id = v_user
    and p.plugin_id = p_plugin_id;
end;
$$;

revoke all on function public.nexus_set_plugin_enabled(text,boolean,boolean) from public;

grant execute
on function public.nexus_set_plugin_enabled(text,boolean,boolean)
to authenticated;


-- Sync a Google-backed plugin after Better Auth OAuth returns.
-- This function never returns OAuth tokens; it only validates granted scopes
-- from Neon Auth and updates the account-scoped plugin connection state.
create or replace function public.nexus_sync_plugin_connection(p_plugin_id text)
returns table(plugin_id text, enabled boolean, connection_status text, granted boolean)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid;
  v_required text[];
  v_granted text[] := array[]::text[];
  v_has_token boolean := false;
  v_connected boolean := false;
begin
  v_user := nullif(auth.user_id(),'')::uuid;
  if v_user is null then
    raise exception 'authentication_required';
  end if;

  v_required := case p_plugin_id
    when 'google-drive' then array['https://www.googleapis.com/auth/drive.readonly']
    when 'gmail' then array['https://www.googleapis.com/auth/gmail.readonly']
    when 'google-calendar' then array['https://www.googleapis.com/auth/calendar.readonly']
    when 'google-contacts' then array['https://www.googleapis.com/auth/contacts.readonly']
    when 'google-sheets' then array['https://www.googleapis.com/auth/spreadsheets.readonly']
    when 'youtube' then array['https://www.googleapis.com/auth/youtube.readonly']
    when 'bigquery' then array['https://www.googleapis.com/auth/bigquery.readonly']
    else null
  end;

  if v_required is null then
    raise exception 'connector_not_supported';
  end if;

  select
    regexp_split_to_array(coalesce(a.scope,''), '[,[:space:]]+'),
    (a."accessToken" is not null or a."refreshToken" is not null)
  into v_granted, v_has_token
  from neon_auth.account a
  where a."userId" = v_user
    and a."providerId" = 'google'
  order by a."updatedAt" desc
  limit 1;

  v_connected := coalesce(v_has_token,false)
    and coalesce(v_granted,array[]::text[]) @> v_required;

  insert into public.nexus_user_plugins(
    user_id, plugin_id, enabled, connection_status, enabled_at, disabled_at, updated_at
  )
  values(
    v_user, p_plugin_id, true,
    case when v_connected then 'connected' else 'disconnected' end,
    now(), null, now()
  )
  on conflict (user_id,plugin_id) do update
  set enabled=true,
      connection_status=case when v_connected then 'connected' else 'disconnected' end,
      enabled_at=coalesce(public.nexus_user_plugins.enabled_at,now()),
      disabled_at=null,
      updated_at=now();

  return query
  select p.plugin_id,p.enabled,p.connection_status,v_connected
  from public.nexus_user_plugins p
  where p.user_id=v_user and p.plugin_id=p_plugin_id;
end;
$$;

revoke all on function public.nexus_sync_plugin_connection(text) from public;
grant execute on function public.nexus_sync_plugin_connection(text) to authenticated;
