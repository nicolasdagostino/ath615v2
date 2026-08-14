-- RLS-aware aggregate used by the Athlete CRM. The target gym is derived from
-- auth.uid(); callers cannot select an arbitrary gym.

create index if not exists class_bookings_user_status_class_non_guest_idx
on public.class_bookings (user_id, status, class_id)
where is_guest = false
  and user_id is not null;
create or replace function public.get_member_activity_snapshot(
  p_member_id uuid,
  p_months integer default 12
)
returns table (
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
security invoker
set search_path = public, pg_temp
as $function$
declare
  v_actor public.profiles%rowtype;
begin
  if auth.uid() is null then
    raise exception using errcode = 'P0001', message = 'unauthenticated';
  end if;

  select p.*
  into v_actor
  from public.profiles p
  where p.id = auth.uid();

  if not found
    or not coalesce(v_actor.is_active, false)
    or v_actor.gym_id is null
    or v_actor.role not in ('admin', 'owner')
  then
    raise exception using errcode = '42501', message = 'forbidden';
  end if;

  if p_member_id is null
    or p_months is null
    or p_months not between 1 and 24
  then
    raise exception using errcode = '22023', message = 'invalid_parameters';
  end if;

  if not exists (
    select 1
    from public.profiles target
    where target.id = p_member_id
      and target.gym_id = v_actor.gym_id
  ) then
    raise exception using errcode = 'P0002', message = 'member_not_found';
  end if;

  return query
  with params as (
    select
      now() as current_at,
      date_trunc('month', now()) -
        make_interval(months => p_months - 1) as period_start,
      date_trunc('month', now()) + interval '1 month' as period_end
  ),
  relevant_bookings as materialized (
    select
      cb.status,
      c.id as class_id,
      c.title as class_title,
      c.starts_at,
      c.program_id,
      pr.name as program_name
    from public.class_bookings cb
    join public.classes c
      on c.id = cb.class_id
    left join public.programs pr
      on pr.id = c.program_id
      and pr.gym_id = v_actor.gym_id
    where cb.user_id = p_member_id
      and cb.is_guest = false
      and c.gym_id = v_actor.gym_id
  ),
  scalar_stats as (
    select
      max(rb.starts_at) filter (
        where rb.status in ('booked', 'attended', 'no_show')
          and rb.starts_at <= params.current_at
      ) as last_booking_at,
      max(rb.starts_at) filter (
        where rb.status = 'attended'
          and rb.starts_at <= params.current_at
      ) as last_attended_at,
      count(*) filter (
        where rb.status in ('booked', 'attended', 'no_show')
      ) as booking_count,
      count(*) filter (where rb.status = 'attended') as attendance_count,
      count(*) filter (where rb.status = 'cancelled') as cancellation_count,
      count(*) filter (where rb.status = 'no_show') as no_show_count
    from relevant_bookings rb
    cross join params
  ),
  upcoming as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'class_id', value.class_id,
          'class_title', value.class_title,
          'program_name', value.program_name,
          'starts_at', value.starts_at
        )
        order by value.starts_at, value.class_id
      ),
      '[]'::jsonb
    ) as values
    from (
      select rb.*
      from relevant_bookings rb
      cross join params
      where rb.status = 'booked'
        and rb.starts_at >= params.current_at
      order by rb.starts_at, rb.class_id
      limit 5
    ) value
  ),
  program_counts as (
    select
      rb.program_id,
      rb.program_name,
      count(*)::bigint as attendance_count
    from relevant_bookings rb
    cross join params
    where rb.status = 'attended'
      and rb.starts_at >= params.period_start
      and rb.starts_at < params.period_end
      and rb.starts_at <= params.current_at
    group by rb.program_id, rb.program_name
  ),
  program_counts_with_total as (
    select
      pc.*,
      sum(pc.attendance_count) over () as total_attendance_count
    from program_counts pc
  ),
  program_values as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'program_id', pc.program_id,
          'program_name', pc.program_name,
          'attendance_count', pc.attendance_count,
          'percentage',
            round(
              pc.attendance_count * 100.0 /
              nullif(pc.total_attendance_count, 0),
              2
            )
        )
        order by
          pc.attendance_count desc,
          (pc.program_id is null),
          pc.program_name nulls last,
          pc.program_id
      ),
      '[]'::jsonb
    ) as values
    from program_counts_with_total pc
  ),
  month_buckets as (
    select generate_series(
      params.period_start,
      params.period_end - interval '1 month',
      interval '1 month'
    ) as month_start
    from params
  ),
  month_counts as (
    select
      date_trunc('month', rb.starts_at) as month_start,
      count(*)::bigint as attendance_count
    from relevant_bookings rb
    cross join params
    where rb.status = 'attended'
      and rb.starts_at >= params.period_start
      and rb.starts_at < params.period_end
      and rb.starts_at <= params.current_at
    group by date_trunc('month', rb.starts_at)
  ),
  month_values as (
    select jsonb_agg(
      jsonb_build_object(
        'month_start', mb.month_start,
        'attendance_count', coalesce(mc.attendance_count, 0)
      )
      order by mb.month_start
    ) as values
    from month_buckets mb
    left join month_counts mc
      on mc.month_start = mb.month_start
  )
  select
    ss.last_booking_at,
    ss.last_attended_at,
    case
      when ss.last_attended_at is null then null
      else floor(
        extract(epoch from (params.current_at - ss.last_attended_at)) / 86400
      )::integer
    end,
    ss.last_attended_at is null,
    ss.booking_count,
    ss.attendance_count,
    ss.cancellation_count,
    ss.no_show_count,
    upcoming.values,
    program_values.values,
    coalesce(month_values.values, '[]'::jsonb)
  from scalar_stats ss
  cross join params
  cross join upcoming
  cross join program_values
  cross join month_values;
end;
$function$;
revoke all on function public.get_member_activity_snapshot(uuid, integer)
from public;
revoke all on function public.get_member_activity_snapshot(uuid, integer)
from anon;
grant execute on function public.get_member_activity_snapshot(uuid, integer)
to authenticated;
