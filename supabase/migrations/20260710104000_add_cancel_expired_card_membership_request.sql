create or replace function public.cancel_expired_card_membership_request(
  p_checkout_session_id text,
  p_stripe_account_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_request public.membership_requests%rowtype;
  v_gym public.gyms%rowtype;
begin
  if p_checkout_session_id is null
     or length(trim(p_checkout_session_id)) = 0 then
    raise exception 'Missing checkout session id';
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

  if v_request.status = 'cancelled'
     and v_request.payment_status = 'cancelled' then
    return;
  end if;

  if v_request.status = 'approved'
     and v_request.payment_status = 'paid' then
    return;
  end if;

  if v_request.status is distinct from 'pending'
     or v_request.payment_status is distinct from 'pending' then
    raise exception 'Membership request is not pending';
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

  update public.membership_requests
  set status = 'cancelled',
      payment_status = 'cancelled'
  where id = v_request.id;
end;
$function$;

revoke all on function public.cancel_expired_card_membership_request(
  text,
  text
) from public;

revoke all on function public.cancel_expired_card_membership_request(
  text,
  text
) from anon;

grant execute on function public.cancel_expired_card_membership_request(
  text,
  text
) to service_role;
