begin;

do $$
declare
  v_user uuid := '61000000-0000-0000-0000-000000000001';
  v_gym uuid := '62000000-0000-0000-0000-000000000001';
begin
  insert into auth.users(id, email, raw_user_meta_data)
  values (v_user, 'consent-member@example.test', '{}'::jsonb);
  insert into public.gyms(id, name, business_name, owner_id, email, address)
  values (v_gym, 'Consent Gym', 'Consent Gym SL', null,
    'gym@example.test', 'Test address');
  update public.profiles set gym_id = v_gym, role = 'athlete', is_active = true
  where id = v_user;
  insert into public.gym_members(gym_id, user_id, role, is_active, joined_at)
  values (v_gym, v_user, 'athlete', true, now());
  insert into public.membership_plans(
    id, gym_id, name, plan_type, credits, price, currency, duration_days, is_active
  ) values (
    '63000000-0000-0000-0000-000000000001', v_gym,
    'Consent Pack', 'class_pack', 5, 35, 'EUR', 30, true
  );
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '61000000-0000-0000-0000-000000000001', true);

do $$
declare v_context jsonb;
begin
  v_context := public.get_membership_checkout_context(
    '63000000-0000-0000-0000-000000000001'
  );
  if v_context #>> '{gym,name}' <> 'Consent Gym'
     or v_context #>> '{plan,price}' <> '35'
     or jsonb_array_length(v_context->'documents') <> 2 then
    raise exception 'checkout context does not expose real gym/plan/documents';
  end if;
end;
$$;

do $$ begin
  begin
    perform public.create_consented_cash_membership_request(
      '63000000-0000-0000-0000-000000000001', '{}'::uuid[]
    );
    raise exception 'request created without required consent';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'required_consent_missing' then raise; end if;
  end;
end $$;

do $$
declare v_terms uuid; v_request uuid;
begin
  select id into v_terms from public.membership_legal_documents
  where document_type = 'terms' and is_active and gym_id is null;
  v_request := public.create_consented_cash_membership_request(
    '63000000-0000-0000-0000-000000000001', array[v_terms]
  );
  if not exists (
    select 1 from public.membership_request_legal_acceptances rla
    join public.membership_legal_acceptances a on a.id = rla.acceptance_id
    where rla.request_id = v_request and a.user_id = auth.uid()
      and a.document_type = 'terms' and a.document_version = '2026-08-25'
  ) then raise exception 'request is not linked to versioned consent'; end if;
end;
$$;

do $$
declare accepted_before timestamptz; accepted_after timestamptz;
begin
  select accepted_at into accepted_before from public.membership_legal_acceptances
  where user_id=auth.uid() and plan_id='63000000-0000-0000-0000-000000000001'
    and document_type='terms';
  perform public.accept_membership_checkout_documents(
    '63000000-0000-0000-0000-000000000001', '{}'::uuid[]
  );
  select accepted_at into accepted_after from public.membership_legal_acceptances
  where user_id=auth.uid() and plan_id='63000000-0000-0000-0000-000000000001'
    and document_type='terms';
  if accepted_before<>accepted_after then
    raise exception 'reused legal acceptance changed accepted_at';
  end if;
end $$;

rollback;
