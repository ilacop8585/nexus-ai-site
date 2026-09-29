-- NEXUS AI provider OAuth token vault
-- Applied to production Neon on 2026-09-29.
-- Tokens are encrypted at rest in a private schema that is not exposed by the Data API.

create schema if not exists private;
revoke all on schema private from public;
revoke all on schema private from anonymous;
revoke all on schema private from authenticated;

create table if not exists private.nexus_plugin_crypto (
  id smallint primary key check (id=1),
  secret text not null,
  created_at timestamptz not null default now()
);

insert into private.nexus_plugin_crypto(id,secret)
values(1,encode(gen_random_bytes(32),'hex'))
on conflict (id) do nothing;

create table if not exists private.nexus_plugin_tokens (
  user_id uuid not null references neon_auth."user"(id) on delete cascade,
  plugin_id text not null,
  provider text not null,
  access_token bytea not null,
  refresh_token bytea,
  token_type text,
  scope text,
  expires_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(user_id,plugin_id)
);

revoke all on private.nexus_plugin_crypto from public, anonymous, authenticated;
revoke all on private.nexus_plugin_tokens from public, anonymous, authenticated;

create or replace function public.nexus_store_plugin_oauth_token(
  p_plugin_id text,
  p_provider text,
  p_access_token text,
  p_refresh_token text default null,
  p_token_type text default null,
  p_scope text default null,
  p_expires_in bigint default null,
  p_metadata jsonb default '{}'::jsonb
)
returns table(plugin_id text, enabled boolean, connection_status text)
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_user uuid;
  v_key text;
begin
  v_user := nullif(auth.user_id(),'')::uuid;
  if v_user is null then raise exception 'authentication_required'; end if;
  if p_plugin_id not in ('neon','github') then raise exception 'unsupported_plugin'; end if;
  if p_provider is null or length(p_provider)>80 then raise exception 'invalid_provider'; end if;
  if p_access_token is null or length(p_access_token)<8 then raise exception 'invalid_access_token'; end if;

  select c.secret into v_key from private.nexus_plugin_crypto c where c.id=1;
  if v_key is null then raise exception 'crypto_key_missing'; end if;

  insert into private.nexus_plugin_tokens(
    user_id,plugin_id,provider,access_token,refresh_token,token_type,scope,expires_at,metadata,updated_at
  ) values(
    v_user,p_plugin_id,p_provider,
    pgp_sym_encrypt(p_access_token,v_key,'cipher-algo=aes256'),
    case when p_refresh_token is null or p_refresh_token='' then null else pgp_sym_encrypt(p_refresh_token,v_key,'cipher-algo=aes256') end,
    left(p_token_type,40),left(p_scope,2000),
    case when p_expires_in is null then null else now()+make_interval(secs=>greatest(0,least(p_expires_in,31536000))::int) end,
    coalesce(p_metadata,'{}'::jsonb),now()
  )
  on conflict on constraint nexus_plugin_tokens_pkey do update
  set provider=excluded.provider,
      access_token=excluded.access_token,
      refresh_token=coalesce(excluded.refresh_token,private.nexus_plugin_tokens.refresh_token),
      token_type=excluded.token_type,
      scope=excluded.scope,
      expires_at=excluded.expires_at,
      metadata=excluded.metadata,
      updated_at=now();

  insert into public.nexus_user_plugins(user_id,plugin_id,enabled,connection_status,enabled_at,disabled_at,updated_at)
  values(v_user,p_plugin_id,true,'connected',now(),null,now())
  on conflict on constraint nexus_user_plugins_pkey do update
  set enabled=true,connection_status='connected',
      enabled_at=coalesce(public.nexus_user_plugins.enabled_at,now()),
      disabled_at=null,updated_at=now();

  return query
  select p.plugin_id,p.enabled,p.connection_status
  from public.nexus_user_plugins p
  where p.user_id=v_user and p.plugin_id=p_plugin_id;
end;
$$;

revoke all on function public.nexus_store_plugin_oauth_token(text,text,text,text,text,text,bigint,jsonb) from public;
grant execute on function public.nexus_store_plugin_oauth_token(text,text,text,text,text,text,bigint,jsonb) to authenticated;

create or replace function public.nexus_disconnect_plugin(p_plugin_id text)
returns boolean
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare v_user uuid;
begin
  v_user := nullif(auth.user_id(),'')::uuid;
  if v_user is null then raise exception 'authentication_required'; end if;
  delete from private.nexus_plugin_tokens t where t.user_id=v_user and t.plugin_id=p_plugin_id;
  update public.nexus_user_plugins p
     set connection_status='disconnected',updated_at=now()
   where p.user_id=v_user and p.plugin_id=p_plugin_id;
  return true;
end;
$$;

revoke all on function public.nexus_disconnect_plugin(text) from public;
grant execute on function public.nexus_disconnect_plugin(text) to authenticated;
