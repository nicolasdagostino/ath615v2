create or replace function public.select_usable_membership(
  p_user_id uuid,
  p_gym_id uuid
)
returns public.member_memberships
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_membership public.member_memberships%rowtype;
begin
  if p_user_id is null then
    raise exception 'Missing user id';
  end if;

  if p_gym_id is null then
    raise exception 'Missing gym id';
  end if;

  select mm.*
  into v_membership
  from public.member_memberships mm
  join public.membership_plans mp
    on mp.id = mm.plan_id
  where mm.user_id = p_user_id
    and mm.gym_id = p_gym_id
    and mm.is_active = true
    and mm.status = 'active'
    and coalesce(mm.starts_at, mm.created_at) <= now()
    and (
      coalesce(mm.expires_at, mm.ends_at) is null
      or coalesce(mm.expires_at, mm.ends_at) > now()
    )
    and (
      mp.plan_type = 'unlimited'
      or (
        mp.plan_type = 'class_pack'
        and mm.credits_remaining > 0
      )
    )
  order by
    case
      when mp.plan_type = 'unlimited' then 0
      else 1
    end,
    coalesce(
      mm.expires_at,
      mm.ends_at,
      'infinity'::timestamptz
    ) asc,
    mm.created_at asc
  limit 1
  for update of mm;

  return v_membership;
end;
$function$;

revoke all on function public.select_usable_membership(
  uuid,
  uuid
) from public;

revoke all on function public.select_usable_membership(
  uuid,
  uuid
) from anon;

revoke all on function public.select_usable_membership(
  uuid,
  uuid
) from authenticated;


create or replace function public.get_current_usable_membership()
returns table (
  membership_id uuid,
  plan_id uuid,
  plan_name text,
  plan_type text,
  credits_remaining integer,
  starts_at timestamptz,
  expires_at timestamptz,
  status text
)
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_user_id uuid := auth.uid();
  v_gym_id uuid;
  v_membership public.member_memberships%rowtype;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select gym_id
  into v_gym_id
  from public.profiles
  where id = v_user_id;

  if v_gym_id is null then
    return;
  end if;

  select *
  into v_membership
  from public.select_usable_membership(
    v_user_id,
    v_gym_id
  );

  if v_membership.id is null then
    return;
  end if;

  return query
  select
    v_membership.id,
    mp.id,
    mp.name,
    mp.plan_type,
    v_membership.credits_remaining,
    v_membership.starts_at,
    coalesce(
      v_membership.expires_at,
      v_membership.ends_at
    ),
    v_membership.status
  from public.membership_plans mp
  where mp.id = v_membership.plan_id;
end;
$function$;

revoke all on function public.get_current_usable_membership()
from public;

revoke all on function public.get_current_usable_membership()
from anon;

grant execute on function public.get_current_usable_membership()
to authenticated;


create or replace function public.book_class_with_membership(
  p_class_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_user_id uuid := auth.uid();
  v_membership public.member_memberships%rowtype;
  v_class public.classes%rowtype;
  v_booked_count integer;
  v_capacity integer;
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
  from public.select_usable_membership(
    v_user_id,
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

  insert into public.class_bookings (
    class_id,
    user_id,
    status,
    membership_id
  )
  values (
    p_class_id,
    v_user_id,
    'booked',
    v_membership.id
  );
end;
$function$;


create or replace function public.promote_first_waitlisted_user(
  p_class_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_class public.classes%rowtype;
  v_capacity integer;
  v_booked_count integer;
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
    from public.select_usable_membership(
      v_waitlist_row.user_id,
      v_class.gym_id
    );

    if v_membership.id is null then
      continue;
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
        v_waitlist_row.user_id,
        v_membership.gym_id,
        v_membership.id,
        -1,
        'waitlist_promoted',
        p_class_id
      );
    end if;

    insert into public.class_bookings (
      class_id,
      user_id,
      status,
      membership_id
    )
    values (
      p_class_id,
      v_waitlist_row.user_id,
      'booked',
      v_membership.id
    );

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
        when v_preferred_locale = 'es'
          then '🎉 ¡Conseguiste una plaza!'
        else '🎉 You got a spot!'
      end,
      case
        when v_preferred_locale = 'es' then format(
          'Se liberó una plaza para %s a las %s.',
          v_class.title,
          to_char(
            v_class.starts_at at time zone 'UTC',
            'HH24:MI'
          )
        )
        else format(
          'A spot opened up for %s at %s.',
          v_class.title,
          to_char(
            v_class.starts_at at time zone 'UTC',
            'HH24:MI'
          )
        )
      end,
      'waitlist_promoted',
      jsonb_build_object('classId', p_class_id),
      now()
    );

    return;
  end loop;
end;
$function$;
