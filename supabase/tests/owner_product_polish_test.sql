begin;
select plan(1);

do $$ declare owner_id uuid:='bf100000-0000-0000-0000-000000000001'; admin_id uuid:='bf100000-0000-0000-0000-000000000002'; athlete_id uuid:='bf100000-0000-0000-0000-000000000003';
begin
  insert into auth.users(id,email) values(owner_id,'owner-polish@test.invalid'),(admin_id,'admin-polish@test.invalid'),(athlete_id,'athlete-polish@test.invalid');
  update profiles set role='owner',is_active=true where id=owner_id;
  update profiles set role='admin',is_active=true where id=admin_id;
  update profiles set role='athlete',is_active=true where id=athlete_id;
end $$;

select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','bf100000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims',jsonb_build_object(
  'sub','bf100000-0000-0000-0000-000000000001','role','authenticated',
  'session_id','bf100000-0000-0000-0000-000000000099'
)::text,true);
select public.create_gym('Owner Polish Gym');

do $$ declare gid uuid; rows_count integer;
begin
  select gym_id into gid from public.list_owner_gym_overview() where gym_name='Owner Polish Gym';
  if gid is null then raise exception 'owner overview omitted owned gym'; end if;
  if public.select_owner_effective_gym(gid)<>gid or public.effective_gym_id()<>gid then raise exception 'owner selection did not become effective'; end if;
  select count(*) into rows_count from public.list_owner_gym_overview();
  if rows_count<>1 then raise exception 'unexpected owner gym count %',rows_count; end if;
end $$;

select set_config('request.jwt.claim.sub','bf100000-0000-0000-0000-000000000003',true);
do $$ begin
  perform public.list_owner_gym_overview();
  raise exception 'athlete received owner gyms';
exception when sqlstate '42501' then null; end $$;
do $$ begin
  perform public.select_owner_effective_gym((select id from gyms where name='Owner Polish Gym'));
  raise exception 'cross-role gym switch accepted';
exception when sqlstate '42501' then null; end $$;

select pass('owner overview, effective selection and cross-role isolation');
select * from finish();

rollback;
