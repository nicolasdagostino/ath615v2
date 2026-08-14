-- Stripe 1: reproducible, effective-gym-safe and idempotent payment plumbing.
-- Card payments remain feature-flagged off in Flutter.

begin;

alter table public.membership_requests
  add column if not exists stripe_checkout_expires_at timestamptz,
  add column if not exists stripe_plan_name text;

do $$
begin
  if exists (
    select 1
    from public.gyms
    where stripe_account_id is not null
    group by stripe_account_id
    having count(*) > 1
  ) then
    raise exception 'duplicate Stripe account assigned to multiple gyms';
  end if;
end;
$$;

drop index if exists public.gyms_stripe_account_id_idx;
create unique index if not exists gyms_stripe_account_id_unique_idx
on public.gyms(stripe_account_id)
where stripe_account_id is not null;

create table if not exists public.stripe_webhook_events (
  stripe_event_id text not null,
  stripe_account_id text not null,
  gym_id uuid not null references public.gyms(id) on delete restrict,
  event_type text not null,
  status text not null default 'processing',
  attempt_count integer not null default 1,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  last_error_code text,
  primary key (stripe_account_id, stripe_event_id),
  constraint stripe_webhook_events_status_check
    check (status in ('processing', 'processed', 'ignored', 'failed')),
  constraint stripe_webhook_events_attempt_count_check
    check (attempt_count > 0),
  constraint stripe_webhook_events_identity_check
    check (
      nullif(btrim(stripe_event_id), '') is not null
      and nullif(btrim(stripe_account_id), '') is not null
      and nullif(btrim(event_type), '') is not null
    )
);

create index if not exists stripe_webhook_events_received_idx
on public.stripe_webhook_events(received_at desc);

alter table public.stripe_webhook_events enable row level security;
revoke all on table public.stripe_webhook_events
from public, anon, authenticated;
grant select, insert, update on table public.stripe_webhook_events
to service_role;

create or replace function public.get_effective_stripe_connect_context()
returns table(
  gym_id uuid,
  gym_name text,
  gym_email text,
  business_name text,
  stripe_account_id text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_gym_id uuid := public.effective_gym_id();
begin
  if v_user_id is null or v_gym_id is null then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.gyms g
    where g.id = v_gym_id
      and (
        g.owner_id = v_user_id
        or exists (
          select 1
          from public.gym_members gm
          where gm.gym_id = g.id
            and gm.user_id = v_user_id
            and gm.role = 'admin'
            and gm.is_active = true
        )
      )
  ) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  return query
  select g.id, g.name, g.email, g.business_name, g.stripe_account_id
  from public.gyms g
  where g.id = v_gym_id;
end;
$function$;

revoke all on function public.get_effective_stripe_connect_context()
from public, anon, authenticated, service_role;
grant execute on function public.get_effective_stripe_connect_context()
to authenticated, service_role;

