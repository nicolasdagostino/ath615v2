-- Enforce the existing Flutter guest-booking contract at the database boundary.
-- The class row lock serializes all booking paths that already lock classes and
-- prevents concurrent guest inserts from taking the same final place.

create index if not exists class_bookings_active_class_idx
on public.class_bookings (class_id)
where status <> 'cancelled';
create or replace function public.enforce_guest_booking_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_actor public.profiles%rowtype;
  v_class public.classes%rowtype;
  v_booked_count integer;
begin
  if new.is_guest is distinct from true then
    return new;
  end if;

  if auth.uid() is null then
    raise exception using errcode = 'P0001', message = 'unauthenticated';
  end if;

  select *
  into v_actor
  from public.profiles p
  where p.id = auth.uid();

  if v_actor.id is null or v_actor.role not in ('admin', 'owner') then
    raise exception using errcode = 'P0001', message = 'unauthorized';
  end if;

  if v_actor.is_active is distinct from true then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;

  if new.user_id is not null
     or new.membership_id is not null
     or new.status is distinct from 'booked'
     or new.guest_name is null
     or length(trim(new.guest_name)) = 0 then
    raise exception using errcode = 'P0001', message = 'invalid_guest';
  end if;

  select *
  into v_class
  from public.classes c
  where c.id = new.class_id
    and c.gym_id = v_actor.gym_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'class_not_found';
  end if;

  if coalesce(v_class.capacity, 0) <= 0 then
    raise exception using errcode = 'P0001', message = 'class_full';
  end if;

  select count(*)
  into v_booked_count
  from public.class_bookings cb
  where cb.class_id = v_class.id
    and cb.status <> 'cancelled';

  if v_booked_count >= v_class.capacity then
    raise exception using errcode = 'P0001', message = 'class_full';
  end if;

  new.user_id := null;
  new.membership_id := null;
  new.guest_name := trim(new.guest_name);
  new.is_guest := true;
  new.status := 'booked';

  return new;
end;
$function$;
revoke all on function public.enforce_guest_booking_insert() from public;
revoke all on function public.enforce_guest_booking_insert() from anon;
revoke all on function public.enforce_guest_booking_insert() from authenticated;
drop trigger if exists enforce_guest_booking_insert on public.class_bookings;
create trigger enforce_guest_booking_insert
before insert on public.class_bookings
for each row
when (new.is_guest = true)
execute function public.enforce_guest_booking_insert();
