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
  v_preferred_locale text := 'en';
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

    select coalesce(preferred_locale, 'en')
    into v_preferred_locale
    from public.profiles
    where id = v_waitlist_row.user_id;

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
      case
        when v_preferred_locale = 'es' then '🎉 ¡Conseguiste una plaza!'
        else '🎉 You got a spot!'
      end,
      case
        when v_preferred_locale = 'es' then format(
          'Se liberó una plaza para %s a las %s.',
          v_class.title,
          to_char(v_class.starts_at at time zone 'UTC', 'HH24:MI')
        )
        else format(
          'A spot opened up for %s at %s.',
          v_class.title,
          to_char(v_class.starts_at at time zone 'UTC', 'HH24:MI')
        )
      end,
      'waitlist_promoted',
      jsonb_build_object('classId', p_class_id),
      now()
    );

    return;
  end loop;
end;
$$;
