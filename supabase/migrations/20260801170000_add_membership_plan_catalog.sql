create index if not exists member_memberships_gym_plan_status_idx
on public.member_memberships (gym_id, plan_id, status, is_active);
create or replace function public.prevent_used_membership_plan_delete()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  if exists (
       select 1 from public.member_memberships where plan_id = old.id
     ) or exists (
       select 1 from public.membership_requests where plan_id = old.id
     ) then
    raise exception 'plan_in_use' using errcode = '23503';
  end if;
  return old;
end;
$function$;
revoke all on function public.prevent_used_membership_plan_delete() from public;
revoke all on function public.prevent_used_membership_plan_delete() from anon;
revoke all on function public.prevent_used_membership_plan_delete() from authenticated;
drop trigger if exists prevent_used_membership_plan_delete on public.membership_plans;
create trigger prevent_used_membership_plan_delete
before delete on public.membership_plans
for each row execute function public.prevent_used_membership_plan_delete();
create or replace function public.list_membership_plan_catalog(
  p_search text default null,
  p_status text default 'all',
  p_plan_type text default 'all',
  p_limit integer default 12,
  p_offset integer default 0
)
returns table (
  plan_id uuid,
  name text,
  plan_type text,
  credits integer,
  price numeric,
  currency text,
  duration_days integer,
  is_active boolean,
  created_at timestamptz,
  active_memberships bigint,
  scheduled_memberships bigint,
  historical_memberships bigint,
  pending_requests bigint,
  total_count bigint
)
language plpgsql
security invoker
set search_path = public, pg_temp
as $function$
declare
  v_actor public.profiles%rowtype;
  v_search text := nullif(btrim(coalesce(p_search, '')), '');
begin
  if p_status not in ('all', 'active', 'inactive')
     or p_plan_type not in ('all', 'class_pack', 'unlimited')
     or p_limit < 1 or p_limit > 50
     or p_offset < 0 then
    raise exception 'invalid_parameters' using errcode = '22023';
  end if;

  select * into v_actor
  from public.profiles
  where id = auth.uid();

  if v_actor.id is null
     or v_actor.role not in ('admin', 'owner')
     or v_actor.gym_id is null then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  return query
  with filtered as (
    select mp.*,
           count(*) over () as matched_count
    from public.membership_plans mp
    where mp.gym_id = v_actor.gym_id
      and (v_search is null or mp.name ilike '%' || v_search || '%')
      and (p_status = 'all' or mp.is_active = (p_status = 'active'))
      and (p_plan_type = 'all' or mp.plan_type = p_plan_type)
    order by mp.is_active desc, mp.created_at desc, mp.id
    limit p_limit offset p_offset
  ),
  membership_counts as (
    select mm.plan_id,
      count(*) filter (
        where mm.status = 'active' and mm.is_active = true
      ) as active_count,
      count(*) filter (
        where mm.status = 'scheduled' and mm.is_active = true
      ) as scheduled_count,
      count(*) filter (
        where mm.status not in ('active', 'scheduled') or mm.is_active = false
      ) as historical_count
    from public.member_memberships mm
    where mm.gym_id = v_actor.gym_id
      and mm.plan_id in (select f.id from filtered f)
    group by mm.plan_id
  ),
  request_counts as (
    select mr.plan_id,
      count(*) filter (where mr.status = 'pending') as pending_count
    from public.membership_requests mr
    where mr.gym_id = v_actor.gym_id
      and mr.status = 'pending'
      and mr.plan_id in (select f.id from filtered f)
    group by mr.plan_id
  )
  select f.id, f.name, f.plan_type, f.credits, f.price, f.currency,
    f.duration_days, f.is_active, f.created_at,
    coalesce(mc.active_count, 0),
    coalesce(mc.scheduled_count, 0),
    coalesce(mc.historical_count, 0),
    coalesce(rc.pending_count, 0),
    f.matched_count
  from filtered f
  left join membership_counts mc on mc.plan_id = f.id
  left join request_counts rc on rc.plan_id = f.id
  order by f.is_active desc, f.created_at desc, f.id;
end;
$function$;
revoke all on function public.list_membership_plan_catalog(text, text, text, integer, integer) from public;
revoke all on function public.list_membership_plan_catalog(text, text, text, integer, integer) from anon;
grant execute on function public.list_membership_plan_catalog(text, text, text, integer, integer) to authenticated;
create or replace function public.delete_unused_membership_plan(p_plan_id uuid)
returns text
language plpgsql
security invoker
set search_path = public, pg_temp
as $function$
declare
  v_actor public.profiles%rowtype;
  v_plan public.membership_plans%rowtype;
begin
  select * into v_actor
  from public.profiles
  where id = auth.uid();

  if v_actor.id is null
     or v_actor.is_active is distinct from true
     or v_actor.role not in ('admin', 'owner')
     or v_actor.gym_id is null then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select * into v_plan
  from public.membership_plans
  where id = p_plan_id and gym_id = v_actor.gym_id
  for update;

  if not found then
    return 'not_found';
  end if;

  if exists (
       select 1 from public.member_memberships where plan_id = v_plan.id
     ) or exists (
       select 1 from public.membership_requests where plan_id = v_plan.id
     ) then
    return 'in_use';
  end if;

  delete from public.membership_plans
  where id = v_plan.id and gym_id = v_actor.gym_id;

  return 'deleted';
end;
$function$;
revoke all on function public.delete_unused_membership_plan(uuid) from public;
revoke all on function public.delete_unused_membership_plan(uuid) from anon;
grant execute on function public.delete_unused_membership_plan(uuid) to authenticated;
