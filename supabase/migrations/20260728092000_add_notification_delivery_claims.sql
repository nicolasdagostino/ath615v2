-- Claim due notification rows atomically so concurrent workers cannot send the
-- same notification twice. The public worker endpoint derives p_gym_id from
-- the authenticated actor before invoking this service-role-only helper.

do $prerequisite$
begin
  if to_regclass('public.notifications') is null
    or to_regclass('public.profiles') is null
    or to_regclass('public.gym_join_requests') is null
  then
    raise exception
      'deployment_prerequisite_missing: notifications/profiles/gym_join_requests';
  end if;
end;
$prerequisite$;
alter table public.notifications
  add column if not exists gym_id uuid,
  add column if not exists processing_at timestamptz,
  add column if not exists processing_token uuid,
  add column if not exists delivery_attempts integer not null default 0;
-- Snapshot the recipient's gym so a queued notification cannot follow a user
-- into another gym. Existing rows use the only versioned source available.
update public.notifications n
set gym_id = p.gym_id
from public.profiles p
where p.id = n.user_id
  and n.gym_id is null;
update public.notifications n
set gym_id = r.gym_id
from public.gym_join_requests r
where n.gym_id is null
  and n.type = 'gym_join_rejected'
  and r.user_id = n.user_id
  and r.status = 'rejected'
  and r.gym_id::text = n.data ->> 'gymId';
create or replace function public.set_notification_gym_id()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  -- Never trust a caller-supplied notification gym.
  select p.gym_id
  into new.gym_id
  from public.profiles p
  where p.id = new.user_id;

  -- Rejected join requests intentionally notify a profile that still has no
  -- gym. The rejected request, not arbitrary JSON, proves the origin gym.
  if new.gym_id is null and new.type = 'gym_join_rejected' then
    select r.gym_id
    into new.gym_id
    from public.gym_join_requests r
    where r.user_id = new.user_id
      and r.status = 'rejected'
      and r.gym_id::text = new.data ->> 'gymId'
    order by r.approved_at desc nulls last, r.created_at desc
    limit 1;
  end if;

  return new;
end;
$function$;
drop trigger if exists notifications_set_gym_id
  on public.notifications;
create trigger notifications_set_gym_id
before insert on public.notifications
for each row execute function public.set_notification_gym_id();
create index if not exists notifications_pending_delivery_idx
  on public.notifications (gym_id, scheduled_for, processing_at)
  where sent_at is null;
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
        p.gym_id = n.gym_id
        or (
          p.gym_id is null
          and n.type = 'gym_join_rejected'
          and exists (
            select 1
            from public.gym_join_requests r
            where r.user_id = n.user_id
              and r.gym_id = n.gym_id
              and r.status = 'rejected'
          )
        )
      )
      and n.sent_at is null
      and n.delivery_attempts < 5
      and n.scheduled_for <= now()
      and (
        n.processing_at is null
        or n.processing_at < now() - interval '10 minutes'
      )
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
create or replace function public.complete_notification_delivery(
  p_notification_id uuid,
  p_claim_token uuid,
  p_sent boolean
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;

  update public.notifications
  set sent_at = case when p_sent then now() else sent_at end,
      processing_at = null,
      processing_token = null
  where id = p_notification_id
    and processing_token = p_claim_token;
end;
$function$;
revoke all on function public.claim_pending_notifications(uuid, uuid, integer)
  from public, anon, authenticated;
grant execute on function public.claim_pending_notifications(uuid, uuid, integer)
  to service_role;
revoke all on function public.complete_notification_delivery(uuid, uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.complete_notification_delivery(uuid, uuid, boolean)
  to service_role;
revoke all on function public.set_notification_gym_id()
  from public, anon, authenticated;
