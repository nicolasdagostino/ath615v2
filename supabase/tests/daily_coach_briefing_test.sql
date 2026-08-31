begin;
select plan(1);

do $$
declare
  v_gym_a uuid := 'd6100000-0000-0000-0000-000000000001';
  v_gym_b uuid := 'd6100000-0000-0000-0000-000000000002';
  v_admin uuid := 'd6200000-0000-0000-0000-000000000001';
  v_coach uuid := 'd6200000-0000-0000-0000-000000000002';
  v_athlete uuid := 'd6200000-0000-0000-0000-000000000003';
  v_previous uuid := 'd6200000-0000-0000-0000-000000000004';
  v_returning uuid := 'd6200000-0000-0000-0000-000000000005';
  v_owner uuid := 'd6200000-0000-0000-0000-000000000006';
  v_program uuid := 'd6300000-0000-0000-0000-000000000001';
  v_today date := (now() at time zone 'Europe/Madrid')::date;
begin
  insert into auth.users(id,email) values
    (v_admin,'briefing-admin@test.invalid'),
    (v_coach,'briefing-coach@test.invalid'),
    (v_athlete,'briefing-first@test.invalid'),
    (v_previous,'briefing-previous@test.invalid'),
    (v_returning,'briefing-returning@test.invalid'),
    (v_owner,'briefing-owner@test.invalid');
  insert into public.gyms(id,name,timezone,lifecycle_status,owner_id) values
    (v_gym_a,'Briefing A','Europe/Madrid','active',v_owner),
    (v_gym_b,'Briefing B','America/New_York','active',v_owner);
  update public.profiles set
    role = case when id = v_admin then 'admin' when id = v_coach then 'coach'
      when id = v_owner then 'owner' else 'athlete' end,
    is_coach = id = v_coach,
    is_active = true,
    full_name = case when id = v_athlete then 'First Athlete'
      when id = v_returning then '' else full_name end,
    gym_id = case when id = v_owner then null when id = v_previous then v_gym_b else v_gym_a end
  where id in (v_admin,v_coach,v_athlete,v_previous,v_returning,v_owner);
  insert into public.gym_members(gym_id,user_id,role,is_active,is_coach,joined_at) values
    (v_gym_a,v_admin,'admin',true,false,now()),
    (v_gym_a,v_coach,'coach',true,true,now()),
    (v_gym_a,v_athlete,'athlete',true,false,now()),
    (v_gym_a,v_returning,'athlete',true,false,now()),
    (v_gym_b,v_previous,'athlete',true,false,now()),
    (v_gym_b,v_athlete,'athlete',true,false,now());
  insert into public.programs(id,gym_id,name) values(v_program,v_gym_a,'CrossFit');
  insert into public.workouts(id,gym_id,program_id,workout_date,description,created_by)
  values('d6400000-0000-0000-0000-000000000001',v_gym_a,v_program,v_today,'Fran',v_admin);
  insert into public.classes(id,gym_id,title,starts_at,duration_minutes,capacity,program_id,coach_id,created_by) values
    ('d6500000-0000-0000-0000-000000000001',v_gym_a,'Later',(v_today+time '18:00') at time zone 'Europe/Madrid',60,16,v_program,v_coach,v_admin),
    ('d6500000-0000-0000-0000-000000000002',v_gym_a,'Earlier',(v_today+time '07:30') at time zone 'Europe/Madrid',60,16,v_program,v_coach,v_admin),
    ('d6500000-0000-0000-0000-000000000003',v_gym_a,'Unassigned',(v_today+time '09:00') at time zone 'Europe/Madrid',60,16,v_program,null,v_admin),
    ('d6500000-0000-0000-0000-000000000004',v_gym_b,'Other gym history',((v_today-30)+time '09:00') at time zone 'America/New_York',60,16,null,null,null),
    ('d6500000-0000-0000-0000-000000000005',v_gym_a,'Cancelled history',((v_today-21)+time '09:00') at time zone 'Europe/Madrid',60,16,null,null,v_admin),
    ('d6500000-0000-0000-0000-000000000006',v_gym_a,'No show history',((v_today-20)+time '09:00') at time zone 'Europe/Madrid',60,16,null,null,v_admin);
  insert into public.class_bookings(id,class_id,user_id,status,is_guest) values
    ('d6600000-0000-0000-0000-000000000001','d6500000-0000-0000-0000-000000000001',v_athlete,'booked',false),
    ('d6600000-0000-0000-0000-000000000002','d6500000-0000-0000-0000-000000000004',v_athlete,'attended',false),
    ('d6600000-0000-0000-0000-000000000003','d6500000-0000-0000-0000-000000000005',v_athlete,'cancelled',false),
    ('d6600000-0000-0000-0000-000000000004','d6500000-0000-0000-0000-000000000006',v_athlete,'no_show',false),
    ('d6600000-0000-0000-0000-000000000005','d6500000-0000-0000-0000-000000000001',v_returning,'booked',false),
    ('d6600000-0000-0000-0000-000000000006','d6500000-0000-0000-0000-000000000006',v_returning,'attended',false);
  insert into public.class_waitlist(class_id,user_id,created_at)
  values('d6500000-0000-0000-0000-000000000001',v_previous,now());
  insert into public.web_app_session_preferences(session_id,user_id,active_gym_id,selection_required)
  values('d6700000-0000-0000-0000-000000000001',v_owner,null,false);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','d6200000-0000-0000-0000-000000000002',true);

