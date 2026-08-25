begin;

do $$
declare
  v_owner uuid := '51000000-0000-0000-0000-000000000001';
  v_admin uuid := '51000000-0000-0000-0000-000000000002';
  v_member uuid := '51000000-0000-0000-0000-000000000003';
  v_direct uuid := '51000000-0000-0000-0000-000000000004';
  v_other_admin uuid := '51000000-0000-0000-0000-000000000005';
  v_gym uuid := '52000000-0000-0000-0000-000000000001';
  v_other_gym uuid := '52000000-0000-0000-0000-000000000002';
begin
  insert into auth.users(id, email, raw_user_meta_data) values
    (v_owner, 'pay-owner@example.test', '{}'::jsonb),
    (v_admin, 'pay-admin@example.test', '{}'::jsonb),
    (v_member, 'pay-member@example.test', '{}'::jsonb),
    (v_direct, 'pay-direct@example.test', '{}'::jsonb),
    (v_other_admin, 'pay-other@example.test', '{}'::jsonb);
  insert into public.gyms(id, name, owner_id, stripe_account_id,
    stripe_onboarding_complete, stripe_charges_enabled, stripe_payouts_enabled)
  values
    (v_gym, 'Payment Gym', v_owner, 'acct_payment', true, true, true),
    (v_other_gym, 'Other Gym', null, 'acct_other_payment', true, true, true);
  update public.profiles set gym_id = case when id = v_other_admin then v_other_gym else v_gym end,
    role = case when id in (v_owner, v_admin, v_other_admin) then 'admin' else 'athlete' end,
    is_active = true, preferred_locale = 'es', full_name = email
  where id in (v_owner, v_admin, v_member, v_direct, v_other_admin);
  insert into public.gym_members(gym_id, user_id, role, is_active, joined_at) values
    (v_gym, v_owner, 'admin', true, now()),
    (v_gym, v_admin, 'admin', true, now()),
    (v_gym, v_member, 'athlete', true, now()),
    (v_gym, v_direct, 'athlete', true, now()),
    (v_other_gym, v_other_admin, 'admin', true, now());
  insert into public.membership_plans(id, gym_id, name, plan_type, credits,
    price, currency, duration_days, is_active) values
    ('53000000-0000-0000-0000-000000000001', v_gym, 'Manual Pack', 'class_pack', 5, 35, 'EUR', 30, true),
    ('53000000-0000-0000-0000-000000000002', v_gym, 'Card Pack', 'class_pack', 10, 50, 'EUR', 30, true),
    ('53000000-0000-0000-0000-000000000003', v_gym, 'Direct Pack', 'class_pack', 3, 20, 'EUR', 30, true);
  insert into public.membership_legal_acceptances(
    user_id, gym_id, plan_id, document_id, document_type,
    document_version, document_url
  )
  select v_member, v_gym, mp.id, d.id, d.document_type, d.version, d.url
  from public.membership_plans mp
  cross join public.membership_legal_documents d
  where mp.gym_id = v_gym and d.is_active and d.is_required;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000003', true);

-- Manual request snapshots price and notifies both authorized recipients.
do $$
declare v_request uuid;
begin
  v_request := public.create_cash_membership_request('53000000-0000-0000-0000-000000000001');
  if not exists(select 1 from public.membership_requests where id = v_request
    and status = 'pending' and payment_method = 'cash' and payment_status = 'pending'
    and amount_total = 3500 and lower(currency) = 'eur') then
    raise exception 'manual request state or audit snapshot incorrect';
  end if;
end;
$$;

reset role;
do $$
declare v_request uuid;
begin
  select id into v_request from public.membership_requests
  where user_id = '51000000-0000-0000-0000-000000000003'
    and plan_id = '53000000-0000-0000-0000-000000000001';
  if (select count(*) from public.notifications where type = 'membership_request'
      and data->>'requestId' = v_request::text) <> 2 then
    raise exception 'manual request did not notify owner and admin exactly once';
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000003', true);

-- Card request remains operational but creates no admin action notification.
do $$
declare v_card record;
begin
  select * into v_card from public.prepare_card_membership_checkout(
    '53000000-0000-0000-0000-000000000002'
  );
  if exists(select 1 from public.notifications where type = 'membership_request'
    and data->>'requestId' = v_card.request_id::text) then
    raise exception 'card pending generated admin notification';
  end if;
end;
$$;

-- Admin list contains only in-person pending requests.
select set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000002', true);
do $$ begin
  if (select count(*) from public.list_effective_membership_requests(false, 50)) <> 1 then
    raise exception 'admin action list includes non-manual requests';
  end if;
end $$;

