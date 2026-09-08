begin;
select plan(1);

do $$
declare
  v_user uuid := 'e7100000-0000-0000-0000-000000000001';
  v_other_user uuid := 'e7100000-0000-0000-0000-000000000002';
  v_owner uuid := 'e7100000-0000-0000-0000-000000000003';
  v_gym_1 uuid := 'e7200000-0000-0000-0000-000000000001';
  v_gym_2 uuid := 'e7200000-0000-0000-0000-000000000002';
  v_session uuid := 'e7300000-0000-0000-0000-000000000001';
begin
  insert into auth.users(id, email) values
    (v_user, 'effective-gym-user@test.invalid'),
    (v_other_user, 'effective-gym-other@test.invalid'),
    (v_owner, 'effective-gym-owner@test.invalid');

  update public.profiles
  set role = case when id = v_owner then 'owner' else 'athlete' end,
      is_active = true,
      gym_id = null
  where id in (v_user, v_other_user, v_owner);

  insert into public.gyms(id, name, owner_id, lifecycle_status) values
    (v_gym_1, 'Effective Gym One', v_owner, 'active'),
    (v_gym_2, 'Effective Gym Two', v_owner, 'active');

  insert into public.gym_members(gym_id, user_id, role, is_active, is_coach, joined_at) values
    (v_gym_1, v_user, 'athlete', true, false, now()),
    (v_gym_2, v_user, 'athlete', true, false, now()),
    (v_gym_2, v_other_user, 'athlete', true, false, now());

  update public.profiles set gym_id = v_gym_1 where id = v_user;
end;
$$;

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'e7100000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e7100000-0000-0000-0000-000000000001',
  'role', 'authenticated'
)::text, true);
do $$
declare
  v_user uuid := 'e7100000-0000-0000-0000-000000000001';
  v_gym_1 uuid := 'e7200000-0000-0000-0000-000000000001';
  v_gym_2 uuid := 'e7200000-0000-0000-0000-000000000002';
begin
  if public.effective_gym_id() is distinct from v_gym_1 then
    raise exception 'active membership did not resolve selected gym';
  end if;

  update public.gym_members set is_active = false
  where gym_id = v_gym_1 and user_id = v_user;
  if public.effective_gym_id() is not null then
    raise exception 'inactive selected membership retained authority';
  end if;

  if not exists (select 1 from public.gym_members where gym_id = v_gym_2 and user_id = v_user and is_active) then
    raise exception 'second active membership fixture missing';
  end if;
  if public.effective_gym_id() is not null then
    raise exception 'backend silently selected another active gym';
  end if;

  perform public.select_effective_gym(v_gym_2);
  if public.effective_gym_id() is distinct from v_gym_2 then
    raise exception 'explicit second gym selection failed';
  end if;

  update public.profiles set gym_id = v_gym_1 where id = v_user;
  delete from public.gym_members where gym_id = v_gym_1 and user_id = v_user;
  if public.effective_gym_id() is not null then
    raise exception 'stale profile gym without relation retained authority';
  end if;

  update public.profiles set gym_id = null where id = v_user;
  if public.effective_gym_id() is not null then
    raise exception 'user without selected membership had context';
  end if;

  update public.profiles set gym_id = v_gym_1 where id = v_user;
  insert into public.gym_members(gym_id, user_id, role, is_active, is_coach, joined_at)
  values(v_gym_1, v_user, 'athlete', true, false, now());
  if public.effective_gym_id() is distinct from v_gym_1 then
    raise exception 'reactivated membership did not restore context';
  end if;
  update public.gym_members set is_active = false where gym_id = v_gym_1 and user_id = v_user;
  if public.effective_gym_id() is not null then
    raise exception 'second deactivation retained context';
  end if;

  update public.profiles set gym_id = v_gym_2 where id = v_user;
  delete from public.gym_members where gym_id = v_gym_2 and user_id = v_user;
  if public.effective_gym_id() is not null then
    raise exception 'another user membership granted cross-user access';
  end if;

  update public.gyms set lifecycle_status = 'suspended' where id = v_gym_2;
  insert into public.gym_members(gym_id, user_id, role, is_active, is_coach, joined_at)
  values(v_gym_2, v_user, 'athlete', true, false, now());
  if public.effective_gym_id() is not null then
    raise exception 'inactive gym lifecycle retained context';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{}', true);
do $$ begin
  if public.effective_gym_id() is not null then
    raise exception 'invalid auth unexpectedly resolved a gym';
  end if;
end $$;

update public.gyms set lifecycle_status = 'active'
where id = 'e7200000-0000-0000-0000-000000000002';
insert into public.web_app_session_preferences(session_id, user_id, active_gym_id, selection_required)
values(
  'e7300000-0000-0000-0000-000000000001',
  'e7100000-0000-0000-0000-000000000003',
  null,
  false
);
select set_config('request.jwt.claim.sub', 'e7100000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e7100000-0000-0000-0000-000000000003',
  'role', 'authenticated',
  'session_id', 'e7300000-0000-0000-0000-000000000001'
)::text, true);
do $$
declare
  v_gym_1 uuid := 'e7200000-0000-0000-0000-000000000001';
  v_other uuid := 'e7400000-0000-0000-0000-000000000001';
begin
  if public.effective_gym_id() is not null then
    raise exception 'owner without inspection had implicit context';
  end if;

  perform public.select_owner_effective_gym(v_gym_1);
  if public.effective_gym_id() is distinct from v_gym_1 then
    raise exception 'valid owner inspection lost context';
  end if;

  update public.platform_owner_gym_inspections
  set session_id = v_other
  where user_id = auth.uid();
  if public.effective_gym_id() is not null then
    raise exception 'invalid owner inspection retained context';
  end if;
end;
$$;

select pass('effective_gym_id requires active membership and preserves validated owner inspection');
select * from finish();
rollback;
