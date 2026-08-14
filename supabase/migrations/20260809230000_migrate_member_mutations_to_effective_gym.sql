-- Vertical 3C2: session-scoped member mutations with a deterministic legacy
-- mirror. Registered Web sessions mutate gym_members. Unregistered sessions
-- keep profiles as their authority and mirror the current legacy gym relation.

create or replace function public.is_registered_web_session()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and public.auth_session_id() is not null
    and exists (
      select 1
      from public.web_app_session_preferences wsp
      where wsp.session_id = public.auth_session_id()
        and wsp.user_id = auth.uid()
    );
$$;
create or replace function public.sync_legacy_gym_members(p_gym_id uuid)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
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
  where p.gym_id = p_gym_id
    and p.role in ('admin', 'athlete', 'coach')
  on conflict (gym_id, user_id) do update
  set role = excluded.role,
      is_active = excluded.is_active,
      is_coach = excluded.is_coach;
$$;
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
  v_user_id uuid := auth.uid();
  v_is_web boolean := public.is_registered_web_session();
  v_gym_id uuid;
  v_actor_role text;
  v_actor_profile public.profiles%rowtype;
  v_member_profile public.profiles%rowtype;
  v_member_relation public.gym_members%rowtype;
  v_updated public.profiles%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode='P0001', message='unauthenticated';
  end if;
  if p_member_id is null then
    raise exception using errcode='P0001', message='member_not_found';
  end if;
  if p_role is null or p_role not in ('admin', 'athlete') then
    raise exception using errcode='P0001', message='invalid_role';
  end if;

  select * into v_actor_profile from public.profiles where id=v_user_id;
  if not found then raise exception using errcode='P0001', message='unauthorized'; end if;

  if v_is_web then
    v_gym_id := public.effective_gym_id();
    v_actor_role := public.effective_gym_role();
    if v_gym_id is null then raise exception using errcode='P0001', message='unauthorized'; end if;
    if v_actor_role <> 'admin' then raise exception using errcode='P0001', message='forbidden'; end if;
  else
    if not coalesce(v_actor_profile.is_active,false) then raise exception using errcode='P0001', message='unauthorized'; end if;
    v_gym_id := v_actor_profile.gym_id;
    v_actor_role := v_actor_profile.role;
    if v_gym_id is null then raise exception using errcode='P0001', message='gym_not_found'; end if;
    if v_actor_role not in ('admin','owner') then raise exception using errcode='P0001', message='forbidden'; end if;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_gym_id::text,615));

  if v_is_web then
    if public.effective_gym_id() is distinct from v_gym_id or public.effective_gym_role() <> 'admin' then
      raise exception using errcode='P0001', message='unauthorized';
    end if;
  else
    select * into v_actor_profile from public.profiles where id=v_user_id for update;
    if not found or not coalesce(v_actor_profile.is_active,false)
       or v_actor_profile.gym_id is distinct from v_gym_id
       or v_actor_profile.role not in ('admin','owner') then
      raise exception using errcode='P0001', message='unauthorized';
    end if;
    perform public.sync_legacy_gym_members(v_gym_id);
  end if;

  select * into v_member_relation
  from public.gym_members gm
  where gm.gym_id=v_gym_id and gm.user_id=p_member_id
  for update;
  if not found then raise exception using errcode='P0001', message='member_not_found'; end if;

  select * into v_member_profile from public.profiles where id=p_member_id for update;
  if not found then raise exception using errcode='P0001', message='member_not_found'; end if;
  if v_member_profile.role='owner' then raise exception using errcode='P0001', message='owner_protected'; end if;

  if v_member_relation.role='admin' and p_role <> 'admin' and v_member_relation.is_active
     and not exists (
       select 1 from public.gym_members gm
       where gm.gym_id=v_gym_id and gm.user_id<>p_member_id
         and gm.role='admin' and gm.is_active
     ) then
    raise exception using errcode='P0001', message='last_admin_not_allowed';
  end if;

  update public.gym_members set role=p_role
  where gym_id=v_gym_id and user_id=p_member_id;

  if v_member_profile.gym_id is not distinct from v_gym_id then
    update public.profiles set role=p_role where id=p_member_id returning * into v_updated;
  else
    v_updated := v_member_profile;
    v_updated.role := p_role;
  end if;
  return v_updated;
end;
$function$;
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
  v_user_id uuid := auth.uid();
  v_is_web boolean := public.is_registered_web_session();
  v_gym_id uuid;
  v_actor_profile public.profiles%rowtype;
  v_member_profile public.profiles%rowtype;
  v_member_relation public.gym_members%rowtype;
  v_updated public.profiles%rowtype;
