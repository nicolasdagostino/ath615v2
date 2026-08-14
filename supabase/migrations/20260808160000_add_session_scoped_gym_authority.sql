-- Session-scoped gym selection for the Web. Operational policies remain
-- legacy until a later vertical explicitly adopts effective_gym_*().

create table public.web_app_session_preferences (
  session_id uuid primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  active_gym_id uuid references public.gyms(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
drop trigger if exists web_app_session_preferences_touch_updated_at
  on public.web_app_session_preferences;
create trigger web_app_session_preferences_touch_updated_at
before update on public.web_app_session_preferences
for each row execute function public.touch_multi_gym_updated_at();
alter table public.web_app_session_preferences enable row level security;
create or replace function public.auth_session_id()
returns uuid
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $function$
declare
  v_session_id text := auth.jwt() ->> 'session_id';
begin
  if v_session_id is null or btrim(v_session_id) = '' then
    return null;
  end if;

  return v_session_id::uuid;
exception
  when invalid_text_representation then
    return null;
end;
$function$;
drop policy if exists "users read current web session preference"
  on public.web_app_session_preferences;
create policy "users read current web session preference"
on public.web_app_session_preferences
for select
to authenticated
using (
  user_id = auth.uid()
  and session_id = public.auth_session_id()
);
revoke all on table public.web_app_session_preferences from public;
revoke all on table public.web_app_session_preferences from anon;
revoke all on table public.web_app_session_preferences from authenticated;
grant select on table public.web_app_session_preferences to authenticated;
create or replace function public.register_web_app_session()
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_session_id uuid := public.auth_session_id();
begin
  if v_user_id is null or v_session_id is null then
    raise exception using errcode = '42501', message = 'unauthenticated';
  end if;

  insert into public.web_app_session_preferences (session_id, user_id)
  values (v_session_id, v_user_id)
  on conflict (session_id) do nothing;

  if not exists (
    select 1
    from public.web_app_session_preferences wsp
    where wsp.session_id = v_session_id
      and wsp.user_id = v_user_id
  ) then
    raise exception using errcode = '42501', message = 'session_access_denied';
  end if;

  return v_session_id;
end;
$function$;
create or replace function public.set_web_active_gym(p_gym_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_session_id uuid := public.auth_session_id();
begin
  if v_user_id is null or v_session_id is null then
    raise exception using errcode = '42501', message = 'unauthenticated';
  end if;

  if p_gym_id is null then
    raise exception using errcode = '22023', message = 'invalid_gym';
  end if;

  perform 1
  from public.web_app_session_preferences wsp
  where wsp.session_id = v_session_id
    and wsp.user_id = v_user_id
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'web_session_not_registered';
  end if;

  perform 1
  from public.gym_members gm
  where gm.user_id = v_user_id
    and gm.gym_id = p_gym_id
    and gm.is_active = true
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'gym_access_denied';
  end if;

  update public.web_app_session_preferences
  set active_gym_id = p_gym_id
  where session_id = v_session_id
    and user_id = v_user_id;

  return p_gym_id;
end;
$function$;
create or replace function public.effective_gym_id()
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_session_id uuid := public.auth_session_id();
  v_selected_gym_id uuid;
  v_is_web_session boolean := false;
begin
  if v_user_id is null then
    return null;
  end if;

  if v_session_id is not null then
    select true, wsp.active_gym_id
    into v_is_web_session, v_selected_gym_id
    from public.web_app_session_preferences wsp
    where wsp.session_id = v_session_id
      and wsp.user_id = v_user_id;
  end if;

  if v_is_web_session then
    if v_selected_gym_id is null then
      return null;
    end if;

    if exists (
      select 1
      from public.gym_members gm
      where gm.user_id = v_user_id
        and gm.gym_id = v_selected_gym_id
        and gm.is_active = true
    ) then
      return v_selected_gym_id;
    end if;

    return null;
  end if;

  select p.gym_id
  into v_selected_gym_id
  from public.profiles p
  where p.id = v_user_id;

  return v_selected_gym_id;
end;
$function$;
create or replace function public.effective_gym_role()
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_session_id uuid := public.auth_session_id();
begin
  if v_user_id is null then
    return null;
  end if;

  if v_session_id is not null and exists (
    select 1
    from public.web_app_session_preferences wsp
    where wsp.session_id = v_session_id
      and wsp.user_id = v_user_id
  ) then
    return (
      select gm.role
      from public.gym_members gm
      where gm.user_id = v_user_id
        and gm.gym_id = public.effective_gym_id()
        and gm.is_active = true
    );
  end if;

  return (select p.role from public.profiles p where p.id = v_user_id);
end;
$function$;
create or replace function public.effective_gym_is_coach()
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_session_id uuid := public.auth_session_id();
begin
  if v_user_id is null then
    return false;
  end if;

  if v_session_id is not null and exists (
    select 1
    from public.web_app_session_preferences wsp
    where wsp.session_id = v_session_id
      and wsp.user_id = v_user_id
  ) then
    return coalesce((
      select gm.is_coach or gm.role = 'coach'
      from public.gym_members gm
      where gm.user_id = v_user_id
        and gm.gym_id = public.effective_gym_id()
        and gm.is_active = true
    ), false);
  end if;

  return coalesce((
    select p.is_coach or p.role = 'coach'
    from public.profiles p
    where p.id = v_user_id
  ), false);
end;
$function$;
revoke all on function public.auth_session_id() from public;
revoke all on function public.auth_session_id() from anon;
revoke all on function public.auth_session_id() from authenticated;
grant execute on function public.auth_session_id() to authenticated;
revoke all on function public.register_web_app_session() from public;
revoke all on function public.register_web_app_session() from anon;
revoke all on function public.register_web_app_session() from authenticated;
grant execute on function public.register_web_app_session() to authenticated;
revoke all on function public.set_web_active_gym(uuid) from public;
revoke all on function public.set_web_active_gym(uuid) from anon;
revoke all on function public.set_web_active_gym(uuid) from authenticated;
grant execute on function public.set_web_active_gym(uuid) to authenticated;
revoke all on function public.effective_gym_id() from public;
revoke all on function public.effective_gym_id() from anon;
revoke all on function public.effective_gym_id() from authenticated;
grant execute on function public.effective_gym_id() to authenticated;
revoke all on function public.effective_gym_role() from public;
revoke all on function public.effective_gym_role() from anon;
revoke all on function public.effective_gym_role() from authenticated;
grant execute on function public.effective_gym_role() to authenticated;
revoke all on function public.effective_gym_is_coach() from public;
revoke all on function public.effective_gym_is_coach() from anon;
revoke all on function public.effective_gym_is_coach() from authenticated;
grant execute on function public.effective_gym_is_coach() to authenticated;
comment on table public.web_app_session_preferences is
  'Web-only gym selection keyed by the authenticated Supabase session_id. Rows do not authorize access without an active gym_members relationship.';
comment on function public.effective_gym_id() is
  'Returns the registered Web session gym, or the legacy profile gym only when the current Supabase session has no Web registration.';
comment on table public.user_app_preferences is
  'Non-authoritative user-level preferences. active_gym_id must not be used by new operational RLS.';
comment on function public.set_active_gym(uuid) is
  'Legacy user-level selection retained for compatibility. New operational RLS must use the session-scoped effective_gym_* helpers.';
