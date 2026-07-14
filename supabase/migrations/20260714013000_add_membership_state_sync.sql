create or replace function public.sync_membership_states()
returns table (
  expired_count integer,
  exhausted_count integer,
  activated_count integer
)
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_expired_count integer := 0;
  v_exhausted_count integer := 0;
  v_activated_count integer := 0;
begin
  update public.member_memberships
  set status = 'expired',
      is_active = false
  where status in ('active', 'scheduled')
    and is_active = true
    and coalesce(expires_at, ends_at) is not null
    and coalesce(expires_at, ends_at) <= now();

  get diagnostics v_expired_count = row_count;

  update public.member_memberships mm
  set status = 'exhausted',
      is_active = false
  from public.membership_plans mp
  where mp.id = mm.plan_id
    and mp.plan_type = 'class_pack'
    and mm.status = 'active'
    and mm.is_active = true
    and coalesce(mm.credits_remaining, 0) <= 0;

  get diagnostics v_exhausted_count = row_count;

  update public.member_memberships
  set status = 'active',
      is_active = true
  where status = 'scheduled'
    and is_active = true
    and coalesce(starts_at, created_at) <= now()
    and (
      coalesce(expires_at, ends_at) is null
      or coalesce(expires_at, ends_at) > now()
    );

  get diagnostics v_activated_count = row_count;

  return query
  select
    v_expired_count,
    v_exhausted_count,
    v_activated_count;
end;
$function$;

revoke all on function public.sync_membership_states()
from public;

revoke all on function public.sync_membership_states()
from anon;

revoke all on function public.sync_membership_states()
from authenticated;

grant execute on function public.sync_membership_states()
to service_role;

do $block$
declare
  v_existing_job_id bigint;
begin
  select jobid
  into v_existing_job_id
  from cron.job
  where jobname = 'sync-membership-states-every-5-min'
  limit 1;

  if v_existing_job_id is not null then
    perform cron.unschedule(v_existing_job_id);
  end if;

  perform cron.schedule(
    'sync-membership-states-every-5-min',
    '*/5 * * * *',
    'select * from public.sync_membership_states();'
  );
end;
$block$;
