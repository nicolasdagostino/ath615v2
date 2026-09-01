begin;
select plan(1);
do $$
declare
  owner_id uuid:='e7100000-0000-0000-0000-000000000001';
  admin_a uuid:='e7100000-0000-0000-0000-000000000002';
  admin_b uuid:='e7100000-0000-0000-0000-000000000003';
  athlete_actor uuid:='e7100000-0000-0000-0000-000000000004';
  coach_actor uuid:='e7100000-0000-0000-0000-000000000005';
  gym_a uuid:='e7200000-0000-0000-0000-000000000001';
  gym_b uuid:='e7200000-0000-0000-0000-000000000002';
  uid uuid; req gym_saas_plan_change_requests; before_plan text;
begin
  if exists(select 1 from saas_plans where (code='free' and monthly_price_eur<>0)
    or (code='starter' and monthly_price_eur<>19) or (code='growth' and monthly_price_eur<>39)
    or (code='pro' and monthly_price_eur<>59) or (code='unlimited' and monthly_price_eur<>79)) then
    raise exception 'SaaS prices incorrect';
  end if;
  insert into auth.users(id,email) values
    (owner_id,'v11-owner@test.invalid'),(admin_a,'v11-admin-a@test.invalid'),(admin_b,'v11-admin-b@test.invalid'),
    (athlete_actor,'v11-athlete@test.invalid'),(coach_actor,'v11-coach@test.invalid');
  update profiles set role=case when id=owner_id then 'owner' when id in(admin_a,admin_b) then 'admin'
    when id=coach_actor then 'coach' else 'athlete' end,is_active=true where id in(owner_id,admin_a,admin_b,athlete_actor,coach_actor);
  insert into gyms(id,name,owner_id) values(gym_a,'V1.1 A',owner_id),(gym_b,'V1.1 B',owner_id);
  insert into gym_members(gym_id,user_id,role,is_active,joined_at) values
    (gym_a,admin_a,'admin',true,now()),(gym_b,admin_b,'admin',true,now()),
    (gym_a,athlete_actor,'athlete',true,now()),(gym_a,coach_actor,'coach',true,now());
  update profiles set gym_id=gym_a where id in(admin_a,athlete_actor,coach_actor);
  update profiles set gym_id=gym_b where id=admin_b;
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  perform platform_set_gym_saas_subscription(gym_a,'starter',null);
  perform platform_set_gym_saas_subscription(gym_b,'growth',null);
  for i in 2..39 loop
    uid:=('e7300000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid;
    insert into auth.users(id,email) values(uid,'v11-a-'||i||'@test.invalid');
    insert into gym_members(gym_id,user_id,role,is_active,joined_at) values(gym_a,uid,'athlete',true,now());
  end loop;
  -- Effective Admin upgrade; request is gym-scoped and unique.
  perform set_config('request.jwt.claim.sub',admin_a::text,true);
  req:=request_effective_gym_saas_plan_change('growth');
  if req.gym_id<>gym_a or req.current_plan_code<>'starter' or req.requested_plan_code<>'growth' then raise exception 'upgrade request incorrect'; end if;
  begin perform request_effective_gym_saas_plan_change('pro'); raise exception 'duplicate pending allowed';
  exception when sqlstate 'P0001' then if sqlerrm<>'saas_plan_change_pending' then raise; end if; end;
  perform cancel_effective_gym_saas_plan_change(req.id);
  begin perform request_effective_gym_saas_plan_change('starter'); raise exception 'same plan allowed';
  exception when sqlstate 'P0001' then if sqlerrm<>'saas_plan_unchanged' then raise; end if; end;
  begin perform request_effective_gym_saas_plan_change('free'); raise exception '39 to FREE allowed';
  exception when sqlstate 'P0001' then if sqlerrm<>'saas_plan_capacity_too_low' then raise; end if; end;
  -- Actor security.
  perform set_config('request.jwt.claim.sub',athlete_actor::text,true);
  begin perform request_effective_gym_saas_plan_change('growth'); raise exception 'athlete requested'; exception when sqlstate '42501' then null; end;
  perform set_config('request.jwt.claim.sub',coach_actor::text,true);
  begin perform request_effective_gym_saas_plan_change('growth'); raise exception 'coach requested'; exception when sqlstate '42501' then null; end;
  -- Exact FREE boundary and rejection does not mutate subscription.
  update gym_members set is_active=false where gym_id=gym_a and role='athlete' and user_id<>athlete_actor;
  for i in 2..10 loop update gym_members set is_active=true where gym_id=gym_a and user_id=('e7300000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid; end loop;
  perform set_config('request.jwt.claim.sub',admin_a::text,true);
  req:=request_effective_gym_saas_plan_change('free');
  perform set_config('request.jwt.claim.sub',admin_a::text,true);
  begin perform platform_review_saas_plan_change(req.id,true,null); raise exception 'admin approved'; exception when sqlstate '42501' then null; end;
  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  before_plan:=(select plan_code from gym_saas_subscriptions where gym_id=gym_a);
  perform platform_review_saas_plan_change(req.id,false,'Commercial review');
  if (select plan_code from gym_saas_subscriptions where gym_id=gym_a)<>before_plan then raise exception 'rejection changed plan'; end if;
  if not exists(select 1 from gym_saas_plan_change_requests where id=req.id and status='rejected' and reviewed_by=owner_id and reviewed_at is not null) then raise exception 'rejection audit missing'; end if;
  update gym_members set is_active=true where gym_id=gym_a and user_id=('e7300000-0000-0000-0000-000000000011')::uuid;
  perform set_config('request.jwt.claim.sub',admin_a::text,true);
  begin perform request_effective_gym_saas_plan_change('free'); raise exception '11 to FREE allowed'; exception when sqlstate 'P0001' then null; end;
  -- 40 to STARTER allowed, 41 rejected.
  perform set_config('request.jwt.claim.sub',owner_id::text,true); perform platform_set_gym_saas_subscription(gym_a,'growth',null);
  for i in 12..40 loop update gym_members set is_active=true where gym_id=gym_a and user_id=('e7300000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid; end loop;
  perform set_config('request.jwt.claim.sub',admin_a::text,true); req:=request_effective_gym_saas_plan_change('starter'); perform cancel_effective_gym_saas_plan_change(req.id);
  uid:='e7300000-0000-0000-0000-000000000041'; insert into auth.users(id,email) values(uid,'v11-a-41@test.invalid');
  insert into gym_members(gym_id,user_id,role,is_active,joined_at) values(gym_a,uid,'athlete',true,now());
  begin perform request_effective_gym_saas_plan_change('starter'); raise exception '41 to STARTER allowed'; exception when sqlstate 'P0001' then null; end;
  -- Unlimited is always requestable and approval is atomic/audited.
  req:=request_effective_gym_saas_plan_change('unlimited');
  perform set_config('request.jwt.claim.sub',owner_id::text,true); perform platform_review_saas_plan_change(req.id,true,null);
  if (select plan_code from gym_saas_subscriptions where gym_id=gym_a)<>'unlimited'
    or not exists(select 1 from gym_saas_plan_change_requests where id=req.id and status='approved' and reviewed_by=owner_id and reviewed_at is not null)
    or (select changed_by from gym_saas_subscriptions where gym_id=gym_a)<>owner_id then raise exception 'approval not atomic/audited'; end if;
  for i in 42..251 loop
    uid:=('e7400000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid;
    insert into auth.users(id,email) values(uid,'v11-big-'||i||'@test.invalid');
    insert into gym_members(gym_id,user_id,role,is_active,joined_at) values(gym_a,uid,'athlete',true,now());
  end loop;
  perform set_config('request.jwt.claim.sub',admin_a::text,true);
  begin perform request_effective_gym_saas_plan_change('pro'); raise exception '251 to PRO allowed'; exception when sqlstate 'P0001' then null; end;
  -- Approval revalidates and leaves request pending on failure.
  for i in 1..39 loop
    uid:=('e7500000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid;
    insert into auth.users(id,email) values(uid,'v11-b-'||i||'@test.invalid');
    insert into gym_members(gym_id,user_id,role,is_active,joined_at) values(gym_b,uid,'athlete',true,now());
  end loop;
  perform set_config('request.jwt.claim.sub',admin_b::text,true); req:=request_effective_gym_saas_plan_change('starter');
  for i in 40..41 loop
    uid:=('e7500000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid;
    insert into auth.users(id,email) values(uid,'v11-b-'||i||'@test.invalid');
    insert into gym_members(gym_id,user_id,role,is_active,joined_at) values(gym_b,uid,'athlete',true,now());
  end loop;
  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  if not exists(select 1 from list_platform_saas_plan_change_requests('pending') where id=req.id and gym_id=gym_b) then raise exception 'Owner pending list missing'; end if;
  begin perform platform_review_saas_plan_change(req.id,true,null); raise exception 'approval skipped revalidation';
  exception when sqlstate 'P0001' then if sqlerrm<>'saas_plan_capacity_too_low' then raise; end if; end;
  if not exists(select 1 from gym_saas_plan_change_requests where id=req.id and status='pending')
    or (select plan_code from gym_saas_subscriptions where gym_id=gym_b)<>'growth' then raise exception 'failed approval was not atomic'; end if;
  perform set_config('request.jwt.claim.sub',admin_b::text,true);
  perform cancel_effective_gym_saas_plan_change(req.id);
  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  update gyms set lifecycle_status='suspended' where id=gym_b;
  perform set_config('request.jwt.claim.sub',admin_b::text,true);
  begin perform request_effective_gym_saas_plan_change('unlimited'); raise exception 'suspended gym requested';
  exception when sqlstate 'P0001' or sqlstate '42501' then null; end;
end $$;
select pass('SaaS V1.1 catalog, requests, security, boundaries and transactional review');
select * from finish();
rollback;
