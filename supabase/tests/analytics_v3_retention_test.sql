begin;

do $$
declare
  gym_a uuid := 'ae000000-0000-0000-0000-000000000001';
  gym_b uuid := 'ae000000-0000-0000-0000-000000000002';
  owner_a uuid := 'ae100000-0000-0000-0000-000000000001';
  admin_a uuid := 'ae100000-0000-0000-0000-000000000002';
  coach_a uuid := 'ae100000-0000-0000-0000-000000000003';
  inactive_admin uuid := 'ae100000-0000-0000-0000-000000000004';
  admin_b uuid := 'ae100000-0000-0000-0000-000000000005';
  plan_pack uuid := 'ae200000-0000-0000-0000-000000000001';
  plan_unlimited uuid := 'ae200000-0000-0000-0000-000000000002';
begin
  insert into auth.users(id,email)
  select id, 'retention-' || row_number() over () || '@example.test'
  from unnest(array[
    owner_a,admin_a,coach_a,inactive_admin,admin_b,
    'ae110000-0000-0000-0000-000000000001'::uuid,
    'ae110000-0000-0000-0000-000000000002'::uuid,
    'ae110000-0000-0000-0000-000000000003'::uuid,
    'ae110000-0000-0000-0000-000000000004'::uuid,
    'ae110000-0000-0000-0000-000000000005'::uuid,
    'ae110000-0000-0000-0000-000000000006'::uuid,
    'ae110000-0000-0000-0000-000000000007'::uuid,
    'ae110000-0000-0000-0000-000000000008'::uuid,
    'ae110000-0000-0000-0000-000000000009'::uuid,
    'ae110000-0000-0000-0000-000000000010'::uuid
  ]) id;

  insert into public.gyms(id,name,timezone,owner_id) values
    (gym_a,'Retention Gym A','Europe/Madrid',owner_a),
    (gym_b,'Retention Gym B','America/New_York',null);

  update public.profiles set
    gym_id = case when id in (admin_b,'ae110000-0000-0000-0000-000000000009') then gym_b else gym_a end,
    role = case when id=owner_a then 'owner' when id in(admin_a,inactive_admin,admin_b) then 'admin'
      when id=coach_a then 'coach' else 'athlete' end,
    full_name = 'Member ' || right(id::text, 2), is_active=true
  where id in (owner_a,admin_a,coach_a,inactive_admin,admin_b,
    'ae110000-0000-0000-0000-000000000001','ae110000-0000-0000-0000-000000000002',
    'ae110000-0000-0000-0000-000000000003','ae110000-0000-0000-0000-000000000004',
    'ae110000-0000-0000-0000-000000000005','ae110000-0000-0000-0000-000000000006',
    'ae110000-0000-0000-0000-000000000007','ae110000-0000-0000-0000-000000000008',
    'ae110000-0000-0000-0000-000000000009','ae110000-0000-0000-0000-000000000010');

  insert into public.gym_members(gym_id,user_id,role,is_active,is_coach,joined_at) values
    (gym_a,admin_a,'admin',true,false,now()-interval '1 year'),
    (gym_a,coach_a,'coach',true,true,now()-interval '1 year'),
    (gym_a,inactive_admin,'admin',false,false,now()-interval '1 year'),
    (gym_b,admin_b,'admin',true,false,now()-interval '1 year');
  insert into public.gym_members(gym_id,user_id,role,is_active,is_coach,joined_at)
  select gym_a,id,'athlete',id <> 'ae110000-0000-0000-0000-000000000010',false,now()-interval '1 year'
  from unnest(array[
    'ae110000-0000-0000-0000-000000000001'::uuid,'ae110000-0000-0000-0000-000000000002'::uuid,
    'ae110000-0000-0000-0000-000000000003'::uuid,'ae110000-0000-0000-0000-000000000004'::uuid,
    'ae110000-0000-0000-0000-000000000005'::uuid,'ae110000-0000-0000-0000-000000000006'::uuid,
    'ae110000-0000-0000-0000-000000000007'::uuid,'ae110000-0000-0000-0000-000000000008'::uuid,
    'ae110000-0000-0000-0000-000000000010'::uuid
  ]) id;
  insert into public.gym_members(gym_id,user_id,role,is_active,is_coach,joined_at)
  values(gym_b,'ae110000-0000-0000-0000-000000000009','athlete',true,false,now()-interval '1 year');

  insert into public.membership_plans(id,gym_id,name,plan_type,credits,price,currency,duration_days) values
    (plan_pack,gym_a,'Retention Pack','class_pack',10,35,'EUR',30),
    (plan_unlimited,gym_a,'Retention Unlimited','unlimited',null,80,'EUR',30);
  insert into public.member_memberships(id,user_id,gym_id,status,starts_at,ends_at,expires_at,is_active,plan_id,credits_remaining) values
    ('ae300000-0000-0000-0000-000000000001','ae110000-0000-0000-0000-000000000002',gym_a,'active',now()-interval '10 days',now()+interval '20 days',now()+interval '20 days',true,plan_pack,5),
    ('ae300000-0000-0000-0000-000000000002','ae110000-0000-0000-0000-000000000003',gym_a,'active',now()-interval '10 days',now()+interval '20 days',now()+interval '20 days',true,plan_pack,5),
    ('ae300000-0000-0000-0000-000000000003','ae110000-0000-0000-0000-000000000005',gym_a,'active',now()-interval '10 days',now()+interval '20 days',now()+interval '20 days',true,plan_pack,2),
    ('ae300000-0000-0000-0000-000000000004','ae110000-0000-0000-0000-000000000006',gym_a,'active',now()-interval '10 days',now()+interval '20 days',now()+interval '20 days',true,plan_unlimited,null),
    ('ae300000-0000-0000-0000-000000000005','ae110000-0000-0000-0000-000000000007',gym_a,'active',now()-interval '10 days',now()+interval '4 days',now()+interval '4 days',true,plan_pack,8);

  insert into public.classes(id,gym_id,title,starts_at,duration_minutes,capacity)
  select gen_random_uuid(),gym_a,'Retention fixture',starts_at,60,12 from unnest(array[
    now()-interval '2 days',now()-interval '8 days',now()-interval '16 days',
    now()-interval '31 days',now()-interval '32 days',now()-interval '33 days',
    now()+interval '3 days',now()-interval '5 days',now()-interval '6 days'
  ]) starts_at;
