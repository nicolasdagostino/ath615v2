create or replace function public.create_member_membership_from_plan(
  p_user_id uuid,
  p_plan_id uuid,
  p_credit_reason text
)
returns public.member_memberships
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_member public.profiles%rowtype;
  v_plan public.membership_plans%rowtype;
  v_membership public.member_memberships%rowtype;
  v_duration_days integer;
  v_start_at timestamptz;
  v_end_at timestamptz;
  v_status text;
  v_last_unlimited_end timestamptz;
begin
  if p_user_id is null then
    raise exception 'Missing user id';
  end if;

  if p_plan_id is null then
    raise exception 'Missing plan id';
  end if;

  if p_credit_reason not in ('assigned', 'paid') then
    raise exception 'Invalid membership credit reason';
  end if;

  select *
  into v_member
  from public.profiles
  where id = p_user_id
  for update;

  if v_member.id is null then
    raise exception 'Member not found';
  end if;

  if v_member.gym_id is null then
    raise exception 'Member has no gym';
  end if;

  select *
  into v_plan
  from public.membership_plans
  where id = p_plan_id
  for update;

  if v_plan.id is null then
    raise exception 'Plan not found';
  end if;

  if v_plan.gym_id is distinct from v_member.gym_id then
    raise exception 'Plan belongs to another gym';
  end if;

  if v_plan.is_active is distinct from true then
    raise exception 'Plan is not active';
  end if;

  if v_plan.plan_type not in ('class_pack', 'unlimited') then
    raise exception 'Unsupported membership plan type';
  end if;

  v_duration_days := greatest(
    coalesce(v_plan.duration_days, 30),
    1
  );

  if v_plan.plan_type = 'class_pack' then
    if v_plan.credits is null or v_plan.credits <= 0 then
      raise exception 'Class pack must have positive credits';
    end if;

    v_start_at := now();
    v_end_at := v_start_at
      + make_interval(days => v_duration_days);
    v_status := 'active';
  else
    perform 1
    from public.member_memberships mm
    join public.membership_plans mp
      on mp.id = mm.plan_id
    where mm.user_id = p_user_id
      and mm.gym_id = v_member.gym_id
      and mm.status in ('active', 'scheduled')
      and mm.is_active = true
      and mp.plan_type = 'unlimited'
    for update of mm;

    if exists (
      select 1
      from public.member_memberships mm
      join public.membership_plans mp
        on mp.id = mm.plan_id
      where mm.user_id = p_user_id
        and mm.gym_id = v_member.gym_id
        and mm.status in ('active', 'scheduled')
        and mm.is_active = true
        and mp.plan_type = 'unlimited'
        and coalesce(mm.expires_at, mm.ends_at) is null
    ) then
      raise exception 'Existing Unlimited membership has no end date';
    end if;

    select max(coalesce(mm.expires_at, mm.ends_at))
    into v_last_unlimited_end
    from public.member_memberships mm
    join public.membership_plans mp
      on mp.id = mm.plan_id
    where mm.user_id = p_user_id
      and mm.gym_id = v_member.gym_id
      and mm.status in ('active', 'scheduled')
      and mm.is_active = true
      and mp.plan_type = 'unlimited'
      and coalesce(mm.expires_at, mm.ends_at) > now();

    v_start_at := greatest(
      now(),
      coalesce(v_last_unlimited_end, now())
    );

    v_end_at := v_start_at
      + make_interval(days => v_duration_days);

    v_status := case
      when v_start_at > now() then 'scheduled'
      else 'active'
    end;
  end if;

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
    p_user_id,
    v_plan.gym_id,
    v_plan.id,
    v_plan.credits,
    v_end_at,
    true,
    v_status,
    v_start_at,
    v_end_at
  )
  returning *
  into v_membership;

  if v_plan.credits is not null then
    insert into public.membership_credit_logs (
      user_id,
      gym_id,
      membership_id,
      amount,
      reason
    )
    values (
      p_user_id,
      v_plan.gym_id,
      v_membership.id,
      v_plan.credits,
      p_credit_reason
    );
  end if;

  return v_membership;
end;
$function$;

revoke all on function public.create_member_membership_from_plan(
  uuid,
  uuid,
  text
) from public;

revoke all on function public.create_member_membership_from_plan(
  uuid,
  uuid,
  text
) from anon;

revoke all on function public.create_member_membership_from_plan(
  uuid,
  uuid,
  text
) from authenticated;