-- Cross-gym admin cannot confirm Gym A.
select set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000005', true);
do $$
declare v_request uuid;
begin
  select id into v_request from public.membership_requests
  where payment_method = 'cash' and user_id = '51000000-0000-0000-0000-000000000003';
  begin
    perform public.confirm_in_person_membership_payment(v_request, 'cash');
    raise exception 'cross-gym admin confirmed payment';
  exception when sqlstate 'P0002' then null;
  end;
end;
$$;

-- Correct admin confirms Bizum atomically; retry has one membership/notification.
select set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000002', true);
do $$
declare v_request uuid; v_membership uuid;
begin
  select id into v_request from public.membership_requests
  where payment_method = 'cash' and user_id = '51000000-0000-0000-0000-000000000003';
  perform public.confirm_in_person_membership_payment(v_request, 'bizum');
  select member_membership_id into v_membership from public.membership_requests where id = v_request;
  perform public.confirm_in_person_membership_payment(v_request, 'bizum');
  if not exists(select 1 from public.membership_requests where id = v_request
    and status = 'approved' and payment_status = 'paid'
    and manual_payment_method = 'bizum'
    and payment_confirmed_by = '51000000-0000-0000-0000-000000000002'
    and payment_confirmed_at is not null and paid_at is not null
    and member_membership_id = v_membership) then
    raise exception 'manual payment audit is incomplete';
  end if;
  if (select count(*) from public.member_memberships where id = v_membership) <> 1 then
    raise exception 'double manual confirm created duplicate membership';
  end if;
end;
$$;

reset role;
do $$ begin
  if (select count(*) from public.notifications where user_id = '51000000-0000-0000-0000-000000000003'
      and type in ('membership_payment_completed', 'membership_scheduled')) <> 1 then
    raise exception 'manual confirm notification count is not one';
  end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000003', true);

-- A second manual request can be rejected without creating a membership.
do $$ begin
  perform public.create_cash_membership_request('53000000-0000-0000-0000-000000000003');
end $$;
select set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000002', true);
do $$
declare v_request uuid;
begin
  select id into v_request from public.membership_requests
  where user_id = '51000000-0000-0000-0000-000000000003'
    and plan_id = '53000000-0000-0000-0000-000000000003' and status = 'pending';
  if not public.reject_membership_request(v_request) then raise exception 'manual reject returned false'; end if;
  if not exists(select 1 from public.membership_requests where id = v_request
    and status = 'rejected' and payment_status = 'cancelled'
    and member_membership_id is null) then raise exception 'manual reject state incorrect'; end if;
end;
$$;

-- Direct assignment is not marked paid and sends one neutral notification.
do $$ begin
  perform public.assign_membership_plan(
    '51000000-0000-0000-0000-000000000004',
    '53000000-0000-0000-0000-000000000003'
  );
  if exists(select 1 from public.membership_requests
    where user_id = '51000000-0000-0000-0000-000000000004') then
    raise exception 'direct assignment invented a payment request';
  end if;
end $$;

reset role;
do $$ begin
  if (select count(*) from public.notifications
      where user_id = '51000000-0000-0000-0000-000000000004'
        and type in ('membership_approved', 'membership_scheduled')
        and data->>'assignmentType' = 'direct') <> 1 then
    raise exception 'direct assignment notification incorrect';
  end if;
end $$;

select set_config('request.jwt.claim.role', 'service_role', true);

-- Card failure is terminal, idempotent and creates no membership.
do $$
declare v_request uuid;
begin
  select id into v_request from public.membership_requests
  where payment_method = 'card' and status = 'pending';
  perform public.attach_card_membership_checkout_session(
    v_request, 'cs_failed', 5000, 'eur', 'acct_payment', now() + interval '1 hour'
  );
  perform public.fail_card_membership_request('cs_failed', 'acct_payment');
  perform public.fail_card_membership_request('cs_failed', 'acct_payment');
  if not exists(select 1 from public.membership_requests where id = v_request
    and status = 'cancelled' and payment_status = 'failed'
    and member_membership_id is null) then
    raise exception 'card failure state incorrect';
  end if;
end;
$$;

-- Legacy approved/payment-pending rows are preserved as unknown legacy state.
do $$
declare v_id uuid := gen_random_uuid();
begin
  insert into public.membership_requests(id, user_id, gym_id, plan_id, status,
    payment_method, payment_status)
  values(v_id, '51000000-0000-0000-0000-000000000004',
    '52000000-0000-0000-0000-000000000001',
    '53000000-0000-0000-0000-000000000003', 'approved', 'cash', 'pending');
  if not exists(select 1 from public.membership_requests where id = v_id
    and status = 'approved' and payment_status = 'pending'
    and payment_confirmed_at is null) then
    raise exception 'legacy row was rewritten';
  end if;
end;
$$;

reset role;

do $$ begin
  if has_function_privilege('authenticated',
    'public.fail_card_membership_request(text,text)', 'EXECUTE') then
    raise exception 'authenticated can fail card requests';
  end if;
end $$;

rollback;
