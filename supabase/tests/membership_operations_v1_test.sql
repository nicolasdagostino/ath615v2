begin;
select plan(1);

do $$
declare
  admin_id uuid := 'a8100000-0000-0000-0000-000000000001';
  owner_id uuid := 'a8100000-0000-0000-0000-000000000002';
  athlete_id uuid := 'a8100000-0000-0000-0000-000000000003';
  coach_id uuid := 'a8100000-0000-0000-0000-000000000004';
  waiter_id uuid := 'a8100000-0000-0000-0000-000000000005';
  used_id uuid := 'a8100000-0000-0000-0000-000000000006';
  other_admin_id uuid := 'a8100000-0000-0000-0000-000000000007';
  owner_session_id uuid := 'a8100000-0000-0000-0000-000000000008';
  v_gym_id uuid := 'a8200000-0000-0000-0000-000000000001';
  v_other_gym_id uuid := 'a8200000-0000-0000-0000-000000000002';
  pack_id uuid := 'a8300000-0000-0000-0000-000000000001';
  unlimited_id uuid := 'a8300000-0000-0000-0000-000000000002';
  void_membership uuid := 'a8400000-0000-0000-0000-000000000001';
  attended_membership uuid := 'a8400000-0000-0000-0000-000000000002';
  no_show_membership uuid := 'a8400000-0000-0000-0000-000000000003';
  cancel_membership uuid := 'a8400000-0000-0000-0000-000000000004';
  active_expiration uuid := 'a8400000-0000-0000-0000-000000000005';
  expired_pack uuid := 'a8400000-0000-0000-0000-000000000006';
  expired_empty_pack uuid := 'a8400000-0000-0000-0000-000000000007';
  scheduled_unlimited uuid := 'a8400000-0000-0000-0000-000000000008';
  next_unlimited uuid := 'a8400000-0000-0000-0000-000000000009';
  expired_unlimited uuid := 'a8400000-0000-0000-0000-000000000010';
  future_class uuid := 'a8500000-0000-0000-0000-000000000001';
  attended_class uuid := 'a8500000-0000-0000-0000-000000000002';
  no_show_class uuid := 'a8500000-0000-0000-0000-000000000003';
  cancel_future_class uuid := 'a8500000-0000-0000-0000-000000000004';
  conflict_class uuid := 'a8500000-0000-0000-0000-000000000005';
  result jsonb;
  preview jsonb;
