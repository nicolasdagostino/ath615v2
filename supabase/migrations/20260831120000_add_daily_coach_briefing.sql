-- Coach Experience V2: one effective-gym, timezone-aware operational payload.

create or replace function public.coach_briefing_can_operate()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select auth.uid() is not null
    and public.effective_gym_id() is not null
    and public.membership_actor_is_active()
    and (
      public.effective_gym_role() = 'admin'
      or public.effective_gym_is_coach()
    )
$function$;

create or replace function public.get_daily_coach_briefing()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
  v_timezone text;
  v_role text := public.effective_gym_role();
  v_date date;
  v_from timestamptz;
  v_to timestamptz;
  v_classes jsonb;
begin
  if not public.coach_briefing_can_operate() then
    raise exception using errcode = '42501', message = 'forbidden';
  end if;

  select g.timezone into v_timezone
  from public.gyms g
  where g.id = v_gym_id and g.lifecycle_status = 'active';
  if not found then
    raise exception using errcode = '42501', message = 'gym_not_active';
  end if;

  v_timezone := coalesce(v_timezone, 'Europe/Madrid');
  v_date := (now() at time zone v_timezone)::date;
  v_from := v_date::timestamp at time zone v_timezone;
  v_to := (v_date + 1)::timestamp at time zone v_timezone;

  with class_rows as (
    select c.*,
      coalesce(nullif(btrim(p.name), ''), c.title, 'Class') as display_name,
      p.name as program_name,
      coach.full_name as coach_name,
      w.description as workout_description
    from public.classes c
    left join public.programs p on p.id = c.program_id and p.gym_id = v_gym_id
    left join public.profiles coach on coach.id = c.coach_id
    left join public.workouts w on w.gym_id = v_gym_id
      and w.program_id = c.program_id and w.workout_date = v_date
    where c.gym_id = v_gym_id
      and c.starts_at >= v_from and c.starts_at < v_to
      and (v_role = 'admin' or c.coach_id = auth.uid())
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', cr.id,
      'title', cr.display_name,
      'starts_at', cr.starts_at,
      'local_start_time', to_char(cr.starts_at at time zone v_timezone, 'HH24:MI'),
      'duration_minutes', coalesce(cr.duration_minutes, 60),
      'capacity', coalesce(cr.capacity, 0),
      'coach_name', cr.coach_name,
      'program_name', cr.program_name,
      'workout_description', cr.workout_description,
      'booked', coalesce((
        select jsonb_agg(jsonb_build_object(
          'booking_id', cb.id,
          'user_id', cb.user_id,
          'name', case when coalesce(cb.is_guest, false)
            then coalesce(nullif(btrim(cb.guest_name), ''), 'Guest')
            else coalesce(nullif(btrim(member.full_name), ''), 'Member') end,
          'avatar_url', case when coalesce(cb.is_guest, false) then null else member.avatar_url end,
          'is_guest', coalesce(cb.is_guest, false),
          'attendance_status', cb.status,
          'first_class', case when cb.user_id is null then false else not exists (
            select 1 from public.class_bookings previous
            join public.classes previous_class on previous_class.id = previous.class_id
            where previous.user_id = cb.user_id
              and previous.status = 'attended'
              and previous_class.gym_id = v_gym_id
              and previous_class.starts_at < cr.starts_at
          ) end,
          'membership_usable', usable.id is not null,
          'membership_plan_type', membership_plan.plan_type,
          'credits_remaining', usable.credits_remaining,
          'membership_expires_at', coalesce(usable.expires_at, usable.ends_at)
        ) order by cb.created_at, cb.id)
        from public.class_bookings cb
        left join public.profiles member on member.id = cb.user_id
        left join lateral public.select_usable_membership(cb.user_id, v_gym_id) usable
          on cb.user_id is not null and not coalesce(cb.is_guest, false)
        left join public.membership_plans membership_plan on membership_plan.id = usable.plan_id
        where cb.class_id = cr.id and cb.status <> 'cancelled'
      ), '[]'::jsonb),
      'waitlist', coalesce((
        select jsonb_agg(jsonb_build_object(
          'user_id', cw.user_id,
          'name', coalesce(nullif(btrim(waiting.full_name), ''), 'Member'),
          'avatar_url', waiting.avatar_url,
          'position', ordered.position
        ) order by ordered.position)
        from (
          select row_number() over(order by cw0.created_at, cw0.user_id) as position,
            cw0.user_id
          from public.class_waitlist cw0 where cw0.class_id = cr.id
        ) ordered
        join public.class_waitlist cw on cw.class_id = cr.id and cw.user_id = ordered.user_id
        join public.profiles waiting on waiting.id = cw.user_id
      ), '[]'::jsonb)
    ) order by cr.starts_at, cr.id
  ), '[]'::jsonb) into v_classes
  from class_rows cr;

  return jsonb_build_object(
    'local_date', v_date,
    'timezone', v_timezone,
    'classes', v_classes
  );
