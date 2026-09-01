begin;
select plan(1);
do $$
declare
 owner_id uuid:='e6100000-0000-0000-0000-000000000001';
 admin_id uuid:='e6100000-0000-0000-0000-000000000002';
 gym_a uuid:='e6200000-0000-0000-0000-000000000001';
 gym_b uuid:='e6200000-0000-0000-0000-000000000002';
 uid uuid; usage record; created uuid; reservation uuid; reservation_two uuid;
begin
 if public.saas_plan_code_for_active_athletes(0)<>'free'
   or public.saas_plan_code_for_active_athletes(10)<>'free'
   or public.saas_plan_code_for_active_athletes(11)<>'starter'
   or public.saas_plan_code_for_active_athletes(40)<>'starter'
   or public.saas_plan_code_for_active_athletes(41)<>'growth'
   or public.saas_plan_code_for_active_athletes(100)<>'growth'
   or public.saas_plan_code_for_active_athletes(101)<>'pro'
   or public.saas_plan_code_for_active_athletes(250)<>'pro'
   or public.saas_plan_code_for_active_athletes(251)<>'unlimited'
 then raise exception 'natural tier boundaries incorrect'; end if;
 insert into auth.users(id,email) values(owner_id,'saas-owner@test.invalid'),(admin_id,'saas-admin@test.invalid');
 update profiles set role=case when id=owner_id then 'owner' else 'admin' end,is_active=true where id in(owner_id,admin_id);
 insert into gyms(id,name,owner_id) values(gym_a,'SaaS A',owner_id),(gym_b,'SaaS B',owner_id);
 insert into gym_members(gym_id,user_id,role,is_active,is_coach,joined_at) values(gym_a,admin_id,'admin',true,false,now());
 update profiles set gym_id=gym_a where id=admin_id;
 if (select plan_code from gym_saas_subscriptions where gym_id=gym_a)<>'free' then raise exception 'new gym not FREE'; end if;
 -- Staff, inactive athletes and coach capability do not count.
 for i in 1..10 loop
  uid:=('e6300000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid;
  insert into auth.users(id,email) values(uid,'saas-athlete-'||i||'@test.invalid');
  insert into gym_members(gym_id,user_id,role,is_active,is_coach,joined_at) values(gym_a,uid,'athlete',true,i=1,now());
 end loop;
 select * into usage from gym_saas_usage_for(gym_a);
 if usage.active_athlete_count<>10 or not usage.limit_reached then raise exception 'active athlete count incorrect'; end if;
 uid:='e6300000-0000-0000-0000-000000000099'; insert into auth.users(id,email) values(uid,'blocked@test.invalid');
 begin
  insert into gym_members(gym_id,user_id,role,is_active,joined_at) values(gym_a,uid,'athlete',true,now());
  raise exception 'limit was bypassed';
 exception when sqlstate 'P0001' then
  if sqlerrm<>'gym_member_limit_reached' then raise; end if;
 end;
 if exists(select 1 from gym_members where gym_id=gym_a and user_id=uid) then raise exception 'partial member remained'; end if;
 insert into gym_members(gym_id,user_id,role,is_active,joined_at) values(gym_a,uid,'athlete',false,now());
 begin
  update gym_members set is_active=true where gym_id=gym_a and user_id=uid;
  raise exception 'reactivation bypassed limit';
 exception when sqlstate 'P0001' then null; end;
 update gym_members set is_active=false where gym_id=gym_a and user_id=('e6300000-0000-0000-0000-000000000001')::uuid;
 update gym_members set is_active=true where gym_id=gym_a and user_id=uid;
 -- Reservations count under the same gym lock and protect the final slot.
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 perform platform_set_gym_saas_subscription(gym_a,'starter',null);
 for i in 11..39 loop
  uid:=('e6300000-0000-0000-0001-'||lpad(i::text,12,'0'))::uuid;
  insert into auth.users(id,email) values(uid,'saas-reserve-'||i||'@test.invalid');
  insert into gym_members(gym_id,user_id,role,is_active,joined_at) values(gym_a,uid,'athlete',true,now());
 end loop;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 reservation:=reserve_effective_gym_athlete_slot('reserved@test.invalid');
 begin
  reservation_two:=reserve_effective_gym_athlete_slot('loser@test.invalid');
  raise exception 'second reservation won final slot';
 exception when sqlstate 'P0001' then
  if sqlerrm<>'gym_member_limit_reached' then raise; end if;
 end;
 update gym_saas_member_slot_reservations set expires_at=now()-interval '1 second' where id=reservation;
 reservation_two:=reserve_effective_gym_athlete_slot('winner-after-expiry@test.invalid');
 perform release_gym_athlete_slot_reservation(reservation_two);
 reservation:=reserve_effective_gym_athlete_slot('materialize@test.invalid');
 uid:='e6300000-0000-0000-0002-000000000001';
 insert into auth.users(id,email) values(uid,'materialize@test.invalid');
 perform set_config('request.jwt.claim.role','service_role',true);
 perform materialize_reserved_gym_athlete(reservation,uid,admin_id);
 if not exists(select 1 from gym_members where gym_id=gym_a and user_id=uid and role='athlete' and is_active)
   or not exists(select 1 from gym_saas_member_slot_reservations where id=reservation and consumed_at is not null)
 then raise exception 'reserved materialization failed'; end if;
 select * into usage from gym_saas_usage_for(gym_a);
 if usage.active_athlete_count<>40 or not usage.limit_reached or usage.over_limit then raise exception 'reached state incorrect'; end if;
 perform set_config('request.jwt.claim.role','authenticated',true);
 -- Gym B is isolated and unlimited works.
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 perform platform_set_gym_saas_subscription(gym_b,'unlimited',null);
 for i in 1..12 loop
  uid:=('e6400000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid;
  insert into auth.users(id,email) values(uid,'saas-b-'||i||'@test.invalid');
  insert into gym_members(gym_id,user_id,role,is_active,joined_at) values(gym_b,uid,'athlete',true,now());
 end loop;
 select * into usage from gym_saas_usage_for(gym_b);
 if usage.active_member_limit is not null or usage.active_athlete_count<>12 then raise exception 'unlimited incorrect'; end if;
 perform platform_set_gym_saas_subscription(gym_b,'free',15);
 select * into usage from gym_saas_usage_for(gym_b);
 if usage.active_member_limit<>15 then raise exception 'override incorrect'; end if;
 perform platform_set_gym_saas_subscription(gym_a,'free',null);
 select * into usage from gym_saas_usage_for(gym_a);
 if not usage.over_limit or usage.limit_reached then raise exception 'over-limit state incorrect'; end if;
 if (select count(*) from gym_members where gym_id=gym_a and role='athlete' and is_active)<>40 then raise exception 'downgrade changed athletes'; end if;
 -- Only Platform Owner can change SaaS assignment; lifecycle is independent.
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 begin perform platform_set_gym_saas_subscription(gym_a,'pro',null); raise exception 'admin changed SaaS plan';
 exception when sqlstate '42501' then null; end;
 if (select lifecycle_status from gyms where id=gym_a)<>'active' then raise exception 'lifecycle changed'; end if;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 select create_gym('SaaS Created') into created;
 if (select plan_code from gym_saas_subscriptions where gym_id=created)<>'free' then raise exception 'create_gym default failed'; end if;
end $$;
select pass('SaaS catalog, usage, default, isolation, permissions and atomic enforcement');
select * from finish();
rollback;
