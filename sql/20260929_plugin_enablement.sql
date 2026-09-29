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
security invoker
set search_path = public
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

grant execute
on function public.nexus_set_plugin_enabled(text,boolean,boolean)
to authenticated;