do $$
declare v jsonb; v_today date := (now() at time zone 'Europe/Madrid')::date;
begin
  v := public.get_daily_coach_briefing();
  if v->>'timezone' <> 'Europe/Madrid' then raise exception 'gym timezone missing'; end if;
  if (v->>'local_date')::date <> v_today or v#>>'{classes,0,local_start_time}' <> '07:30' then
    raise exception 'gym-local today/time is not authoritative';
  end if;
  if jsonb_array_length(v->'classes') <> 2 then raise exception 'coach received classes not assigned to them'; end if;
  if v#>>'{classes,0,title}' <> 'CrossFit' or v#>>'{classes,1,title}' <> 'CrossFit' then
    raise exception 'classes not chronologically ordered or program missing';
  end if;
  if v#>>'{classes,1,workout_description}' <> 'Fran' then raise exception 'WOD missing'; end if;
  if (v#>>'{classes,1,booked,0,first_class}')::boolean is not true then
    raise exception 'other gym attended/cancelled/no-show incorrectly removed first class';
  end if;
  if (v#>>'{classes,1,booked,1,first_class}')::boolean is not false then
    raise exception 'same-gym attended history did not remove first class';
  end if;
  if v#>>'{classes,1,booked,1,name}' <> 'Member'
     or v::text like '%briefing-returning@test.invalid%' then
    raise exception 'empty full name leaked email instead of neutral fallback';
  end if;
  if jsonb_array_length(v#>'{classes,1,waitlist}') <> 1 then raise exception 'waitlist missing'; end if;
  if not public.set_class_booking_attendance_status(
    'd6600000-0000-0000-0000-000000000001','booked','booked'
  ) then raise exception 'assigned active coach cannot update attendance'; end if;
  begin
    perform public.admin_mark_all_class_attended('d6500000-0000-0000-0000-000000000003');
    raise exception 'coach operated unassigned class';
  exception when sqlstate 'P0002' then null; end;
  begin
    perform public.admin_mark_all_class_attended('d6500000-0000-0000-0000-000000000004');
    raise exception 'coach operated cross-gym class';
  exception when sqlstate 'P0002' then null; end;
end;
$$;

reset role;
update public.profiles set is_active=false where id='d6200000-0000-0000-0000-000000000002';
set local role authenticated;
do $$ begin
  begin perform public.get_daily_coach_briefing();
    raise exception 'inactive coach loaded briefing'; exception when sqlstate '42501' then null; end;
  begin perform public.set_class_booking_attendance_status(
    'd6600000-0000-0000-0000-000000000001','booked','attended');
    raise exception 'inactive coach changed attendance'; exception when sqlstate '42501' then null; end;
  begin perform public.admin_mark_all_class_attended('d6500000-0000-0000-0000-000000000001');
    raise exception 'inactive coach ran mark all'; exception when sqlstate '42501' then null; end;
end $$;
reset role;
update public.profiles set is_active=true where id='d6200000-0000-0000-0000-000000000002';
set local role authenticated;

select set_config('request.jwt.claim.sub','d6200000-0000-0000-0000-000000000001',true);
do $$ declare v jsonb; begin
  v := public.get_daily_coach_briefing();
  if jsonb_array_length(v->'classes') <> 3 then raise exception 'admin cannot see gym day'; end if;
end $$;

select set_config('request.jwt.claim.sub','d6200000-0000-0000-0000-000000000003',true);
do $$ begin
  begin
    perform public.get_daily_coach_briefing();
    raise exception 'athlete received coach briefing';
  exception when sqlstate '42501' then null; end;
end $$;

select set_config('request.jwt.claim.sub','d6200000-0000-0000-0000-000000000006',true);
select set_config('request.jwt.claims',jsonb_build_object(
  'sub','d6200000-0000-0000-0000-000000000006','role','authenticated',
  'session_id','d6700000-0000-0000-0000-000000000001'
)::text,true);
do $$ declare v jsonb; begin
  perform public.select_owner_effective_gym('d6100000-0000-0000-0000-000000000001');
  v := public.get_daily_coach_briefing();
  if jsonb_array_length(v->'classes') <> 3 then raise exception 'owner inspection cannot load briefing'; end if;
  perform public.leave_owner_gym_inspection();
end $$;

reset role;
do $$ begin
  if to_regprocedure('public.get_daily_coach_briefing(date)') is not null then
    raise exception 'authenticated caller can still select an arbitrary date';
  end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub','d6200000-0000-0000-0000-000000000001','role','authenticated'
)::text,true);

reset role;
update public.gyms set lifecycle_status='suspended' where id='d6100000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub','d6200000-0000-0000-0000-000000000001','role','authenticated'
)::text,true);
do $$ begin
  begin
    perform public.get_daily_coach_briefing();
    raise exception 'suspended gym remained operational';
  exception when sqlstate '42501' then null; end;
end $$;

reset role;
update public.gyms set lifecycle_status='archived' where id='d6100000-0000-0000-0000-000000000001';
set local role authenticated;
do $$ begin
  begin
    perform public.get_daily_coach_briefing();
    raise exception 'archived gym remained operational';
  exception when sqlstate '42501' then null; end;
end $$;

reset role;
select pass('Daily Coach Briefing is aggregated, role-safe, timezone-aware and gym isolated');
select * from finish();
rollback;