end $$;

-- Attach objective attendance/future/no-show fixtures to the generated classes.
do $$
declare gym_a uuid := 'ae000000-0000-0000-0000-000000000001';
  c2 uuid; c8 uuid; c16 uuid; c31 uuid; c32 uuid; c33 uuid; cf uuid; c5 uuid; c6 uuid;
begin
  select id into c2 from classes where gym_id=gym_a order by abs(extract(epoch from(starts_at-(now()-interval '2 days')))) limit 1;
  select id into c8 from classes where gym_id=gym_a order by abs(extract(epoch from(starts_at-(now()-interval '8 days')))) limit 1;
  select id into c16 from classes where gym_id=gym_a order by abs(extract(epoch from(starts_at-(now()-interval '16 days')))) limit 1;
  select id into c31 from classes where gym_id=gym_a order by abs(extract(epoch from(starts_at-(now()-interval '31 days')))) limit 1;
  select id into c32 from classes where gym_id=gym_a order by abs(extract(epoch from(starts_at-(now()-interval '32 days')))) limit 1;
  select id into c33 from classes where gym_id=gym_a order by abs(extract(epoch from(starts_at-(now()-interval '33 days')))) limit 1;
  select id into cf from classes where gym_id=gym_a and starts_at>now() limit 1;
  select id into c5 from classes where gym_id=gym_a order by abs(extract(epoch from(starts_at-(now()-interval '5 days')))) limit 1;
  select id into c6 from classes where gym_id=gym_a order by abs(extract(epoch from(starts_at-(now()-interval '6 days')))) limit 1;

  insert into class_bookings(id,class_id,user_id,status,is_guest) values
    (gen_random_uuid(),c8,'ae110000-0000-0000-0000-000000000001','attended',false),
    (gen_random_uuid(),cf,'ae110000-0000-0000-0000-000000000001','booked',false),
    (gen_random_uuid(),c16,'ae110000-0000-0000-0000-000000000002','attended',false),
    (gen_random_uuid(),c31,'ae110000-0000-0000-0000-000000000003','attended',false),
    (gen_random_uuid(),c32,'ae110000-0000-0000-0000-000000000003','attended',false),
    (gen_random_uuid(),c33,'ae110000-0000-0000-0000-000000000003','attended',false),
    (gen_random_uuid(),c2,'ae110000-0000-0000-0000-000000000005','attended',false),
    (gen_random_uuid(),c16,'ae110000-0000-0000-0000-000000000006','attended',false),
    (gen_random_uuid(),c2,'ae110000-0000-0000-0000-000000000007','attended',false),
    (gen_random_uuid(),c2,'ae110000-0000-0000-0000-000000000008','attended',false),
    (gen_random_uuid(),c5,'ae110000-0000-0000-0000-000000000008','no_show',false),
    (gen_random_uuid(),c6,'ae110000-0000-0000-0000-000000000008','no_show',false),
    -- Two no-shows alone do not meet the minimum sample of three evaluated bookings.
    (gen_random_uuid(),c5,'ae110000-0000-0000-0000-000000000004','no_show',false),
    (gen_random_uuid(),c6,'ae110000-0000-0000-0000-000000000004','no_show',false);
end $$;

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','ae100000-0000-0000-0000-000000000002',true);

