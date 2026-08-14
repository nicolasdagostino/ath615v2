create or replace function public.admin_add_member_to_class_waitlist(
  p_class_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_actor public.profiles%rowtype;
  v_member public.profiles%rowtype;
  v_class public.classes%rowtype;
  v_membership public.member_memberships%rowtype;
  v_booked_count integer;
  v_waitlist_count integer;
  v_capacity integer;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_class_id is null or p_user_id is null then raise exception 'invalid_request'; end if;

  select * into v_actor from public.profiles where id = auth.uid();
  if v_actor.id is null or v_actor.is_active is distinct from true
     or v_actor.role not in ('admin', 'owner') or v_actor.gym_id is null then
    raise exception 'forbidden';
  end if;

  select * into v_class
  from public.classes
  where id = p_class_id and starts_at > now()
  for update;
  if v_class.id is null or v_class.gym_id is distinct from v_actor.gym_id then
    raise exception 'class_not_found';
  end if;

  select * into v_member from public.profiles where id = p_user_id;
  if v_member.id is null or v_member.gym_id is distinct from v_class.gym_id
     or v_member.is_active is distinct from true or v_member.role = 'owner' then
    raise exception 'member_not_found';
  end if;

  if exists (
    select 1 from public.class_bookings
    where class_id = p_class_id and user_id = p_user_id and status <> 'cancelled'
  ) then raise exception 'already_booked'; end if;
  if exists (
    select 1 from public.class_waitlist
    where class_id = p_class_id and user_id = p_user_id
  ) then raise exception 'already_waitlisted'; end if;

  select count(*) into v_booked_count from public.class_bookings
  where class_id = p_class_id and status <> 'cancelled';
  v_capacity := coalesce(v_class.capacity, 0);
  if v_booked_count < v_capacity then raise exception 'class_not_full'; end if;

  select count(*) into v_waitlist_count from public.class_waitlist
  where class_id = p_class_id;
  if v_waitlist_count >= v_capacity then raise exception 'waitlist_full'; end if;

  select * into v_membership
  from public.select_usable_membership(p_user_id, v_class.gym_id);
  if v_membership.id is null then raise exception 'active_membership_required'; end if;

  insert into public.class_waitlist (class_id, user_id)
  values (p_class_id, p_user_id);
end;
$function$;
revoke all on function public.admin_add_member_to_class_waitlist(uuid, uuid) from public;
revoke all on function public.admin_add_member_to_class_waitlist(uuid, uuid) from anon;
revoke all on function public.admin_add_member_to_class_waitlist(uuid, uuid) from authenticated;
grant execute on function public.admin_add_member_to_class_waitlist(uuid, uuid) to authenticated, service_role;
