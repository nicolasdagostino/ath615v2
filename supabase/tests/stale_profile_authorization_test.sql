-- Synthetic fixtures only. Every assertion runs through authenticated RLS.
-- The transaction rolls back all fixture data and owner inspection changes.
begin;
set local role postgres;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(27);
insert into auth.users(id,email) values
 ('e9210000-0000-0000-0000-000000000001','p0-actor@test.invalid'),
 ('e9210000-0000-0000-0000-000000000002','p0-target@test.invalid'),
 ('e9210000-0000-0000-0000-000000000003','p0-other@test.invalid'),
 ('e9210000-0000-0000-0000-000000000004','p0-owner@test.invalid');
update public.profiles set role=case when id='e9210000-0000-0000-0000-000000000004' then 'owner' else 'athlete' end,
 is_active=true where id in ('e9210000-0000-0000-0000-000000000001','e9210000-0000-0000-0000-000000000002','e9210000-0000-0000-0000-000000000003','e9210000-0000-0000-0000-000000000004');
insert into public.gyms(id,name,owner_id,lifecycle_status) values
 ('e9220000-0000-0000-0000-000000000001','P0 disposable one','e9210000-0000-0000-0000-000000000004','active'),
 ('e9220000-0000-0000-0000-000000000002','P0 disposable two','e9210000-0000-0000-0000-000000000004','active');
update public.profiles set gym_id='e9220000-0000-0000-0000-000000000001'
 where id in ('e9210000-0000-0000-0000-000000000001','e9210000-0000-0000-0000-000000000002');
update public.profiles set gym_id='e9220000-0000-0000-0000-000000000002' where id='e9210000-0000-0000-0000-000000000003';
insert into public.gym_members(gym_id,user_id,role,is_active,joined_at) values
 ('e9220000-0000-0000-0000-000000000001','e9210000-0000-0000-0000-000000000001','athlete',true,now()),
 ('e9220000-0000-0000-0000-000000000001','e9210000-0000-0000-0000-000000000002','athlete',true,now()),
 ('e9220000-0000-0000-0000-000000000002','e9210000-0000-0000-0000-000000000003','athlete',true,now());
insert into public.personal_records(id,user_id,gym_id,exercise_name,weight_kg) values
 ('e9230000-0000-0000-0000-000000000001','e9210000-0000-0000-0000-000000000001','e9220000-0000-0000-0000-000000000001','P0 fixture',1),
 ('e9230000-0000-0000-0000-000000000002','e9210000-0000-0000-0000-000000000002','e9220000-0000-0000-0000-000000000001','P0 fixture',1),
 ('e9230000-0000-0000-0000-000000000003','e9210000-0000-0000-0000-000000000003','e9220000-0000-0000-0000-000000000002','P0 fixture',1);