do $$ declare s jsonb; p jsonb; begin
  s:=get_effective_retention_summary();
  if (s#>>'{segments,no_attendance_7}')::int <> 4
    or (s#>>'{segments,no_attendance_14}')::int <> 3
    or (s#>>'{segments,no_attendance_30}')::int <> 1
    or (s#>>'{segments,active_membership_no_recent_use}')::int <> 3
    or (s#>>'{segments,no_usable_membership}')::int <> 3
    or (s#>>'{segments,expiring_soon}')::int <> 1
    or (s#>>'{segments,low_credits}')::int <> 1
    or (s#>>'{segments,first_class_no_return}')::int <> 3
    or (s#>>'{segments,inactive_recent}')::int <> 1
    or (s#>>'{segments,repeated_no_shows}')::int <> 1 then
    raise exception 'retention summary mismatch: %',s;
  end if;
  p:=list_effective_retention_segment('no_attendance_7',2,0);
  if (p->>'totalCount')::int<>4 or jsonb_array_length(p->'items')<>2 then raise exception 'pagination failed: %',p; end if;
  p:=list_effective_retention_segment('no_attendance_7',20,0);
  if not exists(select 1 from jsonb_array_elements(p->'items') x where (x->>'hasFutureBooking')::boolean) then
    raise exception 'future booking missing: %',p;
  end if;
  p:=list_effective_retention_segment('low_credits',20,0);
  if p#>>'{items,0,membershipPlanType}'<>'class_pack' or (p#>>'{items,0,creditsRemaining}')::int<>2 then
    raise exception 'low credit/unlimited classification failed: %',p;
  end if;
end $$;

-- Batch communication is atomic, deduplicated, and remains in-app with push disabled.
set local role service_role;
insert into notification_preferences(user_id,communications_push_enabled,notifications_push_enabled)
values('ae110000-0000-0000-0000-000000000001',false,true);
set local role authenticated;
create temporary table retention_batch_result(result jsonb);
insert into retention_batch_result
select send_effective_retention_communication(array[
    'ae110000-0000-0000-0000-000000000001'::uuid,
    'ae110000-0000-0000-0000-000000000001'::uuid,
    'ae110000-0000-0000-0000-000000000002'::uuid
  ],'Come back','We miss training with you');
grant select on retention_batch_result to service_role;
set local role service_role;
do $$ declare r jsonb; cid text; begin
  select result into r from retention_batch_result;
  if (r->>'count')::int<>2 then raise exception 'duplicates not normalized: %',r; end if;
  cid:=r->>'communicationId';
  if (select count(*) from notifications where data->>'communicationId'=cid)<>2
    or (select count(distinct data->>'communicationId') from notifications where data->>'communicationId'=cid)<>1
    or exists(select 1 from notifications where data->>'communicationId'=cid and type<>'communication') then
    raise exception 'batch notification mismatch';
  end if;
  if not exists(select 1 from notifications where user_id='ae110000-0000-0000-0000-000000000001' and data->>'communicationId'=cid) then
    raise exception 'push-off user lost in-app communication';
  end if;
end $$;
set local role authenticated;

do $$ declare before_count bigint; begin
  select count(*) into before_count from notifications;
  begin
    perform send_effective_retention_communication(array[
      'ae110000-0000-0000-0000-000000000001'::uuid,
      'ae110000-0000-0000-0000-000000000009'::uuid
    ],'Invalid','Cross gym');
    raise exception 'cross-gym recipient accepted';
  exception when insufficient_privilege then null; end;
  if (select count(*) from notifications)<>before_count then raise exception 'cross-gym batch was partial'; end if;
  begin
    perform send_effective_retention_communication(array_fill(
      'ae110000-0000-0000-0000-000000000001'::uuid,array[101]
    ),'Too many','Rejected');
    raise exception 'batch limit not enforced';
  exception when invalid_parameter_value then null; end;
  begin
    perform send_effective_retention_communication(array[
      'ae110000-0000-0000-0000-000000000010'::uuid
    ],'Inactive','Rejected');
    raise exception 'inactive recipient accepted';
  exception when insufficient_privilege then null; end;
end $$;

-- Owner allowed; coach, athlete and inactive admin rejected.
select set_config('request.jwt.claim.sub','ae100000-0000-0000-0000-000000000001',true);
do $$ begin perform get_effective_retention_summary(); end $$;
select set_config('request.jwt.claim.sub','ae100000-0000-0000-0000-000000000003',true);
do $$ begin begin perform get_effective_retention_summary(); raise exception 'coach allowed'; exception when insufficient_privilege then null; end; end $$;
select set_config('request.jwt.claim.sub','ae110000-0000-0000-0000-000000000001',true);
do $$ begin begin perform list_effective_retention_segment('no_attendance_7',20,0); raise exception 'athlete allowed'; exception when insufficient_privilege then null; end; end $$;
select set_config('request.jwt.claim.sub','ae100000-0000-0000-0000-000000000004',true);
do $$ begin begin perform get_effective_retention_summary(); raise exception 'inactive admin allowed'; exception when insufficient_privilege then null; end; end $$;

-- Other gym cannot observe Gym A segments.
select set_config('request.jwt.claim.sub','ae100000-0000-0000-0000-000000000005',true);
do $$ declare p jsonb; begin
  p:=list_effective_retention_segment('no_usable_membership',20,0);
  if (p->>'totalCount')::int<>1 then raise exception 'cross-gym list leak: %',p; end if;
end $$;

rollback;
