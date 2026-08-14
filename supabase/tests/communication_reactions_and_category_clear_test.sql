do $$
declare
  v_gym_a uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_gym_b uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  v_user_a uuid := '11111111-1111-1111-1111-111111111111';
  v_user_b uuid := '22222222-2222-2222-2222-222222222222';
  v_other uuid := '33333333-3333-3333-3333-333333333333';
begin
  insert into auth.users(id, email) values
    (v_user_a, 'reaction-a@example.test'),
    (v_user_b, 'reaction-b@example.test'),
    (v_other, 'reaction-other@example.test');

  insert into public.gyms(id, name) values
    (v_gym_a, 'Gym A'),
    (v_gym_b, 'Gym B');

  insert into public.profiles(id, email, gym_id, is_active) values
    (v_user_a, 'reaction-a@example.test', v_gym_a, true),
    (v_user_b, 'reaction-b@example.test', v_gym_a, true),
    (v_other, 'reaction-other@example.test', v_gym_b, true);

  insert into public.gym_members(gym_id, user_id, role, joined_at) values
    (v_gym_a, v_user_a, 'athlete', now()),
    (v_gym_a, v_user_b, 'athlete', now()),
    (v_gym_b, v_other, 'athlete', now());
end;
$$;

insert into public.notifications(
  id, user_id, gym_id, title, type, data, scheduled_for, sent_at
) values
  ('a0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'C1', 'communication', '{"communicationId":"dddddddd-dddd-dddd-dddd-dddddddddddd"}', now(), now()),
  ('a0000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'C2', 'communication', '{}', now(), now()),
  ('a0000000-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'N1', 'class_reminder', '{}', now(), now()),
  ('a0000000-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'N2', 'birthday', '{}', now(), now()),
  ('a0000000-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'N3', null, '{}', now(), now()),
  ('b0000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'C1', 'communication', '{"communicationId":"dddddddd-dddd-dddd-dddd-dddddddddddd"}', now(), now()),
  ('b0000000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'B notification', 'birthday', '{}', now(), now()),
  ('c0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Other gym', 'communication', '{}', now(), now());

set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);

do $$
declare
  v_deleted bigint;
  v_count bigint;
begin
  v_deleted := public.clear_effective_notifications_by_category('communication');
  if v_deleted <> 2 then raise exception 'expected 2 communications deleted, got %', v_deleted; end if;
  select count(*) into v_count from public.notifications where user_id = auth.uid() and gym_id = public.effective_gym_id() and type is distinct from 'communication';
  if v_count <> 3 then raise exception 'expected 3 notifications preserved, got %', v_count; end if;
  if public.get_effective_notification_unread_count() <> 3 then raise exception 'expected unread badge 3'; end if;
end;
$$;

reset role;
do $$ begin
  if not exists (select 1 from public.notifications where id = 'b0000000-0000-0000-0000-000000000001') then raise exception 'user B was affected'; end if;
  if not exists (select 1 from public.notifications where id = 'c0000000-0000-0000-0000-000000000001') then raise exception 'gym B was affected'; end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
do $$ declare v_deleted bigint; begin
  v_deleted := public.clear_effective_notifications_by_category('notification');
  if v_deleted <> 3 then raise exception 'expected 3 notifications deleted, got %', v_deleted; end if;
end $$;

reset role;
insert into public.notifications(
  id, user_id, gym_id, title, type, data, scheduled_for, sent_at
) values
  ('a0000000-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Shared', 'communication', '{"communicationId":"eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"}', now(), now()),
  ('b0000000-0000-0000-0000-000000000011', '22222222-2222-2222-2222-222222222222', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Shared', 'communication', '{"communicationId":"eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"}', now(), now()),
  ('a0000000-0000-0000-0000-000000000012', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Reminder', 'class_reminder', '{}', now(), now()),
  ('a0000000-0000-0000-0000-000000000013', '11111111-1111-1111-1111-111111111111', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Wrong gym', 'communication', '{}', now(), now());

set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);

select public.set_communication_reaction('a0000000-0000-0000-0000-000000000011', 'thumbs_up');
do $$ begin
  if (select thumbs_up_count from public.get_communication_reactions('a0000000-0000-0000-0000-000000000011')) <> 1 then raise exception 'thumbs up was not added'; end if;
end $$;
select public.set_communication_reaction('a0000000-0000-0000-0000-000000000011', 'thumbs_up');
do $$ begin
  if (select thumbs_up_count from public.get_communication_reactions('a0000000-0000-0000-0000-000000000011')) <> 0 then raise exception 'same reaction was not toggled off'; end if;
end $$;
select public.set_communication_reaction('a0000000-0000-0000-0000-000000000011', 'thumbs_up');
select public.set_communication_reaction('a0000000-0000-0000-0000-000000000011', 'heart');
do $$ begin
  if (select heart_count from public.get_communication_reactions('a0000000-0000-0000-0000-000000000011')) <> 1 then raise exception 'reaction was not changed to heart'; end if;
end $$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
select public.set_communication_reaction('b0000000-0000-0000-0000-000000000011', 'heart');
do $$ begin
  if (select heart_count from public.get_communication_reactions('b0000000-0000-0000-0000-000000000011')) <> 2 then raise exception 'two-user heart count was not 2'; end if;
  if (select count(*) from public.communication_reactions where notification_id = 'b0000000-0000-0000-0000-000000000011' and user_id = auth.uid()) <> 1 then raise exception 'unique reaction invariant failed'; end if;
end $$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
do $$ begin
  begin
    perform public.set_communication_reaction('a0000000-0000-0000-0000-000000000012', 'heart');
    raise exception 'non-communication reaction unexpectedly accepted';
  exception when insufficient_privilege then null; end;
  begin
    perform public.set_communication_reaction('a0000000-0000-0000-0000-000000000013', 'heart');
    raise exception 'cross-gym reaction unexpectedly accepted';
  exception when insufficient_privilege then null; end;
end $$;
