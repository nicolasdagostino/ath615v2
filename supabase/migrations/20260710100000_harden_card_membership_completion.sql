create unique index if not exists membership_requests_stripe_payment_intent_id_unique_idx
on public.membership_requests (stripe_payment_intent_id)
where stripe_payment_intent_id is not null;

create or replace function public.complete_card_membership_request(
  p_checkout_session_id text,
  p_payment_intent_id text,
  p_amount_total integer,
  p_currency text,
  p_stripe_account_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_request public.membership_requests%rowtype;
  v_member public.profiles%rowtype;
  v_plan public.membership_plans%rowtype;
  v_gym public.gyms%rowtype;
  v_membership_id uuid;
  v_duration_days integer;
  v_is_spanish boolean;
begin
  if p_checkout_session_id is null
     or length(trim(p_checkout_session_id)) = 0 then
    raise exception 'Missing checkout session id';
  end if;

  if p_payment_intent_id is null
     or length(trim(p_payment_intent_id)) = 0 then
    raise exception 'Missing payment intent id';
  end if;

  if p_stripe_account_id is null
     or length(trim(p_stripe_account_id)) = 0 then
    raise exception 'Missing Stripe account id';
  end if;

  select *
  into v_request
  from public.membership_requests
  where stripe_checkout_session_id = p_checkout_session_id
  for update;

  if v_request.id is null then
    raise exception 'Membership request not found';
  end if;

  if v_request.payment_method is distinct from 'card' then
    raise exception 'Membership request is not a card payment';
  end if;

  if v_request.status = 'approved'
     and v_request.payment_status = 'paid' then
    return;
  end if;

  if v_request.status is distinct from 'pending'
     or v_request.payment_status is distinct from 'pending' then
    raise exception 'Membership request is not pending';
  end if;

  if p_amount_total is null
     or v_request.amount_total is null
     or p_amount_total is distinct from v_request.amount_total then
    raise exception 'Payment amount does not match membership request';
  end if;

  if p_currency is null
     or v_request.currency is null
     or lower(p_currency) is distinct from lower(v_request.currency) then
    raise exception 'Payment currency does not match membership request';
  end if;

  select *
  into v_gym
  from public.gyms
  where id = v_request.gym_id;

  if v_gym.id is null then
    raise exception 'Gym not found';
  end if;

  if v_gym.stripe_account_id is distinct from p_stripe_account_id then
    raise exception 'Stripe account does not match gym';
  end if;

  select *
  into v_member
  from public.profiles
  where id = v_request.user_id
  for update;

  if v_member.id is null then
    raise exception 'Member not found';
  end if;

  if v_member.gym_id is distinct from v_request.gym_id then
    raise exception 'Member belongs to another gym';
  end if;

  select *
  into v_plan
  from public.membership_plans
  where id = v_request.plan_id
  for update;

  if v_plan.id is null then
    raise exception 'Plan not found';
  end if;

  if v_plan.gym_id is distinct from v_request.gym_id then
    raise exception 'Plan belongs to another gym';
  end if;

  if v_plan.is_active is distinct from true then
    raise exception 'Plan is not active';
  end if;

  v_duration_days := greatest(coalesce(v_plan.duration_days, 30), 1);

  update public.member_memberships
  set is_active = false
  where user_id = v_request.user_id
    and gym_id = v_request.gym_id
    and is_active = true;

  insert into public.member_memberships (
    user_id,
    gym_id,
    plan_id,
    credits_remaining,
    expires_at,
    is_active,
    status,
    starts_at,
    ends_at
  )
  values (
    v_request.user_id,
    v_plan.gym_id,
    v_plan.id,
    v_plan.credits,
    now() + make_interval(days => v_duration_days),
    true,
    'active',
    now(),
    now() + make_interval(days => v_duration_days)
  )
  returning id into v_membership_id;

  if v_plan.credits is not null then
    insert into public.membership_credit_logs (
      user_id,
      gym_id,
      membership_id,
      amount,
      reason
    )
    values (
      v_request.user_id,
      v_plan.gym_id,
      v_membership_id,
      v_plan.credits,
      'paid'
    );
  end if;

  update public.membership_requests
  set status = 'approved',
      payment_status = 'paid',
      stripe_payment_intent_id = p_payment_intent_id,
      amount_total = p_amount_total,
      currency = lower(p_currency),
      paid_at = now()
  where id = v_request.id;

  v_is_spanish := coalesce(v_member.preferred_locale, 'en') = 'es';

  insert into public.notifications (
    user_id,
    title,
    body,
    type,
    data,
    scheduled_for
  )
  values (
    v_request.user_id,
    case
      when v_is_spanish then '🎉 Membresía activada'
      else '🎉 Membership activated'
    end,
    case
      when v_is_spanish then
        'Tu pago fue confirmado y tu plan ya está activo.'
      else
        'Your payment was confirmed and your plan is now active.'
    end,
    'membership_payment_completed',
    jsonb_build_object(
      'planId', v_plan.id,
      'requestId', v_request.id,
      'paymentMethod', 'card',
      'checkoutSessionId', p_checkout_session_id
    ),
    now()
  );
end;
$function$;

revoke all on function public.complete_card_membership_request(
  text,
  text,
  integer,
  text,
  text
) from public;

revoke all on function public.complete_card_membership_request(
  text,
  text,
  integer,
  text,
  text
) from anon;

grant execute on function public.complete_card_membership_request(
  text,
  text,
  integer,
  text,
  text
) to service_role;