select set_config('request.jwt.claim.sub','e9210000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"e9210000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select is((select count(*) from public.profiles where id='e9210000-0000-0000-0000-000000000002'),1::bigint,'active member reads same-gym profile');
select is((select count(*) from public.profiles where id='e9210000-0000-0000-0000-000000000003'),0::bigint,'different-gym profile denied');
select is((select count(*) from public.profiles where id='e9210000-0000-0000-0000-000000000001'),1::bigint,'self profile preserved');
select is((select count(*) from public.personal_records where id='e9230000-0000-0000-0000-000000000001'),1::bigint,'own record preserved');
select is((select count(*) from public.personal_records where id='e9230000-0000-0000-0000-000000000002'),0::bigint,'ordinary member cannot read another record');
set local role postgres;
update public.profiles set role='admin' where id='e9210000-0000-0000-0000-000000000001';
set local role authenticated;
select ok(public.effective_gym_role()='athlete','active athlete relation overrides stale admin profile');
select ok(not public.membership_actor_can_manage(),'stale admin profile has no management authority');
select is((select count(*) from public.personal_records where id='e9230000-0000-0000-0000-000000000002'),0::bigint,'stale admin with active athlete relation denied records');
set local role postgres;
update public.gym_members set is_active=false where user_id='e9210000-0000-0000-0000-000000000001';
set local role authenticated;
select is((select count(*) from public.profiles where id='e9210000-0000-0000-0000-000000000002'),0::bigint,'inactive membership denies cross-user profile despite overlapping policies');
select is((select count(*) from public.personal_records where id='e9230000-0000-0000-0000-000000000002'),0::bigint,'inactive membership denies admin record');
select is((select count(*) from public.profiles where id='e9210000-0000-0000-0000-000000000001'),1::bigint,'inactive membership retains self profile');
set local role postgres;
delete from public.gym_members where user_id='e9210000-0000-0000-0000-000000000001';
set local role authenticated;
select is((select count(*) from public.profiles where id='e9210000-0000-0000-0000-000000000002'),0::bigint,'missing membership denies stale admin cross-user profile');
select is((select count(*) from public.personal_records where id='e9230000-0000-0000-0000-000000000002'),0::bigint,'missing membership denies stale admin record');
select ok(public.effective_gym_id() is null,'stale selected gym has no authority');
set local role postgres;
update public.profiles set role='athlete' where id='e9210000-0000-0000-0000-000000000001';
insert into public.gym_members(gym_id,user_id,role,is_active,joined_at) values
 ('e9220000-0000-0000-0000-000000000001','e9210000-0000-0000-0000-000000000001','admin',true,now());
set local role authenticated;
select ok(public.effective_gym_role()='admin','active admin relation overrides stale athlete profile');
select ok(public.membership_actor_can_manage(),'relational admin management allowed');
select is((select count(*) from public.profiles where id='e9210000-0000-0000-0000-000000000002'),1::bigint,'relational admin reads same-gym profile');
select is((select count(*) from public.personal_records where id='e9230000-0000-0000-0000-000000000002'),1::bigint,'relational admin reads same-gym records');
select is((select count(*) from public.personal_records where id='e9230000-0000-0000-0000-000000000003'),0::bigint,'relational admin cannot cross gyms');
select set_config('request.jwt.claim.sub','e9210000-0000-0000-0000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"e9210000-0000-0000-0000-000000000004","role":"authenticated","session_id":"e9240000-0000-0000-0000-000000000001"}',true);
select ok(public.effective_gym_id() is null,'non-inspecting owner has no gym authority');
select is((select count(*) from public.personal_records where id='e9230000-0000-0000-0000-000000000002'),0::bigint,'non-inspecting owner cannot read gym records');
select public.select_owner_effective_gym('e9220000-0000-0000-0000-000000000001');
select ok(public.effective_gym_role()='admin' and public.membership_actor_can_manage(),'validated owner inspection retains admin authority without membership');
select is((select count(*) from public.profiles where id='e9210000-0000-0000-0000-000000000002'),1::bigint,'validated owner reads gym profile');
select is((select count(*) from public.personal_records where id='e9230000-0000-0000-0000-000000000002'),1::bigint,'validated owner reads gym records');
set local role postgres;
delete from auth.users where id='e9210000-0000-0000-0000-000000000001';
select ok(not exists(select 1 from public.profiles where id='e9210000-0000-0000-0000-000000000001')
 and not exists(select 1 from public.gym_members where user_id='e9210000-0000-0000-0000-000000000001')
 and not exists(select 1 from public.personal_records where user_id='e9210000-0000-0000-0000-000000000001'),'Auth deletion cascades profile membership and records');
select set_config('request.jwt.claim.sub','e9210000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"e9210000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select is((select count(*) from public.profiles where id='e9210000-0000-0000-0000-000000000002'),0::bigint,'deleted-user old subject cannot read gym profiles');
select is((select count(*) from public.personal_records where id='e9230000-0000-0000-0000-000000000002'),0::bigint,'deleted-user old subject cannot read gym records');
set local role postgres;
select * from finish();
rollback;
