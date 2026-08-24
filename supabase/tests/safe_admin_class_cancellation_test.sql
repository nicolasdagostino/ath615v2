begin;

do $$
declare
  v_gym_a uuid := 'ca000000-0000-0000-0000-000000000001';
  v_gym_b uuid := 'ca000000-0000-0000-0000-000000000002';
  v_admin uuid := 'ca100000-0000-0000-0000-000000000001';
  v_athlete uuid := 'ca100000-0000-0000-0000-000000000002';
  v_member_b uuid := 'ca100000-0000-0000-0000-000000000003';
  v_member_c uuid := 'ca100000-0000-0000-0000-000000000004';
  v_waitlisted uuid := 'ca100000-0000-0000-0000-000000000005';
  v_other_admin uuid := 'ca100000-0000-0000-0000-000000000006';
  v_owner uuid := 'ca100000-0000-0000-0000-000000000007';
begin
  insert into auth.users(id,email) values
    (v_admin,'cancel-admin@example.test'),
    (v_athlete,'cancel-athlete@example.test'),
    (v_member_b,'cancel-b@example.test'),
    (v_member_c,'cancel-c@example.test'),
    (v_waitlisted,'cancel-wait@example.test'),
    (v_other_admin,'cancel-other-admin@example.test'),
    (v_owner,'cancel-owner@example.test');
  insert into public.gyms(id,name) values (v_gym_a,'Cancel Gym A'),(v_gym_b,'Cancel Gym B');
  update public.profiles set
    gym_id=case when id=v_other_admin then v_gym_b else v_gym_a end,
    role=case when id in(v_admin,v_other_admin) then 'admin' when id=v_owner then 'owner' else 'athlete' end,
    is_active=true,
    preferred_locale=case when id=v_member_b then 'en' else 'es' end
  where id in(v_admin,v_athlete,v_member_b,v_member_c,v_waitlisted,v_other_admin,v_owner);
  update public.gyms set owner_id=v_owner where id=v_gym_a;
  insert into public.gym_members(gym_id,user_id,role,is_active,is_coach,joined_at) values
    (v_gym_a,v_admin,'admin',true,false,now()),
    (v_gym_a,v_athlete,'athlete',true,false,now()),
    (v_gym_a,v_member_b,'athlete',true,false,now()),
    (v_gym_a,v_member_c,'athlete',true,false,now()),
    (v_gym_a,v_waitlisted,'athlete',true,false,now()),
    (v_gym_b,v_other_admin,'admin',true,false,now());
  insert into public.programs(id,gym_id,name,is_active) values
    ('ca200000-0000-0000-0000-000000000001',v_gym_a,'CrossFit',true),
    ('ca200000-0000-0000-0000-000000000002',v_gym_b,'Other',true);
  insert into public.membership_plans(id,gym_id,name,plan_type,credits,is_active) values
    ('ca300000-0000-0000-0000-000000000001',v_gym_a,'Pack','class_pack',10,true);
  insert into public.member_memberships(
    id,user_id,gym_id,status,starts_at,expires_at,is_active,plan_id,credits_remaining
  ) values
    ('ca400000-0000-0000-0000-000000000001',v_athlete,v_gym_a,'active',now(),now()+interval '1 year',true,'ca300000-0000-0000-0000-000000000001',4),
    ('ca400000-0000-0000-0000-000000000002',v_member_b,v_gym_a,'active',now(),now()+interval '1 year',true,'ca300000-0000-0000-0000-000000000001',5),
    ('ca400000-0000-0000-0000-000000000003',v_member_c,v_gym_a,'active',now(),now()+interval '1 year',true,'ca300000-0000-0000-0000-000000000001',6);
  insert into public.classes(id,gym_id,program_id,title,starts_at,capacity,recurring_id) values
    ('ca500000-0000-0000-0000-000000000001',v_gym_a,'ca200000-0000-0000-0000-000000000001','Empty',now()+interval '10 days',10,null),
    ('ca500000-0000-0000-0000-000000000002',v_gym_a,'ca200000-0000-0000-0000-000000000001','Affected',now()+interval '11 days',10,null),
    ('ca500000-0000-0000-0000-000000000003',v_gym_a,'ca200000-0000-0000-0000-000000000001','Recurring 1',now()+interval '20 days',10,'ca600000-0000-0000-0000-000000000001'),
    ('ca500000-0000-0000-0000-000000000004',v_gym_a,'ca200000-0000-0000-0000-000000000001','Recurring 2',now()+interval '27 days',10,'ca600000-0000-0000-0000-000000000001'),
    ('ca500000-0000-0000-0000-000000000005',v_gym_a,'ca200000-0000-0000-0000-000000000001','Recurring 3',now()+interval '34 days',10,'ca600000-0000-0000-0000-000000000001'),
    ('ca500000-0000-0000-0000-000000000006',v_gym_a,'ca200000-0000-0000-0000-000000000001','Historical',now()-interval '2 days',10,null),
    ('ca500000-0000-0000-0000-000000000007',v_gym_b,'ca200000-0000-0000-0000-000000000002','Other gym',now()+interval '12 days',10,null);
  insert into public.class_bookings(id,class_id,user_id,status,membership_id) values
    ('ca700000-0000-0000-0000-000000000001','ca500000-0000-0000-0000-000000000002',v_athlete,'booked','ca400000-0000-0000-0000-000000000001'),
    ('ca700000-0000-0000-0000-000000000002','ca500000-0000-0000-0000-000000000002',v_member_b,'booked','ca400000-0000-0000-0000-000000000002'),
    ('ca700000-0000-0000-0000-000000000003','ca500000-0000-0000-0000-000000000002',v_member_c,'booked','ca400000-0000-0000-0000-000000000003'),
    ('ca700000-0000-0000-0000-000000000004','ca500000-0000-0000-0000-000000000003',v_athlete,'booked','ca400000-0000-0000-0000-000000000001'),
    ('ca700000-0000-0000-0000-000000000005','ca500000-0000-0000-0000-000000000004',v_athlete,'booked','ca400000-0000-0000-0000-000000000001'),
    ('ca700000-0000-0000-0000-000000000006','ca500000-0000-0000-0000-000000000005',v_athlete,'booked','ca400000-0000-0000-0000-000000000001'),
    ('ca700000-0000-0000-0000-000000000007','ca500000-0000-0000-0000-000000000006',v_athlete,'attended','ca400000-0000-0000-0000-000000000001');
  insert into public.class_waitlist(class_id,user_id) values
    ('ca500000-0000-0000-0000-000000000002',v_waitlisted);
  insert into public.notification_preferences(
    user_id,communications_push_enabled,notifications_push_enabled
  ) values (v_athlete,true,false);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','ca100000-0000-0000-0000-000000000001',true);

