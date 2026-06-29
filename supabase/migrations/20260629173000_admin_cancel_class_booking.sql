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
        membership_id,
        class_id,
        change,
        reason
      )
      values (
        v_booking.user_id,
        v_membership_id,
        v_booking.class_id,
        1,
        'cancelled'
      );
    end if;
  end if;
end;
$$;
