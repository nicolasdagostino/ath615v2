begin;

do $$
declare
  gym_a uuid := 'ad000000-0000-0000-0000-000000000001';
  gym_b uuid := 'ad000000-0000-0000-0000-000000000002';
  owner_a uuid := 'ad100000-0000-0000-0000-000000000001';
  admin_a uuid := 'ad100000-0000-0000-0000-000000000002';
  coach_a uuid := 'ad100000-0000-0000-0000-000000000003';
  athlete_a uuid := 'ad100000-0000-0000-0000-000000000004';
  inactive_admin uuid := 'ad100000-0000-0000-0000-000000000005';
  admin_b uuid := 'ad100000-0000-0000-0000-000000000006';
  athlete_b uuid := 'ad100000-0000-0000-0000-000000000007';
  pack uuid := 'ad200000-0000-0000-0000-000000000001';
  unlimited uuid := 'ad200000-0000-0000-0000-000000000002';
  pack_b uuid := 'ad200000-0000-0000-0000-000000000003';
  active_pack uuid := 'ad300000-0000-0000-0000-000000000001';
  active_unlimited uuid := 'ad300000-0000-0000-0000-000000000002';
  scheduled_pack uuid := 'ad300000-0000-0000-0000-000000000003';
  expired_pack uuid := 'ad300000-0000-0000-0000-000000000004';
