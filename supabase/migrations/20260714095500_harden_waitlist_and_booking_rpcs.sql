create or replace function public.join_class_waitlist(
  p_class_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_user_id uuid := auth.uid();
  v_class public.classes%rowtype;
  v_membership public.member_memberships%rowtype;
  v_capacity integer;
  v_booked_count integer;
  v_waitlist_count integer;
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
  from public.select_usable_membership(
    v_user_id,
    v_class.gym_id
  );

  if v_membership.id is null then
    raise exception 'Active membership required';
  end if;

  insert into public.class_waitlist (
    class_id,
    user_id
  )
  values (
    p_class_id,
    v_user_id
  )
  on conflict (class_id, user_id) do nothing;
end;
$function$;


drop function if exists public.has_active_membership();


revoke all on function public.join_class_waitlist(uuid)
from public;

revoke all on function public.join_class_waitlist(uuid)
from anon;

revoke all on function public.join_class_waitlist(uuid)
from authenticated;

grant execute on function public.join_class_waitlist(uuid)
to authenticated, service_role;


revoke all on function public.book_class_with_membership(uuid)
from public;

revoke all on function public.book_class_with_membership(uuid)
from anon;

revoke all on function public.book_class_with_membership(uuid)
from authenticated;

grant execute on function public.book_class_with_membership(uuid)
to authenticated, service_role;


revoke all on function public.cancel_my_booking(uuid)
from public;

revoke all on function public.cancel_my_booking(uuid)
from anon;

revoke all on function public.cancel_my_booking(uuid)
from authenticated;

grant execute on function public.cancel_my_booking(uuid)
to authenticated, service_role;


revoke all on function public.admin_cancel_class_booking(uuid)
from public;

revoke all on function public.admin_cancel_class_booking(uuid)
from anon;

revoke all on function public.admin_cancel_class_booking(uuid)
from authenticated;

grant execute on function public.admin_cancel_class_booking(uuid)
to authenticated, service_role;


revoke all on function public.promote_first_waitlisted_user(uuid)
from public;

revoke all on function public.promote_first_waitlisted_user(uuid)
from anon;

revoke all on function public.promote_first_waitlisted_user(uuid)
from authenticated;

grant execute on function public.promote_first_waitlisted_user(uuid)
to service_role;