begin
  if v_user_id is null then raise exception using errcode='P0001', message='unauthenticated'; end if;
  if p_member_id is null then raise exception using errcode='P0001', message='member_not_found'; end if;
  if p_is_active is null then raise exception using errcode='P0001', message='invalid_status'; end if;

  select * into v_actor_profile from public.profiles where id=v_user_id;
  if not found then raise exception using errcode='P0001', message='unauthorized'; end if;
  if v_is_web then
    v_gym_id := public.effective_gym_id();
    if v_gym_id is null then raise exception using errcode='P0001', message='unauthorized'; end if;
    if public.effective_gym_role() <> 'admin' then raise exception using errcode='P0001', message='forbidden'; end if;
  else
    if not coalesce(v_actor_profile.is_active,false) then raise exception using errcode='P0001', message='unauthorized'; end if;
    v_gym_id := v_actor_profile.gym_id;
    if v_gym_id is null then raise exception using errcode='P0001', message='gym_not_found'; end if;
    if v_actor_profile.role not in ('admin','owner') then raise exception using errcode='P0001', message='forbidden'; end if;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_gym_id::text,615));
  if v_is_web then
    if public.effective_gym_id() is distinct from v_gym_id or public.effective_gym_role() <> 'admin' then
      raise exception using errcode='P0001', message='unauthorized';
    end if;
  else
    select * into v_actor_profile from public.profiles where id=v_user_id for update;
    if not found or not coalesce(v_actor_profile.is_active,false)
       or v_actor_profile.gym_id is distinct from v_gym_id
       or v_actor_profile.role not in ('admin','owner') then
      raise exception using errcode='P0001', message='unauthorized';
    end if;
    perform public.sync_legacy_gym_members(v_gym_id);
  end if;

  select * into v_member_relation from public.gym_members gm
  where gm.gym_id=v_gym_id and gm.user_id=p_member_id for update;
  if not found then raise exception using errcode='P0001', message='member_not_found'; end if;
  select * into v_member_profile from public.profiles where id=p_member_id for update;
  if not found then raise exception using errcode='P0001', message='member_not_found'; end if;
  if v_member_profile.role='owner' then raise exception using errcode='P0001', message='owner_protected'; end if;

  if not p_is_active and v_member_relation.is_active and v_member_relation.role='admin'
     and not exists (
       select 1 from public.gym_members gm
       where gm.gym_id=v_gym_id and gm.user_id<>p_member_id
         and gm.role='admin' and gm.is_active
     ) then
    raise exception using errcode='P0001', message='last_admin_not_allowed';
  end if;

  update public.gym_members set is_active=p_is_active
  where gym_id=v_gym_id and user_id=p_member_id;
  if v_member_profile.gym_id is not distinct from v_gym_id then
    update public.profiles set is_active=p_is_active where id=p_member_id returning * into v_updated;
  else
    v_updated := v_member_profile;
    v_updated.is_active := p_is_active;
  end if;
  return v_updated;
end;
$function$;
create or replace function public.set_member_coach_capability(
  p_member_id uuid,
  p_is_coach boolean
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_is_web boolean := public.is_registered_web_session();
  v_gym_id uuid;
  v_actor public.profiles%rowtype;
  v_member public.profiles%rowtype;
  v_relation public.gym_members%rowtype;
begin
  if v_user_id is null then raise exception using errcode='P0001', message='unauthenticated'; end if;
  if p_member_id is null or p_is_coach is null then raise exception using errcode='22023', message='invalid_parameters'; end if;
  select * into v_actor from public.profiles where id=v_user_id;
  if not found then raise exception using errcode='P0001', message='unauthorized'; end if;
  if v_is_web then
    v_gym_id := public.effective_gym_id();
    if v_gym_id is null then raise exception using errcode='P0001', message='unauthorized'; end if;
    if public.effective_gym_role() <> 'admin' then raise exception using errcode='P0001', message='forbidden'; end if;
  else
    if not coalesce(v_actor.is_active,false) then raise exception using errcode='P0001', message='unauthorized'; end if;
    v_gym_id := v_actor.gym_id;
    if v_gym_id is null then raise exception using errcode='P0001', message='gym_not_found'; end if;
    if v_actor.role not in ('admin','owner') then raise exception using errcode='P0001', message='forbidden'; end if;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_gym_id::text,615));
  if v_is_web then
    if public.effective_gym_id() is distinct from v_gym_id or public.effective_gym_role() <> 'admin' then
      raise exception using errcode='P0001', message='unauthorized';
    end if;
  else
    select * into v_actor from public.profiles where id=v_user_id for update;
    if not found or not coalesce(v_actor.is_active,false)
       or v_actor.gym_id is distinct from v_gym_id
       or v_actor.role not in ('admin','owner') then
      raise exception using errcode='P0001', message='unauthorized';
    end if;
    perform public.sync_legacy_gym_members(v_gym_id);
  end if;
  select * into v_relation from public.gym_members gm
  where gm.gym_id=v_gym_id and gm.user_id=p_member_id for update;
  if not found then raise exception using errcode='P0001', message='member_not_found'; end if;
  select * into v_member from public.profiles where id=p_member_id for update;
  if not found then raise exception using errcode='P0001', message='member_not_found'; end if;
  if v_member.role='owner' then raise exception using errcode='P0001', message='owner_protected'; end if;
  if not p_is_coach and v_relation.role='coach' then
    raise exception using errcode='P0001', message='coach_role_requires_capability';
  end if;
  update public.gym_members set is_coach=p_is_coach
  where gym_id=v_gym_id and user_id=p_member_id;
  if v_member.gym_id is not distinct from v_gym_id then
    update public.profiles set is_coach=p_is_coach where id=p_member_id;
  end if;
  return true;
