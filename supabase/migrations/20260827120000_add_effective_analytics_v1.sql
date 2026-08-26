-- Analytics V1: effective-gym, timezone-aware operational aggregates.

create index if not exists gym_members_gym_joined_at_idx
  on public.gym_members (gym_id, joined_at);

create or replace function public.analytics_period_bounds(
  p_timezone text,
  p_period text,
  p_anchor_date date default null
)
returns table(
  period_key text,
  local_from date,
  local_to_exclusive date,
  previous_local_from date,
  previous_local_to_exclusive date,
  utc_from timestamptz,
  utc_to_exclusive timestamptz,
  previous_utc_from timestamptz,
  previous_utc_to_exclusive timestamptz
)
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $function$
declare
  v_today date := coalesce(
    p_anchor_date,
    (statement_timestamp() at time zone p_timezone)::date
  );
  v_from date;
  v_to date;
  v_previous_from date;
  v_previous_to date;
begin
  if p_timezone is null or not exists (
    select 1 from pg_timezone_names where name = p_timezone
  ) then
    raise exception using errcode = '22023', message = 'invalid_gym_timezone';
  end if;

  case p_period
    when '7d' then
      v_to := v_today + 1;
      v_from := v_to - 7;
      v_previous_to := v_from;
      v_previous_from := v_previous_to - 7;
    when '30d' then
      v_to := v_today + 1;
      v_from := v_to - 30;
      v_previous_to := v_from;
      v_previous_from := v_previous_to - 30;
    when 'this_month' then
      v_from := date_trunc('month', v_today)::date;
      v_to := v_today + 1;
      v_previous_from := (v_from - interval '1 month')::date;
      v_previous_to := least(
        v_from,
        (v_previous_from + (v_to - v_from))::date
      );
    when 'previous_month' then
      v_to := date_trunc('month', v_today)::date;
      v_from := (v_to - interval '1 month')::date;
      v_previous_to := v_from;
      v_previous_from := (v_previous_to - interval '1 month')::date;
    when '3m' then
      v_to := v_today + 1;
      v_from := (v_to - interval '3 months')::date;
      v_previous_to := v_from;
      v_previous_from := (v_previous_to - interval '3 months')::date;
    else
      raise exception using errcode = '22023', message = 'invalid_analytics_period';
  end case;

  return query select
    p_period,
    v_from,
    v_to,
    v_previous_from,
    v_previous_to,
    v_from::timestamp at time zone p_timezone,
    v_to::timestamp at time zone p_timezone,
    v_previous_from::timestamp at time zone p_timezone,
    v_previous_to::timestamp at time zone p_timezone;
end;
$function$;

revoke all on function public.analytics_period_bounds(text, text, date)
  from public, anon, authenticated;

create or replace function public.analytics_actor_can_read()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select auth.uid() is not null
    and public.effective_gym_id() is not null
    and (
      exists (
        select 1 from public.gyms g
        where g.id = public.effective_gym_id()
          and g.owner_id = auth.uid()
      )
      or exists (
        select 1 from public.gym_members gm
        where gm.gym_id = public.effective_gym_id()
          and gm.user_id = auth.uid()
          and gm.role = 'admin'
          and gm.is_active
      )
    );
$function$;

revoke all on function public.analytics_actor_can_read()
  from public, anon, authenticated;

