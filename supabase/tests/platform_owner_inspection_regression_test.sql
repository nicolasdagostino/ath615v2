begin;
select plan(1);

do $$
declare
  v_owner uuid:='c4100000-0000-0000-0000-000000000001';
  v_admin uuid:='c4100000-0000-0000-0000-000000000002';
  v_athlete uuid:='c4100000-0000-0000-0000-000000000003';
  v_gym uuid:='c4200000-0000-0000-0000-000000000001';
  v_other_gym uuid:='c4200000-0000-0000-0000-000000000002';
  v_program uuid:='c4300000-0000-0000-0000-000000000001';
  v_session uuid:='c4400000-0000-0000-0000-000000000001';
begin
  insert into auth.users(id,email) values
    (v_owner,'inspection-owner@test.invalid'),
    (v_admin,'inspection-admin@test.invalid'),
    (v_athlete,'inspection-athlete@test.invalid');
  update public.profiles set role=case when id=v_owner then 'owner' when id=v_admin then 'admin' else 'athlete' end,
    is_active=true,gym_id=null where id in(v_owner,v_admin,v_athlete);
  insert into public.gyms(id,name,owner_id,lifecycle_status) values
    (v_gym,'ATHLETE 615 Inspection Fixture',v_owner,'active'),
    (v_other_gym,'Arbitrary Gym',v_owner,'active');
  insert into public.gym_members(gym_id,user_id,role,is_active,is_coach,joined_at) values
    (v_gym,v_admin,'admin',true,false,now()),
    (v_gym,v_athlete,'athlete',true,false,now());
  insert into public.programs(id,gym_id,name) values(v_program,v_gym,'CrossFit');
  insert into public.workouts(id,gym_id,program_id,workout_date,description,created_by)
  values('c4500000-0000-0000-0000-000000000001',v_gym,v_program,current_date,'Existing WOD',v_admin);
  insert into public.classes(id,gym_id,title,starts_at,program_id,created_by)
  values('c4600000-0000-0000-0000-000000000001',v_gym,'Existing Class',now()+interval '1 day',v_program,v_admin);
  insert into public.web_app_session_preferences(session_id,user_id,active_gym_id,selection_required)
  values(v_session,v_owner,null,false);
end;
$$;

select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','c4100000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims',jsonb_build_object(
  'sub','c4100000-0000-0000-0000-000000000001','role','authenticated',
  'session_id','c4400000-0000-0000-0000-000000000001'
)::text,true);
set local role authenticated;

do $$
declare v_gym uuid:='c4200000-0000-0000-0000-000000000001'; v_other uuid:='c4200000-0000-0000-0000-000000000002';
begin
  if public.effective_gym_id() is not null then raise exception 'owner had implicit gym access before inspection'; end if;
  perform public.select_owner_effective_gym(v_gym);
  if public.effective_gym_id()<>v_gym then raise exception 'inspection did not resolve effective gym'; end if;
  if public.effective_gym_role()<>'admin' then raise exception 'inspection lacks effective admin capability'; end if;
  if (select count(*) from public.workouts)<>1 then raise exception 'existing WOD hidden'; end if;
  if (select count(*) from public.programs)<>1 then raise exception 'existing program hidden'; end if;
  if (select count(*) from public.classes)<>1 then raise exception 'existing class hidden'; end if;
  if (select count(*) from public.list_effective_gym_members())<>2 then raise exception 'members forbidden or empty'; end if;
  if not public.can_manage_effective_classes_gym(v_gym)
     or not public.can_manage_effective_workout_gym(v_gym)
     or not public.membership_actor_can_manage() then
    raise exception 'inspection does not have existing admin capabilities';
  end if;
  perform public.leave_owner_gym_inspection();
  if public.effective_gym_id() is not null then raise exception 'leaving inspection retained gym context'; end if;
  begin
    perform public.select_effective_gym(v_other);
    raise exception 'owner selected arbitrary gym without valid inspection';
  exception when sqlstate '42501' then null; end;
  perform public.select_owner_effective_gym(v_gym);
  perform public.platform_set_gym_status(v_gym,'suspended');
  if public.effective_gym_id() is not null then raise exception 'suspended inspection remained operational'; end if;
  perform public.platform_set_gym_status(v_gym,'active');
  if public.effective_gym_id() is not null then raise exception 'reactivation silently restored stale inspection'; end if;
  perform public.select_owner_effective_gym(v_gym);
  perform public.platform_set_gym_status(v_gym,'archived');
  if public.effective_gym_id() is not null then raise exception 'archived inspection remained operational'; end if;
end;
$$;

-- Normal admin remains operational; athlete never receives admin capability.
select set_config('request.jwt.claim.sub','c4100000-0000-0000-0000-000000000002',true);
select set_config('request.jwt.claims',jsonb_build_object(
  'sub','c4100000-0000-0000-0000-000000000002','role','authenticated',
  'session_id','c4400000-0000-0000-0000-000000000002'
)::text,true);
do $$ begin
  update public.profiles set gym_id='c4200000-0000-0000-0000-000000000001' where id=auth.uid();
  perform public.platform_set_gym_status('c4200000-0000-0000-0000-000000000001','active');
exception when sqlstate '42501' then
  -- Admin cannot reactivate; fixture reset is done below as postgres.
  null;
end $$;
reset role;
update public.gyms set lifecycle_status='active',archived_at=null,suspended_at=null
where id='c4200000-0000-0000-0000-000000000001';
update public.profiles set gym_id='c4200000-0000-0000-0000-000000000001'
where id in('c4100000-0000-0000-0000-000000000002','c4100000-0000-0000-0000-000000000003');
set local role authenticated;
do $$ begin
  if public.effective_gym_id()<>'c4200000-0000-0000-0000-000000000001'::uuid
     or public.effective_gym_role()<>'admin' then raise exception 'normal admin regressed'; end if;
end $$;
select set_config('request.jwt.claim.sub','c4100000-0000-0000-0000-000000000003',true);
select set_config('request.jwt.claims',jsonb_build_object(
  'sub','c4100000-0000-0000-0000-000000000003','role','authenticated',
  'session_id','c4400000-0000-0000-0000-000000000003'
)::text,true);
do $$ begin
  if public.effective_gym_role()<>'athlete' then raise exception 'athlete role changed'; end if;
  begin
    perform public.list_effective_gym_members();
    raise exception 'athlete gained admin access';
  exception when sqlstate '42501' then null; end;
end $$;

reset role;
select pass('Platform Owner inspection reads existing data without weakening lifecycle or roles');
select * from finish();
rollback;
