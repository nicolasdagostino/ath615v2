begin;

do $$
declare
  v_owner_a uuid := '10000000-0000-0000-0000-000000000001';
  v_admin_a uuid := '10000000-0000-0000-0000-000000000002';
  v_athlete_a uuid := '10000000-0000-0000-0000-000000000003';
  v_coach_a uuid := '10000000-0000-0000-0000-000000000004';
  v_admin_b uuid := '10000000-0000-0000-0000-000000000005';
  v_gym_a uuid := '20000000-0000-0000-0000-000000000001';
  v_gym_b uuid := '20000000-0000-0000-0000-000000000002';
begin
  insert into auth.users(id, email, raw_user_meta_data)
  values
    (v_owner_a, 'owner-a@example.test', '{}'::jsonb),
    (v_admin_a, 'admin-a@example.test', '{}'::jsonb),
    (v_athlete_a, 'athlete-a@example.test', '{}'::jsonb),
    (v_coach_a, 'coach-a@example.test', '{}'::jsonb),
    (v_admin_b, 'admin-b@example.test', '{}'::jsonb);

  insert into public.gyms(
    id, name, stripe_account_id, stripe_onboarding_complete,
    stripe_charges_enabled, stripe_payouts_enabled
  ) values
    (v_gym_a, 'Gym A', 'acct_A', true, true, true),
    (v_gym_b, 'Gym B', 'acct_B', true, true, true);

  update public.profiles
  set full_name = case id
        when v_owner_a then 'Owner A'
        when v_admin_a then 'Admin A'
        when v_athlete_a then 'Athlete A'
        when v_coach_a then 'Coach A'
        else 'Admin B'
      end,
      gym_id = case when id = v_admin_b then v_gym_b else v_gym_a end,
      role = case
        when id in (v_owner_a, v_admin_a, v_admin_b) then 'admin'
        else 'athlete'
      end,
      is_active = true,
      is_coach = (id = v_coach_a)
  where id in (v_owner_a, v_admin_a, v_athlete_a, v_coach_a, v_admin_b);

  update public.gyms set owner_id = v_owner_a where id = v_gym_a;

  insert into public.gym_members(
    gym_id, user_id, role, is_active, is_coach, joined_at
  )
  values
    (v_gym_a, v_owner_a, 'admin', true, false, now()),
    (v_gym_a, v_admin_a, 'admin', true, false, now()),
    (v_gym_a, v_athlete_a, 'athlete', true, false, now()),
    (v_gym_a, v_coach_a, 'athlete', true, true, now()),
    (v_gym_b, v_admin_b, 'admin', true, false, now());

  insert into public.membership_plans(
    id, gym_id, name, plan_type, credits, price, currency,
    duration_days, is_active
  ) values
    ('30000000-0000-0000-0000-000000000001', v_gym_a,
      'Pack A', 'class_pack', 5, 49.95, 'EUR', 30, true),
    ('30000000-0000-0000-0000-000000000002', v_gym_b,
      'Pack B', 'class_pack', 5, 1.00, 'USD', 30, true);
end;
$$;

-- Connect authorization: effective owner/admin only.
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000001',
  true
);
do $$ begin
  if (select gym_id from public.get_effective_stripe_connect_context())
     <> '20000000-0000-0000-0000-000000000001'::uuid then
    raise exception 'owner did not resolve effective gym A';
  end if;
end $$;

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000002',
  true
);
do $$ begin
  if (select gym_id from public.get_effective_stripe_connect_context())
     <> '20000000-0000-0000-0000-000000000001'::uuid then
    raise exception 'admin did not resolve effective gym A';
  end if;
end $$;

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000003',
  true
);
do $$ begin
  begin
    perform public.get_effective_stripe_connect_context();
    raise exception 'athlete unexpectedly authorized for Connect';
  exception when insufficient_privilege then null;
  end;
end $$;

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000004',
  true
);
do $$ begin
  begin
    perform public.get_effective_stripe_connect_context();
    raise exception 'coach unexpectedly authorized for Connect';
  exception when insufficient_privilege then null;
  end;
end $$;

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000005',
  true
);
do $$ begin
  if (select gym_id from public.get_effective_stripe_connect_context())
     <> '20000000-0000-0000-0000-000000000002'::uuid then
    raise exception 'gym B admin escaped its effective gym';
  end if;
end $$;

-- Cross-gym checkout is rejected; same effective operation is reused.
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000003',
  true
);
do $$
declare
  v_first record;
  v_second record;