end;
$function$;
create or replace function public.create_member_membership_from_plan(
  p_user_id uuid,
  p_plan_id uuid,
  p_credit_reason text,
  p_gym_id uuid
)
returns public.member_memberships
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_plan public.membership_plans%rowtype;
  v_duration_days integer;
  v_start_at timestamptz;
  v_end_at timestamptz;
  v_status text;
  v_last_unlimited_end timestamptz;
  v_membership public.member_memberships%rowtype;
begin
  if p_user_id is null then raise exception 'Missing user id'; end if;
  if p_plan_id is null or p_gym_id is null then raise exception 'Plan not found'; end if;
  if p_credit_reason not in ('assigned','paid') then raise exception 'Invalid membership credit reason'; end if;
  if not exists (select 1 from public.gym_members gm where gm.user_id=p_user_id and gm.gym_id=p_gym_id) then
    raise exception 'Member not found';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user_id::text || ':' || p_gym_id::text,616)
  );
  select * into v_plan from public.membership_plans
  where id=p_plan_id and gym_id=p_gym_id for update;
  if not found then raise exception 'Plan not found'; end if;
  if v_plan.is_active is distinct from true then raise exception 'Plan is not active'; end if;
  if v_plan.plan_type not in ('class_pack','unlimited') then raise exception 'Unsupported membership plan type'; end if;
  v_duration_days := greatest(coalesce(v_plan.duration_days,30),1);

  if v_plan.plan_type='class_pack' then
    if v_plan.credits is null or v_plan.credits<=0 then raise exception 'Class pack must have positive credits'; end if;
    v_start_at:=now(); v_end_at:=v_start_at+make_interval(days=>v_duration_days); v_status:='active';
  else
    perform 1 from public.member_memberships mm join public.membership_plans mp on mp.id=mm.plan_id
    where mm.user_id=p_user_id and mm.gym_id=p_gym_id and mm.status in ('active','scheduled')
      and mm.is_active and mp.plan_type='unlimited' for update of mm;
    if exists (
      select 1 from public.member_memberships mm join public.membership_plans mp on mp.id=mm.plan_id
      where mm.user_id=p_user_id and mm.gym_id=p_gym_id and mm.status in ('active','scheduled')
        and mm.is_active and mp.plan_type='unlimited' and coalesce(mm.expires_at,mm.ends_at) is null
    ) then raise exception 'Existing Unlimited membership has no end date'; end if;
    select max(coalesce(mm.expires_at,mm.ends_at)) into v_last_unlimited_end
    from public.member_memberships mm join public.membership_plans mp on mp.id=mm.plan_id
    where mm.user_id=p_user_id and mm.gym_id=p_gym_id and mm.status in ('active','scheduled')
      and mm.is_active and mp.plan_type='unlimited' and coalesce(mm.expires_at,mm.ends_at)>now();
    v_start_at:=greatest(now(),coalesce(v_last_unlimited_end,now()));
    v_end_at:=v_start_at+make_interval(days=>v_duration_days);
    v_status:=case when v_start_at>now() then 'scheduled' else 'active' end;
  end if;

  insert into public.member_memberships(
    user_id,gym_id,plan_id,credits_remaining,expires_at,is_active,status,starts_at,ends_at
  ) values (
    p_user_id,p_gym_id,v_plan.id,v_plan.credits,v_end_at,true,v_status,v_start_at,v_end_at
  ) returning * into v_membership;
  if v_plan.credits is not null then
    insert into public.membership_credit_logs(user_id,gym_id,membership_id,amount,reason)
    values(p_user_id,p_gym_id,v_membership.id,v_plan.credits,p_credit_reason);
  end if;
  return v_membership;
