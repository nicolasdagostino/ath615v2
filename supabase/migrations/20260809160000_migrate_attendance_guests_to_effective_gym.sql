-- Vertical 3B2: Attendance, guests, and minimum member identity.

create or replace function public.list_effective_attendance_profiles(p_class_id uuid)
returns table(user_id uuid, full_name text, avatar_url text)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if public.effective_gym_role() <> 'admin' then raise exception 'Not allowed'; end if;
  if not exists (
    select 1 from public.classes c
    where c.id = p_class_id and c.gym_id = public.effective_gym_id()
  ) then raise exception 'Class not found'; end if;

  return query
  select p.id, p.full_name, p.avatar_url
  from public.class_bookings cb
  join public.profiles p on p.id = cb.user_id
  where cb.class_id = p_class_id
    and cb.status <> 'cancelled'
    and not coalesce(cb.is_guest, false)
  order by p.id;
end;
$function$;
create or replace function public.is_effective_attendance_member(
  p_class_id uuid,
  p_member_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select auth.uid() is not null
    and public.effective_gym_role() = 'admin'
    and exists (
      select 1
      from public.classes c
      join public.gym_members gm
        on gm.gym_id = c.gym_id
       and gm.user_id = p_member_id
       and gm.is_active = true
      where c.id = p_class_id
        and c.gym_id = public.effective_gym_id()
    );
$function$;
create or replace function public.search_members_available_for_class(
  p_class_id uuid,
  p_query text default null
)
returns table(
  user_id uuid,
  full_name text,
  email text,
  avatar_url text,
  membership_id uuid,
  plan_name text,
  plan_type text,
  credits_remaining integer,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_class public.classes%rowtype;
  v_query text := lower(btrim(coalesce(p_query, '')));
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if p_class_id is null then raise exception 'Missing class id'; end if;
  if public.effective_gym_role() <> 'admin' then
    raise exception 'Only gym admins can search members';
  end if;

  select * into v_class
  from public.classes c
  where c.id = p_class_id
    and c.gym_id = public.effective_gym_id();
  if not found then raise exception 'Class not found'; end if;

  return query
  select
    p.id,
    p.full_name,
    p.email,
    p.avatar_url,
    mm.id,
    mp.name,
    mp.plan_type,
    mm.credits_remaining,
    coalesce(mm.expires_at, mm.ends_at)
  from public.gym_members gm
  join public.profiles p on p.id = gm.user_id
  join lateral public.select_usable_membership(p.id, v_class.gym_id) mm on true
  join public.membership_plans mp on mp.id = mm.plan_id
  where gm.gym_id = v_class.gym_id
    and gm.is_active = true
    and gm.role in ('athlete', 'admin', 'coach')
    and not exists (
      select 1 from public.class_bookings cb
      where cb.class_id = p_class_id
        and cb.user_id = p.id
        and cb.status <> 'cancelled'
    )
    and (
      v_query = ''
      or lower(coalesce(p.full_name, '')) like '%' || v_query || '%'
      or lower(coalesce(p.email, '')) like '%' || v_query || '%'
    )
  order by coalesce(nullif(btrim(p.full_name), ''), p.email, ''), gm.id
  limit 30;
end;
$function$;
create or replace function public.set_class_booking_attendance_status(
  p_booking_id uuid,
  p_expected_status text,
  p_status text
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_booking public.class_bookings%rowtype;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if public.effective_gym_role() <> 'admin' then raise exception 'Not allowed'; end if;
  if p_expected_status not in ('booked', 'attended', 'no_show')
     or p_status not in ('booked', 'attended', 'no_show') then
    raise exception 'Invalid attendance status';
  end if;

  select cb.* into v_booking
  from public.class_bookings cb
  join public.classes c on c.id = cb.class_id
  where cb.id = p_booking_id
    and c.gym_id = public.effective_gym_id()
  for update of cb;
  if not found then raise exception 'Booking not found'; end if;
  if v_booking.status is distinct from p_expected_status then return false; end if;
  if v_booking.status = p_status then return true; end if;

  update public.class_bookings cb set status = p_status where cb.id = v_booking.id;
  return true;
end;
$function$;
create or replace function public.finish_class_attendance(p_class_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_class public.classes%rowtype;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if public.effective_gym_role() <> 'admin' then raise exception 'Not allowed'; end if;
  select * into v_class from public.classes c
  where c.id = p_class_id and c.gym_id = public.effective_gym_id()
  for update;
  if not found then raise exception 'Class not found'; end if;
  update public.class_bookings cb
  set status = 'attended'
  where cb.class_id = v_class.id and cb.status = 'booked';
end;
$function$;
create or replace function public.enforce_guest_booking_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_class public.classes%rowtype;
  v_booked_count integer;
begin
  if new.is_guest is distinct from true then return new; end if;
  if auth.uid() is null then raise exception using errcode='P0001', message='unauthenticated'; end if;
  if public.effective_gym_role() <> 'admin' then raise exception using errcode='P0001', message='unauthorized'; end if;
  if new.user_id is not null
     or new.membership_id is not null
     or new.status is distinct from 'booked'
     or new.guest_name is null
     or length(btrim(new.guest_name)) = 0 then
    raise exception using errcode='P0001', message='invalid_guest';
  end if;

  select * into v_class from public.classes c
  where c.id = new.class_id and c.gym_id = public.effective_gym_id()
  for update;
  if not found then raise exception using errcode='P0001', message='class_not_found'; end if;
  if coalesce(v_class.capacity, 0) <= 0 then raise exception using errcode='P0001', message='class_full'; end if;
  select count(*) into v_booked_count from public.class_bookings cb
  where cb.class_id = v_class.id and cb.status <> 'cancelled';
  if v_booked_count >= v_class.capacity then raise exception using errcode='P0001', message='class_full'; end if;

  new.user_id := null;
  new.membership_id := null;
  new.guest_name := btrim(new.guest_name);
  new.is_guest := true;
  new.status := 'booked';
  return new;
end;
$function$;
revoke all on function public.list_effective_attendance_profiles(uuid) from public, anon;
revoke all on function public.is_effective_attendance_member(uuid, uuid) from public, anon;
revoke all on function public.search_members_available_for_class(uuid, text) from public, anon;
revoke all on function public.set_class_booking_attendance_status(uuid, text, text) from public, anon;
revoke all on function public.finish_class_attendance(uuid) from public, anon;
revoke all on function public.enforce_guest_booking_insert() from public, anon, authenticated;
grant execute on function public.list_effective_attendance_profiles(uuid) to authenticated, service_role;
grant execute on function public.is_effective_attendance_member(uuid, uuid) to authenticated, service_role;
grant execute on function public.search_members_available_for_class(uuid, text) to authenticated, service_role;
grant execute on function public.set_class_booking_attendance_status(uuid, text, text) to authenticated, service_role;
grant execute on function public.finish_class_attendance(uuid) to authenticated, service_role;
grant execute on function public.enforce_guest_booking_insert() to service_role;