begin
  begin
    perform public.prepare_card_membership_checkout(
      '30000000-0000-0000-0000-000000000002'
    );
    raise exception 'cross-gym plan unexpectedly accepted';
  exception when raise_exception then
    if sqlerrm <> 'plan_not_found' then raise; end if;
  end;

  select * into v_first from public.prepare_card_membership_checkout(
    '30000000-0000-0000-0000-000000000001'
  );
  select * into v_second from public.prepare_card_membership_checkout(
    '30000000-0000-0000-0000-000000000001'
  );

  if v_first.request_id <> v_second.request_id then
    raise exception 'double checkout created two acquisition requests';
  end if;
  if v_first.amount_total <> 4995 or v_first.currency <> 'eur' then
    raise exception 'checkout did not use plan price/currency';
  end if;
end $$;

reset role;
select set_config('request.jwt.claim.role', 'service_role', true);

-- Attach validates Stripe account and price. Then completion is idempotent,
-- and an expired event received after payment cannot cancel it.
do $$
declare
  v_request_id uuid;
  v_membership_count bigint;
begin
  select id into v_request_id
  from public.membership_requests
  where user_id = '10000000-0000-0000-0000-000000000003'
    and plan_id = '30000000-0000-0000-0000-000000000001'
    and status = 'pending';

  begin
    perform public.attach_card_membership_checkout_session(
      v_request_id, 'cs_A', 4995, 'eur', 'acct_B', now() + interval '1 hour'
    );
    raise exception 'wrong Stripe account unexpectedly attached';
  exception when raise_exception then
    if sqlerrm <> 'stripe_account_mismatch' then raise; end if;
  end;

  perform public.attach_card_membership_checkout_session(
    v_request_id, 'cs_A', 4995, 'eur', 'acct_A', now() + interval '1 hour'
  );

  begin
    perform public.complete_card_membership_request(
      'cs_A', 'pi_A', 4995, 'eur', 'acct_B'
    );
    raise exception 'wrong Stripe account unexpectedly completed request';
  exception when raise_exception then
    if sqlerrm <> 'Stripe account does not match gym' then raise; end if;
  end;

  perform public.complete_card_membership_request(
    'cs_A', 'pi_A', 4995, 'eur', 'acct_A'
  );
  perform public.complete_card_membership_request(
    'cs_A', 'pi_A', 4995, 'eur', 'acct_A'
  );

  select count(*) into v_membership_count
  from public.member_memberships
  where user_id = '10000000-0000-0000-0000-000000000003'
    and plan_id = '30000000-0000-0000-0000-000000000001';
  if v_membership_count <> 1 then
    raise exception 'duplicate completed event created % memberships',
      v_membership_count;
  end if;

  perform public.cancel_expired_card_membership_request('cs_A', 'acct_A');
  if not exists (
    select 1 from public.membership_requests
    where id = v_request_id and status = 'approved' and payment_status = 'paid'
  ) then
    raise exception 'expired event cancelled a paid membership request';
  end if;
end $$;

-- Ledger rejects cross-account identity and claims a duplicate exactly once.
do $$
declare
  v_claim record;
begin
  select * into v_claim from public.claim_stripe_webhook_event(
    'evt_A', 'checkout.session.completed', 'acct_A'
  );
  if not v_claim.claimed or v_claim.gym_id <>
    '20000000-0000-0000-0000-000000000001'::uuid then
    raise exception 'first webhook event was not claimed for gym A';
  end if;

  perform public.complete_stripe_webhook_event(
    'evt_A', 'acct_A', 'processed', null
  );

  select * into v_claim from public.claim_stripe_webhook_event(
    'evt_A', 'checkout.session.completed', 'acct_A'
  );
  if v_claim.claimed then
    raise exception 'duplicate webhook event was claimed twice';
  end if;

  begin
    perform public.complete_stripe_webhook_event(
      'evt_A', 'acct_B', 'processed', null
    );
    raise exception 'wrong connected account completed gym A ledger event';
  exception when raise_exception then
    if sqlerrm <> 'stripe_event_not_claimed' then raise; end if;
  end;
end $$;

reset role;

-- Internal webhook routines are not callable by app users.
do $$ begin
  if has_function_privilege(
    'authenticated',
    'public.complete_card_membership_request(text,text,integer,text,text)',
    'EXECUTE'
  ) then raise exception 'authenticated can complete card membership'; end if;
  if has_function_privilege(
    'authenticated',
    'public.cancel_expired_card_membership_request(text,text)',
    'EXECUTE'
  ) then raise exception 'authenticated can cancel card membership'; end if;
  if has_function_privilege(
    'authenticated',
    'public.claim_stripe_webhook_event(text,text,text)',
    'EXECUTE'
  ) then raise exception 'authenticated can claim Stripe events'; end if;
  if has_function_privilege(
    'authenticated',
    'public.attach_card_membership_checkout_session(uuid,text,integer,text,text,timestamptz)',
    'EXECUTE'
  ) then raise exception 'authenticated can attach Stripe sessions'; end if;
end $$;

rollback;
