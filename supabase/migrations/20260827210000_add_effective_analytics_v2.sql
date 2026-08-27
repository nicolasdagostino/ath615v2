-- Analytics V2: membership and confirmed operational revenue aggregates.

create index if not exists member_memberships_gym_created_at_idx
  on public.member_memberships (gym_id, created_at);

create index if not exists membership_credit_logs_gym_created_at_idx
  on public.membership_credit_logs (gym_id, created_at);

create index if not exists membership_requests_paid_analytics_idx
  on public.membership_requests (gym_id, paid_at)
  where payment_status = 'paid';

create or replace function public.get_effective_membership_analytics(
  p_period text default '30d'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
  v_timezone text;
  v_bounds record;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'unauthenticated';
  end if;
  if v_gym_id is null or not public.analytics_actor_can_read() then
    raise exception using errcode = '42501', message = 'analytics_forbidden';
  end if;

  select g.timezone into v_timezone from public.gyms g where g.id = v_gym_id;
  select * into strict v_bounds
  from public.analytics_period_bounds(v_timezone, p_period, null);

  with snapshot as (
    select
      count(*) filter (where mm.status = 'active')::bigint as active,
      count(*) filter (where mm.status = 'active' and mp.plan_type = 'class_pack')::bigint as active_packs,
      count(*) filter (where mm.status = 'active' and mp.plan_type = 'unlimited')::bigint as active_unlimited,
      count(*) filter (where mm.status = 'scheduled')::bigint as scheduled,
      count(*) filter (where mm.status = 'exhausted')::bigint as exhausted,
      count(*) filter (where mm.status = 'expired')::bigint as expired,
      count(*) filter (where mm.status = 'cancelled')::bigint as cancelled,
      count(*) filter (where mm.status = 'replaced')::bigint as replaced,
      coalesce(sum(mm.credits_remaining) filter (
        where mp.plan_type = 'class_pack'
          and mm.status in ('active', 'scheduled')
      ), 0)::bigint as current_remaining,
      coalesce(sum(mm.credits_remaining) filter (
        where mp.plan_type = 'class_pack'
          and mm.status = 'expired'
          and coalesce(mm.expires_at, mm.ends_at) >= v_bounds.utc_from
          and coalesce(mm.expires_at, mm.ends_at) < v_bounds.utc_to_exclusive
          and mm.credits_remaining > 0
      ), 0)::bigint as expired_unused
    from public.member_memberships mm
    left join public.membership_plans mp on mp.id = mm.plan_id
    where mm.gym_id = v_gym_id
  ), activity as (
    select
      count(*) filter (
        where mm.created_at >= v_bounds.utc_from
          and mm.created_at < v_bounds.utc_to_exclusive
      )::bigint as created,
      count(*) filter (
        where mm.created_at >= v_bounds.previous_utc_from
          and mm.created_at < v_bounds.previous_utc_to_exclusive
      )::bigint as previous_created
    from public.member_memberships mm
    where mm.gym_id = v_gym_id
  ), credit_totals as (
    select
      coalesce(sum(l.amount) filter (where l.reason = 'paid' and l.amount > 0), 0)::bigint as purchased,
      coalesce(sum(l.amount) filter (where l.reason = 'assigned' and l.amount > 0), 0)::bigint as assigned,
      coalesce(-sum(l.amount) filter (where l.reason = 'booked' and l.amount < 0), 0)::bigint as consumed,
      coalesce(sum(l.amount) filter (
        where l.reason in ('cancelled', 'class_cancelled') and l.amount > 0
      ), 0)::bigint as refunded,
      count(*) filter (
        where l.reason not in ('paid','assigned','booked','cancelled','class_cancelled')
      )::bigint as unclassified
    from public.membership_credit_logs l
    where l.gym_id = v_gym_id
      and l.created_at >= v_bounds.utc_from
      and l.created_at < v_bounds.utc_to_exclusive
  ), membership_plan_rows as (
    select
      mm.plan_id,
      coalesce(mp.name, '—') as plan_name,
      count(*)::bigint as memberships_created,
      count(*) filter (where mm.status = 'active')::bigint as active_now
    from public.member_memberships mm
    left join public.membership_plans mp on mp.id = mm.plan_id
    where mm.gym_id = v_gym_id
      and mm.created_at >= v_bounds.utc_from
      and mm.created_at < v_bounds.utc_to_exclusive
    group by mm.plan_id, mp.name
  ), paid_plan_rows as (
    select mr.plan_id, count(*)::bigint as paid_sales
    from public.membership_requests mr
    where mr.gym_id = v_gym_id
      and mr.payment_status = 'paid'
      and mr.paid_at >= v_bounds.utc_from
      and mr.paid_at < v_bounds.utc_to_exclusive
    group by mr.plan_id
  ), assigned_plan_rows as (
    select mm.plan_id, count(distinct l.membership_id)::bigint as assignments
    from public.membership_credit_logs l
    join public.member_memberships mm
      on mm.id = l.membership_id and mm.gym_id = v_gym_id
    where l.gym_id = v_gym_id
      and l.reason = 'assigned'
      and l.amount > 0
      and l.created_at >= v_bounds.utc_from
      and l.created_at < v_bounds.utc_to_exclusive
    group by mm.plan_id
  ), all_plan_ids as (
    select plan_id from membership_plan_rows
    union select plan_id from paid_plan_rows
    union select plan_id from assigned_plan_rows
  ), plan_rows as (
    select jsonb_agg(
      jsonb_build_object(
        'planId', ids.plan_id,
        'planName', coalesce(mp.name, m.plan_name, '—'),
        'membershipsCreated', coalesce(m.memberships_created, 0),
        'activeNow', coalesce(m.active_now, 0),
        'paidSales', coalesce(p.paid_sales, 0),
        'directAssignments', coalesce(a.assignments, 0)
      ) order by coalesce(m.memberships_created, 0) desc,
        coalesce(p.paid_sales, 0) desc, coalesce(mp.name, m.plan_name, '—')
    ) as value
    from all_plan_ids ids
    left join membership_plan_rows m on m.plan_id is not distinct from ids.plan_id
    left join paid_plan_rows p on p.plan_id is not distinct from ids.plan_id
    left join assigned_plan_rows a on a.plan_id is not distinct from ids.plan_id
    left join public.membership_plans mp on mp.id = ids.plan_id
  )
  select jsonb_build_object(
    'period', jsonb_build_object(
      'key', v_bounds.period_key,
      'timezone', v_timezone,
      'from', v_bounds.local_from,
      'toExclusive', v_bounds.local_to_exclusive
    ),
    'snapshot', jsonb_build_object(
      'active', s.active,
      'activePacks', s.active_packs,
      'activeUnlimited', s.active_unlimited,
      'scheduled', s.scheduled,
      'exhausted', s.exhausted,
      'expired', s.expired,
      'cancelled', s.cancelled,
      'replaced', s.replaced
    ),
    'activity', jsonb_build_object(
      'created', a.created,
      'previousCreated', a.previous_created
    ),
    'credits', jsonb_build_object(
      'purchasedGranted', c.purchased,
      'assignedGranted', c.assigned,
      'consumed', c.consumed,
      'refunded', c.refunded,
      'netConsumed', c.consumed - c.refunded,
      'currentRemaining', s.current_remaining,
      'expiredUnused', s.expired_unused,
      'unclassifiedLogs', c.unclassified
    ),
    'plans', coalesce(p.value, '[]'::jsonb)
  ) into v_result
  from snapshot s cross join activity a cross join credit_totals c cross join plan_rows p;

  return v_result;
end;
$function$;

create or replace function public.get_effective_revenue_analytics(
  p_period text default '30d'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
  v_timezone text;
  v_bounds record;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'unauthenticated';
  end if;
  if v_gym_id is null or not public.analytics_actor_can_read() then
    raise exception using errcode = '42501', message = 'analytics_forbidden';
  end if;

  select g.timezone into v_timezone from public.gyms g where g.id = v_gym_id;
  select * into strict v_bounds
  from public.analytics_period_bounds(v_timezone, p_period, null);

  with auditable_paid as (
    select
      mr.id, mr.plan_id, mr.amount_total::bigint as amount_minor,
      upper(mr.currency) as currency, mr.paid_at,
      case
        when mr.payment_method = 'card' then 'card'
        when mr.payment_method = 'cash' and mr.manual_payment_method = 'cash' then 'cash'
        when mr.payment_method = 'cash' and mr.manual_payment_method = 'bizum' then 'bizum'
        else null
      end as method,
      coalesce(nullif(btrim(mr.stripe_plan_name), ''), nullif(btrim(mp.name), ''), 'Deleted plan') as plan_name
    from public.membership_requests mr
    left join public.membership_plans mp on mp.id = mr.plan_id
    where mr.gym_id = v_gym_id
      and mr.payment_status = 'paid'
      and mr.paid_at is not null
      and mr.amount_total is not null
      and mr.amount_total >= 0
      and nullif(btrim(mr.currency), '') is not null
  ), current_paid as (
    select * from auditable_paid
    where paid_at >= v_bounds.utc_from and paid_at < v_bounds.utc_to_exclusive
  ), previous_paid as (
    select * from auditable_paid
    where paid_at >= v_bounds.previous_utc_from and paid_at < v_bounds.previous_utc_to_exclusive
  ), current_currency as (
    select currency, sum(amount_minor)::bigint as total_minor,
      count(*)::bigint as payment_count,
      round(avg(amount_minor))::bigint as average_minor
    from current_paid group by currency
  ), previous_currency as (
    select currency, sum(amount_minor)::bigint as total_minor,
      count(*)::bigint as payment_count,
      round(avg(amount_minor))::bigint as average_minor
    from previous_paid group by currency
  ), currency_rows as (
    select jsonb_agg(jsonb_build_object(
      'currency', c.currency,
      'totalMinor', c.total_minor,
      'paymentCount', c.payment_count,
      'averageMinor', c.average_minor,
      'previousTotalMinor', coalesce(p.total_minor, 0),
      'previousPaymentCount', coalesce(p.payment_count, 0),
      'previousAverageMinor', p.average_minor
    ) order by c.currency) as value
    from current_currency c left join previous_currency p using (currency)
  ), method_rows as (
    select jsonb_agg(jsonb_build_object(
      'currency', currency, 'method', method,
      'totalMinor', total_minor, 'paymentCount', payment_count
    ) order by currency, method) as value
    from (
      select currency, method, sum(amount_minor)::bigint as total_minor,
        count(*)::bigint as payment_count
      from current_paid where method is not null
      group by currency, method
    ) x
  ), plan_aggregate as (
    select currency, plan_id, plan_name, sum(amount_minor)::bigint as revenue_minor,
      count(*)::bigint as payment_count,
      round(avg(amount_minor))::bigint as average_minor
    from current_paid group by currency, plan_id, plan_name
  ), plan_rows as (
    select jsonb_agg(jsonb_build_object(
      'currency', p.currency, 'planId', p.plan_id, 'planName', p.plan_name,
      'revenueMinor', p.revenue_minor, 'paymentCount', p.payment_count,
      'averageMinor', p.average_minor,
      'revenueShare', round(100 * p.revenue_minor::numeric / nullif(c.total_minor, 0), 1)
    ) order by p.currency, p.revenue_minor desc, p.plan_name) as value
    from plan_aggregate p join current_currency c using (currency)
  ), trend_aggregate as (
    select
      case when p_period = '3m'
        then date_trunc('week', paid_at at time zone v_timezone)::date
        else (paid_at at time zone v_timezone)::date
      end as bucket_start,
      currency, sum(amount_minor)::bigint as total_minor,
      count(*)::bigint as payment_count
    from current_paid
    group by 1, currency
  ), trend_rows as (
    select jsonb_agg(jsonb_build_object(
      'bucketStart', bucket_start, 'currency', currency,
      'totalMinor', total_minor, 'paymentCount', payment_count
    ) order by currency, bucket_start) as value
    from trend_aggregate
  ), state_counts as (
    select
      count(*) filter (where payment_status = 'paid')::bigint as paid,
      count(*) filter (where payment_status = 'pending')::bigint as pending,
      count(*) filter (where payment_status = 'failed')::bigint as failed,
      count(*) filter (where payment_status = 'cancelled')::bigint as cancelled
    from public.membership_requests
    where gym_id = v_gym_id
      and created_at >= v_bounds.utc_from and created_at < v_bounds.utc_to_exclusive
  ), exclusions as (
    select
      count(*) filter (
        where payment_status = 'paid' and (
          paid_at is null or amount_total is null
          or amount_total < 0 or nullif(btrim(currency), '') is null
        )
      )::bigint as paid_missing_audit,
      count(*) filter (
        where status = 'approved' and payment_status = 'pending'
      )::bigint as legacy_approved_pending,
      count(*) filter (
        where payment_status = 'paid' and payment_method = 'cash'
          and manual_payment_method is null
      )::bigint as unclassified_manual_method
    from public.membership_requests
    where gym_id = v_gym_id
      and created_at >= v_bounds.utc_from and created_at < v_bounds.utc_to_exclusive
  )
  select jsonb_build_object(
    'period', jsonb_build_object(
      'key', v_bounds.period_key, 'timezone', v_timezone,
      'from', v_bounds.local_from, 'toExclusive', v_bounds.local_to_exclusive
    ),
    'currencies', coalesce(c.value, '[]'::jsonb),
    'methods', coalesce(m.value, '[]'::jsonb),
    'plans', coalesce(p.value, '[]'::jsonb),
    'trend', coalesce(t.value, '[]'::jsonb),
    'states', jsonb_build_object(
      'paid', s.paid, 'pending', s.pending,
      'failed', s.failed, 'cancelled', s.cancelled
    ),
    'excluded', jsonb_build_object(
      'paidMissingAudit', e.paid_missing_audit,
      'legacyApprovedPending', e.legacy_approved_pending,
      'unclassifiedManualMethod', e.unclassified_manual_method
    )
  ) into v_result
  from currency_rows c cross join method_rows m cross join plan_rows p
    cross join trend_rows t cross join state_counts s cross join exclusions e;

  return v_result;
end;
$function$;

revoke all on function public.get_effective_membership_analytics(text)
  from public, anon;
revoke all on function public.get_effective_revenue_analytics(text)
  from public, anon;
grant execute on function public.get_effective_membership_analytics(text)
  to authenticated, service_role;
grant execute on function public.get_effective_revenue_analytics(text)
  to authenticated, service_role;

comment on function public.get_effective_membership_analytics(text) is
  'Owner/admin-only membership snapshot, period activity, and classified credit aggregates for the effective gym.';
comment on function public.get_effective_revenue_analytics(text) is
  'Owner/admin-only confirmed operational revenue aggregates using historical paid request amounts for the effective gym.';
