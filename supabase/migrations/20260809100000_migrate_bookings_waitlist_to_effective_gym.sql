-- Vertical 3B1: session-scoped booking/waitlist authority.

create or replace function public.is_active_gym_member(
  p_user_id uuid,
  p_gym_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select p_user_id is not null
    and p_gym_id is not null
    and exists (
      select 1
      from public.gym_members gm
      where gm.user_id = p_user_id
        and gm.gym_id = p_gym_id
        and gm.is_active = true
    );
$function$;
revoke all on function public.is_active_gym_member(uuid, uuid) from public, anon, authenticated;
grant execute on function public.is_active_gym_member(uuid, uuid) to service_role;
drop policy if exists "admin insert guest bookings" on public.class_bookings;
drop policy if exists "admin update gym bookings" on public.class_bookings;
drop policy if exists "book class" on public.class_bookings;
drop policy if exists "cancel own booking" on public.class_bookings;
drop policy if exists "read my gym bookings" on public.class_bookings;
drop policy if exists "effective gym members read bookings" on public.class_bookings;
drop policy if exists "effective members insert own bookings" on public.class_bookings;
drop policy if exists "effective admins insert guest bookings" on public.class_bookings;
drop policy if exists "effective members cancel own bookings" on public.class_bookings;
drop policy if exists "effective admins update bookings" on public.class_bookings;
create policy "effective gym members read bookings"
on public.class_bookings for select to authenticated
using (
  exists (
    select 1 from public.classes c
    where c.id = class_bookings.class_id
      and c.gym_id = public.effective_gym_id()
  )
);
create policy "effective admins insert guest bookings"
on public.class_bookings for insert to authenticated
with check (
  is_guest = true
  and user_id is null
  and guest_name is not null
  and length(btrim(guest_name)) > 0
  and public.effective_gym_role() = 'admin'
  and exists (
    select 1 from public.classes c
    where c.id = class_bookings.class_id
      and c.gym_id = public.effective_gym_id()
  )
);
create policy "effective admins update bookings"
on public.class_bookings for update to authenticated
using (
  public.effective_gym_role() = 'admin'
  and exists (
    select 1 from public.classes c
    where c.id = class_bookings.class_id
      and c.gym_id = public.effective_gym_id()
  )
)
with check (
  public.effective_gym_role() = 'admin'
  and exists (
    select 1 from public.classes c
    where c.id = class_bookings.class_id
      and c.gym_id = public.effective_gym_id()
  )
);
drop policy if exists "admins manage gym waitlist" on public.class_waitlist;
drop policy if exists "admins view gym waitlist" on public.class_waitlist;
drop policy if exists "athletes join own waitlist" on public.class_waitlist;
drop policy if exists "athletes leave own waitlist" on public.class_waitlist;
drop policy if exists "gym members view class waitlist" on public.class_waitlist;
drop policy if exists "effective gym members read waitlist" on public.class_waitlist;
drop policy if exists "effective members join own waitlist" on public.class_waitlist;
drop policy if exists "effective members leave own waitlist" on public.class_waitlist;
drop policy if exists "effective admins delete waitlist" on public.class_waitlist;
create policy "effective gym members read waitlist"
on public.class_waitlist for select to authenticated
using (
  exists (
    select 1 from public.classes c
    where c.id = class_waitlist.class_id
      and c.gym_id = public.effective_gym_id()
  )
);
create policy "effective admins delete waitlist"
on public.class_waitlist for delete to authenticated
using (
  public.effective_gym_role() = 'admin'
  and exists (
    select 1 from public.classes c
    where c.id = class_waitlist.class_id
      and c.gym_id = public.effective_gym_id()
  )
);
create or replace function public.book_class_with_membership(p_class_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_gym_id uuid := public.effective_gym_id();
  v_membership public.member_memberships%rowtype;
  v_class public.classes%rowtype;
  v_booked_count integer;
begin
  if v_user_id is null then raise exception 'Not authenticated'; end if;

  select * into v_class from public.classes
  where id = p_class_id and gym_id = v_gym_id and starts_at > now()
  for update;
  if not found then raise exception 'Class not found'; end if;
  if not public.is_active_gym_member(v_user_id, v_class.gym_id) then
    raise exception 'Not allowed';
  end if;
  if public.effective_gym_role() not in ('athlete', 'admin', 'coach') then
    raise exception 'Not allowed';
  end if;

  if exists (select 1 from public.class_bookings where class_id = p_class_id and user_id = v_user_id and status <> 'cancelled') then
    raise exception 'Already booked';
  end if;
  select count(*) into v_booked_count from public.class_bookings
  where class_id = p_class_id and status <> 'cancelled';
  if v_booked_count >= coalesce(v_class.capacity, 0) then raise exception 'Class is full'; end if;

  select * into v_membership from public.select_usable_membership(v_user_id, v_class.gym_id);
  if v_membership.id is null then raise exception 'Active membership required'; end if;

  if v_membership.credits_remaining is not null then
    update public.member_memberships mm
    set credits_remaining = mm.credits_remaining - 1,
        status = case when mm.credits_remaining = 1 then 'exhausted' else mm.status end,
        is_active = case when mm.credits_remaining = 1 then false else mm.is_active end
    where mm.id = v_membership.id;
    insert into public.membership_credit_logs(user_id, gym_id, membership_id, amount, reason, class_id)
    values (v_user_id, v_class.gym_id, v_membership.id, -1, 'booked', p_class_id);
  end if;

  delete from public.class_waitlist where class_id = p_class_id and user_id = v_user_id;
  insert into public.class_bookings(class_id, user_id, status, membership_id)
  values (p_class_id, v_user_id, 'booked', v_membership.id);
end;
$function$;
create or replace function public.join_class_waitlist(p_class_id uuid)
returns void language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_gym_id uuid := public.effective_gym_id();
  v_class public.classes%rowtype;
  v_membership public.member_memberships%rowtype;
  v_booked_count integer;
  v_waitlist_count integer;
begin
  if v_user_id is null then raise exception 'Not authenticated'; end if;
  select * into v_class from public.classes
  where id = p_class_id and gym_id = v_gym_id and starts_at > now()
  for update;
  if not found then raise exception 'Class not found'; end if;
  if not public.is_active_gym_member(v_user_id, v_class.gym_id) then raise exception 'Not allowed'; end if;
  if public.effective_gym_role() not in ('athlete', 'admin', 'coach') then raise exception 'Not allowed'; end if;

  select count(*) into v_booked_count from public.class_bookings where class_id = p_class_id and status <> 'cancelled';
  if v_booked_count < coalesce(v_class.capacity, 0) then raise exception 'Class is not full'; end if;
  select count(*) into v_waitlist_count from public.class_waitlist where class_id = p_class_id;
  if v_waitlist_count >= coalesce(v_class.capacity, 0) then raise exception 'Waitlist is full'; end if;
  if exists (select 1 from public.class_bookings where class_id = p_class_id and user_id = v_user_id and status <> 'cancelled') then raise exception 'Already booked'; end if;

  select * into v_membership from public.select_usable_membership(v_user_id, v_class.gym_id);
  if v_membership.id is null then raise exception 'Active membership required'; end if;
  insert into public.class_waitlist(class_id, user_id) values (p_class_id, v_user_id)
  on conflict (class_id, user_id) do nothing;
end;
$function$;
create or replace function public.leave_class_waitlist(p_class_id uuid)
returns void language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  delete from public.class_waitlist cw
  using public.classes c
  where cw.class_id = p_class_id
    and cw.user_id = auth.uid()
    and c.id = cw.class_id
    and c.gym_id = v_gym_id;
end;
$function$;
create or replace function public.admin_add_member_to_class(p_class_id uuid, p_user_id uuid)
returns table(booking_id uuid, user_id uuid, status text, created_at timestamptz, guest_name text, is_guest boolean, membership_id uuid)
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare
  v_class public.classes%rowtype;
  v_membership public.member_memberships%rowtype;
  v_booking public.class_bookings%rowtype;
  v_booked_count integer;
  v_booking_status text;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if p_class_id is null then raise exception 'Missing class id'; end if;
  if p_user_id is null then raise exception 'Missing user id'; end if;
  if public.effective_gym_role() <> 'admin' then raise exception 'Only gym admins can add members to classes'; end if;

  select * into v_class from public.classes
  where id = p_class_id and gym_id = public.effective_gym_id()
  for update;
  if not found then raise exception 'Class not found'; end if;
  if not public.is_active_gym_member(p_user_id, v_class.gym_id) then raise exception 'Member not found'; end if;
  if exists (select 1 from public.class_bookings cb where cb.class_id = p_class_id and cb.user_id = p_user_id and cb.status <> 'cancelled') then raise exception 'Member is already added to this class'; end if;
  select count(*) into v_booked_count from public.class_bookings cb where cb.class_id = p_class_id and cb.status <> 'cancelled';
  if v_booked_count >= coalesce(v_class.capacity, 0) then raise exception 'Class is full'; end if;

  select * into v_membership from public.select_usable_membership(p_user_id, v_class.gym_id);
  if v_membership.id is null then raise exception 'Active membership required'; end if;
  if v_membership.credits_remaining is not null then
    update public.member_memberships mm
    set credits_remaining = mm.credits_remaining - 1,
        status = case when mm.credits_remaining = 1 then 'exhausted' else mm.status end,
        is_active = case when mm.credits_remaining = 1 then false else mm.is_active end
    where mm.id = v_membership.id;
    insert into public.membership_credit_logs(user_id, gym_id, membership_id, amount, reason, class_id)
    values (p_user_id, v_class.gym_id, v_membership.id, -1, 'admin_added', p_class_id);
  end if;
  delete from public.class_waitlist cw where cw.class_id = p_class_id and cw.user_id = p_user_id;
  v_booking_status := case when v_class.starts_at + make_interval(mins => greatest(coalesce(v_class.duration_minutes, 60), 1)) <= now() then 'attended' else 'booked' end;
  insert into public.class_bookings(class_id, user_id, status, is_guest, membership_id)
  values (p_class_id, p_user_id, v_booking_status, false, v_membership.id)
  returning * into v_booking;
  return query select v_booking.id, v_booking.user_id, v_booking.status, v_booking.created_at, v_booking.guest_name, v_booking.is_guest, v_booking.membership_id;
end;
$function$;
create or replace function public.admin_add_member_to_class_waitlist(p_class_id uuid, p_user_id uuid)
returns void language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare
  v_class public.classes%rowtype;
  v_membership public.member_memberships%rowtype;
  v_booked_count integer;
  v_waitlist_count integer;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_class_id is null or p_user_id is null then raise exception 'invalid_request'; end if;
  if public.effective_gym_role() <> 'admin' then raise exception 'forbidden'; end if;
  select * into v_class from public.classes
  where id = p_class_id and gym_id = public.effective_gym_id() and starts_at > now()
  for update;
  if not found then raise exception 'class_not_found'; end if;
  if not public.is_active_gym_member(p_user_id, v_class.gym_id) then raise exception 'member_not_found'; end if;
  if exists (select 1 from public.class_bookings where class_id = p_class_id and user_id = p_user_id and status <> 'cancelled') then raise exception 'already_booked'; end if;
  if exists (select 1 from public.class_waitlist where class_id = p_class_id and user_id = p_user_id) then raise exception 'already_waitlisted'; end if;
  select count(*) into v_booked_count from public.class_bookings where class_id = p_class_id and status <> 'cancelled';
  if v_booked_count < coalesce(v_class.capacity, 0) then raise exception 'class_not_full'; end if;
  select count(*) into v_waitlist_count from public.class_waitlist where class_id = p_class_id;
  if v_waitlist_count >= coalesce(v_class.capacity, 0) then raise exception 'waitlist_full'; end if;
  select * into v_membership from public.select_usable_membership(p_user_id, v_class.gym_id);
  if v_membership.id is null then raise exception 'active_membership_required'; end if;
  insert into public.class_waitlist(class_id, user_id) values (p_class_id, p_user_id);
end;
$function$;
create or replace function public.promote_first_waitlisted_user(p_class_id uuid)
returns void language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare
  v_class public.classes%rowtype;
  v_waitlist_row public.class_waitlist%rowtype;
  v_membership public.member_memberships%rowtype;
  v_booked_count integer;
  v_preferred_locale text := 'en';
begin
  select * into v_class from public.classes where id = p_class_id for update;
  if not found or v_class.starts_at <= now() then return; end if;
  loop
    select count(*) into v_booked_count from public.class_bookings where class_id = p_class_id and status <> 'cancelled';
    if v_booked_count >= coalesce(v_class.capacity, 0) then return; end if;
    select * into v_waitlist_row from public.class_waitlist
    where class_id = p_class_id order by created_at, id limit 1 for update skip locked;
    if not found then return; end if;
    delete from public.class_waitlist where id = v_waitlist_row.id;
    if not public.is_active_gym_member(v_waitlist_row.user_id, v_class.gym_id) then continue; end if;
    if exists (select 1 from public.class_bookings where class_id = p_class_id and user_id = v_waitlist_row.user_id and status <> 'cancelled') then continue; end if;
    select * into v_membership from public.select_usable_membership(v_waitlist_row.user_id, v_class.gym_id);
    if v_membership.id is null then continue; end if;
    if v_membership.credits_remaining is not null then
      update public.member_memberships
      set credits_remaining = credits_remaining - 1,
          status = case when credits_remaining = 1 then 'exhausted' else status end,
          is_active = case when credits_remaining = 1 then false else is_active end
      where id = v_membership.id;
      insert into public.membership_credit_logs(user_id, gym_id, membership_id, amount, reason, class_id)
      values (v_waitlist_row.user_id, v_class.gym_id, v_membership.id, -1, 'waitlist_promoted', p_class_id);
    end if;
    insert into public.class_bookings(class_id, user_id, status, membership_id)
    values (p_class_id, v_waitlist_row.user_id, 'booked', v_membership.id);
    select coalesce(preferred_locale, 'en') into v_preferred_locale from public.profiles where id = v_waitlist_row.user_id;
    insert into public.notifications(user_id, title, body, type, data, scheduled_for, gym_id)
    values (
      v_waitlist_row.user_id,
      case when v_preferred_locale = 'es' then '🎉 ¡Conseguiste una plaza!' else '🎉 You got a spot!' end,
      case when v_preferred_locale = 'es'
        then format('Se liberó una plaza para %s a las %s.', v_class.title, to_char(v_class.starts_at at time zone 'UTC', 'HH24:MI'))
        else format('A spot opened up for %s at %s.', v_class.title, to_char(v_class.starts_at at time zone 'UTC', 'HH24:MI')) end,
      'waitlist_promoted', jsonb_build_object('classId', p_class_id), now(), v_class.gym_id
    );
    return;
  end loop;
end;
$function$;
create or replace function public.cancel_my_booking(p_class_id uuid)
returns void language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_booking public.class_bookings%rowtype;
  v_class public.classes%rowtype;
  v_membership public.member_memberships%rowtype;
  v_expiration timestamptz;
begin
  if v_user_id is null then raise exception 'Not authenticated'; end if;
  select cb.* into v_booking
  from public.class_bookings cb join public.classes c on c.id = cb.class_id
  where cb.class_id = p_class_id and cb.user_id = v_user_id and cb.status = 'booked'
    and c.starts_at > now() and c.gym_id = public.effective_gym_id()
  for update of cb;
  if not found then raise exception 'Booking can only be cancelled before class starts'; end if;
  select * into v_class from public.classes where id = v_booking.class_id;
  update public.class_bookings set status = 'cancelled' where id = v_booking.id;
  if v_booking.membership_id is not null then
    select * into v_membership from public.member_memberships
    where id = v_booking.membership_id and user_id = v_user_id and gym_id = v_class.gym_id for update;
    if found and v_membership.credits_remaining is not null then
      v_expiration := coalesce(v_membership.expires_at, v_membership.ends_at);
      update public.member_memberships
      set credits_remaining = credits_remaining + 1,
          status = case when v_expiration is not null and v_expiration <= now() then 'expired' when status = 'exhausted' then 'active' else status end,
          is_active = case when v_expiration is not null and v_expiration <= now() then false when status = 'exhausted' then true else is_active end
      where id = v_membership.id;
      insert into public.membership_credit_logs(user_id, gym_id, membership_id, amount, reason, class_id)
      values (v_user_id, v_class.gym_id, v_membership.id, 1, 'cancelled', v_booking.class_id);
    end if;
  end if;
  perform public.promote_first_waitlisted_user(v_booking.class_id);
end;
$function$;
create or replace function public.admin_cancel_class_booking(p_booking_id uuid)
returns void language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare
  v_booking public.class_bookings%rowtype;
  v_class public.classes%rowtype;
  v_membership public.member_memberships%rowtype;
  v_expiration timestamptz;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if public.effective_gym_role() <> 'admin' then raise exception 'Not allowed'; end if;
  select * into v_booking from public.class_bookings where id = p_booking_id for update;
  if not found then raise exception 'Booking not found'; end if;
  select * into v_class from public.classes where id = v_booking.class_id and gym_id = public.effective_gym_id();
  if not found then raise exception 'Booking not found'; end if;
  if v_booking.status = 'cancelled' then return; end if;
  update public.class_bookings set status = 'cancelled' where id = v_booking.id;
  if not coalesce(v_booking.is_guest, false) and v_booking.user_id is not null and v_booking.membership_id is not null then
    select * into v_membership from public.member_memberships
    where id = v_booking.membership_id and user_id = v_booking.user_id and gym_id = v_class.gym_id for update;
    if found and v_membership.credits_remaining is not null then
      v_expiration := coalesce(v_membership.expires_at, v_membership.ends_at);
      update public.member_memberships
      set credits_remaining = credits_remaining + 1,
          status = case when v_expiration is not null and v_expiration <= now() then 'expired' when status = 'exhausted' then 'active' else status end,
          is_active = case when v_expiration is not null and v_expiration <= now() then false when status = 'exhausted' then true else is_active end
      where id = v_membership.id;
      insert into public.membership_credit_logs(user_id, gym_id, membership_id, amount, reason, class_id)
      values (v_booking.user_id, v_class.gym_id, v_membership.id, 1, 'cancelled', v_booking.class_id);
    end if;
  end if;
  perform public.promote_first_waitlisted_user(v_booking.class_id);
end;
$function$;
create or replace function public.set_notification_gym_id()
returns trigger language plpgsql security definer
set search_path = public, pg_temp
as $function$
begin
  if new.type = 'waitlist_promoted' then
    select c.gym_id into new.gym_id
    from public.classes c
    where c.id::text = new.data ->> 'classId';
    if new.gym_id is null then raise exception 'invalid_notification_origin'; end if;
    return new;
  end if;

  select p.gym_id into new.gym_id from public.profiles p where p.id = new.user_id;
  if new.gym_id is null and new.type = 'gym_join_rejected' then
    select r.gym_id into new.gym_id from public.gym_join_requests r
    where r.user_id = new.user_id and r.status = 'rejected'
      and r.gym_id::text = new.data ->> 'gymId'
    order by r.approved_at desc nulls last, r.created_at desc limit 1;
  end if;
  return new;
end;
$function$;
create or replace function public.claim_pending_notifications(
  p_gym_id uuid,
  p_claim_token uuid,
  p_limit integer default 50
)
returns setof public.notifications
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  if p_gym_id is null or p_claim_token is null then
    raise exception using errcode = 'P0001', message = 'invalid_claim';
  end if;

  return query
  with candidates as (
    select n.id
    from public.notifications n
    join public.profiles p on p.id = n.user_id
    where n.gym_id = p_gym_id
      and coalesce(p.is_active, false)
      and (
        exists (
          select 1 from public.gym_members gm
          where gm.user_id = n.user_id
            and gm.gym_id = n.gym_id
            and gm.is_active = true
        )
        or p.gym_id = n.gym_id
        or (
          p.gym_id is null
          and n.type = 'gym_join_rejected'
          and exists (
            select 1 from public.gym_join_requests r
            where r.user_id = n.user_id
              and r.gym_id = n.gym_id
              and r.status = 'rejected'
          )
        )
      )
      and n.sent_at is null
      and n.delivery_attempts < 5
      and n.scheduled_for <= now()
      and (n.processing_at is null or n.processing_at < now() - interval '10 minutes')
    order by n.scheduled_for, n.id
    for update of n skip locked
    limit greatest(1, least(coalesce(p_limit, 50), 50))
  )
  update public.notifications n
  set processing_at = now(),
      processing_token = p_claim_token,
      delivery_attempts = n.delivery_attempts + 1
  from candidates c
  where n.id = c.id
  returning n.*;
end;
$function$;
revoke all on function public.book_class_with_membership(uuid) from public, anon;
revoke all on function public.cancel_my_booking(uuid) from public, anon;
revoke all on function public.admin_add_member_to_class(uuid, uuid) from public, anon;
revoke all on function public.admin_add_member_to_class_waitlist(uuid, uuid) from public, anon;
revoke all on function public.admin_cancel_class_booking(uuid) from public, anon;
revoke all on function public.join_class_waitlist(uuid) from public, anon;
revoke all on function public.leave_class_waitlist(uuid) from public, anon;
revoke all on function public.promote_first_waitlisted_user(uuid) from public, anon, authenticated;
revoke all on function public.set_notification_gym_id() from public, anon, authenticated;
grant execute on function public.book_class_with_membership(uuid) to authenticated, service_role;
grant execute on function public.cancel_my_booking(uuid) to authenticated, service_role;
grant execute on function public.admin_add_member_to_class(uuid, uuid) to authenticated, service_role;
grant execute on function public.admin_add_member_to_class_waitlist(uuid, uuid) to authenticated, service_role;
grant execute on function public.admin_cancel_class_booking(uuid) to authenticated, service_role;
grant execute on function public.join_class_waitlist(uuid) to authenticated, service_role;
grant execute on function public.leave_class_waitlist(uuid) to authenticated, service_role;
grant execute on function public.promote_first_waitlisted_user(uuid) to service_role;
grant execute on function public.set_notification_gym_id() to service_role;
