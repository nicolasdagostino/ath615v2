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
  v_membership_id uuid;
  v_duration_days integer;
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
  where id = v_request.plan_id
  for update;

  if v_plan.id is null then
    raise exception 'Plan not found';
  end if;

  if v_plan.gym_id is distinct from v_admin.gym_id then
    raise exception 'Plan belongs to another gym';
  end if;

  if v_plan.is_active is distinct from true then
    raise exception 'Plan is not active';
  end if;

  v_duration_days := greatest(coalesce(v_plan.duration_days, 30), 1);

  update public.member_memberships
  set is_active = false
  where user_id = v_request.user_id
    and gym_id = v_admin.gym_id
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
      'assigned'
    );
  end if;

  update public.membership_requests
  set status = 'approved'
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
        'Tu plan ya está activo. Ya puedes reservar clases.'
      else
        'Your plan is now active. You can start booking classes.'
    end,
    'membership_approved',
    jsonb_build_object(
      'planId', v_plan.id,
      'requestId', v_request.id,
      'paymentMethod', 'cash'
    ),
    now()
  );
end;
$function$;

revoke all on function public.approve_cash_membership_request(uuid) from public;
revoke all on function public.approve_cash_membership_request(uuid) from anon;
grant execute on function public.approve_cash_membership_request(uuid) to authenticated;
