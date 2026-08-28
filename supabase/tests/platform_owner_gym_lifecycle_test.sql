begin;
select plan(1);

do $$
declare
  v_owner uuid := 'c3100000-0000-0000-0000-000000000001';
  v_admin uuid := 'c3100000-0000-0000-0000-000000000002';
  v_member uuid := 'c3100000-0000-0000-0000-000000000003';
  v_shared uuid := 'c3100000-0000-0000-0000-000000000004';
  v_gym_a uuid := 'c3200000-0000-0000-0000-000000000001';
  v_gym_b uuid := 'c3200000-0000-0000-0000-000000000002';
  v_delete uuid := 'c3200000-0000-0000-0000-000000000003';
  v_protected uuid := 'c3200000-0000-0000-0000-000000000004';
  v_created uuid;
  v_context jsonb;
begin
  insert into auth.users(id,email) values
    (v_owner,'platform-owner-lifecycle@test.invalid'),
    (v_admin,'admin-lifecycle@test.invalid'),
    (v_member,'member-lifecycle@test.invalid'),
    (v_shared,'shared-lifecycle@test.invalid');
  update public.profiles set role=case when id=v_owner then 'owner' when id=v_admin then 'admin' else 'athlete' end,
    is_active=true,gym_id=null where id in(v_owner,v_admin,v_member,v_shared);
  insert into public.gyms(id,name,owner_id,lifecycle_status,stripe_account_id) values
    (v_gym_a,'Lifecycle Gym A',v_owner,'active',null),
    (v_gym_b,'Lifecycle Gym B',v_owner,'active',null),
    (v_delete,'Lifecycle QA Delete',v_owner,'archived',null),
    (v_protected,'Lifecycle Protected',v_owner,'archived','acct_test_protected');
  insert into public.gym_members(gym_id,user_id,role,is_active,is_coach,joined_at) values
    (v_gym_a,v_owner,'admin',true,false,now()),
    (v_gym_a,v_admin,'admin',true,false,now()),
    (v_gym_a,v_member,'athlete',true,false,now()),
    (v_gym_b,v_member,'athlete',true,false,now()),
    (v_gym_b,v_shared,'athlete',true,false,now()),
    (v_delete,v_shared,'athlete',true,false,now());
  update public.profiles set gym_id=v_gym_a where id in(v_admin,v_member);
  update public.profiles set gym_id=v_delete where id=v_shared;
  insert into public.classes(id,gym_id,title,starts_at,created_by)
  values
    ('c3300000-0000-0000-0000-000000000001',v_gym_a,'Preserved class',now(),v_admin),
    ('c3300000-0000-0000-0000-000000000002',v_delete,'Disposable QA class',now(),v_owner);

  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',v_owner::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object(
    'sub',v_owner,'role','authenticated',
    'session_id','c3100000-0000-0000-0000-000000000099'::uuid
  )::text,true);

  -- Creating a gym does not implicitly enter it.
  select public.create_gym('Lifecycle Newly Created') into v_created;
  if (select gym_id from public.profiles where id=v_owner) is not null then
    raise exception 'create_gym changed Platform Owner context';
  end if;
  if not exists(select 1 from public.gym_members where gym_id=v_created and user_id=v_owner and is_active) then
    raise exception 'created gym lacks owner relation';
  end if;
  if (select count(*) from public.list_owner_gym_overview() where gym_id in(v_gym_a,v_gym_b,v_delete,v_protected,v_created))<>5 then
    raise exception 'owner overview did not include lifecycle states';
  end if;

  -- Admins cannot mutate platform lifecycle state.
  perform set_config('request.jwt.claim.sub',v_admin::text,true);
  begin
    perform public.platform_set_gym_status(v_gym_a,'suspended');
    raise exception 'admin changed platform lifecycle';
  exception when sqlstate '42501' then null; end;
  begin
    perform public.platform_delete_gym(v_delete,'Lifecycle QA Delete');
    raise exception 'admin deleted a gym';
  exception when sqlstate '42501' then null; end;

  -- Suspension is centralized in effective_gym_id and preserves all data.
  perform set_config('request.jwt.claim.sub',v_owner::text,true);
  perform public.platform_set_gym_status(v_gym_a,'suspended');
  if not exists(select 1 from public.classes where gym_id=v_gym_a and title='Preserved class') then
    raise exception 'suspension deleted operational data';
  end if;
  perform set_config('request.jwt.claim.sub',v_member::text,true);
  if public.effective_gym_id() is not null then raise exception 'suspended gym remained operational'; end if;
  select public.get_selected_gym_access_context() into v_context;
  if v_context->>'status'<>'suspended' or not exists(
    select 1 from jsonb_array_elements(v_context->'active_gyms') x where x->>'id'=v_gym_b::text
  ) then raise exception 'suspended context did not expose active alternative'; end if;
  if public.select_effective_gym(v_gym_b)<>v_gym_b or public.effective_gym_id()<>v_gym_b then
    raise exception 'multi-gym member could not select active alternative';
  end if;

  -- Reactivation restores access; archive is a distinct non-operational state.
  perform set_config('request.jwt.claim.sub',v_owner::text,true);
  perform public.platform_set_gym_status(v_gym_a,'active');
  perform set_config('request.jwt.claim.sub',v_admin::text,true);
  if public.effective_gym_id()<>v_gym_a then raise exception 'reactivation did not restore access'; end if;
  perform set_config('request.jwt.claim.sub',v_owner::text,true);
  perform public.platform_set_gym_status(v_gym_a,'archived');
  if not exists(select 1 from public.classes where gym_id=v_gym_a) then raise exception 'archive deleted data'; end if;
  begin
    perform public.select_owner_effective_gym(v_gym_a);
    raise exception 'owner entered archived gym operationally';
  exception when sqlstate '42501' then null; end;

  -- Protected Stripe/financial/legal candidates cannot be hard-deleted.
  if coalesce((public.platform_gym_delete_eligibility(v_protected)->>'can_delete')::boolean,true) then
    raise exception 'protected gym reported deletable';
  end if;
  begin
    perform public.platform_delete_gym(v_protected,'Lifecycle Protected');
    raise exception 'protected gym was deleted';
  exception when sqlstate '23503' then null; end;

  -- A QA-only archived gym can be purged without deleting a shared user.
  if not (public.platform_gym_delete_eligibility(v_delete)->>'can_delete')::boolean then
    raise exception 'clean archived QA gym was not deletable';
  end if;
  begin
    perform public.platform_delete_gym(v_delete,'wrong name');
    raise exception 'weak delete confirmation accepted';
  exception when sqlstate '22023' then null; end;
  perform public.platform_delete_gym(v_delete,'Lifecycle QA Delete');
  if exists(select 1 from public.gyms where id=v_delete) or exists(select 1 from public.classes where gym_id=v_delete) then
    raise exception 'QA gym purge left gym-scoped rows';
  end if;
  if not exists(select 1 from public.profiles where id=v_shared)
     or not exists(select 1 from auth.users where id=v_shared)
     or not exists(select 1 from public.gym_members where gym_id=v_gym_b and user_id=v_shared) then
    raise exception 'QA gym purge deleted shared user identity or other relation';
  end if;
end;
$$;

select pass('Platform Owner lifecycle, central gate, multi-gym and safe delete');
select * from finish();
rollback;
