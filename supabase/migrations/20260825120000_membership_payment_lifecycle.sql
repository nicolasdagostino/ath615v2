-- Stripe 2: explicit and auditable membership payment lifecycle.
-- Card payments remain disabled in Flutter.

begin;

alter table public.membership_requests
  add column if not exists manual_payment_method text,
  add column if not exists payment_confirmed_by uuid references public.profiles(id) on delete set null,
  add column if not exists payment_confirmed_at timestamptz,
  add column if not exists member_membership_id uuid references public.member_memberships(id) on delete set null;

alter table public.membership_requests
  drop constraint if exists membership_requests_manual_payment_method_check;
alter table public.membership_requests
  add constraint membership_requests_manual_payment_method_check
  check (manual_payment_method is null or manual_payment_method in ('cash', 'bizum'));

create unique index if not exists membership_requests_member_membership_unique_idx
on public.membership_requests(member_membership_id)
where member_membership_id is not null;

create or replace function public.notify_membership_request_admins()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_requester_name text;
  v_plan_name text;
begin
  if new.status <> 'pending' or new.payment_method <> 'cash' then
    return new;
  end if;

  select coalesce(nullif(btrim(p.full_name), ''), nullif(btrim(p.email), ''), 'Member')
  into v_requester_name
  from public.profiles p
  where p.id = new.user_id;
  v_requester_name := coalesce(nullif(btrim(v_requester_name), ''), 'Member');

  select mp.name into v_plan_name
  from public.membership_plans mp
  where mp.id = new.plan_id and mp.gym_id = new.gym_id;
  v_plan_name := coalesce(nullif(btrim(v_plan_name), ''), 'Membership');

  insert into public.notifications(user_id, gym_id, title, body, type, data, scheduled_for)
  select recipient.user_id, new.gym_id,
    case when coalesce(p.preferred_locale, 'en') = 'es'
      then 'Nueva solicitud de membresía' else 'New membership request' end,
    case when coalesce(p.preferred_locale, 'en') = 'es'
      then format('%s solicitó %s.', v_requester_name, v_plan_name)
      else format('%s requested %s.', v_requester_name, v_plan_name) end,
    'membership_request',
    jsonb_build_object('requestId', new.id, 'planId', new.plan_id,
      'gymId', new.gym_id, 'section', 'membership'),
    clock_timestamp()
  from (
    select gm.user_id from public.gym_members gm
    where gm.gym_id = new.gym_id and gm.role = 'admin' and gm.is_active = true
    union
    select g.owner_id from public.gyms g
    where g.id = new.gym_id and g.owner_id is not null
  ) recipient
  join public.profiles p on p.id = recipient.user_id
  where recipient.user_id is distinct from new.user_id;
  return new;
end;
$function$;

create or replace function public.create_cash_membership_request(p_plan_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_gym_id uuid := public.effective_gym_id();
  v_plan public.membership_plans%rowtype;
  v_request_id uuid;
begin
  if v_user_id is null or v_gym_id is null or not public.membership_actor_is_active() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user_id::text || ':' || v_gym_id::text || ':' || p_plan_id::text, 618)
  );
  select * into v_plan from public.membership_plans
  where id = p_plan_id and gym_id = v_gym_id and is_active = true;
  if not found then raise exception 'plan_not_found' using errcode = 'P0001'; end if;
  if exists(select 1 from public.membership_requests
    where user_id = v_user_id and gym_id = v_gym_id and plan_id = p_plan_id and status = 'pending') then
    raise exception 'request_pending' using errcode = 'P0001';
  end if;
  insert into public.membership_requests(
    user_id, gym_id, plan_id, status, payment_method, payment_status,
    amount_total, currency, stripe_plan_name
  ) values (
    v_user_id, v_gym_id, p_plan_id, 'pending', 'cash', 'pending',
    round(v_plan.price * 100)::integer, lower(v_plan.currency), v_plan.name
  ) returning id into v_request_id;
  return v_request_id;
end;
$function$;

create or replace function public.list_effective_membership_requests(
  p_own boolean default false, p_limit integer default 50
)
returns table(
  request_id uuid, user_id uuid, plan_id uuid, status text,
  payment_method text, payment_status text, created_at timestamptz,
  member_name text, member_email text, plan_name text, plan_type text,
  plan_price numeric, currency text
)
language plpgsql stable security definer set search_path = public, pg_temp
as $function$
declare v_gym_id uuid := public.effective_gym_id();
begin
  if auth.uid() is null or v_gym_id is null or not public.membership_actor_is_active()
     or p_limit < 1 or p_limit > 100 then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if not p_own and not public.membership_actor_can_manage() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return query
  select mr.id, mr.user_id, mr.plan_id, mr.status, mr.payment_method,
    mr.payment_status, mr.created_at,
    case when p_own then null else p.full_name end,
    case when p_own then null else p.email end,
    coalesce(mr.stripe_plan_name, mp.name), mp.plan_type,
    coalesce(mr.amount_total::numeric / 100, mp.price),
    coalesce(mr.currency, mp.currency)
  from public.membership_requests mr
  join public.membership_plans mp on mp.id = mr.plan_id and mp.gym_id = mr.gym_id
  left join public.profiles p on p.id = mr.user_id
  where mr.gym_id = v_gym_id
    and (not p_own or mr.user_id = auth.uid())
    and (p_own or (mr.status = 'pending' and mr.payment_method = 'cash'))
  order by mr.created_at desc, mr.id desc limit p_limit;
