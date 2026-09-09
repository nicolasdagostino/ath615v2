create or replace function public.list_effective_pending_membership_requests()
returns table(
  request_id uuid,
  user_id uuid,
  plan_id uuid,
  status text,
  payment_method text,
  payment_status text,
  amount_total integer,
  currency text,
  created_at timestamptz,
  member_name text,
  member_email text,
  member_avatar_url text,
  plan_name text,
  plan_type text,
  credits integer,
  plan_price numeric,
  plan_currency text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
begin
  if auth.uid() is null then
    raise exception using errcode = 'P0001', message = 'unauthenticated';
  end if;
  if v_gym_id is null or not public.membership_actor_can_manage() then
    raise exception using errcode = '42501', message = 'forbidden';
  end if;

  return query
  select
    r.id,
    r.user_id,
    r.plan_id,
    r.status,
    r.payment_method,
    r.payment_status,
    r.amount_total,
    r.currency,
    r.created_at,
    p.full_name,
    p.email,
    p.avatar_url,
    mp.name,
    mp.plan_type,
    mp.credits,
    mp.price,
    mp.currency
  from public.membership_requests r
  join public.profiles p on p.id = r.user_id
  join public.membership_plans mp on mp.id = r.plan_id and mp.gym_id = r.gym_id
  where r.gym_id = v_gym_id
    and r.status = 'pending'
    and r.payment_method = 'cash'
    and r.payment_status = 'pending'
  order by r.created_at desc, r.id desc;
end;
$function$;

revoke all on function public.list_effective_pending_membership_requests()
from public, anon, authenticated;
grant execute on function public.list_effective_pending_membership_requests()
to authenticated;

comment on function public.list_effective_pending_membership_requests() is
  'Lists pending in-person membership requests and their exact requester identity for the effective gym administrator.';
