-- Hotfix 3F: preserve the legacy Owner Dashboard without allowing registered
-- Web sessions to fall back to profiles authority.

create or replace function public.dashboard_actor_can_administer()
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
begin
  if auth.uid() is null then
    return false;
  end if;

  if public.is_registered_web_session() then
    return public.effective_gym_id() is not null
      and public.effective_gym_role() = 'admin'
      and public.dashboard_actor_is_active();
  end if;

  return exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.gym_id = public.effective_gym_id()
      and p.gym_id is not null
      and coalesce(p.is_active, false)
      and p.role in ('admin', 'owner')
  );
end;
$function$;
create or replace function public.get_effective_dashboard_context()
returns table(
  gym_id uuid,
  gym_name text,
  gym_logo_url text,
  actor_role text,
  actor_is_coach boolean,
  display_name text,
  actor_access text,
  session_scoped boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
  v_role text := public.effective_gym_role();
  v_session_scoped boolean := public.is_registered_web_session();
begin
  if auth.uid() is null then
    raise exception using errcode='P0001', message='unauthenticated';
  end if;
  if v_gym_id is null then
    return;
  end if;
  if v_role = 'owner' then
    if v_session_scoped or not public.dashboard_actor_can_administer() then
      return;
    end if;
  elsif v_role not in ('admin', 'athlete', 'coach') then
    return;
  end if;
  return query
  select g.id, g.name, g.logo_url, v_role,
    public.effective_gym_is_coach(), p.full_name,
    case when public.dashboard_actor_is_active() then 'active' else 'inactive' end,
    v_session_scoped
  from public.gyms g
  join public.profiles p on p.id = auth.uid()
  where g.id = v_gym_id;
end;
$function$;
create or replace function public.list_effective_dashboard_members()
returns table(
  user_id uuid,
  full_name text,
  email text,
  phone text,
  birth_date date,
  avatar_url text,
  member_role text,
  is_active boolean,
  is_coach boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
begin
  if auth.uid() is null then
    raise exception using errcode='P0001', message='unauthenticated';
  end if;
  if v_gym_id is null or not public.dashboard_actor_can_administer() then
    raise exception using errcode='42501', message='forbidden';
  end if;
  return query
  select p.id, p.full_name, p.email, p.phone, p.birth_date, p.avatar_url,
    gm.role, gm.is_active, (gm.is_coach or gm.role = 'coach')
  from public.gym_members gm
  join public.profiles p on p.id = gm.user_id
  where gm.gym_id = v_gym_id
  order by p.id;
end;
$function$;
create or replace function public.get_effective_pending_join_request_count()
returns bigint
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
  v_count bigint;
begin
  if auth.uid() is null then
    raise exception using errcode='P0001', message='unauthenticated';
  end if;
  if v_gym_id is null or not public.dashboard_actor_can_administer() then
    raise exception using errcode='42501', message='forbidden';
  end if;
  select count(*) into v_count
  from public.gym_join_requests r
  where r.gym_id = v_gym_id and r.status = 'pending';
  return v_count;
end;
$function$;
create or replace function public.list_gym_activity(
  p_limit integer default 25,
  p_offset integer default 0
)
returns table(event_id uuid, kind text, occurred_at timestamptz,
  member_id uuid, member_name text, guest_name text, class_id uuid,
  class_title text, workout_id uuid, workout_program_name text,
  membership_name text, total_count bigint)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare v_gym_id uuid := public.effective_gym_id();
begin
  if auth.uid() is null then raise exception using errcode='P0001', message='unauthenticated'; end if;
  if v_gym_id is null or not public.dashboard_actor_can_administer() then
    raise exception using errcode='42501', message='forbidden';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 or p_offset is null or p_offset < 0 then
    raise exception using errcode='22023', message='invalid_parameters';
  end if;
  return query
  select e.id, e.kind, e.occurred_at, e.member_id,
    coalesce(nullif(btrim(p.full_name),''),nullif(btrim(p.email),'')),
    e.guest_name, e.class_id, c.title, e.workout_id, pr.name,
    coalesce(mp.name, requested_plan.name), count(*) over()
  from public.gym_activity_events e
  left join public.profiles p on p.id=e.member_id
  left join public.classes c on c.id=e.class_id and c.gym_id=e.gym_id
  left join public.workouts w on w.id=e.workout_id and w.gym_id=e.gym_id
  left join public.programs pr on pr.id=w.program_id and pr.gym_id=e.gym_id
  left join public.member_memberships mm on mm.id=e.membership_id and mm.gym_id=e.gym_id
  left join public.membership_plans mp on mp.id=mm.plan_id and mp.gym_id=e.gym_id
  left join public.membership_requests mr on mr.id=e.membership_request_id and mr.gym_id=e.gym_id
  left join public.membership_plans requested_plan on requested_plan.id=mr.plan_id and requested_plan.gym_id=e.gym_id
  where e.gym_id=v_gym_id
  order by e.occurred_at desc,e.id desc limit p_limit offset p_offset;
end;
$function$;
create or replace function public.list_members_without_recent_bookings(
  p_inactive_days integer default 15,
  p_limit integer default 5,
  p_offset integer default 0
)
returns table(user_id uuid, display_name text, avatar_url text, phone text,
  email text, current_plan_name text, last_class_starts_at timestamptz,
  days_since_last_booking integer, never_booked boolean, total_count bigint)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare v_gym_id uuid := public.effective_gym_id();
begin
  if auth.uid() is null then raise exception using errcode='P0001', message='unauthenticated'; end if;
  if v_gym_id is null or not public.dashboard_actor_can_administer() then
    raise exception using errcode='42501', message='forbidden';
  end if;
  if p_inactive_days is null or p_inactive_days not between 1 and 365
    or p_limit is null or p_limit not between 1 and 50 or p_offset is null or p_offset < 0 then
    raise exception using errcode='22023', message='invalid_parameters';
  end if;
  return query
  with active_athletes as (
    select p.id, coalesce(nullif(trim(p.full_name),''),nullif(trim(p.email),''),'—') member_name,
      p.avatar_url member_avatar_url, nullif(trim(p.phone),'') member_phone,
      nullif(trim(p.email),'') member_email
    from public.gym_members gm join public.profiles p on p.id=gm.user_id
    where gm.gym_id=v_gym_id and gm.is_active and gm.role='athlete'
  ), last_activity as (
    select cb.user_id,max(c.starts_at) last_starts_at
    from public.classes c join public.class_bookings cb on cb.class_id=c.id
    join active_athletes aa on aa.id=cb.user_id
    where c.gym_id=v_gym_id and cb.user_id is not null and not coalesce(cb.is_guest,false)
      and cb.status in ('booked','attended','no_show') group by cb.user_id
  ), candidates as (
    select aa.*,la.last_starts_at from active_athletes aa left join last_activity la on la.user_id=aa.id
    where la.last_starts_at is null or la.last_starts_at < now()-make_interval(days=>p_inactive_days)
  ), paged as (
    select candidates.*,count(*) over() matching_count from candidates
    order by (last_starts_at is null) desc,last_starts_at asc nulls first,member_name,id
    limit p_limit offset p_offset
  )
  select pg.id,pg.member_name,pg.member_avatar_url,pg.member_phone,pg.member_email,
    usable.plan_name,pg.last_starts_at,
    case when pg.last_starts_at is null then null else floor(extract(epoch from(now()-pg.last_starts_at))/86400)::integer end,
    pg.last_starts_at is null,pg.matching_count
  from paged pg left join lateral (
    select mp.name plan_name from public.member_memberships mm
    join public.membership_plans mp on mp.id=mm.plan_id
    where mm.user_id=pg.id and mm.gym_id=v_gym_id
      and public.is_membership_usable(
        mm.is_active,mm.status,mm.starts_at,mm.created_at,mm.expires_at,
        mm.ends_at,mm.credits_remaining,mp.plan_type,now()
      )
    order by case when mp.plan_type='unlimited' then 0 else 1 end,
      coalesce(mm.expires_at,mm.ends_at,'infinity'::timestamptz),mm.created_at,mm.id limit 1
  ) usable on true
  order by (pg.last_starts_at is null) desc,pg.last_starts_at asc nulls first,pg.member_name,pg.id;
end;
$function$;
create or replace function public.get_coach_class_summary(p_period text default 'week')
returns table(coach_id uuid,coach_name text,scheduled_count bigint,completed_count bigint)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id(); v_local_now timestamp:=now() at time zone 'Europe/Madrid'; v_start timestamptz; v_end timestamptz;
begin
  if p_period not in ('week','month') then raise exception 'invalid_period' using errcode='22023'; end if;
  if auth.uid() is null then raise exception using errcode='P0001',message='unauthenticated'; end if;
  if v_gym_id is null or not public.dashboard_actor_can_administer() then
    raise exception using errcode='42501',message='forbidden';
  end if;
  if p_period='week' then v_start:=date_trunc('week',v_local_now) at time zone 'Europe/Madrid'; v_end:=(date_trunc('week',v_local_now)+interval '1 week') at time zone 'Europe/Madrid';
  else v_start:=date_trunc('month',v_local_now) at time zone 'Europe/Madrid'; v_end:=(date_trunc('month',v_local_now)+interval '1 month') at time zone 'Europe/Madrid'; end if;
  return query select p.id,coalesce(nullif(btrim(p.full_name),''),'—'),count(c.id),count(c.id) filter(where c.starts_at<now())
  from public.gym_members gm join public.profiles p on p.id=gm.user_id
  left join public.classes c on c.coach_id=gm.user_id and c.gym_id=gm.gym_id and c.starts_at>=v_start and c.starts_at<v_end
  where gm.gym_id=v_gym_id and gm.is_active and (gm.is_coach or gm.role='coach')
  group by p.id,p.full_name order by coalesce(nullif(btrim(p.full_name),''),'—'),p.id;
end;
$function$;
drop policy if exists "effective admins view activity events"
  on public.gym_activity_events;
create policy "effective admins view activity events"
on public.gym_activity_events for select to authenticated
using (
  gym_id = public.effective_gym_id()
  and public.dashboard_actor_can_administer()
);
revoke all on function public.dashboard_actor_can_administer()
  from public, anon, authenticated, service_role;