end;
$function$;

create or replace function public.confirm_in_person_membership_payment(
  p_request_id uuid, p_manual_payment_method text
)
returns table(request_status text, payment_status text, membership_id uuid, membership_status text)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_gym_id uuid := public.effective_gym_id();
  v_request public.membership_requests%rowtype;
  v_member public.profiles%rowtype;
  v_plan public.membership_plans%rowtype;
  v_membership public.member_memberships%rowtype;
  v_is_spanish boolean;
begin
  if v_actor_id is null or v_gym_id is null or not public.membership_actor_can_manage() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_manual_payment_method not in ('cash', 'bizum') then
    raise exception 'invalid_manual_payment_method' using errcode = '22023';
  end if;
  select * into v_request from public.membership_requests
  where id = p_request_id and gym_id = v_gym_id for update;
  if not found then raise exception 'request_not_found' using errcode = 'P0002'; end if;
  if v_request.status = 'approved' and v_request.payment_status = 'paid'
     and v_request.member_membership_id is not null then
    return query select v_request.status, v_request.payment_status,
      v_request.member_membership_id, mm.status
    from public.member_memberships mm where mm.id = v_request.member_membership_id;
    return;
  end if;
  if v_request.payment_method <> 'cash' or v_request.status <> 'pending'
     or v_request.payment_status <> 'pending' then
    raise exception 'request_not_pending_in_person' using errcode = 'P0001';
  end if;
  if not exists(select 1 from public.gym_members gm
    where gm.gym_id = v_gym_id and gm.user_id = v_request.user_id and gm.is_active = true) then
    raise exception 'member_not_found' using errcode = 'P0001';
  end if;
  select * into v_member from public.profiles where id = v_request.user_id for update;
  select * into v_plan from public.membership_plans
  where id = v_request.plan_id and gym_id = v_gym_id;
  if not found then raise exception 'plan_not_found' using errcode = 'P0001'; end if;
  select * into v_membership from public.create_member_membership_from_plan(
    v_request.user_id, v_request.plan_id, 'paid', v_gym_id
  );
  update public.membership_requests set
    status = 'approved', payment_status = 'paid',
    manual_payment_method = p_manual_payment_method,
    payment_confirmed_by = v_actor_id, payment_confirmed_at = now(),
    paid_at = now(), member_membership_id = v_membership.id,
    amount_total = coalesce(amount_total, round(v_plan.price * 100)::integer),
    currency = coalesce(currency, lower(v_plan.currency)),
    stripe_plan_name = coalesce(stripe_plan_name, v_plan.name)
  where id = v_request.id;
  v_is_spanish := coalesce(v_member.preferred_locale, 'en') = 'es';
  insert into public.notifications(user_id, gym_id, title, body, type, data, scheduled_for)
  values (
    v_request.user_id, v_gym_id,
    case when v_membership.status = 'scheduled' and v_is_spanish then 'Membresía programada'
         when v_membership.status = 'scheduled' then 'Membership scheduled'
         when v_is_spanish then 'Nueva membresía' else 'New membership' end,
    case when v_membership.status = 'scheduled' and v_is_spanish
           then format('Tu pago fue confirmado. El plan %s comenzará próximamente.', v_plan.name)
         when v_membership.status = 'scheduled'
           then format('Your payment was confirmed. The %s plan will start soon.', v_plan.name)
         when v_is_spanish then format('Tu pago fue confirmado y se activó el plan %s.', v_plan.name)
         else format('Your payment was confirmed and the %s plan is active.', v_plan.name) end,
    case when v_membership.status = 'scheduled' then 'membership_scheduled' else 'membership_payment_completed' end,
    jsonb_build_object('planId', v_plan.id, 'requestId', v_request.id,
      'paymentMethod', 'in_person', 'manualPaymentMethod', p_manual_payment_method,
      'membershipId', v_membership.id, 'membershipStatus', v_membership.status,
      'startsAt', v_membership.starts_at), now()
  );
  return query select 'approved'::text, 'paid'::text, v_membership.id, v_membership.status;
end;
$function$;