begin
  insert into auth.users(id,email) values
    (owner_a,'analytics-v2-owner@example.test'),
    (admin_a,'analytics-v2-admin@example.test'),
    (coach_a,'analytics-v2-coach@example.test'),
    (athlete_a,'analytics-v2-athlete@example.test'),
    (inactive_admin,'analytics-v2-inactive@example.test'),
    (admin_b,'analytics-v2-admin-b@example.test'),
    (athlete_b,'analytics-v2-athlete-b@example.test');

  insert into public.gyms(id,name,timezone,owner_id) values
    (gym_a,'Analytics V2 Gym A','Europe/Madrid',owner_a),
    (gym_b,'Analytics V2 Gym B','America/New_York',null);

  update public.profiles set gym_id = case when id = admin_b or id = athlete_b then gym_b else gym_a end,
    role = case when id = owner_a then 'owner' when id in (admin_a,inactive_admin,admin_b) then 'admin'
      when id = coach_a then 'coach' else 'athlete' end,
    is_active = true
  where id in (owner_a,admin_a,coach_a,athlete_a,inactive_admin,admin_b,athlete_b);

  insert into public.gym_members(gym_id,user_id,role,is_active,is_coach,joined_at) values
    (gym_a,admin_a,'admin',true,false,now()-interval '1 year'),
    (gym_a,coach_a,'coach',true,true,now()-interval '1 year'),
    (gym_a,athlete_a,'athlete',true,false,now()-interval '1 year'),
    (gym_a,inactive_admin,'admin',false,false,now()-interval '1 year'),
    (gym_b,admin_b,'admin',true,false,now()-interval '1 year'),
    (gym_b,athlete_b,'athlete',true,false,now()-interval '1 year');

  insert into public.membership_plans(id,gym_id,name,plan_type,credits,price,currency,duration_days) values
    (pack,gym_a,'Pack A','class_pack',10,35,'EUR',30),
    (unlimited,gym_a,'Unlimited A','unlimited',null,80,'EUR',30),
    (pack_b,gym_b,'Pack B','class_pack',5,20,'USD',30);

  insert into public.member_memberships(id,user_id,gym_id,status,starts_at,ends_at,expires_at,is_active,plan_id,credits_remaining,created_at) values
    (active_pack,athlete_a,gym_a,'active',now()-interval '2 days',now()+interval '28 days',now()+interval '28 days',true,pack,7,now()-interval '2 days'),
    (active_unlimited,coach_a,gym_a,'active',now()-interval '3 days',now()+interval '27 days',now()+interval '27 days',true,unlimited,null,now()-interval '3 days'),
    (scheduled_pack,athlete_a,gym_a,'scheduled',now()+interval '2 days',now()+interval '32 days',now()+interval '32 days',true,pack,10,now()-interval '1 day'),
    (expired_pack,athlete_a,gym_a,'expired',now()-interval '35 days',now()-interval '1 day',now()-interval '1 day',false,pack,3,now()-interval '35 days'),
    ('ad300000-0000-0000-0000-000000000005',athlete_a,gym_a,'exhausted',now()-interval '20 days',now()+interval '10 days',now()+interval '10 days',false,pack,0,now()-interval '20 days'),
    ('ad300000-0000-0000-0000-000000000006',athlete_a,gym_a,'cancelled',now()-interval '15 days',now()+interval '15 days',now()+interval '15 days',false,pack,4,now()-interval '15 days'),
    ('ad300000-0000-0000-0000-000000000007',athlete_a,gym_a,'replaced',now()-interval '10 days',now()+interval '20 days',now()+interval '20 days',false,pack,5,now()-interval '10 days'),
    ('ad300000-0000-0000-0000-000000000008',athlete_b,gym_b,'active',now()-interval '1 day',now()+interval '29 days',now()+interval '29 days',true,pack_b,5,now()-interval '1 day');

  insert into public.membership_credit_logs(id,user_id,gym_id,membership_id,amount,reason,created_at) values
    ('ad400000-0000-0000-0000-000000000001',athlete_a,gym_a,active_pack,10,'paid',now()-interval '2 days'),
    ('ad400000-0000-0000-0000-000000000002',athlete_a,gym_a,active_pack,-1,'booked',now()-interval '2 days'),
    ('ad400000-0000-0000-0000-000000000003',athlete_a,gym_a,active_pack,1,'cancelled',now()-interval '1 day'),
    ('ad400000-0000-0000-0000-000000000004',athlete_a,gym_a,scheduled_pack,10,'assigned',now()-interval '1 day'),
    ('ad400000-0000-0000-0000-000000000005',athlete_a,gym_a,active_pack,1,'class_cancelled',now()-interval '1 day'),
    ('ad400000-0000-0000-0000-000000000006',athlete_b,gym_b,'ad300000-0000-0000-0000-000000000008',5,'paid',now()-interval '1 day');

  insert into public.membership_requests(
    id,user_id,gym_id,plan_id,status,payment_method,payment_status,
    amount_total,currency,paid_at,stripe_plan_name,manual_payment_method,created_at
  ) values
    ('ad500000-0000-0000-0000-000000000001',athlete_a,gym_a,pack,'approved','card','paid',3500,'EUR',now()-interval '2 days','Pack A',null,now()-interval '2 days'),
    ('ad500000-0000-0000-0000-000000000002',athlete_a,gym_a,pack,'approved','cash','paid',3500,'EUR',now()-interval '1 day','Historic Pack A','cash',now()-interval '1 day'),
    ('ad500000-0000-0000-0000-000000000003',athlete_a,gym_a,unlimited,'approved','cash','paid',8000,'USD',now()-interval '1 day','Unlimited historic','bizum',now()-interval '1 day'),
    ('ad500000-0000-0000-0000-000000000004',athlete_a,gym_a,pack,'pending','card','pending',3500,'EUR',null,'Pack A',null,now()-interval '1 day'),
    ('ad500000-0000-0000-0000-000000000005',athlete_a,gym_a,pack,'rejected','card','failed',3500,'EUR',null,'Pack A',null,now()-interval '1 day'),
    ('ad500000-0000-0000-0000-000000000006',athlete_a,gym_a,pack,'cancelled','card','cancelled',3500,'EUR',null,'Pack A',null,now()-interval '1 day'),
    ('ad500000-0000-0000-0000-000000000007',athlete_a,gym_a,pack,'approved','cash','pending',null,'EUR',null,null,null,now()-interval '1 day'),
    ('ad500000-0000-0000-0000-000000000008',athlete_a,gym_a,pack,'approved','card','paid',null,'EUR',null,null,null,now()-interval '1 day'),
    ('ad500000-0000-0000-0000-000000000009',athlete_a,gym_a,pack,'approved','cash','paid',1200,'EUR',now()-interval '1 day','Pack A',null,now()-interval '1 day'),
    ('ad500000-0000-0000-0000-000000000010',athlete_a,gym_a,pack,'approved','card','paid',1000,'EUR',now()-interval '40 days','Pack A',null,now()-interval '40 days'),
    ('ad500000-0000-0000-0000-000000000011',athlete_b,gym_b,pack_b,'approved','card','paid',2000,'USD',now()-interval '1 day','Pack B',null,now()-interval '1 day');
end $$;

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','ad100000-0000-0000-0000-000000000002',true);