begin
  insert into auth.users(id,email) values
    (admin_id,'membership-ops-admin@example.test'),
    (owner_id,'membership-ops-owner@example.test'),
    (athlete_id,'membership-ops-athlete@example.test'),
    (coach_id,'membership-ops-coach@example.test'),
    (waiter_id,'membership-ops-waiter@example.test'),
    (used_id,'membership-ops-used@example.test'),
    (other_admin_id,'membership-ops-other-admin@example.test');

  insert into public.gyms(id,name,owner_id) values
    (v_gym_id,'Membership Operations Gym',owner_id),
    (v_other_gym_id,'Other Membership Gym',other_admin_id);
  update public.profiles set
    gym_id=case when id=owner_id then null when id=other_admin_id then v_other_gym_id else v_gym_id end,
    role=case when id=owner_id then 'owner' when id in(admin_id,other_admin_id) then 'admin'
              when id=coach_id then 'coach' else 'athlete' end,
    is_active=true,full_name=email
  where id in(admin_id,owner_id,athlete_id,coach_id,waiter_id,used_id,other_admin_id);
  insert into public.gym_members(gym_id,user_id,role,is_active,joined_at) values
    (v_gym_id,admin_id,'admin',true,now()),
    (v_gym_id,athlete_id,'athlete',true,now()),(v_gym_id,coach_id,'coach',true,now()),
    (v_gym_id,waiter_id,'athlete',true,now()),(v_gym_id,used_id,'athlete',true,now()),
    (v_other_gym_id,other_admin_id,'admin',true,now());
  insert into public.web_app_session_preferences(session_id,user_id,active_gym_id,selection_required)
  values(owner_session_id,owner_id,null,false);

  insert into public.membership_plans(id,gym_id,name,plan_type,credits,duration_days,is_active)
  values(pack_id,v_gym_id,'Pack 5','class_pack',5,30,true),
    (unlimited_id,v_gym_id,'Unlimited','unlimited',null,30,true);
  insert into public.member_memberships(
    id,user_id,gym_id,plan_id,status,is_active,starts_at,expires_at,ends_at,credits_remaining
  ) values
    (void_membership,athlete_id,v_gym_id,pack_id,'active',true,now()-interval '2 days',now()+interval '30 days',now()+interval '30 days',4),
    (attended_membership,used_id,v_gym_id,pack_id,'active',true,now()-interval '2 days',now()+interval '30 days',now()+interval '30 days',4),
    (no_show_membership,coach_id,v_gym_id,pack_id,'active',true,now()-interval '2 days',now()+interval '30 days',now()+interval '30 days',4),
    (cancel_membership,owner_id,v_gym_id,pack_id,'active',true,now()-interval '3 days',now()+interval '30 days',now()+interval '30 days',3),
    (active_expiration,waiter_id,v_gym_id,pack_id,'active',true,now()-interval '2 days',now()+interval '20 days',now()+interval '20 days',3),
    (expired_pack,waiter_id,v_gym_id,pack_id,'expired',false,now()-interval '40 days',now()-interval '10 days',now()-interval '10 days',2),
    (expired_empty_pack,waiter_id,v_gym_id,pack_id,'expired',false,now()-interval '40 days',now()-interval '10 days',now()-interval '10 days',0),
    (scheduled_unlimited,waiter_id,v_gym_id,unlimited_id,'scheduled',true,now()+interval '35 days',now()+interval '65 days',now()+interval '65 days',null),
    (next_unlimited,waiter_id,v_gym_id,unlimited_id,'scheduled',true,now()+interval '66 days',now()+interval '96 days',now()+interval '96 days',null),
    (expired_unlimited,used_id,v_gym_id,unlimited_id,'expired',false,now()-interval '40 days',now()-interval '10 days',now()-interval '10 days',null);

  if exists(select 1 from public.member_memberships mm join public.membership_plans mp on mp.id=mm.plan_id
    where (mp.plan_type='class_pack' and mm.credits_total<>mp.credits)
       or (mp.plan_type='unlimited' and mm.credits_total is not null)) then
    raise exception 'credits_total snapshot is incorrect';
  end if;
  update public.membership_plans set credits=9 where id=pack_id;
  if (select credits_total from public.member_memberships where id=void_membership)<>5 then
    raise exception 'historical credits_total changed with plan';
  end if;

  insert into public.classes(id,gym_id,title,starts_at,capacity) values
    (future_class,v_gym_id,'Void Future',now()+interval '3 days',1),
    (attended_class,v_gym_id,'Attended',now()-interval '1 day',10),
    (no_show_class,v_gym_id,'No Show',now()-interval '1 day',10),
    (cancel_future_class,v_gym_id,'Cancel Future',now()+interval '4 days',10),
    (conflict_class,v_gym_id,'Expiration Conflict',now()+interval '12 days',10);
  insert into public.class_bookings(class_id,user_id,status,membership_id) values
    (future_class,athlete_id,'booked',void_membership),
    (attended_class,used_id,'attended',attended_membership),
    (no_show_class,coach_id,'no_show',no_show_membership),
    (attended_class,owner_id,'attended',cancel_membership),
    (cancel_future_class,owner_id,'booked',cancel_membership),
    (conflict_class,waiter_id,'booked',active_expiration);
  insert into public.class_waitlist(class_id,user_id,created_at) values
    (future_class,athlete_id,now()-interval '1 minute'),
    (future_class,waiter_id,now());
  insert into public.member_memberships(user_id,gym_id,plan_id,status,is_active,starts_at,expires_at,ends_at,credits_remaining)
  values(waiter_id,v_gym_id,unlimited_id,'active',true,now()-interval '1 day',now()+interval '30 days',now()+interval '30 days',null);

  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',athlete_id::text,true);
  begin perform public.get_member_membership_operation_preview(void_membership,null);
    raise exception 'athlete preview allowed'; exception when sqlstate '42501' then null; end;
  begin perform public.void_member_membership(void_membership,'assigned_by_mistake',null);
    raise exception 'athlete void allowed'; exception when sqlstate '42501' then null; end;
  perform set_config('request.jwt.claim.sub',coach_id::text,true);
  begin perform public.cancel_member_membership(cancel_membership,'administrative',null);
    raise exception 'coach cancel allowed'; exception when sqlstate '42501' then null; end;
  perform set_config('request.jwt.claim.sub',''::text,true);
  begin perform public.change_member_membership_expiration(active_expiration,now()+interval '40 days','injury',null,false);
    raise exception 'anon expiration allowed'; exception when sqlstate '42501' then null; end;
  perform set_config('request.jwt.claim.sub',other_admin_id::text,true);
  begin perform public.get_member_membership_operation_preview(void_membership,null);
    raise exception 'cross-gym preview allowed'; exception when sqlstate 'P0002' then null; end;
  begin perform public.void_member_membership(void_membership,'assigned_by_mistake',null);
    raise exception 'cross-gym void allowed'; exception when sqlstate 'P0002' then null; end;

  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  preview:=public.get_member_membership_operation_preview(void_membership,null);
  if (preview->>'plan_name')<>'Pack 5' or (preview->>'future_booked_count')::int<>1
    or (preview->>'credits_total')::int<>5 then raise exception 'impact preview incorrect'; end if;
  result:=public.void_member_membership(void_membership,'assigned_by_mistake',null);
  if result->>'status'<>'voided' or (result->>'cancelled_booking_count')::int<>1
    or not exists(select 1 from public.member_memberships where id=void_membership and status='voided' and not is_active and credits_remaining=5)
    or not exists(select 1 from public.class_bookings where class_id=future_class and user_id=athlete_id and status='cancelled')
    or not exists(select 1 from public.class_bookings where class_id=future_class and user_id=waiter_id and status='booked')
    or exists(select 1 from public.class_bookings where class_id=future_class and user_id=athlete_id and status='booked')
    or (select count(*) from public.membership_credit_logs where membership_id=void_membership and reason='cancelled')<>1 then
    raise exception 'void/refund/waitlist semantics incorrect';
  end if;
  result:=public.void_member_membership(void_membership,'assigned_by_mistake',null);
  if not (result->>'already_applied')::boolean
    or (select count(*) from public.membership_credit_logs where membership_id=void_membership and reason='cancelled')<>1
    or (select count(*) from public.membership_admin_events where membership_id=void_membership and operation_type='void')<>1 then
    raise exception 'void retry double-applied';
  end if;
  begin perform public.void_member_membership(attended_membership,'requested_by_mistake',null);
    raise exception 'void with attendance allowed'; exception when sqlstate 'P0001' then
      if sqlerrm<>'membership_has_usage' then raise; end if; end;
  begin perform public.void_member_membership(no_show_membership,'requested_by_mistake',null);
    raise exception 'void with no-show allowed'; exception when sqlstate 'P0001' then
      if sqlerrm<>'membership_has_usage' then raise; end if; end;

  result:=public.cancel_member_membership(cancel_membership,'member_request',null);
  if result->>'status'<>'cancelled' or (result->>'cancelled_booking_count')::int<>1
    or not exists(select 1 from public.member_memberships where id=cancel_membership and status='cancelled' and not is_active and credits_remaining=4)
    or not exists(select 1 from public.class_bookings where class_id=attended_class and user_id=owner_id and status='attended') then
    raise exception 'cancel historical/future semantics incorrect';
  end if;
  result:=public.cancel_member_membership(cancel_membership,'member_request',null);
  if not (result->>'already_applied')::boolean
    or (select count(*) from public.membership_credit_logs where membership_id=cancel_membership and reason='cancelled')<>1 then
    raise exception 'cancel retry double-refunded';
  end if;

  begin perform public.change_member_membership_expiration(active_expiration,now()+interval '10 days','injury',null,false);
    raise exception 'conflicting expiration allowed without confirmation'; exception when sqlstate 'P0001' then
      if sqlerrm<>'future_bookings_conflict' then raise; end if; end;
  result:=public.change_member_membership_expiration(active_expiration,now()+interval '10 days','injury',null,true);
  if (result->>'cancelled_booking_count')::int<>1
    or not exists(select 1 from public.member_memberships where id=active_expiration
      and expires_at=ends_at and status='active' and credits_remaining=4)
    or not exists(select 1 from public.class_bookings where class_id=conflict_class and status='cancelled') then
    raise exception 'shortening expiration semantics incorrect';
  end if;
  perform public.change_member_membership_expiration(active_expiration,now()+interval '50 days','commercial_extension',null,false);
  perform public.change_member_membership_expiration(expired_pack,now()+interval '20 days','administrative_correction',null,false);
  perform public.change_member_membership_expiration(expired_empty_pack,now()+interval '20 days','administrative_correction',null,false);
  perform public.change_member_membership_expiration(expired_unlimited,now()+interval '20 days','administrative_correction',null,false);
  if not exists(select 1 from public.member_memberships where id=expired_pack and status='active' and is_active)
    or not exists(select 1 from public.member_memberships where id=expired_empty_pack and status='exhausted' and not is_active)
    or not exists(select 1 from public.member_memberships where id=expired_unlimited and status='active' and is_active) then
    raise exception 'expired pack reactivation state incorrect';
  end if;
  begin perform public.change_member_membership_expiration(scheduled_unlimited,now()+interval '75 days','gym_closure',null,false);
    raise exception 'chained unlimited changed'; exception when sqlstate 'P0001' then
      if sqlerrm<>'scheduled_unlimited_chain_conflict' then raise; end if; end;
  begin perform public.change_member_membership_expiration(scheduled_unlimited,now()+interval '20 days','gym_closure',null,false);
    raise exception 'expiration at/before scheduled start allowed'; exception when sqlstate '22023' then
      if sqlerrm<>'expiration_before_start' then raise; end if; end;
  delete from public.member_memberships where id=next_unlimited;
  perform public.change_member_membership_expiration(scheduled_unlimited,now()+interval '75 days','gym_closure',null,false);
  if not exists(select 1 from public.member_memberships where id=scheduled_unlimited
    and status='scheduled' and is_active and expires_at=ends_at) then
    raise exception 'scheduled expiration change incorrect';
  end if;
  begin perform public.change_member_membership_expiration(active_expiration,now()-interval '1 day','injury',null,false);
    raise exception 'past expiration allowed'; exception when sqlstate '22023' then null; end;
  begin perform public.change_member_membership_expiration(cancel_membership,now()+interval '60 days','injury',null,false);
    raise exception 'terminal expiration changed'; exception when sqlstate 'P0001' then null; end;

  perform public.sync_membership_states();
  if not exists(select 1 from public.member_memberships where id=void_membership and status='voided' and not is_active)
    or not exists(select 1 from public.member_memberships where id=cancel_membership and status='cancelled' and not is_active) then
    raise exception 'cron reactivated terminal membership';
  end if;
  if (select count(*) from public.membership_admin_events where gym_id=v_gym_id)<>8
    or not exists(select 1 from public.gym_activity_events where membership_id=void_membership and kind='membership_voided')
    or not exists(select 1 from public.gym_activity_events where membership_id=cancel_membership and kind='membership_cancelled')
    or not exists(select 1 from public.gym_activity_events where membership_id=active_expiration and kind='membership_expiration_changed') then
    raise exception 'membership audit events incorrect';
  end if;
  if not exists(select 1 from public.membership_admin_events
    where membership_id=active_expiration and operation_type='expiration_change'
      and old_expires_at is distinct from new_expires_at and performed_by=admin_id) then
    raise exception 'expiration audit snapshot incorrect';
  end if;

  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object(
    'sub',owner_id,'role','authenticated','session_id',owner_session_id
  )::text,true);
  perform public.select_owner_effective_gym(v_gym_id);
  preview:=public.get_member_membership_operation_preview(active_expiration,null);
  if preview->>'membership_id'<>active_expiration::text then
    raise exception 'Platform Owner inspection cannot manage membership';
  end if;
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object(
    'sub',admin_id,'role','authenticated'
  )::text,true);

  if has_table_privilege('anon','public.membership_admin_events','SELECT')
    or has_table_privilege('authenticated','public.membership_admin_events','INSERT')
    or has_table_privilege('authenticated','public.membership_admin_events','UPDATE')
    or has_table_privilege('authenticated','public.membership_admin_events','DELETE') then
    raise exception 'audit table grants are excessive';
  end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','a8100000-0000-0000-0000-000000000003',true);
do $$ begin
  if exists(select 1 from public.membership_admin_events) then raise exception 'athlete read audit rows'; end if;
end $$;
select set_config('request.jwt.claim.sub','a8100000-0000-0000-0000-000000000001',true);
do $$ begin
  if not exists(select 1 from public.membership_admin_events where gym_id='a8200000-0000-0000-0000-000000000001') then
    raise exception 'admin cannot read audit rows';
  end if;
end $$;
select set_config('request.jwt.claim.sub','a8100000-0000-0000-0000-000000000002',true);
select set_config('request.jwt.claims',jsonb_build_object(
  'sub','a8100000-0000-0000-0000-000000000002','role','authenticated',
  'session_id','a8100000-0000-0000-0000-000000000008'
)::text,true);
do $$ begin
  if not exists(select 1 from public.membership_admin_events where gym_id='a8200000-0000-0000-0000-000000000001') then
    raise exception 'gym owner cannot read audit rows';
  end if;
end $$;
reset role;

select pass('Membership Operations V1 preserves credits, bookings, state, audit and tenant security');
select * from finish();
rollback;