create or replace function public.assign_membership_plan(
  p_user_id uuid,
  p_plan_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_admin public.profiles%rowtype;
  v_member public.profiles%rowtype;
  v_plan public.membership_plans%rowtype;
  v_membership public.member_memberships%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select *
  into v_admin
  from public.profiles
  where id = auth.uid();

  if v_admin.id is null
     or v_admin.role not in ('admin', 'owner')
     or v_admin.gym_id is null then
    raise exception 'Only gym admins can assign membership plans';
  end if;

  select *
  into v_member
  from public.profiles
  where id = p_user_id
  for update;

  if v_member.id is null then
    raise exception 'Member not found';
  end if;

  if v_member.gym_id is distinct from v_admin.gym_id then
    raise exception 'Member belongs to another gym';
  end if;

  select *
  into v_plan
  from public.membership_plans
  where id = p_plan_id;

  if v_plan.id is null then
    raise exception 'Plan not found';
  end if;

  if v_plan.gym_id is distinct from v_admin.gym_id then
    raise exception 'Plan belongs to another gym';
  end if;

  select *
  into v_membership
  from public.create_member_membership_from_plan(
    p_user_id,
    p_plan_id,
    'assigned'
  );
end;
$function$;


create or replace function public.approve_cash_membership_request(
  p_request_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_admin public.profiles%rowtype;
  v_member public.profiles%rowtype;
  v_request public.membership_requests%rowtype;
  v_plan public.membership_plans%rowtype;
  v_membership public.member_memberships%rowtype;
  v_is_spanish boolean;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select *
  into v_admin
  from public.profiles
  where id = auth.uid();

  if v_admin.id is null
     or v_admin.role not in ('admin', 'owner')
     or v_admin.gym_id is null then
    raise exception 'Only gym admins can approve membership requests';
  end if;

  select *
  into v_request
  from public.membership_requests
  where id = p_request_id
    and status = 'pending'
  for update;

  if v_request.id is null then
    raise exception 'Pending membership request not found';
  end if;

  if v_request.gym_id is distinct from v_admin.gym_id then
    raise exception 'Membership request belongs to another gym';
  end if;

  if v_request.payment_method is distinct from 'cash' then
    raise exception 'Only cash membership requests can be approved manually';
  end if;

  if v_request.payment_status is distinct from 'pending' then
    raise exception 'Cash membership request is not pending payment';
  end if;

  select *
  into v_member
  from public.profiles
  where id = v_request.user_id
  for update;

  if v_member.id is null then
    raise exception 'Member not found';
  end if;

  if v_member.gym_id is distinct from v_admin.gym_id then
    raise exception 'Member belongs to another gym';
  end if;

  select *
  into v_plan
  from public.membership_plans
  where id = v_request.plan_id;

  if v_plan.id is null then
    raise exception 'Plan not found';
  end if;

  if v_plan.gym_id is distinct from v_admin.gym_id then
    raise exception 'Plan belongs to another gym';
  end if;

  select *
  into v_membership
  from public.create_member_membership_from_plan(
    v_request.user_id,
    v_request.plan_id,
    'assigned'
  );

  update public.membership_requests
  set status = 'approved'
  where id = v_request.id;

  v_is_spanish :=
    coalesce(v_member.preferred_locale, 'en') = 'es';

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
      when v_membership.status = 'scheduled'
        and v_is_spanish then '🗓️ Membresía programada'
      when v_membership.status = 'scheduled'
        then '🗓️ Membership scheduled'
      when v_is_spanish then '🎉 Membresía activada'
      else '🎉 Membership activated'
    end,
    case
      when v_membership.status = 'scheduled'
        and v_is_spanish then
        'Tu nuevo plan comenzará cuando termine tu plan Unlimited actual.'
      when v_membership.status = 'scheduled' then
        'Your new plan will start when your current Unlimited plan ends.'
      when v_is_spanish then
        'Tu plan ya está activo. Ya puedes reservar clases.'
      else
        'Your plan is now active. You can start booking classes.'
    end,
    case
      when v_membership.status = 'scheduled'
        then 'membership_scheduled'
      else 'membership_approved'
    end,
    jsonb_build_object(
      'planId', v_plan.id,
      'requestId', v_request.id,
      'paymentMethod', 'cash',
      'membershipId', v_membership.id,
      'membershipStatus', v_membership.status,
      'startsAt', v_membership.starts_at
    ),
    now()
  );
end;
$function$;


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
  v_membership public.member_memberships%rowtype;
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
  where id = v_request.plan_id;

  if v_plan.id is null then
    raise exception 'Plan not found';
  end if;

  if v_plan.gym_id is distinct from v_request.gym_id then
    raise exception 'Plan belongs to another gym';
  end if;

  select *
  into v_membership
  from public.create_member_membership_from_plan(
    v_request.user_id,
    v_request.plan_id,
    'paid'
  );

  update public.membership_requests
  set status = 'approved',
      payment_status = 'paid',
      stripe_payment_intent_id = p_payment_intent_id,
      amount_total = p_amount_total,
      currency = lower(p_currency),
      paid_at = now()
  where id = v_request.id;

  v_is_spanish :=
    coalesce(v_member.preferred_locale, 'en') = 'es';

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
      when v_membership.status = 'scheduled'
        and v_is_spanish then '🗓️ Membresía programada'
      when v_membership.status = 'scheduled'
        then '🗓️ Membership scheduled'
      when v_is_spanish then '🎉 Membresía activada'
      else '🎉 Membership activated'
    end,
    case
      when v_membership.status = 'scheduled'
        and v_is_spanish then
        'Tu pago fue confirmado. El nuevo plan comenzará cuando termine tu Unlimited actual.'
      when v_membership.status = 'scheduled' then
        'Your payment was confirmed. The new plan will start when your current Unlimited plan ends.'
      when v_is_spanish then
        'Tu pago fue confirmado y tu plan ya está activo.'
      else
        'Your payment was confirmed and your plan is now active.'
    end,
    case
      when v_membership.status = 'scheduled'
        then 'membership_scheduled'
      else 'membership_payment_completed'
    end,
    jsonb_build_object(
      'planId', v_plan.id,
      'requestId', v_request.id,
      'paymentMethod', 'card',
      'checkoutSessionId', p_checkout_session_id,
      'membershipId', v_membership.id,
      'membershipStatus', v_membership.status,
      'startsAt', v_membership.starts_at
    ),
    now()
  );
end;
$function$;
