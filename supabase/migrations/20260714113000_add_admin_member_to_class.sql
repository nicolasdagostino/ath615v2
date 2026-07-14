create or replace function public.admin_add_member_to_class(
  p_class_id uuid,
  p_user_id uuid
)
returns table (
  booking_id uuid,
  user_id uuid,
  status text,
  created_at timestamptz,
  guest_name text,
  is_guest boolean,
  membership_id uuid
)
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_admin public.profiles%rowtype;
  v_member public.profiles%rowtype;
  v_class public.classes%rowtype;
  v_membership public.member_memberships%rowtype;
  v_booking public.class_bookings%rowtype;
  v_booked_count integer;
  v_capacity integer;
  v_booking_status text;
  v_class_ends_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if p_class_id is null then
    raise exception 'Missing class id';
  end if;

  if p_user_id is null then
    raise exception 'Missing user id';
  end if;

  select *
  into v_admin
  from public.profiles
  where id = auth.uid();

  if v_admin.id is null
     or v_admin.role not in ('admin', 'owner')
     or v_admin.gym_id is null then
    raise exception 'Only gym admins can add members to classes';
  end if;

  select *
  into v_class
  from public.classes
  where id = p_class_id
  for update;

  if v_class.id is null then
    raise exception 'Class not found';
  end if;

  if v_class.gym_id is distinct from v_admin.gym_id then
    raise exception 'Class belongs to another gym';
  end if;

  select *
  into v_member
  from public.profiles
  where id = p_user_id
  for update;

  if v_member.id is null then
    raise exception 'Member not found';
  end if;

  if v_member.gym_id is distinct from v_class.gym_id then
    raise exception 'Member belongs to another gym';
  end if;

  if v_member.is_active is distinct from true then
    raise exception 'Member account is inactive';
  end if;

  if exists (
    select 1
    from public.class_bookings cb
    where cb.class_id = p_class_id
      and cb.user_id = p_user_id
      and cb.status <> 'cancelled'
  ) then
    raise exception 'Member is already added to this class';
  end if;

  select count(*)
  into v_booked_count
  from public.class_bookings cb
  where cb.class_id = p_class_id
    and cb.status <> 'cancelled';

  v_capacity := coalesce(v_class.capacity, 0);

  if v_booked_count >= v_capacity then
    raise exception 'Class is full';
  end if;

  select *
  into v_membership
  from public.select_usable_membership(
    p_user_id,
    v_class.gym_id
  );

  if v_membership.id is null then
    raise exception 'Active membership required';
  end if;

  if v_membership.credits_remaining is not null then
    update public.member_memberships
    set credits_remaining = credits_remaining - 1,
        status = case
          when credits_remaining = 1 then 'exhausted'
          else status
        end,
        is_active = case
          when credits_remaining = 1 then false
          else is_active
        end
    where id = v_membership.id;

    insert into public.membership_credit_logs (
      user_id,
      gym_id,
      membership_id,
      amount,
      reason,
      class_id
    )
    values (
      p_user_id,
      v_membership.gym_id,
      v_membership.id,
      -1,
      'admin_added',
      p_class_id
    );
  end if;

  delete from public.class_waitlist
  where class_id = p_class_id
    and user_id = p_user_id;

  v_class_ends_at :=
    v_class.starts_at
    + make_interval(
        mins => greatest(
          coalesce(v_class.duration_minutes, 60),
          1
        )
      );

  v_booking_status := case
    when v_class_ends_at <= now() then 'attended'
    else 'booked'
  end;

  insert into public.class_bookings (
    class_id,
    user_id,
    status,
    is_guest,
    membership_id
  )
  values (
    p_class_id,
    p_user_id,
    v_booking_status,
    false,
    v_membership.id
  )
  returning *
  into v_booking;

  return query
  select
    v_booking.id,
    v_booking.user_id,
    v_booking.status,
    v_booking.created_at,
    v_booking.guest_name,
    v_booking.is_guest,
    v_booking.membership_id;
end;
$function$;


revoke all on function public.admin_add_member_to_class(
  uuid,
  uuid
) from public;

revoke all on function public.admin_add_member_to_class(
  uuid,
  uuid
) from anon;

revoke all on function public.admin_add_member_to_class(
  uuid,
  uuid
) from authenticated;

grant execute on function public.admin_add_member_to_class(
  uuid,
  uuid
) to authenticated, service_role;
