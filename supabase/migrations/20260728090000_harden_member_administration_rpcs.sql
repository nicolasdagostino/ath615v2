-- Harden administrative member mutations while preserving the Flutter/web API.

do $prerequisite$
begin
  if to_regclass('public.profiles') is null then
    raise exception 'deployment_prerequisite_missing: public.profiles';
  end if;
end;
$prerequisite$;
create or replace function public.update_member_role(
  p_member_id uuid,
  p_role text
)
returns public.profiles
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_actor public.profiles%rowtype;
  v_member public.profiles%rowtype;
  v_updated public.profiles%rowtype;
begin
  if auth.uid() is null then
    raise exception using errcode = 'P0001', message = 'unauthenticated';
  end if;

  -- Read the gym without taking a profile lock, then serialize all
  -- administrative continuity decisions for that gym. Acquiring this lock
  -- before row locks prevents A->B/B->A deadlocks.
  select *
  into v_actor
  from public.profiles
  where id = auth.uid();

  if not found or not coalesce(v_actor.is_active, false) then
    raise exception using errcode = 'P0001', message = 'unauthorized';
  end if;

  if v_actor.gym_id is null then
    raise exception using errcode = 'P0001', message = 'gym_not_found';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_actor.gym_id::text, 615)
  );

  -- The actor may have changed while waiting for the gym lock.
  select *
  into v_actor
  from public.profiles
  where id = auth.uid()
  for update;

  if not found
    or not coalesce(v_actor.is_active, false)
    or v_actor.gym_id is null
  then
    raise exception using errcode = 'P0001', message = 'unauthorized';
  end if;

  if v_actor.role not in ('admin', 'owner') then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;

  if p_role is null or p_role not in ('admin', 'athlete') then
    raise exception using errcode = 'P0001', message = 'invalid_role';
  end if;

  select *
  into v_member
  from public.profiles
  where id = p_member_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'member_not_found';
  end if;

  if v_member.gym_id is distinct from v_actor.gym_id then
    raise exception using errcode = 'P0001', message = 'cross_gym_forbidden';
  end if;

  if v_member.role = 'owner' then
    raise exception using errcode = 'P0001', message = 'owner_protected';
  end if;

  if v_member.role = 'admin' and p_role = 'athlete' and not exists (
    select 1
    from public.profiles p
    where p.gym_id = v_actor.gym_id
      and p.id <> v_member.id
      and p.role in ('admin', 'owner')
      and coalesce(p.is_active, false)
  ) then
    raise exception using errcode = 'P0001', message = 'last_admin_not_allowed';
  end if;

  update public.profiles
  set role = p_role
  where id = v_member.id
  returning *
  into v_updated;

  return v_updated;
end;
$function$;
revoke all on function public.update_member_role(uuid, text) from public;
revoke all on function public.update_member_role(uuid, text) from anon;
revoke all on function public.update_member_role(uuid, text) from authenticated;
revoke all on function public.update_member_role(uuid, text) from service_role;
grant execute on function public.update_member_role(uuid, text)
  to authenticated;
create or replace function public.set_gym_member_active(
  p_member_id uuid,
  p_is_active boolean
)
returns public.profiles
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_actor public.profiles%rowtype;
  v_member public.profiles%rowtype;
  v_updated public.profiles%rowtype;
begin
  if auth.uid() is null then
    raise exception using errcode = 'P0001', message = 'unauthenticated';
  end if;

  if p_is_active is null then
    raise exception using errcode = 'P0001', message = 'invalid_status';
  end if;

  -- See update_member_role: the gym advisory lock serializes all role/status
  -- transitions that could remove the final active administrator.
  select *
  into v_actor
  from public.profiles
  where id = auth.uid();

  if not found or not coalesce(v_actor.is_active, false) then
    raise exception using errcode = 'P0001', message = 'unauthorized';
  end if;

  if v_actor.gym_id is null then
    raise exception using errcode = 'P0001', message = 'gym_not_found';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_actor.gym_id::text, 615)
  );

  select *
  into v_actor
  from public.profiles
  where id = auth.uid()
  for update;

  if not found
    or not coalesce(v_actor.is_active, false)
    or v_actor.gym_id is null
  then
    raise exception using errcode = 'P0001', message = 'unauthorized';
  end if;

  if v_actor.role not in ('admin', 'owner') then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;

  select *
  into v_member
  from public.profiles
  where id = p_member_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'member_not_found';
  end if;

  if v_member.gym_id is distinct from v_actor.gym_id then
    raise exception using errcode = 'P0001', message = 'cross_gym_forbidden';
  end if;

  if v_member.role = 'owner' then
    raise exception using errcode = 'P0001', message = 'owner_protected';
  end if;

  if not p_is_active
    and coalesce(v_member.is_active, false)
    and v_member.role = 'admin'
    and not exists (
      select 1
      from public.profiles p
      where p.gym_id = v_actor.gym_id
        and p.id <> v_member.id
        and p.role in ('admin', 'owner')
        and coalesce(p.is_active, false)
    )
  then
    raise exception using errcode = 'P0001', message = 'last_admin_not_allowed';
  end if;

  update public.profiles
  set is_active = p_is_active
  where id = v_member.id
  returning *
  into v_updated;

  return v_updated;
end;
$function$;
revoke all on function public.set_gym_member_active(uuid, boolean) from public;
revoke all on function public.set_gym_member_active(uuid, boolean) from anon;
revoke all on function public.set_gym_member_active(uuid, boolean) from authenticated;
revoke all on function public.set_gym_member_active(uuid, boolean) from service_role;
grant execute on function public.set_gym_member_active(uuid, boolean)
  to authenticated;