create or replace function public.get_effective_analytics_overview(
  p_period text default '30d'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
  v_timezone text;
  v_bounds record;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'unauthenticated';
  end if;
  if v_gym_id is null or not public.analytics_actor_can_read() then
    raise exception using errcode = '42501', message = 'analytics_forbidden';
  end if;

  select g.timezone into v_timezone from public.gyms g where g.id = v_gym_id;
  select * into strict v_bounds
  from public.analytics_period_bounds(v_timezone, p_period, null);

  with period_classes as (
    select
      c.id,
      greatest(coalesce(c.capacity, 0), 0)::bigint as capacity
    from public.classes c
    where c.gym_id = v_gym_id
      and c.starts_at
          + make_interval(mins => greatest(coalesce(c.duration_minutes, 60), 1))
          >= v_bounds.utc_from
      and c.starts_at
          + make_interval(mins => greatest(coalesce(c.duration_minutes, 60), 1))
          < v_bounds.utc_to_exclusive
      and c.starts_at
          + make_interval(mins => greatest(coalesce(c.duration_minutes, 60), 1))
          <= statement_timestamp()
  ), previous_classes as (
    select
      c.id,
      greatest(coalesce(c.capacity, 0), 0)::bigint as capacity
    from public.classes c
    where c.gym_id = v_gym_id
      and c.starts_at
          + make_interval(mins => greatest(coalesce(c.duration_minutes, 60), 1))
          >= v_bounds.previous_utc_from
      and c.starts_at
          + make_interval(mins => greatest(coalesce(c.duration_minutes, 60), 1))
          < v_bounds.previous_utc_to_exclusive
      and c.starts_at
          + make_interval(mins => greatest(coalesce(c.duration_minutes, 60), 1))
          <= statement_timestamp()
  ), current_per_class as (
    select
      pc.id,
      pc.capacity,
      count(cb.id) filter (where cb.status <> 'cancelled')::bigint as bookings,
      count(cb.id) filter (where cb.status = 'attended')::bigint as attendances,
      count(cb.id) filter (where cb.status = 'no_show')::bigint as no_shows
    from period_classes pc
    left join public.class_bookings cb on cb.class_id = pc.id
    group by pc.id, pc.capacity
  ), previous_per_class as (
    select
      pc.id,
      pc.capacity,
      count(cb.id) filter (where cb.status <> 'cancelled')::bigint as bookings,
      count(cb.id) filter (where cb.status = 'attended')::bigint as attendances,
      count(cb.id) filter (where cb.status = 'no_show')::bigint as no_shows
    from previous_classes pc
    left join public.class_bookings cb on cb.class_id = pc.id
    group by pc.id, pc.capacity
  ), current_totals as (
    select
      count(*)::bigint as classes,
      coalesce(sum(bookings), 0)::bigint as bookings,
      coalesce(sum(attendances), 0)::bigint as attendances,
      coalesce(sum(no_shows), 0)::bigint as no_shows,
      case when coalesce(sum(capacity), 0) = 0 then null else
        round(100 * sum(bookings)::numeric / sum(capacity), 1)
      end as global_occupancy,
      round(
        avg(100 * bookings::numeric / nullif(capacity, 0))
          filter (where capacity > 0),
        1
      ) as average_occupancy
    from current_per_class
  ), previous_totals as (
    select
      count(*)::bigint as classes,
      coalesce(sum(bookings), 0)::bigint as bookings,
      coalesce(sum(attendances), 0)::bigint as attendances,
      coalesce(sum(no_shows), 0)::bigint as no_shows,
      case when coalesce(sum(capacity), 0) = 0 then null else
        round(100 * sum(bookings)::numeric / sum(capacity), 1)
      end as global_occupancy,
      round(
        avg(100 * bookings::numeric / nullif(capacity, 0))
          filter (where capacity > 0),
        1
      ) as average_occupancy
    from previous_per_class
  ), members as (
    select
      count(*) filter (where gm.is_active)::bigint as active_members,
      count(*) filter (
        where gm.joined_at >= v_bounds.utc_from
          and gm.joined_at < v_bounds.utc_to_exclusive
      )::bigint as new_members,
      count(*) filter (
        where gm.joined_at >= v_bounds.previous_utc_from
          and gm.joined_at < v_bounds.previous_utc_to_exclusive
      )::bigint as previous_new_members
    from public.gym_members gm
    where gm.gym_id = v_gym_id
  )
  select jsonb_build_object(
    'period', jsonb_build_object(
      'key', v_bounds.period_key,
      'timezone', v_timezone,
      'from', v_bounds.local_from,
      'toExclusive', v_bounds.local_to_exclusive,
      'previousFrom', v_bounds.previous_local_from,
      'previousToExclusive', v_bounds.previous_local_to_exclusive
    ),
    'current', jsonb_build_object(
      'activeMembers', m.active_members,
      'newMembers', m.new_members,
      'deliveredClasses', c.classes,
      'bookings', c.bookings,
      'attendances', c.attendances,
      'noShows', c.no_shows,
      'globalOccupancy', c.global_occupancy,
      'averageClassOccupancy', c.average_occupancy
    ),
    'previous', jsonb_build_object(
      'newMembers', m.previous_new_members,
      'deliveredClasses', p.classes,
      'bookings', p.bookings,
      'attendances', p.attendances,
      'noShows', p.no_shows,
      'globalOccupancy', p.global_occupancy,
      'averageClassOccupancy', p.average_occupancy
    ),
    'caveats', jsonb_build_object(
      'activeMembersIsCurrentSnapshot', true,
      'newMembersUsesGymJoinedAt', true
    )
  ) into v_result
  from current_totals c cross join previous_totals p cross join members m;

  return v_result;
end;
$function$;

create or replace function public.get_effective_attendance_analytics(
  p_period text default '30d'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
  v_timezone text;
  v_bounds record;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'unauthenticated';
  end if;
  if v_gym_id is null or not public.analytics_actor_can_read() then
    raise exception using errcode = '42501', message = 'analytics_forbidden';
  end if;

  select g.timezone into v_timezone from public.gyms g where g.id = v_gym_id;
  select * into strict v_bounds
  from public.analytics_period_bounds(v_timezone, p_period, null);

  with period_classes as materialized (
    select
      c.id,
      c.program_id,
      p.name as program_name,
      c.starts_at,
      (c.starts_at at time zone v_timezone)::date as local_date,
      extract(isodow from c.starts_at at time zone v_timezone)::integer as weekday,
      extract(hour from c.starts_at at time zone v_timezone)::integer as local_hour,
      greatest(coalesce(c.capacity, 0), 0)::bigint as capacity
    from public.classes c
    left join public.programs p
      on p.id = c.program_id and p.gym_id = v_gym_id
    where c.gym_id = v_gym_id
      and c.starts_at
          + make_interval(mins => greatest(coalesce(c.duration_minutes, 60), 1))
          >= v_bounds.utc_from
      and c.starts_at
          + make_interval(mins => greatest(coalesce(c.duration_minutes, 60), 1))
          < v_bounds.utc_to_exclusive
      and c.starts_at
          + make_interval(mins => greatest(coalesce(c.duration_minutes, 60), 1))
          <= statement_timestamp()
  ), per_class as materialized (
    select
      pc.*,
      count(cb.id) filter (where cb.status <> 'cancelled')::bigint as bookings,
      count(cb.id) filter (where cb.status = 'attended')::bigint as attendances,
      count(cb.id) filter (where cb.status = 'no_show')::bigint as no_shows
    from period_classes pc
    left join public.class_bookings cb on cb.class_id = pc.id
    group by pc.id, pc.program_id, pc.program_name, pc.starts_at,
      pc.local_date, pc.weekday, pc.local_hour, pc.capacity
  ), dates as (
    select generate_series(
      v_bounds.local_from::timestamp,
      (v_bounds.local_to_exclusive - 1)::timestamp,
      interval '1 day'
    )::date as local_date
  ), trend as (
    select jsonb_agg(jsonb_build_object(
      'date', d.local_date,
      'bookings', coalesce(x.bookings, 0),
      'attendances', coalesce(x.attendances, 0),
      'noShows', coalesce(x.no_shows, 0),
      'occupancy', x.occupancy
    ) order by d.local_date) as value
    from dates d
    left join (
      select
        local_date,
        sum(bookings)::bigint as bookings,
        sum(attendances)::bigint as attendances,
        sum(no_shows)::bigint as no_shows,
        case when sum(capacity) = 0 then null else
          round(100 * sum(bookings)::numeric / sum(capacity), 1)
        end as occupancy
      from per_class group by local_date
    ) x using (local_date)
  ), program_rows as (
    select jsonb_agg(jsonb_build_object(
      'programId', program_id,
      'programName', coalesce(program_name, '—'),
      'classes', classes,
      'bookings', bookings,
      'attendances', attendances,
      'noShows', no_shows,
      'occupancy', occupancy
    ) order by bookings desc, program_name) as value
    from (
      select program_id, program_name, count(*)::bigint as classes,
        sum(bookings)::bigint as bookings,
        sum(attendances)::bigint as attendances,
        sum(no_shows)::bigint as no_shows,
        case when sum(capacity) = 0 then null else
          round(100 * sum(bookings)::numeric / sum(capacity), 1)
        end as occupancy
      from per_class group by program_id, program_name
    ) x
  ), weekday_rows as (
    select jsonb_agg(jsonb_build_object(
      'weekday', weekday,
      'classes', classes,
      'bookings', bookings,
      'attendances', attendances,
      'occupancy', occupancy
    ) order by bookings desc, weekday) as value
    from (
      select weekday, count(*)::bigint as classes,
        sum(bookings)::bigint as bookings,
        sum(attendances)::bigint as attendances,
        case when sum(capacity) = 0 then null else
          round(100 * sum(bookings)::numeric / sum(capacity), 1)
        end as occupancy
      from per_class group by weekday
    ) x
  ), hour_rows as (
    select jsonb_agg(jsonb_build_object(
      'hour', local_hour,
      'classes', classes,
      'bookings', bookings,
      'attendances', attendances,
      'occupancy', occupancy
    ) order by bookings desc, local_hour) as value
    from (
      select local_hour, count(*)::bigint as classes,
        sum(bookings)::bigint as bookings,
        sum(attendances)::bigint as attendances,
        case when sum(capacity) = 0 then null else
          round(100 * sum(bookings)::numeric / sum(capacity), 1)
        end as occupancy
      from per_class group by local_hour
    ) x
  ), most_rows as (
    select jsonb_agg(row_value order by occupancy desc, bookings desc) as value
    from (
      select jsonb_build_object(
        'classId', id,
        'programName', coalesce(program_name, '—'),
        'date', local_date,
        'hour', local_hour,
        'capacity', capacity,
        'bookings', bookings,
        'attendances', attendances,
        'occupancy', round(100 * bookings::numeric / capacity, 1)
      ) as row_value,
      round(100 * bookings::numeric / capacity, 1) as occupancy,
      bookings
      from per_class where capacity > 0
      order by occupancy desc, bookings desc limit 5
    ) x
  ), least_rows as (
    select jsonb_agg(row_value order by occupancy asc, bookings asc) as value
    from (
      select jsonb_build_object(
        'classId', id,
        'programName', coalesce(program_name, '—'),
        'date', local_date,
        'hour', local_hour,
        'capacity', capacity,
        'bookings', bookings,
        'attendances', attendances,
        'occupancy', round(100 * bookings::numeric / capacity, 1)
      ) as row_value,
      round(100 * bookings::numeric / capacity, 1) as occupancy,
      bookings
      from per_class where capacity > 0
      order by occupancy asc, bookings asc limit 5
    ) x
  )
  select jsonb_build_object(
    'period', jsonb_build_object(
      'key', v_bounds.period_key,
      'timezone', v_timezone,
      'from', v_bounds.local_from,
      'toExclusive', v_bounds.local_to_exclusive
    ),
    'trend', coalesce(t.value, '[]'::jsonb),
    'programs', coalesce(p.value, '[]'::jsonb),
    'weekdays', coalesce(w.value, '[]'::jsonb),
    'hours', coalesce(h.value, '[]'::jsonb),
    'mostOccupiedClasses', coalesce(m.value, '[]'::jsonb),
    'leastOccupiedClasses', coalesce(l.value, '[]'::jsonb)
  ) into v_result
  from trend t cross join program_rows p cross join weekday_rows w
    cross join hour_rows h cross join most_rows m cross join least_rows l;

  return v_result;
end;
$function$;

revoke all on function public.get_effective_analytics_overview(text)
  from public, anon;
revoke all on function public.get_effective_attendance_analytics(text)
  from public, anon;
grant execute on function public.get_effective_analytics_overview(text)
  to authenticated, service_role;
grant execute on function public.get_effective_attendance_analytics(text)
  to authenticated, service_role;

comment on function public.get_effective_analytics_overview(text) is
  'Owner/admin-only compact Analytics V1 overview for the effective gym.';
comment on function public.get_effective_attendance_analytics(text) is
  'Owner/admin-only attendance aggregates for the effective gym and local dates.';