end;
$function$;

create or replace function public.set_class_booking_attendance_status(
  p_booking_id uuid,
  p_expected_status text,
  p_status text
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_booking public.class_bookings%rowtype;
begin
  if auth.uid() is null or not public.coach_briefing_can_operate() then
    raise exception using errcode = '42501', message = 'forbidden';
  end if;
  if p_expected_status not in ('booked', 'attended', 'no_show')
     or p_status not in ('booked', 'attended', 'no_show') then
    raise exception using errcode = '22023', message = 'invalid_attendance_status';
  end if;

  select cb.* into v_booking
  from public.class_bookings cb
  join public.classes c on c.id = cb.class_id
  where cb.id = p_booking_id and c.gym_id = public.effective_gym_id()
    and (public.effective_gym_role() = 'admin' or c.coach_id = auth.uid())
  for update of cb;
  if not found then raise exception using errcode = 'P0002', message = 'booking_not_found'; end if;
  if v_booking.status is distinct from p_expected_status then return false; end if;
  if v_booking.status is distinct from p_status then
    update public.class_bookings set status = p_status where id = v_booking.id;
  end if;
  return true;
end;
$function$;

create or replace function public.admin_mark_all_class_attended(p_class_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_class public.classes%rowtype;
  v_updated integer;
begin
  if auth.uid() is null or not public.coach_briefing_can_operate() then
    raise exception using errcode = '42501', message = 'forbidden';
  end if;
  select c.* into v_class from public.classes c
  where c.id = p_class_id and c.gym_id = public.effective_gym_id()
    and (public.effective_gym_role() = 'admin' or c.coach_id = auth.uid())
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'class_not_found'; end if;
  if v_class.starts_at > now() then
    raise exception using errcode = '22023', message = 'class_not_started';
  end if;
  perform 1 from public.class_bookings cb
  where cb.class_id = v_class.id and cb.status = 'booked'
  order by cb.id for update;
  update public.class_bookings cb set status = 'attended'
  where cb.class_id = v_class.id and cb.status = 'booked'
    and not coalesce(cb.is_guest, false);
  get diagnostics v_updated = row_count;
  return v_updated;
end;
$function$;

revoke all on function public.coach_briefing_can_operate() from public, anon, authenticated;
revoke all on function public.get_daily_coach_briefing() from public, anon;
revoke all on function public.set_class_booking_attendance_status(uuid, text, text) from public, anon;
revoke all on function public.admin_mark_all_class_attended(uuid) from public, anon;
grant execute on function public.coach_briefing_can_operate() to authenticated, service_role;
grant execute on function public.get_daily_coach_briefing() to authenticated, service_role;
grant execute on function public.set_class_booking_attendance_status(uuid, text, text) to authenticated, service_role;
grant execute on function public.admin_mark_all_class_attended(uuid) to authenticated, service_role;