create or replace function public.approve_cash_membership_request(p_request_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp
as $function$
begin
  perform public.confirm_in_person_membership_payment(p_request_id, 'cash');
end;
$function$;

create or replace function public.reject_membership_request(p_request_id uuid)
returns boolean language plpgsql security definer set search_path = public, pg_temp
as $function$
declare v_gym_id uuid := public.effective_gym_id();
begin
  if auth.uid() is null or v_gym_id is null or not public.membership_actor_can_manage() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  update public.membership_requests
  set status = 'rejected', payment_status = 'cancelled'
  where id = p_request_id and gym_id = v_gym_id and status = 'pending'
    and payment_method = 'cash' and payment_status = 'pending';
  return found;
end;
$function$;

create or replace function public.fail_card_membership_request(
  p_checkout_session_id text, p_stripe_account_id text
)
returns void language plpgsql security definer set search_path = public, pg_temp
as $function$
declare v_request public.membership_requests%rowtype; v_account text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  select mr.* into v_request
  from public.membership_requests mr
  where mr.stripe_checkout_session_id = p_checkout_session_id for update;
  if not found then raise exception 'request_not_found' using errcode = 'P0002'; end if;
  select g.stripe_account_id into v_account from public.gyms g where g.id = v_request.gym_id;
  if v_account is distinct from p_stripe_account_id then
    raise exception 'stripe_account_mismatch' using errcode = 'P0001';
  end if;
  if v_request.status = 'approved' and v_request.payment_status = 'paid' then return; end if;
  if v_request.status = 'cancelled' and v_request.payment_status = 'failed' then return; end if;
  if v_request.status <> 'pending' or v_request.payment_status <> 'pending'
     or v_request.payment_method <> 'card' then
    raise exception 'request_not_pending_card' using errcode = 'P0001';
  end if;
  update public.membership_requests
  set status = 'cancelled', payment_status = 'failed'
  where id = v_request.id;
end;
$function$;

-- Replace card completion to link the single created membership to its request.
create or replace function public.complete_card_membership_request(
  p_checkout_session_id text, p_payment_intent_id text, p_amount_total integer,
  p_currency text, p_stripe_account_id text
)
returns void language plpgsql security definer set search_path = public, pg_temp
as $function$
declare
  v_request public.membership_requests%rowtype; v_member public.profiles%rowtype;
  v_plan public.membership_plans%rowtype; v_gym public.gyms%rowtype;
  v_membership public.member_memberships%rowtype; v_is_spanish boolean;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'forbidden' using errcode = '42501'; end if;
  if nullif(btrim(p_checkout_session_id), '') is null or nullif(btrim(p_payment_intent_id), '') is null
     or nullif(btrim(p_stripe_account_id), '') is null then raise exception 'invalid_payment' using errcode = '22023'; end if;
  select * into v_request from public.membership_requests
  where stripe_checkout_session_id = p_checkout_session_id for update;
  if not found then raise exception 'request_not_found' using errcode = 'P0002'; end if;
  if v_request.payment_method <> 'card' then raise exception 'not_card_payment' using errcode = 'P0001'; end if;
  if v_request.status = 'approved' and v_request.payment_status = 'paid'
     and v_request.member_membership_id is not null then return; end if;
  if v_request.status <> 'pending' or v_request.payment_status <> 'pending' then
    raise exception 'request_not_pending' using errcode = 'P0001';
  end if;
  if p_amount_total is distinct from v_request.amount_total
     or lower(p_currency) is distinct from lower(v_request.currency) then
    raise exception 'payment_amount_mismatch' using errcode = 'P0001';
  end if;
  select * into v_gym from public.gyms where id = v_request.gym_id;
  if v_gym.stripe_account_id is distinct from p_stripe_account_id then
    raise exception 'stripe_account_mismatch' using errcode = 'P0001';
  end if;
  if not exists(select 1 from public.gym_members gm
    where gm.gym_id = v_request.gym_id and gm.user_id = v_request.user_id and gm.is_active = true) then
    raise exception 'member_not_found' using errcode = 'P0001';
  end if;
  select * into v_member from public.profiles where id = v_request.user_id for update;
  select * into v_plan from public.membership_plans
  where id = v_request.plan_id and gym_id = v_request.gym_id;
  select * into v_membership from public.create_member_membership_from_plan(
    v_request.user_id, v_request.plan_id, 'paid', v_request.gym_id
  );
  update public.membership_requests set status = 'approved', payment_status = 'paid',
    stripe_payment_intent_id = p_payment_intent_id, paid_at = now(),
    member_membership_id = v_membership.id
  where id = v_request.id;
  v_is_spanish := coalesce(v_member.preferred_locale, 'en') = 'es';
  insert into public.notifications(user_id, gym_id, title, body, type, data, scheduled_for)
  values(v_request.user_id, v_request.gym_id,
    case when v_membership.status = 'scheduled' and v_is_spanish then 'Membresía programada'
         when v_membership.status = 'scheduled' then 'Membership scheduled'
         when v_is_spanish then 'Pago completado' else 'Payment completed' end,
    case when v_membership.status = 'scheduled' and v_is_spanish
           then format('Tu pago fue confirmado. El plan %s comenzará próximamente.', v_plan.name)
         when v_membership.status = 'scheduled'
           then format('Your payment was confirmed. The %s plan will start soon.', v_plan.name)
         when v_is_spanish then format('Tu pago fue confirmado y se activó el plan %s.', v_plan.name)
         else format('Your payment was confirmed and the %s plan is active.', v_plan.name) end,
    case when v_membership.status = 'scheduled' then 'membership_scheduled' else 'membership_payment_completed' end,
    jsonb_build_object('planId', v_plan.id, 'requestId', v_request.id,
      'paymentMethod', 'card', 'checkoutSessionId', p_checkout_session_id,
      'membershipId', v_membership.id, 'membershipStatus', v_membership.status,
      'startsAt', v_membership.starts_at), now());
end;
$function$;

-- Direct assignment is not a sale; it creates a membership and one neutral notification.
create or replace function public.assign_membership_plan(p_user_id uuid, p_plan_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp
as $function$
declare
  v_actor_id uuid := auth.uid(); v_gym_id uuid := public.effective_gym_id();
  v_membership public.member_memberships%rowtype; v_plan public.membership_plans%rowtype;
  v_target public.profiles%rowtype; v_locale text;
begin
  if v_actor_id is null or v_gym_id is null or not public.membership_actor_can_manage() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if not exists(select 1 from public.gym_members gm
    where gm.gym_id = v_gym_id and gm.user_id = p_user_id and gm.is_active = true) then
    raise exception 'member_not_found' using errcode = 'P0001';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_gym_id::text, 615));
  select * into v_target from public.profiles where id = p_user_id for update;
  if not found or v_target.role = 'owner' then
    raise exception 'member_not_found' using errcode = 'P0001';
  end if;
  select * into v_plan from public.membership_plans
  where id = p_plan_id and gym_id = v_gym_id and is_active = true;
  if not found then raise exception 'plan_not_found' using errcode = 'P0001'; end if;
  select * into v_membership from public.create_member_membership_from_plan(
    p_user_id, p_plan_id, 'assigned', v_gym_id
  );
  select coalesce(preferred_locale, 'en') into v_locale from public.profiles where id = p_user_id;
  insert into public.notifications(user_id, gym_id, title, body, type, data, scheduled_for)
  values(p_user_id, v_gym_id,
    case when v_membership.status = 'scheduled' and v_locale = 'es' then 'Membresía programada'
         when v_membership.status = 'scheduled' then 'Membership scheduled'
         when v_locale = 'es' then 'Nueva membresía' else 'New membership' end,
    case when v_membership.status = 'scheduled' and v_locale = 'es'
           then format('Se te asignó el plan %s. Comenzará próximamente.', v_plan.name)
         when v_membership.status = 'scheduled'
           then format('The %s plan was assigned to you and will start soon.', v_plan.name)
         when v_locale = 'es' then format('Se te asignó el plan %s.', v_plan.name)
         else format('The %s plan was assigned to you.', v_plan.name) end,
    case when v_membership.status = 'scheduled' then 'membership_scheduled' else 'membership_approved' end,
    jsonb_build_object('planId', v_plan.id, 'assignmentType', 'direct',
      'membershipId', v_membership.id, 'membershipStatus', v_membership.status,
      'startsAt', v_membership.starts_at), now());
end;
$function$;

revoke all on function public.confirm_in_person_membership_payment(uuid, text) from public, anon, authenticated, service_role;
grant execute on function public.confirm_in_person_membership_payment(uuid, text) to authenticated, service_role;
revoke all on function public.approve_cash_membership_request(uuid) from public, anon, authenticated, service_role;
grant execute on function public.approve_cash_membership_request(uuid) to authenticated, service_role;
revoke all on function public.reject_membership_request(uuid) from public, anon, authenticated, service_role;
grant execute on function public.reject_membership_request(uuid) to authenticated, service_role;
revoke all on function public.fail_card_membership_request(text, text) from public, anon, authenticated, service_role;
grant execute on function public.fail_card_membership_request(text, text) to service_role;
revoke all on function public.complete_card_membership_request(text, text, integer, text, text) from public, anon, authenticated, service_role;
grant execute on function public.complete_card_membership_request(text, text, integer, text, text) to service_role;
revoke all on function public.assign_membership_plan(uuid, uuid) from public, anon, authenticated, service_role;
grant execute on function public.assign_membership_plan(uuid, uuid) to authenticated, service_role;

commit;