end;
$function$;
create or replace function public.assign_membership_plan(p_user_id uuid,p_plan_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_is_web boolean:=public.is_registered_web_session();
  v_gym_id uuid;
  v_actor public.profiles%rowtype;
  v_target public.profiles%rowtype;
begin
  if v_user_id is null then raise exception 'Not authenticated'; end if;
  select * into v_actor from public.profiles where id=v_user_id;
  if not found then raise exception 'Only gym admins can assign membership plans'; end if;
  if v_is_web then
    v_gym_id:=public.effective_gym_id();
    if v_gym_id is null or public.effective_gym_role()<>'admin' then raise exception 'Only gym admins can assign membership plans'; end if;
  else
    if not coalesce(v_actor.is_active,false) or v_actor.role not in ('admin','owner') or v_actor.gym_id is null then
      raise exception 'Only gym admins can assign membership plans';
    end if;
    v_gym_id:=v_actor.gym_id;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_gym_id::text,615));
  if v_is_web then
    if public.effective_gym_id() is distinct from v_gym_id or public.effective_gym_role()<>'admin' then
      raise exception 'Only gym admins can assign membership plans';
    end if;
  else
    select * into v_actor from public.profiles where id=v_user_id for update;
    if not found or not coalesce(v_actor.is_active,false)
       or v_actor.gym_id is distinct from v_gym_id
       or v_actor.role not in ('admin','owner') then
      raise exception 'Only gym admins can assign membership plans';
    end if;
    perform public.sync_legacy_gym_members(v_gym_id);
  end if;
  select * into v_target from public.profiles where id=p_user_id for update;
  if not found then raise exception 'Member not found'; end if;
  if v_target.role='owner' then raise exception 'Owner protected'; end if;
  if not exists(select 1 from public.gym_members gm where gm.gym_id=v_gym_id and gm.user_id=p_user_id) then
    raise exception 'Member not found';
  end if;
  perform 1 from public.gym_members gm
  where gm.gym_id=v_gym_id and gm.user_id=p_user_id for update;
  if not exists(select 1 from public.membership_plans mp where mp.id=p_plan_id and mp.gym_id=v_gym_id) then
    raise exception 'Plan not found';
  end if;
  perform public.create_member_membership_from_plan(p_user_id,p_plan_id,'assigned',v_gym_id);
end;
$function$;
create or replace function public.list_effective_assignable_membership_plans()
returns table(plan_id uuid,name text,plan_type text,credits integer,created_at timestamptz)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id();
begin
  if auth.uid() is null or v_gym_id is null or public.effective_gym_role() not in ('admin','owner') then
    raise exception using errcode='42501', message='forbidden';
  end if;
  return query select mp.id,mp.name,mp.plan_type,mp.credits,mp.created_at
  from public.membership_plans mp
  where mp.gym_id=v_gym_id and mp.is_active=true
  order by mp.created_at,mp.id;
end;
$function$;
revoke all on function public.is_registered_web_session() from public,anon,authenticated,service_role;
revoke all on function public.sync_legacy_gym_members(uuid) from public,anon,authenticated,service_role;
revoke all on function public.update_member_role(uuid,text) from public,anon,authenticated,service_role;
revoke all on function public.set_gym_member_active(uuid,boolean) from public,anon,authenticated,service_role;
revoke all on function public.set_member_coach_capability(uuid,boolean) from public,anon,authenticated,service_role;
revoke all on function public.create_member_membership_from_plan(uuid,uuid,text,uuid) from public,anon,authenticated,service_role;
revoke all on function public.assign_membership_plan(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function public.list_effective_assignable_membership_plans() from public,anon,authenticated,service_role;
grant execute on function public.is_registered_web_session() to authenticated,service_role;
grant execute on function public.sync_legacy_gym_members(uuid) to service_role;
grant execute on function public.update_member_role(uuid,text) to authenticated,service_role;
grant execute on function public.set_gym_member_active(uuid,boolean) to authenticated,service_role;
grant execute on function public.set_member_coach_capability(uuid,boolean) to authenticated,service_role;
grant execute on function public.create_member_membership_from_plan(uuid,uuid,text,uuid) to service_role;
grant execute on function public.assign_membership_plan(uuid,uuid) to authenticated,service_role;
grant execute on function public.list_effective_assignable_membership_plans() to authenticated,service_role;
