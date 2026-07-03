create or replace function public.leave_current_gym()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_booking record;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select *
  into v_profile
  from public.profiles
  where id = v_user_id
  for update;

  if not found then
    raise exception 'Profile not found';
  end if;

  if v_profile.gym_id is null then
    return;
  end if;

  if v_profile.role in ('admin', 'owner') then
    raise exception 'Admins and owners cannot leave a gym from the app';
  end if;

  for v_booking in
    select cb.class_id
    from public.class_bookings cb
    join public.classes c on c.id = cb.class_id
    where cb.user_id = v_user_id
      and c.gym_id = v_profile.gym_id
      and cb.status = 'booked'
      and c.starts_at > now()
  loop
    perform public.cancel_my_booking(v_booking.class_id);
  end loop;

  delete from public.class_waitlist cw
  using public.classes c
  where cw.class_id = c.id
    and cw.user_id = v_user_id
    and c.gym_id = v_profile.gym_id;

  update public.member_memberships
  set is_active = false,
      status = 'cancelled'
  where user_id = v_user_id
    and gym_id = v_profile.gym_id
    and is_active = true;

  update public.gym_join_requests
  set status = 'cancelled'
  where user_id = v_user_id
    and gym_id = v_profile.gym_id
    and status = 'pending';

  update public.profiles
  set gym_id = null,
      role = 'athlete',
      is_active = true
  where id = v_user_id;
end;
$$;

grant execute on function public.leave_current_gym() to authenticated;
