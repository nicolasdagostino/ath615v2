begin;
select plan(1);

do $$
declare
  v_admin_a uuid := 'e8100000-0000-0000-0000-000000000001';
  v_admin_b uuid := 'e8100000-0000-0000-0000-000000000002';
  v_athlete_a uuid := 'e8100000-0000-0000-0000-000000000003';
  v_athlete_b uuid := 'e8100000-0000-0000-0000-000000000004';
  v_gym_a uuid := 'e8200000-0000-0000-0000-000000000001';
  v_gym_b uuid := 'e8200000-0000-0000-0000-000000000002';
begin
  insert into auth.users(id, email) values
    (v_admin_a, 'identity-admin-a@test.invalid'),
    (v_admin_b, 'identity-admin-b@test.invalid'),
    (v_athlete_a, 'identity-athlete-a@test.invalid'),
    (v_athlete_b, 'identity-athlete-b@test.invalid');
  insert into public.gyms(id, name) values
    (v_gym_a, 'Identity Gym A'),
    (v_gym_b, 'Identity Gym B');
  update public.profiles set
    gym_id = case when id in (v_admin_a, v_athlete_a) then v_gym_a else v_gym_b end,
    role = case when id in (v_admin_a, v_admin_b) then 'admin' else 'athlete' end,
    full_name = case when id = v_athlete_a then 'Ada Athlete' when id = v_athlete_b then 'Bea Athlete' else full_name end,
    avatar_url = case when id = v_athlete_a then 'avatars/ada.webp' else null end,
    is_active = true
  where id in (v_admin_a, v_admin_b, v_athlete_a, v_athlete_b);
  insert into public.gym_members(gym_id, user_id, role, is_active, is_coach, joined_at) values
    (v_gym_a, v_admin_a, 'admin', true, false, now()),
    (v_gym_b, v_admin_b, 'admin', true, false, now()),
    (v_gym_a, v_athlete_a, 'athlete', true, false, now()),
    (v_gym_b, v_athlete_b, 'athlete', true, false, now());
  insert into public.membership_plans(id, gym_id, name, plan_type, credits, price, currency, duration_days) values
    ('e8300000-0000-0000-0000-000000000001', v_gym_a, 'Pack A', 'class_pack', 5, 35, 'EUR', 30),
    ('e8300000-0000-0000-0000-000000000002', v_gym_b, 'Pack B', 'class_pack', 10, 60, 'EUR', 30);
  insert into public.membership_legal_acceptances(
    user_id, gym_id, plan_id, document_id, document_type,
    document_version, document_url, accepted_at
  )
  select fixture.user_id, fixture.gym_id, fixture.plan_id, d.id,
    d.document_type, d.version, d.url, now()
  from (values
    (v_athlete_a, v_gym_a, 'e8300000-0000-0000-0000-000000000001'::uuid),
    (v_athlete_b, v_gym_b, 'e8300000-0000-0000-0000-000000000002'::uuid)
  ) fixture(user_id, gym_id, plan_id)
  cross join public.membership_legal_documents d
  where d.is_active and d.is_required
    and (d.gym_id is null or d.gym_id = fixture.gym_id);

  insert into public.membership_requests(id, user_id, gym_id, plan_id, status, payment_method, payment_status) values
    ('e8400000-0000-0000-0000-000000000001', v_athlete_a, v_gym_a, 'e8300000-0000-0000-0000-000000000001', 'pending', 'cash', 'pending'),
    ('e8400000-0000-0000-0000-000000000002', v_athlete_b, v_gym_b, 'e8300000-0000-0000-0000-000000000002', 'pending', 'cash', 'pending');

  -- Simulate a multi-gym selection that excludes the requester from a
  -- profiles.gym_id based member list without changing request ownership.
  update public.profiles set gym_id = v_gym_b where id = v_athlete_a;
end;
$$;

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e8100000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare v_row record;
begin
  select * into v_row from public.list_effective_pending_membership_requests();
  if v_row.request_id is distinct from 'e8400000-0000-0000-0000-000000000001'::uuid
    or v_row.user_id is distinct from 'e8100000-0000-0000-0000-000000000003'::uuid
    or v_row.member_name is distinct from 'Ada Athlete'
    or v_row.member_email is distinct from 'identity-athlete-a@test.invalid'
    or v_row.member_avatar_url is distinct from 'avatars/ada.webp'
    or v_row.plan_name is distinct from 'Pack A' then
    raise exception 'request identity was not resolved exactly: %', row_to_json(v_row);
  end if;
  if (select count(*) from public.list_effective_pending_membership_requests()) <> 1 then
    raise exception 'cross-gym request leaked';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', 'e8100000-0000-0000-0000-000000000003', true);
do $$ begin
  begin
    perform public.list_effective_pending_membership_requests();
    raise exception 'athlete listed administrative requests';
  exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub', 'e8100000-0000-0000-0000-000000000002', true);
do $$ begin
  if (select count(*) from public.list_effective_pending_membership_requests()) <> 1
    or not exists (
      select 1 from public.list_effective_pending_membership_requests()
      where member_name = 'Bea Athlete'
    ) then
    raise exception 'gym B identity isolation failed';
  end if;
end $$;

reset role;
select pass('request identity is exact, useful, and isolated to effective gym admins');
select * from finish();
rollback;
