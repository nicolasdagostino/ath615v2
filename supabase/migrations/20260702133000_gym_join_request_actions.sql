create or replace function public.approve_gym_join_request(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin profiles%rowtype;
  v_request gym_join_requests%rowtype;
  v_gym gyms%rowtype;
begin
  select * into v_admin
  from public.profiles
  where id = auth.uid();

  if v_admin.id is null or v_admin.role not in ('admin', 'owner') then
    raise exception 'Only admins can approve join requests';
  end if;

  select * into v_request
  from public.gym_join_requests
  where id = p_request_id
    and status = 'pending'
  for update;

  if v_request.id is null then
    raise exception 'Join request not found';
  end if;

  if v_request.gym_id is distinct from v_admin.gym_id then
    raise exception 'Join request belongs to another gym';
  end if;

  select * into v_gym
  from public.gyms
  where id = v_request.gym_id;

  update public.profiles
  set gym_id = v_request.gym_id,
      role = 'athlete',
      is_active = true
  where id = v_request.user_id;

  update public.gym_join_requests
  set status = 'approved',
      approved_at = now(),
      approved_by = auth.uid()
  where id = v_request.id;

  insert into public.notifications (
    user_id,
    title,
    body,
    type,
    data,
    scheduled_for
  )
  values (
    v_request.user_id,
    '🎉 Welcome!',
    format('You now have access to %s.', coalesce(v_gym.name, 'your gym')),
    'gym_join_approved',
    jsonb_build_object('gymId', v_request.gym_id),
    now()
  );
end;
$$;

create or replace function public.reject_gym_join_request(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin profiles%rowtype;
  v_request gym_join_requests%rowtype;
begin
  select * into v_admin
  from public.profiles
  where id = auth.uid();

  if v_admin.id is null or v_admin.role not in ('admin', 'owner') then
    raise exception 'Only admins can reject join requests';
  end if;

  select * into v_request
  from public.gym_join_requests
  where id = p_request_id
    and status = 'pending'
  for update;

  if v_request.id is null then
    raise exception 'Join request not found';
  end if;

  if v_request.gym_id is distinct from v_admin.gym_id then
    raise exception 'Join request belongs to another gym';
  end if;

  update public.gym_join_requests
  set status = 'rejected',
      approved_at = now(),
      approved_by = auth.uid()
  where id = v_request.id;
end;
$$;

grant execute on function public.approve_gym_join_request(uuid) to authenticated;
grant execute on function public.reject_gym_join_request(uuid) to authenticated;