create or replace function public.prepare_card_membership_checkout(
  p_plan_id uuid
)
returns table(
  request_id uuid,
  gym_id uuid,
  plan_id uuid,
  plan_name text,
  amount_total integer,
  currency text,
  stripe_account_id text,
  existing_session_id text,
  existing_session_expires_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_gym_id uuid := public.effective_gym_id();
  v_plan public.membership_plans%rowtype;
  v_gym public.gyms%rowtype;
  v_request public.membership_requests%rowtype;
  v_amount_total integer;
begin
  if v_user_id is null or v_gym_id is null
     or not public.membership_actor_is_active() then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.gym_members gm
    where gm.user_id = v_user_id
      and gm.gym_id = v_gym_id
      and gm.is_active = true
  ) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select *
  into v_plan
  from public.membership_plans mp
  where mp.id = p_plan_id
    and mp.gym_id = v_gym_id
    and mp.is_active = true;

  if not found then
    raise exception 'plan_not_found' using errcode = 'P0001';
  end if;

  if v_plan.price is null or v_plan.price <= 0 then
    raise exception 'invalid_plan_price' using errcode = 'P0001';
  end if;

  select *
  into v_gym
  from public.gyms g
  where g.id = v_gym_id;

  if not found
     or nullif(btrim(v_gym.stripe_account_id), '') is null
     or v_gym.stripe_charges_enabled is distinct from true
     or v_gym.stripe_payouts_enabled is distinct from true then
    raise exception 'stripe_account_not_ready' using errcode = 'P0001';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_user_id::text || ':' || v_gym_id::text || ':' || p_plan_id::text,
      619
    )
  );

  select *
  into v_request
  from public.membership_requests mr
  where mr.user_id = v_user_id
    and mr.gym_id = v_gym_id
    and mr.plan_id = p_plan_id
    and mr.status = 'pending'
  for update;

  if found and v_request.payment_method <> 'card' then
    raise exception 'request_pending' using errcode = 'P0001';
  end if;

  v_amount_total := round(v_plan.price * 100)::integer;

  if not found then
    insert into public.membership_requests (
      user_id,
      gym_id,
      plan_id,
      status,
      payment_method,
      payment_status,
      amount_total,
      currency,
      stripe_plan_name
    )
    values (
      v_user_id,
      v_gym_id,
      v_plan.id,
      'pending',
      'card',
      'pending',
      v_amount_total,
      lower(v_plan.currency),
      v_plan.name
    )
    returning * into v_request;
  elsif v_request.stripe_checkout_session_id is null then
    update public.membership_requests mr
    set amount_total = coalesce(mr.amount_total, v_amount_total),
        currency = coalesce(mr.currency, lower(v_plan.currency)),
        stripe_plan_name = coalesce(mr.stripe_plan_name, v_plan.name)
    where mr.id = v_request.id
    returning * into v_request;
  end if;

  return query
  select
    v_request.id,
    v_gym_id,
    v_plan.id,
    coalesce(v_request.stripe_plan_name, v_plan.name),
    v_request.amount_total,
    lower(v_request.currency),
    v_gym.stripe_account_id,
    v_request.stripe_checkout_session_id,
    v_request.stripe_checkout_expires_at;
end;
$function$;

