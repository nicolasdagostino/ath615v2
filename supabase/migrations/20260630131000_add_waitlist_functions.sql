create or replace function public.join_class_waitlist(p_class_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_class public.classes%rowtype;
  v_membership public.member_memberships%rowtype;
  v_capacity int;
  v_booked_count int;
  v_waitlist_count int;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select *
  into v_class
  from public.classes
  where id = p_class_id
    and starts_at > now();

  if not found then
    raise exception 'Class not found';
  end if;

  select count(*)
  into v_booked_count
  from public.class_bookings
  where class_id = p_class_id
    and status <> 'cancelled';

  v_capacity := coalesce(v_class.capacity, 0);

  if v_booked_count < v_capacity then
    raise exception 'Class is not full';
  end if;

  select count(*)
  into v_waitlist_count
  from public.class_waitlist
  where class_id = p_class_id;

  if v_waitlist_count >= v_capacity then
    raise exception 'Waitlist is full';
  end if;

  if exists (
    select 1
    from public.class_bookings
    where class_id = p_class_id
      and user_id = v_user_id
      and status <> 'cancelled'
  ) then
    raise exception 'Already booked';
  end if;

  select *
  into v_membership
  from public.member_memberships
  where user_id = v_user_id
    and gym_id = v_class.gym_id
    and is_active = true
    and status = 'active'
    and (expires_at is null or expires_at > now())
  order by created_at desc
  limit 1;

  if not found then
    raise exception 'Active membership required';
  end if;

  if v_membership.credits_remaining is not null and v_membership.credits_remaining <= 0 then
    raise exception 'No credits remaining';
  end if;

  insert into public.class_waitlist (class_id, user_id)
  values (p_class_id, v_user_id)
  on conflict (class_id, user_id) do nothing;
end;
$$;

create or replace function public.leave_class_waitlist(p_class_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.class_waitlist
  where class_id = p_class_id
    and user_id = auth.uid();
end;
$$;

create or replace function public.promote_first_waitlisted_user(p_class_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_class public.classes%rowtype;
  v_capacity int;
  v_booked_count int;
  v_waitlist_row public.class_waitlist%rowtype;
  v_membership public.member_memberships%rowtype;
begin
  select *
  into v_class
  from public.classes
  where id = p_class_id
  for update;

  if not found then
    return;
  end if;

  if v_class.starts_at <= now() then
    return;
  end if;

  loop
    select count(*)
    into v_booked_count
    from public.class_bookings
    where class_id = p_class_id
      and status <> 'cancelled';

    v_capacity := coalesce(v_class.capacity, 0);

    if v_booked_count >= v_capacity then
      return;
    end if;

    select *
    into v_waitlist_row
    from public.class_waitlist
    where class_id = p_class_id
    order by created_at asc
    limit 1
    for update skip locked;

    if not found then
      return;
    end if;

    delete from public.class_waitlist
    where id = v_waitlist_row.id;

    if exists (
      select 1
      from public.class_bookings
      where class_id = p_class_id
        and user_id = v_waitlist_row.user_id
        and status <> 'cancelled'
    ) then
      continue;
    end if;

    select *
    into v_membership
    from public.member_memberships
    where user_id = v_waitlist_row.user_id
      and gym_id = v_class.gym_id
      and is_active = true
      and status = 'active'
      and (expires_at is null or expires_at > now())
    order by created_at desc
    limit 1
    for update;

    if not found then
      continue;
    end if;

    if v_membership.credits_remaining is not null then
      if v_membership.credits_remaining <= 0 then
        continue;
      end if;

      update public.member_memberships
      set credits_remaining = credits_remaining - 1
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
        v_waitlist_row.user_id,
        v_membership.gym_id,
        v_membership.id,
        -1,
        'waitlist_promoted',
        p_class_id
      );
    end if;

    insert into public.class_bookings (class_id, user_id, status)
    values (p_class_id, v_waitlist_row.user_id, 'booked');

    insert into public.notifications (
      user_id,
      title,
      body,
      type,
      data,
      scheduled_for
    )
    values (
      v_waitlist_row.user_id,
      '🎉 You got a spot!',
      format(
        'A spot opened up for %s at %s.',
        v_class.title,
        to_char(v_class.starts_at at time zone ''UTC'', 'HH24:MI')
      ),
      'waitlist_promoted',
      jsonb_build_object('classId', p_class_id),
      now()
    );

    return;
  end loop;
end;
$$;

create or replace function public.book_class_with_membership(p_class_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_membership public.member_memberships%rowtype;
  v_class public.classes%rowtype;
  v_booked_count int;
  v_capacity int;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select *
  into v_class
  from public.classes
  where id = p_class_id
    and starts_at > now()
  for update;

  if not found then
    raise exception 'Class not found';
  end if;

  select count(*)
  into v_booked_count
  from public.class_bookings
  where class_id = p_class_id
    and status <> 'cancelled';

  v_capacity := coalesce(v_class.capacity, 0);

  if v_booked_count >= v_capacity then
    raise exception 'Class is full';
  end if;

  if exists (
    select 1
    from public.class_bookings
    where class_id = p_class_id
      and user_id = v_user_id
      and status <> 'cancelled'
  ) then
    raise exception 'Already booked';
  end if;

  select *
  into v_membership
  from public.member_memberships
  where user_id = v_user_id
    and gym_id = v_class.gym_id
    and is_active = true
    and status = 'active'
    and (expires_at is null or expires_at > now())
  order by created_at desc
  limit 1
  for update;

  if not found then
    raise exception 'Active membership required';
  end if;

  if v_membership.credits_remaining is not null then
    if v_membership.credits_remaining <= 0 then
      raise exception 'No credits remaining';
    end if;

    update public.member_memberships
    set credits_remaining = credits_remaining - 1
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
      -1,
      'booked',
      p_class_id
    );
  end if;

  delete from public.class_waitlist
  where class_id = p_class_id
    and user_id = v_user_id;

  insert into public.class_bookings (class_id, user_id, status)
  values (p_class_id, v_user_id, 'booked');
end;
$$;

create or replace function public.cancel_my_booking(p_class_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_membership public.member_memberships%rowtype;
begin
  select *
  into v_membership
  from public.member_memberships
  where user_id = auth.uid()
    and is_active = true
    and status = 'active'
    and (expires_at is null or expires_at > now())
    and credits_remaining is not null
  order by created_at desc
  limit 1;

  update public.class_bookings cb
  set status = 'cancelled'
  from public.classes c
  where cb.class_id = c.id
    and cb.class_id = p_class_id
    and cb.user_id = auth.uid()
    and cb.status = 'booked'
    and c.starts_at > now();

  if not found then
    raise exception 'Booking can only be cancelled before class starts';
  end if;

  if v_membership.id is not null then
    update public.member_memberships
    set credits_remaining = credits_remaining + 1
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
      auth.uid(),
      v_membership.gym_id,
      v_membership.id,
      1,
      'cancelled',
      p_class_id
    );
  end if;

  perform public.promote_first_waitlisted_user(p_class_id);
end;
$$;

create or replace function public.admin_cancel_class_booking(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.class_bookings%rowtype;
  v_class public.classes%rowtype;
  v_membership_id uuid;
begin
  select *
  into v_booking
  from public.class_bookings
  where id = p_booking_id;

  if not found then
    raise exception 'Booking not found';
  end if;

  select *
  into v_class
  from public.classes
  where id = v_booking.class_id;

  if not exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.gym_id = v_class.gym_id
      and p.role = any (array['admin'::text, 'owner'::text])
  ) then
    raise exception 'Not allowed';
  end if;

  if v_booking.status = 'cancelled' then
    return;
  end if;

  update public.class_bookings
  set status = 'cancelled'
  where id = p_booking_id;

  if coalesce(v_booking.is_guest, false) = false and v_booking.user_id is not null then
    select mm.id
    into v_membership_id
    from public.member_memberships mm
    join public.membership_plans mp on mp.id = mm.plan_id
    where mm.user_id = v_booking.user_id
      and mm.gym_id = v_class.gym_id
      and mm.status = 'active'
      and mp.plan_type = 'dropin'
    order by mm.created_at desc
    limit 1;

    if v_membership_id is not null then
      update public.member_memberships
      set credits_remaining = credits_remaining + 1
      where id = v_membership_id;

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
        v_membership_id,
        1,
        'cancelled',
        v_booking.class_id
      );
    end if;
  end if;

  perform public.promote_first_waitlisted_user(v_booking.class_id);
end;
$$;
