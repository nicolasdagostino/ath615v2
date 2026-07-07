alter table public.membership_plans
add column if not exists duration_days integer not null default 30;

update public.membership_plans
set duration_days = 30
where duration_days is null;

create or replace function public.assign_membership_plan(
  p_user_id uuid,
  p_plan_id uuid
)
returns void
language plpgsql
security definer
as $function$
declare
  v_plan public.membership_plans%rowtype;
  v_membership_id uuid;
  v_duration_days integer;
begin
  select *
  into v_plan
  from public.membership_plans
  where id = p_plan_id;

  if v_plan.id is null then
    raise exception 'Plan not found';
  end if;

  v_duration_days := greatest(coalesce(v_plan.duration_days, 30), 1);

  update public.member_memberships
  set is_active = false
  where user_id = p_user_id
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
    p_user_id,
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
      p_user_id,
      v_plan.gym_id,
      v_membership_id,
      v_plan.credits,
      'assigned'
    );
  end if;
end;
$function$;
