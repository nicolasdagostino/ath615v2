begin;

do $$
declare
  gym_a uuid := 'a1000000-0000-0000-0000-000000000001';
  gym_b uuid := 'b1000000-0000-0000-0000-000000000001';
  owner_a uuid := 'a2000000-0000-0000-0000-000000000001';
  admin_a uuid := 'a2000000-0000-0000-0000-000000000002';
  coach_a uuid := 'a2000000-0000-0000-0000-000000000003';
  member_a uuid := 'a2000000-0000-0000-0000-000000000004';
  admin_b uuid := 'b2000000-0000-0000-0000-000000000001';
  member_b uuid := 'b2000000-0000-0000-0000-000000000002';
begin
  insert into auth.users(id, email, raw_user_meta_data) values
    (owner_a, 'notes-owner-a@example.test', '{}'::jsonb),
    (admin_a, 'notes-admin-a@example.test', '{}'::jsonb),
    (coach_a, 'notes-coach-a@example.test', '{}'::jsonb),
    (member_a, 'notes-member-a@example.test', '{}'::jsonb),
    (admin_b, 'notes-admin-b@example.test', '{}'::jsonb),
    (member_b, 'notes-member-b@example.test', '{}'::jsonb);

  insert into public.gyms(id, name, owner_id) values
    (gym_a, 'Notes Gym A', owner_a),
    (gym_b, 'Notes Gym B', admin_b);

  update public.profiles set gym_id = gym_a, is_active = true,
    role = case id when owner_a then 'owner' when admin_a then 'admin'
      when coach_a then 'coach' else 'athlete' end,
    is_coach = id = coach_a
  where id in (owner_a, admin_a, coach_a, member_a);
  update public.profiles set gym_id = gym_b, is_active = true,
    role = case id when admin_b then 'admin' else 'athlete' end
  where id in (admin_b, member_b);

  insert into public.gym_members(gym_id,user_id,role,is_active,is_coach,joined_at)
  values
    (gym_a,owner_a,'admin',true,false,now()),
    (gym_a,admin_a,'admin',true,false,now()),
    (gym_a,coach_a,'coach',true,true,now()),
    (gym_a,member_a,'athlete',true,false,now()),
    (gym_b,admin_b,'admin',true,false,now()),
    (gym_b,member_b,'athlete',true,false,now());
  insert into public.member_staff_notes(
    id,gym_id,member_user_id,author_user_id,body
  ) values (
    'a3000000-0000-0000-0000-000000000001',gym_a,member_a,admin_a,'Seed note'
  );
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);

-- Effective admin can create and whitespace is normalized.
select set_config('request.jwt.claim.sub', 'a2000000-0000-0000-0000-000000000002', true);
do $$
declare note_id uuid;
begin
  note_id := public.save_member_staff_note(
    'a2000000-0000-0000-0000-000000000004', '  Admin note  ', false
  );
  if not exists (select 1 from public.member_staff_notes
    where id = note_id and body = 'Admin note') then
    raise exception 'admin could not create normalized note';
  end if;
end;
$$;

-- Owner can create.
select set_config('request.jwt.claim.sub', 'a2000000-0000-0000-0000-000000000001', true);
do $$ begin
  perform public.save_member_staff_note(
    'a2000000-0000-0000-0000-000000000004', 'Owner note', false
  );
end $$;

-- Coach capability is read-only.
select set_config('request.jwt.claim.sub', 'a2000000-0000-0000-0000-000000000003', true);
do $$ begin
  if (select count(*) from public.list_effective_member_staff_notes(
    'a2000000-0000-0000-0000-000000000004')) <> 3 then
    raise exception 'coach could not read member notes';
  end if;
  begin
    perform public.save_member_staff_note(
      'a2000000-0000-0000-0000-000000000004', 'Forbidden coach write', false
    );
    raise exception 'coach wrote a note';
  exception when insufficient_privilege then null; end;
end $$;

