-- Canonical, side-effect-free predicate shared by membership selection and
-- administrative reporting. The existing selector retains its locking and
-- ordering semantics.

create or replace function public.is_membership_usable(
  p_is_active boolean,
  p_status text,
  p_starts_at timestamptz,
  p_created_at timestamptz,
  p_expires_at timestamptz,
  p_ends_at timestamptz,
  p_credits_remaining integer,
  p_plan_type text,
  p_at timestamptz default now()
)
returns boolean
language sql
immutable
security invoker
set search_path = public, pg_temp
as $function$
  select coalesce((
    coalesce(p_is_active, false)
    and p_status = 'active'
    and coalesce(p_starts_at, p_created_at) <= p_at
    and (
      coalesce(p_expires_at, p_ends_at) is null
      or coalesce(p_expires_at, p_ends_at) > p_at
    )
    and (
      p_plan_type = 'unlimited'
      or (
        p_plan_type = 'class_pack'
        and p_credits_remaining > 0
      )
    )
  ), false);
$function$;
revoke all on function public.is_membership_usable(
  boolean, text, timestamptz, timestamptz, timestamptz, timestamptz,
  integer, text, timestamptz
) from public;
revoke all on function public.is_membership_usable(
  boolean, text, timestamptz, timestamptz, timestamptz, timestamptz,
  integer, text, timestamptz
) from anon;
grant execute on function public.is_membership_usable(
  boolean, text, timestamptz, timestamptz, timestamptz, timestamptz,
  integer, text, timestamptz
) to authenticated;
create or replace function public.select_usable_membership(
  p_user_id uuid,
  p_gym_id uuid
)
returns public.member_memberships
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_membership public.member_memberships%rowtype;
begin
  if p_user_id is null then
    raise exception 'Missing user id';
  end if;
  if p_gym_id is null then
    raise exception 'Missing gym id';
  end if;

  select mm.*
  into v_membership
  from public.member_memberships mm
  join public.membership_plans mp on mp.id = mm.plan_id
  where mm.user_id = p_user_id
    and mm.gym_id = p_gym_id
    and public.is_membership_usable(
      mm.is_active, mm.status, mm.starts_at, mm.created_at,
      mm.expires_at, mm.ends_at, mm.credits_remaining, mp.plan_type, now()
    )
  order by
    case when mp.plan_type = 'unlimited' then 0 else 1 end,
    coalesce(mm.expires_at, mm.ends_at, 'infinity'::timestamptz) asc,
    mm.created_at asc
  limit 1
  for update of mm;

  return v_membership;
end;
$function$;
revoke all on function public.select_usable_membership(uuid, uuid) from public;
revoke all on function public.select_usable_membership(uuid, uuid) from anon;
revoke all on function public.select_usable_membership(uuid, uuid)
from authenticated;
create or replace function public.get_members_without_usable_membership(
  p_search text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  user_id uuid,
  full_name text,
  email text,
  role text,
  is_active boolean,
  phone text,
  birth_date date,
  created_at timestamptz,
  total_count bigint
)
language plpgsql
security invoker
set search_path = public, pg_temp
as $function$
declare
  v_actor public.profiles%rowtype;
  v_search text := lower(trim(coalesce(p_search, '')));
  v_at timestamptz := now();
begin
  if auth.uid() is null then
    raise exception using errcode = 'P0001', message = 'unauthenticated';
  end if;

  select p.* into v_actor
  from public.profiles p
  where p.id = auth.uid();

  if not found
    or not coalesce(v_actor.is_active, false)
    or v_actor.gym_id is null
    or v_actor.role not in ('admin', 'owner')
  then
    raise exception using errcode = '42501', message = 'forbidden';
  end if;

  if length(v_search) > 80
    or p_limit is null
    or p_limit not between 1 and 100
    or p_offset is null
    or p_offset < 0
  then
    raise exception using errcode = '22023', message = 'invalid_parameters';
  end if;

  return query
  with candidates as (
    select
      p.id,
      nullif(trim(p.full_name), '') as member_name,
      nullif(trim(p.email), '') as member_email,
      p.role::text as member_role,
      p.is_active as member_is_active,
      nullif(trim(p.phone), '') as member_phone,
      p.birth_date as member_birth_date,
      p.created_at as member_created_at
    from public.profiles p
    where p.gym_id = v_actor.gym_id
      and p.role = 'athlete'
      and p.role <> 'owner'
      and coalesce(p.is_active, false)
      and (
        v_search = ''
        or strpos(lower(coalesce(p.full_name, '')), v_search) > 0
        or strpos(lower(coalesce(p.email, '')), v_search) > 0
      )
      and not exists (
        select 1
        from public.member_memberships mm
        join public.membership_plans mp on mp.id = mm.plan_id
        where mm.user_id = p.id
          and mm.gym_id = v_actor.gym_id
          and public.is_membership_usable(
            mm.is_active, mm.status, mm.starts_at, mm.created_at,
            mm.expires_at, mm.ends_at, mm.credits_remaining,
            mp.plan_type, v_at
          )
      )
  ),
  paged as (
    select candidates.*, count(*) over () as matching_count
    from candidates
    order by member_name asc nulls last, member_created_at asc, id asc
    limit p_limit
    offset p_offset
  )
  select
    pg.id, pg.member_name, pg.member_email, pg.member_role,
    pg.member_is_active, pg.member_phone, pg.member_birth_date,
    pg.member_created_at, pg.matching_count
  from paged pg
  order by pg.member_name asc nulls last, pg.member_created_at asc, pg.id asc;
end;
$function$;
revoke all on function public.get_members_without_usable_membership(
  text, integer, integer
) from public;
revoke all on function public.get_members_without_usable_membership(
  text, integer, integer
) from anon;
grant execute on function public.get_members_without_usable_membership(
  text, integer, integer
) to authenticated;