do $$
declare m jsonb; r jsonb;
begin
  m := public.get_effective_membership_analytics('30d');
  if m #>> '{period,timezone}' <> 'Europe/Madrid'
      or (m #>> '{snapshot,active}')::int <> 2
      or (m #>> '{snapshot,activePacks}')::int <> 1
      or (m #>> '{snapshot,activeUnlimited}')::int <> 1
      or (m #>> '{snapshot,scheduled}')::int <> 1
      or (m #>> '{snapshot,exhausted}')::int <> 1
      or (m #>> '{snapshot,cancelled}')::int <> 1
      or (m #>> '{snapshot,replaced}')::int <> 1 then
    raise exception 'membership snapshot mismatch: %',m;
  end if;
  if (m #>> '{credits,purchasedGranted}')::int <> 10
      or (m #>> '{credits,assignedGranted}')::int <> 10
      or (m #>> '{credits,consumed}')::int <> 1
      or (m #>> '{credits,refunded}')::int <> 2
      or (m #>> '{credits,netConsumed}')::int <> -1
      or (m #>> '{credits,currentRemaining}')::int <> 17
      or (m #>> '{credits,expiredUnused}')::int <> 3 then
    raise exception 'credit classification mismatch: %',m;
  end if;
  if not exists (
    select 1 from jsonb_array_elements(m->'plans') p
    where p->>'planName' = 'Pack A'
      and (p->>'paidSales')::int = 3
      and (p->>'directAssignments')::int = 1
  ) then raise exception 'plan ranking mismatch: %',m; end if;

  r := public.get_effective_revenue_analytics('30d');
  if jsonb_array_length(r->'currencies') <> 2 then
    raise exception 'multi-currency was combined: %',r;
  end if;
  if not exists (
    select 1 from jsonb_array_elements(r->'currencies') c
    where c->>'currency' = 'EUR' and (c->>'totalMinor')::int = 8200
      and (c->>'paymentCount')::int = 3
  ) or not exists (
    select 1 from jsonb_array_elements(r->'currencies') c
    where c->>'currency' = 'USD' and (c->>'totalMinor')::int = 8000
  ) then raise exception 'historical revenue mismatch: %',r; end if;
  if not exists (
    select 1 from jsonb_array_elements(r->'plans') p
    where p->>'planName' = 'Historic Pack A' and (p->>'revenueMinor')::int = 3500
  ) then raise exception 'historical plan label not used: %',r; end if;
  if (r #>> '{states,pending}')::int <> 2
      or (r #>> '{states,failed}')::int <> 1
      or (r #>> '{states,cancelled}')::int <> 1
      or (r #>> '{excluded,paidMissingAudit}')::int <> 1
      or (r #>> '{excluded,legacyApprovedPending}')::int <> 1
      or (r #>> '{excluded,unclassifiedManualMethod}')::int <> 1 then
    raise exception 'legacy/state classification mismatch: %',r;
  end if;
end $$;

-- Owner receives the same effective-gym aggregates.
select set_config('request.jwt.claim.sub','ad100000-0000-0000-0000-000000000001',true);
do $$ declare r jsonb; begin
  r := public.get_effective_revenue_analytics('30d');
  if jsonb_array_length(r->'currencies') <> 2 then raise exception 'owner denied'; end if;
end $$;

-- Coach, athlete, and inactive admin are rejected.
select set_config('request.jwt.claim.sub','ad100000-0000-0000-0000-000000000003',true);
do $$ begin begin perform public.get_effective_membership_analytics('30d'); raise exception 'coach allowed'; exception when insufficient_privilege then null; end; end $$;
select set_config('request.jwt.claim.sub','ad100000-0000-0000-0000-000000000004',true);
do $$ begin begin perform public.get_effective_revenue_analytics('30d'); raise exception 'athlete allowed'; exception when insufficient_privilege then null; end; end $$;
select set_config('request.jwt.claim.sub','ad100000-0000-0000-0000-000000000005',true);
do $$ begin begin perform public.get_effective_membership_analytics('30d'); raise exception 'inactive admin allowed'; exception when insufficient_privilege then null; end; end $$;

-- Gym B sees only its own USD payment and membership.
select set_config('request.jwt.claim.sub','ad100000-0000-0000-0000-000000000006',true);
do $$ declare m jsonb; r jsonb; begin
  m := public.get_effective_membership_analytics('30d');
  r := public.get_effective_revenue_analytics('30d');
  if (m #>> '{snapshot,active}')::int <> 1
      or jsonb_array_length(r->'currencies') <> 1
      or r #>> '{currencies,0,currency}' <> 'USD'
      or (r #>> '{currencies,0,totalMinor}')::int <> 2000 then
    raise exception 'cross-gym isolation failed: %, %',m,r;
  end if;
end $$;

rollback;
