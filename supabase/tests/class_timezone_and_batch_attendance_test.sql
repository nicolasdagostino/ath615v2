begin;

do $$
declare
  v_gym_a uuid := 'ab000000-0000-0000-0000-000000000001';
  v_gym_b uuid := 'ab000000-0000-0000-0000-000000000002';
  v_admin uuid := 'ab100000-0000-0000-0000-000000000001';
  v_athlete uuid := 'ab100000-0000-0000-0000-000000000002';
  v_other_admin uuid := 'ab100000-0000-0000-0000-000000000003';
  v_attended uuid := 'ab100000-0000-0000-0000-000000000004';
  v_no_show uuid := 'ab100000-0000-0000-0000-000000000005';
begin
  insert into auth.users(id,email) values
    (v_admin,'batch-admin@example.test'),
    (v_athlete,'batch-athlete@example.test'),
    (v_other_admin,'batch-other@example.test'),
    (v_attended,'batch-attended@example.test'),
    (v_no_show,'batch-noshow@example.test');
  insert into public.gyms(id,name,timezone) values
    (v_gym_a,'Attendance Gym','Europe/Madrid'),
    (v_gym_b,'Other Gym','Europe/London');
  update public.profiles set
    gym_id=case when id=v_other_admin then v_gym_b else v_gym_a end,
    role=case when id in(v_admin,v_other_admin) then 'admin' else 'athlete' end,
    is_active=true
  where id in(v_admin,v_athlete,v_other_admin,v_attended,v_no_show);
  insert into public.gym_members(gym_id,user_id,role,is_active,is_coach,joined_at) values
    (v_gym_a,v_admin,'admin',true,false,now()),
    (v_gym_a,v_athlete,'athlete',true,false,now()),
    (v_gym_a,v_attended,'athlete',true,false,now()),
    (v_gym_a,v_no_show,'athlete',true,false,now()),
    (v_gym_b,v_other_admin,'admin',true,false,now());
  insert into public.classes(id,gym_id,title,starts_at,capacity) values
    ('ab200000-0000-0000-0000-000000000001',v_gym_a,'Started',now()-interval '10 minutes',10),
    ('ab200000-0000-0000-0000-000000000002',v_gym_a,'Future',now()+interval '1 hour',10),
    ('ab200000-0000-0000-0000-000000000003',v_gym_b,'Other',now()-interval '10 minutes',10);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',v_admin::text,true);
  insert into public.class_bookings(id,class_id,user_id,status,is_guest,guest_name) values
    ('ab300000-0000-0000-0000-000000000001','ab200000-0000-0000-0000-000000000001',v_athlete,'booked',false,null),
    ('ab300000-0000-0000-0000-000000000002','ab200000-0000-0000-0000-000000000001',v_attended,'attended',false,null),
    ('ab300000-0000-0000-0000-000000000003','ab200000-0000-0000-0000-000000000001',v_no_show,'no_show',false,null),
    ('ab300000-0000-0000-0000-000000000004','ab200000-0000-0000-0000-000000000001',null,'booked',true,'Guest');

  insert into public.notifications(user_id,gym_id,title,body,type,data,scheduled_for)
  values (
    v_athlete,v_gym_a,'CLASE CANCELADA',
    'La clase WOD del 26/08/2026 a las 17:30 fue cancelada.',
    'class_cancelled',
    jsonb_build_object('startsAt','2026-08-26T17:30:00Z'),now()
  );
end;
$$;

do $$ begin
  if not exists (
    select 1 from public.notifications
    where type='class_cancelled' and body like '%19:30%'
      and body not like '%17:30%'
  ) then raise exception '19:30 local cancellation time was not rendered'; end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','ab100000-0000-0000-0000-000000000001',true);

do $$ declare v_count integer; begin
  v_count := public.admin_mark_all_class_attended('ab200000-0000-0000-0000-000000000001');
  if v_count <> 1 then raise exception 'updated count mismatch: %',v_count; end if;
  v_count := public.admin_mark_all_class_attended('ab200000-0000-0000-0000-000000000001');
  if v_count <> 0 then raise exception 'second call was not idempotent'; end if;
end $$;

reset role;
do $$ begin
  if (select status from public.class_bookings where id='ab300000-0000-0000-0000-000000000001') <> 'attended' then raise exception 'booked member unchanged'; end if;
  if (select status from public.class_bookings where id='ab300000-0000-0000-0000-000000000002') <> 'attended' then raise exception 'attended changed'; end if;
  if (select status from public.class_bookings where id='ab300000-0000-0000-0000-000000000003') <> 'no_show' then raise exception 'no_show changed'; end if;
  if (select status from public.class_bookings where id='ab300000-0000-0000-0000-000000000004') <> 'booked' then raise exception 'guest was changed'; end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','ab100000-0000-0000-0000-000000000001',true);
do $$ begin
  begin
    perform public.admin_mark_all_class_attended('ab200000-0000-0000-0000-000000000002');
    raise exception 'future class accepted';
  exception when invalid_parameter_value then
    if sqlerrm <> 'class_not_started' then raise; end if;
  end;
end $$;

select set_config('request.jwt.claim.sub','ab100000-0000-0000-0000-000000000002',true);
do $$ begin
  begin
    perform public.admin_mark_all_class_attended('ab200000-0000-0000-0000-000000000001');
    raise exception 'athlete accepted';
  exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','ab100000-0000-0000-0000-000000000003',true);
do $$ begin
  begin
    perform public.admin_mark_all_class_attended('ab200000-0000-0000-0000-000000000001');
    raise exception 'cross-gym admin accepted';
  exception when no_data_found then null; end;
end $$;

rollback;
