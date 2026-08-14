-- Vertical 3C1: relational, read-only Members and Athlete CRM contracts.

create or replace function public.can_read_effective_members()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select auth.uid() is not null
    and public.effective_gym_id() is not null
    and public.effective_gym_role() in ('admin', 'owner');
$function$;
create or replace function public.list_effective_gym_members(
  p_search text default null,
  p_role text default null,
  p_status text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table(
  user_id uuid,
  full_name text,
  email text,
  avatar_url text,
  role text,
  is_active boolean,
  is_coach boolean,
  phone text,
  birth_date date,
  joined_at timestamptz,
  total_count bigint
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
  v_search text := lower(btrim(coalesce(p_search, '')));
begin
  if not public.can_read_effective_members() then
    raise exception using errcode='42501', message='forbidden';
  end if;
  if length(v_search) > 80
     or coalesce(p_role, 'all') not in ('all', 'admin', 'athlete', 'coach')
     or coalesce(p_status, 'all') not in ('all', 'active', 'inactive')
     or p_limit is null or p_limit not between 1 and 100
     or p_offset is null or p_offset < 0 then
    raise exception using errcode='22023', message='invalid_parameters';
  end if;

  return query
  select
    gm.user_id,
    nullif(btrim(p.full_name), ''),
    nullif(btrim(p.email), ''),
    nullif(btrim(p.avatar_url), ''),
    gm.role,
    gm.is_active,
    gm.is_coach or gm.role = 'coach',
    nullif(btrim(p.phone), ''),
    p.birth_date,
    gm.joined_at,
    count(*) over ()
  from public.gym_members gm
  join public.profiles p on p.id = gm.user_id
  where gm.gym_id = v_gym_id
    and (coalesce(p_role, 'all') = 'all' or gm.role = p_role)
    and (
      coalesce(p_status, 'all') = 'all'
      or gm.is_active = (p_status = 'active')
    )
    and (
      v_search = ''
      or strpos(lower(coalesce(p.full_name, '')), v_search) > 0
      or strpos(lower(coalesce(p.email, '')), v_search) > 0
    )
  order by nullif(btrim(p.full_name), '') asc nulls last, gm.joined_at, gm.user_id
  limit p_limit offset p_offset;
end;
$function$;
create or replace function public.get_members_without_usable_membership(
  p_search text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table(
  user_id uuid,
  full_name text,
  email text,
  role text,
  is_active boolean,
  phone text,
  birth_date date,
  created_at timestamptz,
  total_count bigint
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
  v_search text := lower(btrim(coalesce(p_search, '')));
  v_at timestamptz := now();
begin
  if not public.can_read_effective_members() then
    raise exception using errcode='42501', message='forbidden';
  end if;
  if length(v_search) > 80
     or p_limit is null or p_limit not between 1 and 100
     or p_offset is null or p_offset < 0 then
    raise exception using errcode='22023', message='invalid_parameters';
  end if;

  return query
  with candidates as (
    select
      gm.user_id,
      nullif(btrim(p.full_name), '') as member_name,
      nullif(btrim(p.email), '') as member_email,
      gm.role as member_role,
      gm.is_active as member_is_active,
      nullif(btrim(p.phone), '') as member_phone,
      p.birth_date as member_birth_date,
      gm.joined_at as member_joined_at
    from public.gym_members gm
    join public.profiles p on p.id = gm.user_id
    where gm.gym_id = v_gym_id
      and gm.role = 'athlete'
      and gm.is_active
      and (
        v_search = ''
        or strpos(lower(coalesce(p.full_name, '')), v_search) > 0
        or strpos(lower(coalesce(p.email, '')), v_search) > 0
      )
      and not exists (
        select 1
        from public.member_memberships mm
        join public.membership_plans mp on mp.id = mm.plan_id
        where mm.user_id = gm.user_id
          and mm.gym_id = v_gym_id
          and public.is_membership_usable(
            mm.is_active, mm.status, mm.starts_at, mm.created_at,
            mm.expires_at, mm.ends_at, mm.credits_remaining,
            mp.plan_type, v_at
          )
      )
  ), paged as (
    select candidates.*, count(*) over () as matching_count
    from candidates
    order by member_name asc nulls last, member_joined_at, user_id
    limit p_limit offset p_offset
  )
  select
    pg.user_id, pg.member_name, pg.member_email, pg.member_role,
    pg.member_is_active, pg.member_phone, pg.member_birth_date,
    pg.member_joined_at, pg.matching_count
  from paged pg
  order by pg.member_name asc nulls last, pg.member_joined_at, pg.user_id;
end;
$function$;
create or replace function public.get_effective_gym_member(p_member_id uuid)
returns table(
  user_id uuid,
  full_name text,
  email text,
  phone text,
  avatar_url text,
  birth_date date,
  joined_at timestamptz,
  role text,
  is_coach boolean,
  is_active boolean
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
begin
  if not public.can_read_effective_members() then
    raise exception using errcode='42501', message='forbidden';
  end if;
  return query
  select
    gm.user_id, nullif(btrim(p.full_name), ''), nullif(btrim(p.email), ''),
    nullif(btrim(p.phone), ''), nullif(btrim(p.avatar_url), ''), p.birth_date,
    gm.joined_at, gm.role, gm.is_coach or gm.role='coach', gm.is_active
  from public.gym_members gm
  join public.profiles p on p.id = gm.user_id
  where gm.gym_id = v_gym_id and gm.user_id = p_member_id;
end;
$function$;
create or replace function public.list_effective_member_memberships(p_member_id uuid)
returns table(
  membership_id uuid,
  user_id uuid,
  is_active boolean,
  status text,
  starts_at timestamptz,
  created_at timestamptz,
  expires_at timestamptz,
  ends_at timestamptz,
  credits_remaining integer,
  plan_name text,
  plan_type text,
  initial_credits integer
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
begin
  if not public.can_read_effective_members() then
    raise exception using errcode='42501', message='forbidden';
  end if;
  if not exists (
    select 1 from public.gym_members gm
    where gm.gym_id=v_gym_id and gm.user_id=p_member_id
  ) then return; end if;

  return query
  select mm.id, mm.user_id, mm.is_active, mm.status, mm.starts_at,
    mm.created_at, mm.expires_at, mm.ends_at, mm.credits_remaining,
    mp.name, mp.plan_type, mp.credits
  from public.member_memberships mm
  join public.membership_plans mp on mp.id=mm.plan_id and mp.gym_id=v_gym_id
  where mm.user_id=p_member_id and mm.gym_id=v_gym_id
  order by mm.created_at desc, mm.id desc;
end;
$function$;
create or replace function public.list_effective_membership_usage(
  p_member_id uuid,
  p_membership_id uuid
)
returns table(
  booking_id uuid,
  status text,
  class_title text,
  starts_at timestamptz,
  program_name text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
begin
  if not public.can_read_effective_members() then
    raise exception using errcode='42501', message='forbidden';
  end if;
  if not exists (
    select 1 from public.gym_members gm
    where gm.gym_id=v_gym_id and gm.user_id=p_member_id
  ) then return; end if;
  if not exists (
    select 1 from public.member_memberships mm
    where mm.id=p_membership_id and mm.user_id=p_member_id and mm.gym_id=v_gym_id
  ) then return; end if;

  return query
  select cb.id, cb.status, c.title, c.starts_at, pr.name
  from public.class_bookings cb
  join public.classes c on c.id=cb.class_id and c.gym_id=v_gym_id
  left join public.programs pr on pr.id=c.program_id and pr.gym_id=v_gym_id
  where cb.user_id=p_member_id and cb.membership_id=p_membership_id
  order by c.starts_at desc, cb.id desc;
end;
$function$;
create or replace function public.get_member_activity_snapshot(
  p_member_id uuid,
  p_months integer default 12
)
returns table(
  last_booking_class_at timestamptz,
  last_attendance_at timestamptz,
  days_since_attendance integer,
  never_attended boolean,
  total_bookings bigint,
  total_attendances bigint,
  total_cancellations bigint,
  total_no_shows bigint,
  upcoming_bookings jsonb,
  program_attendance jsonb,
  monthly_attendance jsonb
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
begin
  if not public.can_read_effective_members() then
    raise exception using errcode='42501', message='forbidden';
  end if;
  if p_member_id is null or p_months is null or p_months not between 1 and 24 then
    raise exception using errcode='22023', message='invalid_parameters';
  end if;
  if not exists (
    select 1 from public.gym_members gm
    where gm.gym_id=v_gym_id and gm.user_id=p_member_id
  ) then
    raise exception using errcode='P0002', message='member_not_found';
  end if;

  return query
  with params as (
    select now() as current_at,
      date_trunc('month',now())-make_interval(months=>p_months-1) as period_start,
      date_trunc('month',now())+interval '1 month' as period_end
  ), relevant_bookings as materialized (
    select cb.status,c.id class_id,c.title class_title,c.starts_at,c.program_id,pr.name program_name
    from public.class_bookings cb
    join public.classes c on c.id=cb.class_id and c.gym_id=v_gym_id
    left join public.programs pr on pr.id=c.program_id and pr.gym_id=v_gym_id
    where cb.user_id=p_member_id and not cb.is_guest
  ), scalar_stats as (
    select
      max(rb.starts_at) filter(where rb.status in ('booked','attended','no_show') and rb.starts_at<=params.current_at) last_booking_at,
      max(rb.starts_at) filter(where rb.status='attended' and rb.starts_at<=params.current_at) last_attended_at,
      count(*) filter(where rb.status in ('booked','attended','no_show')) booking_count,
      count(*) filter(where rb.status='attended') attendance_count,
      count(*) filter(where rb.status='cancelled') cancellation_count,
      count(*) filter(where rb.status='no_show') no_show_count
    from relevant_bookings rb cross join params
  ), upcoming as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'class_id',v.class_id,'class_title',v.class_title,'program_name',v.program_name,'starts_at',v.starts_at
    ) order by v.starts_at,v.class_id),'[]'::jsonb) values
    from (select rb.* from relevant_bookings rb cross join params
      where rb.status='booked' and rb.starts_at>=params.current_at
      order by rb.starts_at,rb.class_id limit 5) v
  ), program_counts as (
    select rb.program_id,rb.program_name,count(*)::bigint attendance_count
    from relevant_bookings rb cross join params
    where rb.status='attended' and rb.starts_at>=params.period_start
      and rb.starts_at<params.period_end and rb.starts_at<=params.current_at
    group by rb.program_id,rb.program_name
  ), program_totals as (
    select pc.*,sum(pc.attendance_count) over() total_attendance_count from program_counts pc
  ), program_values as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'program_id',pc.program_id,'program_name',pc.program_name,
      'attendance_count',pc.attendance_count,'percentage',round(pc.attendance_count*100.0/nullif(pc.total_attendance_count,0),2)
    ) order by pc.attendance_count desc,(pc.program_id is null),pc.program_name nulls last,pc.program_id),'[]'::jsonb) values
    from program_totals pc
  ), month_buckets as (
    select generate_series(params.period_start,params.period_end-interval '1 month',interval '1 month') month_start from params
  ), month_counts as (
    select date_trunc('month',rb.starts_at) month_start,count(*)::bigint attendance_count
    from relevant_bookings rb cross join params
    where rb.status='attended' and rb.starts_at>=params.period_start
      and rb.starts_at<params.period_end and rb.starts_at<=params.current_at
    group by date_trunc('month',rb.starts_at)
  ), month_values as (
    select jsonb_agg(jsonb_build_object('month_start',mb.month_start,'attendance_count',coalesce(mc.attendance_count,0)) order by mb.month_start) values
    from month_buckets mb left join month_counts mc on mc.month_start=mb.month_start
  )
  select ss.last_booking_at,ss.last_attended_at,
    case when ss.last_attended_at is null then null else floor(extract(epoch from(params.current_at-ss.last_attended_at))/86400)::integer end,
    ss.last_attended_at is null,ss.booking_count,ss.attendance_count,ss.cancellation_count,ss.no_show_count,
    upcoming.values,program_values.values,coalesce(month_values.values,'[]'::jsonb)
  from scalar_stats ss cross join params cross join upcoming cross join program_values cross join month_values;
end;
$function$;
revoke all on function public.can_read_effective_members() from public, anon, authenticated;
revoke all on function public.list_effective_gym_members(text,text,text,integer,integer) from public, anon;
revoke all on function public.get_members_without_usable_membership(text,integer,integer) from public, anon;
revoke all on function public.get_effective_gym_member(uuid) from public, anon;
revoke all on function public.list_effective_member_memberships(uuid) from public, anon;
revoke all on function public.list_effective_membership_usage(uuid,uuid) from public, anon;
revoke all on function public.get_member_activity_snapshot(uuid,integer) from public, anon;
grant execute on function public.can_read_effective_members() to service_role;
grant execute on function public.list_effective_gym_members(text,text,text,integer,integer) to authenticated,service_role;
grant execute on function public.get_members_without_usable_membership(text,integer,integer) to authenticated,service_role;
grant execute on function public.get_effective_gym_member(uuid) to authenticated,service_role;
grant execute on function public.list_effective_member_memberships(uuid) to authenticated,service_role;
grant execute on function public.list_effective_membership_usage(uuid,uuid) to authenticated,service_role;
grant execute on function public.get_member_activity_snapshot(uuid,integer) to authenticated,service_role;
