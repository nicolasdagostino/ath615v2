create or replace function public.cancel_my_booking(
  p_class_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_user_id uuid := auth.uid();
  v_booking public.class_bookings%rowtype;
  v_class public.classes%rowtype;
  v_membership public.member_memberships%rowtype;
  v_expiration timestamptz;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select cb.*
  into v_booking
  from public.class_bookings cb
  join public.classes c
    on c.id = cb.class_id
  where cb.class_id = p_class_id
    and cb.user_id = v_user_id
    and cb.status = 'booked'
    and c.starts_at > now()
  for update of cb;

  if not found then
    raise exception 'Booking can only be cancelled before class starts';
  end if;

  select *
  into v_class
  from public.classes
  where id = v_booking.class_id;

  update public.class_bookings
  set status = 'cancelled'
  where id = v_booking.id;

  if v_booking.membership_id is not null then
    select *
    into v_membership
    from public.member_memberships
    where id = v_booking.membership_id
      and user_id = v_user_id
      and gym_id = v_class.gym_id
    for update;

    if found and v_membership.credits_remaining is not null then
      v_expiration := coalesce(
        v_membership.expires_at,
        v_membership.ends_at
      );

      update public.member_memberships
      set credits_remaining = credits_remaining + 1,
          status = case
            when v_expiration is not null
              and v_expiration <= now()
              then 'expired'
            when v_membership.status = 'exhausted'
              then 'active'
            else v_membership.status
          end,
          is_active = case
            when v_expiration is not null
              and v_expiration <= now()
              then false
            when v_membership.status = 'exhausted'
              then true
            else v_membership.is_active
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
        v_user_id,
        v_membership.gym_id,
        v_membership.id,
        1,
        'cancelled',
        v_booking.class_id
      );
    end if;
  end if;

  perform public.promote_first_waitlisted_user(v_booking.class_id);
end;
$function$;

create or replace function public.admin_cancel_class_booking(
  p_booking_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_booking public.class_bookings%rowtype;
  v_class public.classes%rowtype;
  v_membership public.member_memberships%rowtype;
  v_expiration timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select *
  into v_booking
  from public.class_bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'Booking not found';
  end if;

  select *
  into v_class
  from public.classes
  where id = v_booking.class_id;

  if not found then
    raise exception 'Class not found';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.gym_id = v_class.gym_id
      and p.role in ('admin', 'owner')
  ) then
    raise exception 'Not allowed';
  end if;

  if v_booking.status = 'cancelled' then
    return;
  end if;

  update public.class_bookings
  set status = 'cancelled'
  where id = v_booking.id;

  if coalesce(v_booking.is_guest, false) = false
     and v_booking.user_id is not null
     and v_booking.membership_id is not null then

    select *
    into v_membership
    from public.member_memberships
    where id = v_booking.membership_id
      and user_id = v_booking.user_id
      and gym_id = v_class.gym_id
    for update;

    if found and v_membership.credits_remaining is not null then
      v_expiration := coalesce(
        v_membership.expires_at,
        v_membership.ends_at
      );

      update public.member_memberships
      set credits_remaining = credits_remaining + 1,
          status = case
            when v_expiration is not null
              and v_expiration <= now()
              then 'expired'
            when v_membership.status = 'exhausted'
              then 'active'
            else v_membership.status
          end,
          is_active = case
            when v_expiration is not null
              and v_expiration <= now()
              then false
            when v_membership.status = 'exhausted'
              then true
            else v_membership.is_active
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
        v_booking.user_id,
        v_class.gym_id,
        v_membership.id,
        1,
        'cancelled',
        v_booking.class_id
      );
    end if;
  end if;

  perform public.promote_first_waitlisted_user(v_booking.class_id);
end;
$function$;
