create or replace function public.notify_membership_request_admins()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_requester_name text;
  v_plan_name text;
begin
  if new.status <> 'pending' then
    return new;
  end if;

  select coalesce(
    nullif(btrim(p.full_name), ''),
    nullif(btrim(p.email), ''),
    'Member'
  )
  into v_requester_name
  from public.profiles p
  where p.id = new.user_id;

  v_requester_name := coalesce(
    nullif(btrim(v_requester_name), ''),
    'Member'
  );

  select mp.name
  into v_plan_name
  from public.membership_plans mp
  where mp.id = new.plan_id
    and mp.gym_id = new.gym_id;

  v_plan_name := coalesce(
    nullif(btrim(v_plan_name), ''),
    'Membership'
  );

  insert into public.notifications (
    user_id,
    gym_id,
    title,
    body,
    type,
    data,
    scheduled_for
  )
  select
    recipient.user_id,
    new.gym_id,
    case
      when coalesce(profile.preferred_locale, 'en') = 'es'
        then 'Nueva solicitud de membresía'
      else 'New membership request'
    end,
    case
      when coalesce(profile.preferred_locale, 'en') = 'es'
        then format('%s solicitó %s.', v_requester_name, v_plan_name)
      else format('%s requested %s.', v_requester_name, v_plan_name)
    end,
    'membership_request',
    jsonb_build_object(
      'requestId', new.id,
      'planId', new.plan_id,
      'gymId', new.gym_id,
      'section', 'membership'
    ),
    clock_timestamp()
  from (
    select gm.user_id
    from public.gym_members gm
    where gm.gym_id = new.gym_id
      and gm.role = 'admin'
      and gm.is_active = true

    union

    select g.owner_id
    from public.gyms g
    where g.id = new.gym_id
      and g.owner_id is not null
  ) recipient
  join public.profiles profile on profile.id = recipient.user_id
  where recipient.user_id is distinct from new.user_id;

  return new;
end;
$$;

revoke all on function public.notify_membership_request_admins() from public;

drop trigger if exists membership_requests_notify_admins
on public.membership_requests;

create trigger membership_requests_notify_admins
after insert on public.membership_requests
for each row
when (new.status = 'pending')
execute function public.notify_membership_request_admins();