-- The owner is authorized even without a duplicate gym_members row.
select set_config('request.jwt.claim.sub','ca100000-0000-0000-0000-000000000007',true);
select * from public.admin_cancel_class('ca500000-0000-0000-0000-000000000001','single');
select set_config('request.jwt.claim.sub','ca100000-0000-0000-0000-000000000001',true);

do $$
declare v_result record;
begin
  select * into v_result from public.get_class_cancellation_impact(
    'ca500000-0000-0000-0000-000000000002','single'
  );
  if (v_result.classes_count,v_result.bookings_count,v_result.waitlist_count,v_result.credits_to_refund)
    is distinct from (1::bigint,3::bigint,1::bigint,3::bigint) then
    raise exception 'impact mismatch: %',row_to_json(v_result);
  end if;
  select * into v_result from public.admin_cancel_class(
    'ca500000-0000-0000-0000-000000000002','single'
  );
  if (v_result.classes_count,v_result.bookings_count,v_result.waitlist_count,v_result.credits_refunded)
    is distinct from (1::bigint,3::bigint,1::bigint,3::bigint) then
    raise exception 'cancel result mismatch: %',row_to_json(v_result);
  end if;
end;
$$;

reset role;
do $$
begin
  if exists(select 1 from public.classes where id='ca500000-0000-0000-0000-000000000002') then raise exception 'class not deleted'; end if;
  if (select credits_remaining from public.member_memberships where id='ca400000-0000-0000-0000-000000000001') <> 5 then raise exception 'member A refund mismatch'; end if;
  if (select credits_remaining from public.member_memberships where id='ca400000-0000-0000-0000-000000000002') <> 6 then raise exception 'member B refund mismatch'; end if;
  if (select credits_remaining from public.member_memberships where id='ca400000-0000-0000-0000-000000000003') <> 7 then raise exception 'member C refund mismatch'; end if;
  if (select count(*) from public.membership_credit_logs where reason='class_cancelled') <> 3 then raise exception 'refund logs mismatch'; end if;
  if (select count(*) from public.notifications where type='class_cancelled') <> 4 then raise exception 'booking/waitlist notifications mismatch'; end if;
  if not exists(select 1 from public.notifications where user_id='ca100000-0000-0000-0000-000000000002' and type='class_cancelled' and sent_at is null) then raise exception 'push-off notification was not queued in-app'; end if;
  if exists(select 1 from public.notifications where data->>'waitlist'='true' and body ilike '%credit%') then raise exception 'waitlist claimed a refund'; end if;
