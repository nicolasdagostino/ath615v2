begin;

do $$
declare
  v_gym_a uuid := 'ac000000-0000-0000-0000-000000000001';
  v_gym_b uuid := 'ac000000-0000-0000-0000-000000000002';
  v_empty_gym uuid := 'ac000000-0000-0000-0000-000000000003';
  v_owner uuid := 'ac100000-0000-0000-0000-000000000001';
  v_admin uuid := 'ac100000-0000-0000-0000-000000000002';
  v_athlete uuid := 'ac100000-0000-0000-0000-000000000003';
  v_coach uuid := 'ac100000-0000-0000-0000-000000000004';
  v_other_admin uuid := 'ac100000-0000-0000-0000-000000000005';
  v_empty_admin uuid := 'ac100000-0000-0000-0000-000000000006';
  v_inactive_admin uuid := 'ac100000-0000-0000-0000-000000000007';
  v_program uuid := 'ac200000-0000-0000-0000-000000000001';
  v_current_class uuid := 'ac300000-0000-0000-0000-000000000001';
  v_previous_class uuid := 'ac300000-0000-0000-0000-000000000002';
  v_other_class uuid := 'ac300000-0000-0000-0000-000000000003';
begin
  insert into auth.users(id,email) values
    (v_owner,'analytics-owner@example.test'),
    (v_admin,'analytics-admin@example.test'),
    (v_athlete,'analytics-athlete@example.test'),
    (v_coach,'analytics-coach@example.test'),
    (v_other_admin,'analytics-other-admin@example.test'),
    (v_empty_admin,'analytics-empty-admin@example.test'),
    (v_inactive_admin,'analytics-inactive-admin@example.test');

  insert into public.gyms(id,name,timezone) values
    (v_gym_a,'Analytics Gym A','Europe/Madrid'),
    (v_gym_b,'Analytics Gym B','America/New_York'),
    (v_empty_gym,'Analytics Empty Gym','Europe/London');

  update public.profiles set
    gym_id = case
      when id in (v_owner,v_admin,v_athlete,v_coach,v_inactive_admin) then v_gym_a
      when id = v_other_admin then v_gym_b
      else v_empty_gym
    end,
    role = case
      when id = v_owner then 'owner'
      when id in (v_admin,v_other_admin,v_empty_admin,v_inactive_admin) then 'admin'
      when id = v_coach then 'coach'
      else 'athlete'
    end,
    is_active = true
  where id in (v_owner,v_admin,v_athlete,v_coach,v_other_admin,v_empty_admin,v_inactive_admin);

  update public.gyms set owner_id = v_owner where id = v_gym_a;

  insert into public.gym_members(
    gym_id,user_id,role,is_active,is_coach,joined_at
  ) values
    (v_gym_a,v_admin,'admin',true,false,now()-interval '20 days'),
    (v_gym_a,v_athlete,'athlete',true,false,now()-interval '2 days'),
    (v_gym_a,v_coach,'coach',true,true,now()-interval '40 days'),
    (v_gym_a,v_inactive_admin,'admin',false,false,now()-interval '40 days'),
    (v_gym_b,v_other_admin,'admin',true,false,now()-interval '100 days'),
    (v_empty_gym,v_empty_admin,'admin',true,false,now()-interval '100 days');

  insert into public.programs(id,gym_id,name) values
    (v_program,v_gym_a,'Analytics Program');

  insert into public.classes(
    id,gym_id,program_id,title,starts_at,duration_minutes,capacity
  ) values
    (v_current_class,v_gym_a,v_program,'Do not expose this title',
      now()-interval '1 day',60,10),
    (v_previous_class,v_gym_a,v_program,'Previous',
      now()-interval '8 days',60,20),
    (v_other_class,v_gym_b,null,'Other gym',
      now()-interval '1 day',60,1);

  insert into public.class_bookings(
    id,class_id,user_id,status,is_guest,guest_name
  ) values
    ('ac400000-0000-0000-0000-000000000001',v_current_class,v_athlete,'attended',false,null),
    ('ac400000-0000-0000-0000-000000000002',v_current_class,v_coach,'no_show',false,null),
    ('ac400000-0000-0000-0000-000000000003',v_current_class,v_owner,'booked',false,null),
    ('ac400000-0000-0000-0000-000000000004',v_current_class,v_admin,'cancelled',false,null),
    ('ac400000-0000-0000-0000-000000000005',v_previous_class,v_athlete,'attended',false,null),
    ('ac400000-0000-0000-0000-000000000006',v_previous_class,v_coach,'booked',false,null),
    ('ac400000-0000-0000-0000-000000000007',v_other_class,v_other_admin,'attended',false,null);
end;
$$;

-- DST conversion is based on local midnights, not fixed UTC offsets.
do $$
declare v_bounds record;
begin
  select * into v_bounds
  from public.analytics_period_bounds('Europe/Madrid','7d','2026-03-29');
  if v_bounds.utc_to_exclusive - v_bounds.utc_from <> interval '167 hours' then
    raise exception '7-day range did not preserve the DST transition';
  end if;
  if ('2026-03-30'::timestamp at time zone 'Europe/Madrid')
      - ('2026-03-29'::timestamp at time zone 'Europe/Madrid')
      <> interval '23 hours' then
    raise exception 'Europe/Madrid DST day was not 23 hours';
  end if;
  if v_bounds.local_to_exclusive <> date '2026-03-30'
      or v_bounds.utc_to_exclusive
        <> ('2026-03-30'::timestamp at time zone 'Europe/Madrid') then
    raise exception 'DST-safe period bound mismatch';
  end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','ac100000-0000-0000-0000-000000000002',true);