-- Athlete cannot read via RLS/RPC and has no table mutation grant.
select set_config('request.jwt.claim.sub', 'a2000000-0000-0000-0000-000000000004', true);
do $$ begin
  if (select count(*) from public.member_staff_notes) <> 0 then
    raise exception 'athlete read notes through RLS';
  end if;
  begin
    perform public.list_effective_member_staff_notes(
      'a2000000-0000-0000-0000-000000000004'
    );
    raise exception 'athlete read notes through RPC';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.member_staff_notes(
      gym_id,member_user_id,author_user_id,body
    ) values (
      'a1000000-0000-0000-0000-000000000001', auth.uid(), auth.uid(), 'No'
    );
    raise exception 'athlete inserted note';
  exception when insufficient_privilege then null; end;
end $$;

-- Other-gym admin cannot see, associate, modify, or delete Gym A notes.
select set_config('request.jwt.claim.sub', 'b2000000-0000-0000-0000-000000000001', true);
do $$
declare note_a uuid;
begin
  select id into note_a from public.member_staff_notes
  where gym_id = 'a1000000-0000-0000-0000-000000000001' limit 1;
  if note_a is not null then raise exception 'RLS leaked cross-gym note'; end if;
  begin
    perform public.list_effective_member_staff_notes(
      'a2000000-0000-0000-0000-000000000004'
    );
    raise exception 'other-gym admin listed notes';
  exception when no_data_found then null; end;
  begin
    perform public.save_member_staff_note(
      'a2000000-0000-0000-0000-000000000004', 'Fraud', false
    );
    raise exception 'other-gym member was associated';
  exception when no_data_found then null; end;
  begin
    update public.member_staff_notes set body = 'Cross gym';
    raise exception 'direct update was granted';
  exception when insufficient_privilege then null; end;
  if public.delete_member_staff_note(
    'a3000000-0000-0000-0000-000000000001'
  ) then raise exception 'other-gym admin deleted note'; end if;
end $$;

-- Pin switch is one atomic operation; edit and delete remain gym-scoped.
select set_config('request.jwt.claim.sub', 'a2000000-0000-0000-0000-000000000002', true);
do $$
declare first_note uuid; second_note uuid;
begin
  first_note := public.save_member_staff_note(
    'a2000000-0000-0000-0000-000000000004', 'First pinned', true
  );
  second_note := public.save_member_staff_note(
    'a2000000-0000-0000-0000-000000000004', 'Second pinned', true
  );
  if (select count(*) from public.member_staff_notes where
    gym_id = 'a1000000-0000-0000-0000-000000000001'
    and member_user_id = 'a2000000-0000-0000-0000-000000000004'
    and is_pinned) <> 1 then raise exception 'pinned note is not unique'; end if;
  if (select is_pinned from public.member_staff_notes where id = first_note)
     or not (select is_pinned from public.member_staff_notes where id = second_note) then
    raise exception 'pin switch did not atomically replace old pinned note';
  end if;
  perform public.save_member_staff_note(
    'a2000000-0000-0000-0000-000000000004', 'Edited pinned', true, second_note
  );
  if (select body from public.member_staff_notes where id = second_note) <> 'Edited pinned'
  then raise exception 'edit failed'; end if;
  if not public.delete_member_staff_note(first_note) then
    raise exception 'delete RPC returned false';
  end if;
  if exists(select 1 from public.member_staff_notes where id = first_note) then
    raise exception 'deleted note still exists';
  end if;
end;
$$;

-- Empty and oversized bodies are rejected server-side.
do $$ begin
  begin
    perform public.save_member_staff_note(
      'a2000000-0000-0000-0000-000000000004', '   ', false
    );
    raise exception 'empty body accepted';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.save_member_staff_note(
      'a2000000-0000-0000-0000-000000000004', repeat('x', 2001), false
    );
    raise exception 'oversized body accepted';
  exception when invalid_parameter_value then null; end;
end $$;

rollback;
