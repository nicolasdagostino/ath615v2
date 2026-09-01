begin;
select plan(1);

do $$
declare
  owner_id uuid:='f1100000-0000-0000-0000-000000000001';
  admin_id uuid:='f1100000-0000-0000-0000-000000000002';
  athlete_id uuid:='f1100000-0000-0000-0000-000000000003';
  gym_a uuid:='f1200000-0000-0000-0000-000000000001';
  gym_b uuid:='f1200000-0000-0000-0000-000000000002';
  dashboard jsonb; detail jsonb; request_id uuid; before_members bigint; before_requests bigint;
begin
  insert into auth.users(id,email) values
    (owner_id,'owner-v2@test.invalid'),(admin_id,'admin-v2@test.invalid'),(athlete_id,'athlete-v2@test.invalid');
  update profiles set
    role=case when id=owner_id then 'owner' when id=admin_id then 'admin' else 'athlete' end,
    is_active=true,
    full_name=case when id=admin_id then 'Admin Contact' else full_name end,
    phone=case when id=admin_id then '+34000000000' else phone end
  where id in(owner_id,admin_id,athlete_id);
  insert into gyms(id,name,owner_id) values(gym_a,'Owner CRM Active',owner_id),(gym_b,'Owner CRM Suspended',owner_id);
  update gyms set phone='+34111111111',email='gym@test.invalid',website='https://example.invalid',address='Test address'
    where id=gym_a;
  update gyms set lifecycle_status='suspended' where id=gym_b;
  insert into gym_members(gym_id,user_id,role,is_active,joined_at) values
    (gym_a,admin_id,'admin',true,now()),(gym_a,athlete_id,'athlete',true,now());
  update profiles set gym_id=gym_a where id in(admin_id,athlete_id);
  perform set_config('request.jwt.claim.role','authenticated',true);

  -- Neither an athlete nor a gym Admin can use Platform Owner read RPCs,
  -- including an explicit gym id from their own or another gym.
  perform set_config('request.jwt.claim.sub',athlete_id::text,true);
  begin perform get_platform_owner_dashboard_v2(); raise exception 'athlete read dashboard';
  exception when sqlstate '42501' then null; end;
  begin perform get_platform_gym_crm_v2(gym_b); raise exception 'athlete cross-gym detail';
  exception when sqlstate '42501' then null; end;
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  begin perform get_platform_owner_dashboard_v2(); raise exception 'admin read dashboard';
  exception when sqlstate '42501' then null; end;
  begin perform get_platform_gym_crm_v2(gym_a); raise exception 'admin read own Platform detail';
  exception when sqlstate '42501' then null; end;

  -- Add one real pending request through the V1.1 contract.
  select id into request_id from request_effective_gym_saas_plan_change('starter');
  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  select count(*) into before_members from gym_members;
  select count(*) into before_requests from gym_saas_plan_change_requests;
  dashboard:=get_platform_owner_dashboard_v2();
  detail:=get_platform_gym_crm_v2(gym_a);

  if (dashboard->'summary'->>'active_gym_count')::bigint<1
    or (dashboard->'summary'->>'suspended_gym_count')::bigint<1
    or (dashboard->'summary'->>'pending_plan_request_count')::bigint<1 then
    raise exception 'dashboard KPI aggregate incorrect';
  end if;
  if not exists(select 1 from jsonb_array_elements(dashboard->'gyms') g
    where g->>'gym_id'=gym_b::text and g->>'lifecycle_status'='suspended') then
    raise exception 'lifecycle filter data missing';
  end if;
  if detail->>'gym_name'<>'Owner CRM Active' or detail->>'saas_plan_name'<>'FREE'
    or (detail->>'saas_active_athlete_count')::bigint<>1
    or detail->'pending_plan_request'->>'id'<>request_id::text then
    raise exception 'CRM SaaS data incorrect';
  end if;
  if detail->'contact'->>'phone'<>'+34111111111'
    or jsonb_array_length(detail->'admins')<>1
    or detail->'admins'->0->>'full_name'<>'Admin Contact'
    or detail->'admins'->0->>'phone'<>'+34000000000' then
    raise exception 'CRM minimized contact data incorrect';
  end if;
  if (detail->>'database_record_count')::bigint<2
    or (detail->>'database_record_share_percent')::numeric<0
    or detail->>'storage_attribution_available'<>'false' then
    raise exception 'data health semantics incorrect';
  end if;
  if (select count(*) from gym_members)<>before_members
    or (select count(*) from gym_saas_plan_change_requests)<>before_requests
    or not exists(select 1 from gym_saas_plan_change_requests where id=request_id and status='pending') then
    raise exception 'read RPC mutated state';
  end if;
end $$;

select pass('Platform Owner UX V2 aggregates, privacy, security and read-only behavior hold');
select * from finish();
rollback;
