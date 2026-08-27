-- Analytics V3: actionable retention segments and manual batch communication.

create or replace function public.effective_retention_member_facts()
returns table(
  user_id uuid,
  display_name text,
  avatar_url text,
  last_attended_at timestamptz,
  attendances_count bigint,
  usable_membership boolean,
  membership_plan_name text,
  membership_plan_type text,
  credits_remaining integer,
  membership_ends_at timestamptz,
  has_future_booking boolean,
  future_booking_at timestamptz,
  no_show_count_30d bigint,
  evaluated_bookings_30d bigint
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
  v_timezone text;
  v_today date;
  v_no_show_from timestamptz;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'unauthenticated';
  end if;
  if v_gym_id is null or not public.analytics_actor_can_read() then
    raise exception using errcode = '42501', message = 'analytics_forbidden';
  end if;

  select g.timezone into v_timezone from public.gyms g where g.id = v_gym_id;
  v_today := (statement_timestamp() at time zone v_timezone)::date;
  v_no_show_from := (v_today - 30)::timestamp at time zone v_timezone;

  return query
  with athletes as (
    select gm.user_id, coalesce(nullif(btrim(p.full_name), ''),
      nullif(btrim(p.email), ''), '—') as member_name,
      nullif(btrim(p.avatar_url), '') as member_avatar
    from public.gym_members gm
    join public.profiles p on p.id = gm.user_id
    where gm.gym_id = v_gym_id and gm.is_active and gm.role = 'athlete'
  ), attendance as (
    select cb.user_id, max(c.starts_at) as last_attended,
      count(*)::bigint as attended_count
    from public.class_bookings cb
    join public.classes c on c.id = cb.class_id and c.gym_id = v_gym_id
    join athletes a on a.user_id = cb.user_id
    where cb.status = 'attended' and not coalesce(cb.is_guest, false)
    group by cb.user_id
  ), future_bookings as (
    select cb.user_id, min(c.starts_at) as next_booking
    from public.class_bookings cb
    join public.classes c on c.id = cb.class_id and c.gym_id = v_gym_id
    join athletes a on a.user_id = cb.user_id
    where cb.status = 'booked' and not coalesce(cb.is_guest, false)
      and c.starts_at > statement_timestamp()
    group by cb.user_id
  ), evaluated_bookings as (
    select cb.user_id,
      count(*) filter (where cb.status = 'no_show')::bigint as no_show_count,
      count(*)::bigint as evaluated_count
    from public.class_bookings cb
    join public.classes c on c.id = cb.class_id and c.gym_id = v_gym_id
    join athletes a on a.user_id = cb.user_id
    where cb.status in ('attended', 'no_show') and not coalesce(cb.is_guest, false)
      and c.starts_at >= v_no_show_from
      and c.starts_at < statement_timestamp()
    group by cb.user_id
  )
  select a.user_id, a.member_name, a.member_avatar,
    at.last_attended, coalesce(at.attended_count, 0),
    usable.membership_id is not null,
    usable.plan_name, usable.plan_type, usable.remaining,
    usable.ends_at,
    fb.next_booking is not null, fb.next_booking,
    coalesce(eb.no_show_count, 0), coalesce(eb.evaluated_count, 0)
  from athletes a
  left join attendance at on at.user_id = a.user_id
  left join future_bookings fb on fb.user_id = a.user_id
  left join evaluated_bookings eb on eb.user_id = a.user_id
  left join lateral (
    select mm.id as membership_id, mp.name as plan_name,
      mp.plan_type, mm.credits_remaining as remaining,
      coalesce(mm.expires_at, mm.ends_at) as ends_at
    from public.member_memberships mm
    join public.membership_plans mp on mp.id = mm.plan_id
    where mm.gym_id = v_gym_id and mm.user_id = a.user_id
      and public.is_membership_usable(
        mm.is_active, mm.status, mm.starts_at, mm.created_at,
        mm.expires_at, mm.ends_at, mm.credits_remaining,
        mp.plan_type, statement_timestamp()
      )
    order by case when mp.plan_type = 'unlimited' then 0 else 1 end,
      coalesce(mm.expires_at, mm.ends_at, 'infinity'::timestamptz),
      mm.created_at, mm.id
    limit 1
  ) usable on true;
end;
$function$;

revoke all on function public.effective_retention_member_facts()
  from public, anon, authenticated, service_role;

create or replace function public.get_effective_retention_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
  v_timezone text;
  v_today date;
  v_cutoff_7 timestamptz;
  v_cutoff_14 timestamptz;
  v_cutoff_30 timestamptz;
  v_expiry_limit timestamptz;
  v_result jsonb;
begin
  if v_gym_id is null or not public.analytics_actor_can_read() then
    raise exception using errcode = '42501', message = 'analytics_forbidden';
  end if;
  select g.timezone into v_timezone from public.gyms g where g.id = v_gym_id;
  v_today := (statement_timestamp() at time zone v_timezone)::date;
  v_cutoff_7 := (v_today - 7)::timestamp at time zone v_timezone;
  v_cutoff_14 := (v_today - 14)::timestamp at time zone v_timezone;
  v_cutoff_30 := (v_today - 30)::timestamp at time zone v_timezone;
  v_expiry_limit := (v_today + 8)::timestamp at time zone v_timezone;

  with facts as (select * from public.effective_retention_member_facts())
  select jsonb_build_object(
    'timezone', v_timezone,
    'segments', jsonb_build_object(
      'no_attendance_7', count(*) filter (
        where attendances_count > 0 and last_attended_at < v_cutoff_7),
      'no_attendance_14', count(*) filter (
        where attendances_count > 0 and last_attended_at < v_cutoff_14),
      'no_attendance_30', count(*) filter (
        where attendances_count > 0 and last_attended_at < v_cutoff_30),
      'active_membership_no_recent_use', count(*) filter (
        where usable_membership and (
          last_attended_at is null or last_attended_at < v_cutoff_14)),
      'no_usable_membership', count(*) filter (where not usable_membership),
      'expiring_soon', count(*) filter (
        where usable_membership and membership_ends_at >= v_today::timestamp at time zone v_timezone
          and membership_ends_at < v_expiry_limit),
      'low_credits', count(*) filter (
        where usable_membership and membership_plan_type = 'class_pack'
          and credits_remaining between 0 and 2),
      'first_class_no_return', count(*) filter (
        where attendances_count = 1 and last_attended_at < v_cutoff_7),
      'inactive_recent', count(*) filter (
        where attendances_count >= 3 and last_attended_at < v_cutoff_14),
      'repeated_no_shows', count(*) filter (
        where evaluated_bookings_30d >= 3 and no_show_count_30d >= 2)
    )
  ) into v_result from facts;
  return v_result;
end;
$function$;

create or replace function public.list_effective_retention_segment(
  p_segment text,
  p_limit integer default 20,
  p_offset integer default 0
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
  v_today date;
  v_cutoff_7 timestamptz;
  v_cutoff_14 timestamptz;
  v_cutoff_30 timestamptz;
  v_expiry_start timestamptz;
  v_expiry_limit timestamptz;
  v_result jsonb;
begin
  if v_gym_id is null or not public.analytics_actor_can_read() then
    raise exception using errcode = '42501', message = 'analytics_forbidden';
  end if;
  if p_segment not in (
    'no_attendance_7','no_attendance_14','no_attendance_30',
    'active_membership_no_recent_use','no_usable_membership',
    'expiring_soon','low_credits','first_class_no_return',
    'inactive_recent','repeated_no_shows'
  ) or p_limit is null or p_limit not between 1 and 50
    or p_offset is null or p_offset < 0 then
    raise exception using errcode = '22023', message = 'invalid_parameters';
  end if;

  select g.timezone into v_timezone from public.gyms g where g.id = v_gym_id;
  v_today := (statement_timestamp() at time zone v_timezone)::date;
  v_cutoff_7 := (v_today - 7)::timestamp at time zone v_timezone;
  v_cutoff_14 := (v_today - 14)::timestamp at time zone v_timezone;
  v_cutoff_30 := (v_today - 30)::timestamp at time zone v_timezone;
  v_expiry_start := v_today::timestamp at time zone v_timezone;
  v_expiry_limit := (v_today + 8)::timestamp at time zone v_timezone;

  with facts as (select * from public.effective_retention_member_facts()),
  filtered as (
    select f.* from facts f where case p_segment
      when 'no_attendance_7' then attendances_count > 0 and last_attended_at < v_cutoff_7
      when 'no_attendance_14' then attendances_count > 0 and last_attended_at < v_cutoff_14
      when 'no_attendance_30' then attendances_count > 0 and last_attended_at < v_cutoff_30
      when 'active_membership_no_recent_use' then usable_membership and
        (last_attended_at is null or last_attended_at < v_cutoff_14)
      when 'no_usable_membership' then not usable_membership
      when 'expiring_soon' then usable_membership and
        membership_ends_at >= v_expiry_start and membership_ends_at < v_expiry_limit
      when 'low_credits' then usable_membership and membership_plan_type = 'class_pack'
        and credits_remaining between 0 and 2
      when 'first_class_no_return' then attendances_count = 1 and last_attended_at < v_cutoff_7
      when 'inactive_recent' then attendances_count >= 3 and last_attended_at < v_cutoff_14
      when 'repeated_no_shows' then evaluated_bookings_30d >= 3
        and no_show_count_30d >= 2
      else false end
  ), paged as (
    select f.*, count(*) over() as total_count
    from filtered f
    order by last_attended_at asc nulls first, display_name, user_id
    limit p_limit offset p_offset
  )
  select jsonb_build_object(
    'segment', p_segment, 'limit', p_limit, 'offset', p_offset,
    'totalCount', coalesce(max(total_count), 0),
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'userId', user_id, 'name', display_name, 'avatarUrl', avatar_url,
      'lastAttendedAt', last_attended_at, 'attendancesCount', attendances_count,
      'usableMembership', usable_membership, 'membershipPlanName', membership_plan_name,
      'membershipPlanType', membership_plan_type, 'creditsRemaining', credits_remaining,
      'membershipEndsAt', membership_ends_at, 'hasFutureBooking', has_future_booking,
      'futureBookingAt', future_booking_at, 'noShowCount30d', no_show_count_30d
    ) order by last_attended_at asc nulls first, display_name, user_id), '[]'::jsonb)
  ) into v_result from paged;
  return v_result;
