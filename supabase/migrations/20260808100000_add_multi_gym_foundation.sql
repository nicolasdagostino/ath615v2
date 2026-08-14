-- Multi-gym foundation. Legacy profile gym, role and Coach fields remain the
-- production authority until later verticals migrate each operational module.

create table if not exists public.gym_members (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id),
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null,
  is_active boolean not null default true,
  is_coach boolean not null default false,
  joined_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  invited_by uuid references public.profiles(id) on delete set null,
  constraint gym_members_gym_user_key unique (gym_id, user_id),
  constraint gym_members_role_check check (role in ('admin', 'athlete', 'coach'))
);
create table if not exists public.user_app_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  active_gym_id uuid references public.gyms(id) on delete set null,
  updated_at timestamptz not null default now()
);
create index if not exists gym_members_user_active_gym_idx
  on public.gym_members (user_id, is_active, gym_id);
create or replace function public.touch_multi_gym_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;
revoke all on function public.touch_multi_gym_updated_at() from public;
revoke all on function public.touch_multi_gym_updated_at() from anon;
revoke all on function public.touch_multi_gym_updated_at() from authenticated;
drop trigger if exists gym_members_touch_updated_at on public.gym_members;
create trigger gym_members_touch_updated_at
before update on public.gym_members
for each row execute function public.touch_multi_gym_updated_at();
drop trigger if exists user_app_preferences_touch_updated_at
  on public.user_app_preferences;
create trigger user_app_preferences_touch_updated_at
before update on public.user_app_preferences
for each row execute function public.touch_multi_gym_updated_at();
-- Owners remain global through gyms.owner_id. A legacy owner profile pointing
-- at the last-created gym is not evidence of operational membership.
do $backfill$
declare
  v_eligible bigint;
  v_existing bigint;
  v_inserted bigint;
  v_excluded_owners bigint;
begin
  select count(*) into v_eligible
  from public.profiles p
  where p.gym_id is not null
    and p.role in ('admin', 'athlete', 'coach');

  select count(*) into v_existing
  from public.profiles p
  join public.gym_members gm
    on gm.gym_id = p.gym_id and gm.user_id = p.id
  where p.gym_id is not null
    and p.role in ('admin', 'athlete', 'coach');

  select count(*) into v_excluded_owners
  from public.profiles p
  where p.gym_id is not null and p.role = 'owner';

  insert into public.gym_members (
    gym_id, user_id, role, is_active, is_coach, joined_at
  )
  select
    p.gym_id,
    p.id,
    p.role,
    coalesce(p.is_active, true),
    coalesce(p.is_coach, false),
    coalesce(p.created_at, now())
  from public.profiles p
  where p.gym_id is not null
    and p.role in ('admin', 'athlete', 'coach')
  on conflict (gym_id, user_id) do nothing;

  get diagnostics v_inserted = row_count;
  raise notice
    'multi_gym_backfill eligible=% existing=% inserted=% excluded_owners=%',
    v_eligible, v_existing, v_inserted, v_excluded_owners;
end;
$backfill$;
alter table public.gym_members enable row level security;
alter table public.user_app_preferences enable row level security;
drop policy if exists "users read own gym memberships" on public.gym_members;
create policy "users read own gym memberships"
on public.gym_members
for select
to authenticated
using (user_id = auth.uid());
drop policy if exists "users read own app preferences"
  on public.user_app_preferences;
create policy "users read own app preferences"
on public.user_app_preferences
for select
to authenticated
using (user_id = auth.uid());
revoke all on table public.gym_members from public;
revoke all on table public.gym_members from anon;
revoke all on table public.gym_members from authenticated;
grant select on table public.gym_members to authenticated;
revoke all on table public.user_app_preferences from public;
revoke all on table public.user_app_preferences from anon;
revoke all on table public.user_app_preferences from authenticated;
grant select on table public.user_app_preferences to authenticated;
create or replace function public.current_gym_id()
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_selected uuid;
  v_only uuid;
  v_count integer;
begin
  if v_user_id is null then
    return null;
  end if;

  select uap.active_gym_id
  into v_selected
  from public.user_app_preferences uap
  where uap.user_id = v_user_id;

  if v_selected is not null and exists (
    select 1
    from public.gym_members gm
    where gm.user_id = v_user_id
      and gm.gym_id = v_selected
      and gm.is_active = true
  ) then
    return v_selected;
  end if;

  select count(*), (array_agg(gm.gym_id order by gm.gym_id))[1]
  into v_count, v_only
  from public.gym_members gm
  where gm.user_id = v_user_id
    and gm.is_active = true;

  if v_count = 1 then
    return v_only;
  end if;

  return null;
end;
$function$;
create or replace function public.current_gym_role()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select gm.role
  from public.gym_members gm
  where gm.user_id = auth.uid()
    and gm.gym_id = public.current_gym_id()
    and gm.is_active = true;
$function$;
create or replace function public.current_gym_is_coach()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select coalesce((
    select gm.is_coach or gm.role = 'coach'
    from public.gym_members gm
    where gm.user_id = auth.uid()
      and gm.gym_id = public.current_gym_id()
      and gm.is_active = true
  ), false);
$function$;
create or replace function public.is_current_gym_member()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select public.current_gym_id() is not null;
$function$;
create or replace function public.set_active_gym(p_gym_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'unauthenticated';
  end if;

  if p_gym_id is null then
    raise exception using errcode = '22023', message = 'invalid_gym';
  end if;

  -- The row lock serializes selection with future relationship deactivation.
  perform 1
  from public.gym_members gm
  where gm.user_id = v_user_id
    and gm.gym_id = p_gym_id
    and gm.is_active = true
  for update;

  if not found then
    -- Do not reveal whether the gym or another user's relationship exists.
    raise exception using errcode = '42501', message = 'gym_access_denied';
  end if;

  insert into public.user_app_preferences (user_id, active_gym_id)
  values (v_user_id, p_gym_id)
  on conflict (user_id) do update
    set active_gym_id = excluded.active_gym_id;

  return p_gym_id;
end;
$function$;
revoke all on function public.current_gym_id() from public;
revoke all on function public.current_gym_id() from anon;
revoke all on function public.current_gym_id() from authenticated;
grant execute on function public.current_gym_id() to authenticated;
revoke all on function public.current_gym_role() from public;
revoke all on function public.current_gym_role() from anon;
revoke all on function public.current_gym_role() from authenticated;
grant execute on function public.current_gym_role() to authenticated;
revoke all on function public.current_gym_is_coach() from public;
revoke all on function public.current_gym_is_coach() from anon;
revoke all on function public.current_gym_is_coach() from authenticated;
grant execute on function public.current_gym_is_coach() to authenticated;
revoke all on function public.is_current_gym_member() from public;
revoke all on function public.is_current_gym_member() from anon;
revoke all on function public.is_current_gym_member() from authenticated;
grant execute on function public.is_current_gym_member() to authenticated;
revoke all on function public.set_active_gym(uuid) from public;
revoke all on function public.set_active_gym(uuid) from anon;
revoke all on function public.set_active_gym(uuid) from authenticated;
grant execute on function public.set_active_gym(uuid) to authenticated;