do $$
declare v_overview jsonb; v_attendance jsonb;
begin
  v_overview := public.get_effective_analytics_overview('7d');
  if v_overview #>> '{period,timezone}' <> 'Europe/Madrid' then
    raise exception 'gym timezone mismatch: %',v_overview;
  end if;
  if (v_overview #>> '{current,activeMembers}')::integer <> 3 then
    raise exception 'active member isolation mismatch: %',v_overview;
  end if;
  if (v_overview #>> '{current,newMembers}')::integer <> 1 then
    raise exception 'new members mismatch: %',v_overview;
  end if;
  if (v_overview #>> '{current,deliveredClasses}')::integer <> 1
      or (v_overview #>> '{current,bookings}')::integer <> 3
      or (v_overview #>> '{current,attendances}')::integer <> 1
      or (v_overview #>> '{current,noShows}')::integer <> 1 then
    raise exception 'current metrics mismatch: %',v_overview;
  end if;
  if (v_overview #>> '{current,globalOccupancy}')::numeric <> 30.0 then
    raise exception 'cancelled booking affected occupancy: %',v_overview;
  end if;
  if (v_overview #>> '{previous,bookings}')::integer <> 2
      or (v_overview #>> '{previous,globalOccupancy}')::numeric <> 10.0 then
    raise exception 'previous metrics mismatch: %',v_overview;
  end if;

  v_attendance := public.get_effective_attendance_analytics('7d');
  if jsonb_array_length(v_attendance->'programs') <> 1
      or v_attendance #>> '{programs,0,programName}' <> 'Analytics Program' then
    raise exception 'program aggregation mismatch: %',v_attendance;
  end if;
  if jsonb_array_length(v_attendance->'mostOccupiedClasses') <> 1
      or v_attendance #>> '{mostOccupiedClasses,0,bookings}' <> '3' then
    raise exception 'class ranking mismatch: %',v_attendance;
  end if;
  if v_attendance::text like '%Do not expose this title%' then
    raise exception 'free-text class title leaked into analytics';
  end if;
end $$;

-- Coach and athlete cannot invoke global analytics.
select set_config('request.jwt.claim.sub','ac100000-0000-0000-0000-000000000004',true);
do $$ begin
  begin
    perform public.get_effective_analytics_overview('7d');
    raise exception 'coach was allowed';
  exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','ac100000-0000-0000-0000-000000000003',true);
do $$ begin
  begin
    perform public.get_effective_attendance_analytics('7d');
    raise exception 'athlete was allowed';
  exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','ac100000-0000-0000-0000-000000000007',true);
do $$ begin
  begin
    perform public.get_effective_analytics_overview('7d');
    raise exception 'inactive admin was allowed';
  exception when insufficient_privilege then null; end;
end $$;

-- Owner retains access through the established owner authority.
select set_config('request.jwt.claim.sub','ac100000-0000-0000-0000-000000000001',true);
do $$ declare v_result jsonb; begin
  v_result := public.get_effective_analytics_overview('7d');
  if (v_result #>> '{current,bookings}')::integer <> 3 then
    raise exception 'owner result mismatch';
  end if;
end $$;

-- A different gym admin sees only that gym.
select set_config('request.jwt.claim.sub','ac100000-0000-0000-0000-000000000005',true);
do $$ declare v_result jsonb; begin
  v_result := public.get_effective_analytics_overview('7d');
  if v_result #>> '{period,timezone}' <> 'America/New_York'
      or (v_result #>> '{current,bookings}')::integer <> 1 then
    raise exception 'cross-gym isolation failed: %',v_result;
  end if;
end $$;

-- New gyms produce a complete, finite empty response.
select set_config('request.jwt.claim.sub','ac100000-0000-0000-0000-000000000006',true);
do $$ declare v_overview jsonb; v_attendance jsonb; begin
  v_overview := public.get_effective_analytics_overview('7d');
  v_attendance := public.get_effective_attendance_analytics('7d');
  if (v_overview #>> '{current,deliveredClasses}')::integer <> 0
      or v_overview #> '{current,globalOccupancy}' <> 'null'::jsonb
      or jsonb_array_length(v_attendance->'programs') <> 0 then
    raise exception 'empty gym response invalid: %, %',v_overview,v_attendance;
  end if;
end $$;

-- Invalid periods are rejected, and the internal date helper is not exposed.
do $$ begin
  begin
    perform public.get_effective_analytics_overview('arbitrary');
    raise exception 'invalid period accepted';
  exception when invalid_parameter_value then null; end;
  if has_function_privilege(
    'authenticated',
    'public.analytics_period_bounds(text,text,date)',
    'execute'
  ) then raise exception 'internal bounds helper exposed'; end if;
end $$;

rollback;