end;
$$;

-- Repeating the operation is a safe no-op, with no duplicate effects.
set local role authenticated;
select set_config('request.jwt.claim.sub','ca100000-0000-0000-0000-000000000001',true);
do $$ declare v_result record; begin
  select * into v_result from public.admin_cancel_class('ca500000-0000-0000-0000-000000000002','single');
  if v_result.classes_count <> 0 or v_result.credits_refunded <> 0 then raise exception 'repeat was not a no-op'; end if;
end $$;
reset role;
do $$ begin
  if (select count(*) from public.membership_credit_logs where reason='class_cancelled') <> 3 then raise exception 'double refund'; end if;
  if (select count(*) from public.notifications where type='class_cancelled') <> 4 then raise exception 'duplicate notification'; end if;
end $$;

-- Single occurrence leaves later repeats; future scope removes only from base.
set local role authenticated;
select set_config('request.jwt.claim.sub','ca100000-0000-0000-0000-000000000001',true);
select * from public.admin_cancel_class('ca500000-0000-0000-0000-000000000003','single');
do $$ begin
  if exists(select 1 from public.classes where id='ca500000-0000-0000-0000-000000000003') then raise exception 'single occurrence survived'; end if;
  if not exists(select 1 from public.classes where id in('ca500000-0000-0000-0000-000000000004','ca500000-0000-0000-0000-000000000005')) then raise exception 'future occurrence removed by single'; end if;
end $$;
select * from public.admin_cancel_class('ca500000-0000-0000-0000-000000000004','future');
do $$ begin
  if exists(select 1 from public.classes where id in('ca500000-0000-0000-0000-000000000004','ca500000-0000-0000-0000-000000000005')) then raise exception 'future occurrences survived'; end if;
end $$;

-- Historical/attended classes cannot be cancelled or refunded.
do $$ begin
  begin
    perform public.admin_cancel_class('ca500000-0000-0000-0000-000000000006','single');
    raise exception 'historical class unexpectedly cancelled';
  exception when raise_exception then
    if sqlerrm <> 'class_already_started' then raise; end if;
  end;
end $$;

-- Athlete and another-gym admin are denied.
select set_config('request.jwt.claim.sub','ca100000-0000-0000-0000-000000000002',true);
do $$ begin
  begin
    perform public.admin_cancel_class('ca500000-0000-0000-0000-000000000006','single');
    raise exception 'athlete unexpectedly authorized';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','ca100000-0000-0000-0000-000000000006',true);
do $$ begin
  begin
    perform public.admin_cancel_class('ca500000-0000-0000-0000-000000000006','single');
    raise exception 'cross-gym admin unexpectedly authorized';
  exception when insufficient_privilege then null; end;
end $$;

rollback;