end;
$function$;

create or replace function public.send_effective_retention_communication(
  p_recipient_ids uuid[],
  p_title text,
  p_body text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
  v_title text := btrim(coalesce(p_title, ''));
  v_body text := btrim(coalesce(p_body, ''));
  v_recipient_ids uuid[];
  v_communication_id uuid := gen_random_uuid();
  v_count bigint;
begin
  if v_gym_id is null or not public.analytics_actor_can_read() then
    raise exception using errcode = '42501', message = 'analytics_forbidden';
  end if;
  if p_recipient_ids is null or cardinality(p_recipient_ids) not between 1 and 100
    or array_position(p_recipient_ids, null) is not null
    or length(v_title) not between 1 and 120
    or length(v_body) not between 1 and 2000 then
    raise exception using errcode = '22023', message = 'invalid_payload';
  end if;

  select array_agg(id order by id) into v_recipient_ids
  from (select distinct unnest(p_recipient_ids) as id) recipients;

  select count(*) into v_count
  from public.gym_members gm
  where gm.gym_id = v_gym_id and gm.is_active and gm.role = 'athlete'
    and gm.user_id = any(v_recipient_ids);
  if v_count <> cardinality(v_recipient_ids) then
    raise exception using errcode = '42501', message = 'invalid_recipient';
  end if;

  insert into public.notifications(user_id, gym_id, title, body, type, data, scheduled_for)
  select recipient_id, v_gym_id, v_title, v_body, 'communication',
    jsonb_build_object(
      'channel', 'admin', 'audience', 'selection', 'createdBy', auth.uid(),
      'communicationId', v_communication_id
    ), clock_timestamp()
  from unnest(v_recipient_ids) recipient_id;

  return jsonb_build_object(
    'count', cardinality(v_recipient_ids),
    'communicationId', v_communication_id
  );
end;
$function$;

revoke all on function public.get_effective_retention_summary()
  from public, anon;
revoke all on function public.list_effective_retention_segment(text, integer, integer)
  from public, anon;
revoke all on function public.send_effective_retention_communication(uuid[], text, text)
  from public, anon;
grant execute on function public.get_effective_retention_summary()
  to authenticated, service_role;
grant execute on function public.list_effective_retention_segment(text, integer, integer)
  to authenticated, service_role;
grant execute on function public.send_effective_retention_communication(uuid[], text, text)
  to authenticated, service_role;

comment on function public.get_effective_retention_summary() is
  'Owner/admin-only counts for objective retention segments in the effective gym.';
comment on function public.list_effective_retention_segment(text, integer, integer) is
  'Owner/admin-only paginated operational member facts for one retention segment.';
comment on function public.send_effective_retention_communication(uuid[], text, text) is
  'Atomic owner/admin communication to at most 100 active athletes in the effective gym.';