revoke all on function public.prepare_card_membership_checkout(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.prepare_card_membership_checkout(uuid)
to authenticated, service_role;

create or replace function public.attach_card_membership_checkout_session(
  p_request_id uuid,
  p_checkout_session_id text,
  p_amount_total integer,
  p_currency text,
  p_stripe_account_id text,
  p_expires_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_request public.membership_requests%rowtype;
  v_gym public.gyms%rowtype;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if nullif(btrim(p_checkout_session_id), '') is null
     or nullif(btrim(p_stripe_account_id), '') is null
     or p_amount_total is null
     or p_expires_at is null then
    raise exception 'invalid_checkout_session' using errcode = '22023';
  end if;

  select *
  into v_request
  from public.membership_requests mr
  where mr.id = p_request_id
  for update;

  if not found
     or v_request.status <> 'pending'
     or v_request.payment_method <> 'card'
     or v_request.payment_status <> 'pending' then
    raise exception 'pending_card_request_not_found' using errcode = 'P0001';
  end if;

  select * into v_gym
  from public.gyms g
  where g.id = v_request.gym_id;

  if not found
     or v_gym.stripe_account_id is distinct from p_stripe_account_id then
    raise exception 'stripe_account_mismatch' using errcode = 'P0001';
  end if;

  if v_request.amount_total is distinct from p_amount_total
     or lower(v_request.currency) is distinct from lower(p_currency) then
    raise exception 'checkout_amount_mismatch' using errcode = 'P0001';
  end if;

  if v_request.stripe_checkout_session_id is not null
     and v_request.stripe_checkout_session_id <> p_checkout_session_id then
    raise exception 'checkout_session_already_attached' using errcode = 'P0001';
  end if;

  update public.membership_requests
  set stripe_checkout_session_id = p_checkout_session_id,
      stripe_checkout_expires_at = p_expires_at
  where id = v_request.id;
end;
$function$;

revoke all on function public.attach_card_membership_checkout_session(
  uuid, text, integer, text, text, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function public.attach_card_membership_checkout_session(
  uuid, text, integer, text, text, timestamptz
) to service_role;

create or replace function public.claim_stripe_webhook_event(
  p_event_id text,
  p_event_type text,
  p_stripe_account_id text
)
returns table(claimed boolean, gym_id uuid)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid;
  v_event public.stripe_webhook_events%rowtype;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if nullif(btrim(p_event_id), '') is null
     or nullif(btrim(p_event_type), '') is null
     or nullif(btrim(p_stripe_account_id), '') is null then
    raise exception 'invalid_stripe_event' using errcode = '22023';
  end if;

  select g.id into v_gym_id
  from public.gyms g
  where g.stripe_account_id = p_stripe_account_id;

  if not found then
    raise exception 'stripe_account_not_found' using errcode = 'P0001';
  end if;

  insert into public.stripe_webhook_events (
    stripe_event_id,
    stripe_account_id,
    gym_id,
    event_type
  )
  values (p_event_id, p_stripe_account_id, v_gym_id, p_event_type)
  on conflict (stripe_account_id, stripe_event_id) do nothing
  returning * into v_event;

  if found then
    return query select true, v_gym_id;
    return;
  end if;

  select * into v_event
  from public.stripe_webhook_events e
  where e.stripe_account_id = p_stripe_account_id
    and e.stripe_event_id = p_event_id
  for update;

  if v_event.event_type <> p_event_type
     or v_event.gym_id <> v_gym_id then
    raise exception 'stripe_event_identity_mismatch' using errcode = 'P0001';
  end if;

  if v_event.status = 'failed'
     or (
       v_event.status = 'processing'
       and v_event.received_at < now() - interval '5 minutes'
     ) then
    update public.stripe_webhook_events
    set status = 'processing',
        attempt_count = attempt_count + 1,
        received_at = now(),
        processed_at = null,
        last_error_code = null
    where stripe_account_id = p_stripe_account_id
      and stripe_event_id = p_event_id;
    return query select true, v_gym_id;
    return;
  end if;

  return query select false, v_gym_id;
end;
$function$;

create or replace function public.complete_stripe_webhook_event(
  p_event_id text,
  p_stripe_account_id text,
  p_status text,
  p_error_code text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if p_status not in ('processed', 'ignored', 'failed') then
    raise exception 'invalid_stripe_event_status' using errcode = '22023';
  end if;

  update public.stripe_webhook_events
  set status = p_status,
      processed_at = now(),
      last_error_code = case
        when p_error_code is null then null
        else left(p_error_code, 120)
      end
  where stripe_event_id = p_event_id
    and stripe_account_id = p_stripe_account_id
    and status = 'processing';

  if not found then
    raise exception 'stripe_event_not_claimed' using errcode = 'P0001';
  end if;
end;
$function$;

revoke all on function public.claim_stripe_webhook_event(text, text, text)
from public, anon, authenticated, service_role;
grant execute on function public.claim_stripe_webhook_event(text, text, text)
to service_role;

revoke all on function public.complete_stripe_webhook_event(
  text, text, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.complete_stripe_webhook_event(
  text, text, text, text
) to service_role;

-- Webhook-only/internal routines must never be callable by app users.
revoke all on function public.complete_card_membership_request(
  text, text, integer, text, text
) from public, anon, authenticated;
grant execute on function public.complete_card_membership_request(
  text, text, integer, text, text
) to service_role;

revoke all on function public.cancel_expired_card_membership_request(
  text, text
) from public, anon, authenticated;
grant execute on function public.cancel_expired_card_membership_request(
  text, text
) to service_role;

revoke all on function public.create_member_membership_from_plan(
  uuid, uuid, text
) from public, anon, authenticated;
grant execute on function public.create_member_membership_from_plan(
  uuid, uuid, text
) to service_role;

revoke all on function public.create_member_membership_from_plan(
  uuid, uuid, text, uuid
) from public, anon, authenticated;
grant execute on function public.create_member_membership_from_plan(
  uuid, uuid, text, uuid
) to service_role;

-- Manual cash approval remains an authenticated admin operation.
revoke all on function public.approve_cash_membership_request(uuid)
from public, anon;
grant execute on function public.approve_cash_membership_request(uuid)
to authenticated, service_role;

commit;
