-- Paginated, RLS-aware administrative report for athletes without recent
-- booking activity. The actor gym is always derived from auth.uid().

create index if not exists classes_gym_starts_id_idx
on public.classes (gym_id, starts_at, id);
create or replace function public.list_members_without_recent_bookings(
  p_inactive_days integer default 15,
  p_limit integer default 5,
  p_offset integer default 0
)
returns table (
  user_id uuid,
  display_name text,
  avatar_url text,
  phone text,
  email text,
  current_plan_name text,
  last_class_starts_at timestamptz,
  days_since_last_booking integer,
  never_booked boolean,
  total_count bigint
)
language plpgsql
security invoker
set search_path = public, pg_temp
as $function$
declare
  v_actor public.profiles%rowtype;
begin
  if auth.uid() is null then
    raise exception using errcode = 'P0001', message = 'unauthenticated';
  end if;

  select p.*
  into v_actor
  from public.profiles p
  where p.id = auth.uid();

  if not found
    or not coalesce(v_actor.is_active, false)
    or v_actor.gym_id is null
    or v_actor.role not in ('admin', 'owner')
  then
    raise exception using errcode = '42501', message = 'forbidden';
  end if;

  if p_inactive_days is null
    or p_inactive_days not between 1 and 365
    or p_limit is null
    or p_limit not between 1 and 50
    or p_offset is null
    or p_offset < 0
  then
    raise exception using errcode = '22023', message = 'invalid_parameters';
  end if;

  return query
  with active_athletes as (
    select
      p.id,
      coalesce(
        nullif(trim(p.full_name), ''),
        nullif(trim(p.email), ''),
        '—'
      ) as member_name,
      p.avatar_url as member_avatar_url,
      nullif(trim(p.phone), '') as member_phone,
      nullif(trim(p.email), '') as member_email
    from public.profiles p
    where p.gym_id = v_actor.gym_id
      and coalesce(p.is_active, false)
      and p.role = 'athlete'
  ),
  last_activity as (
    select
      cb.user_id,
      max(c.starts_at) as last_starts_at
    from public.classes c
    join public.class_bookings cb
      on cb.class_id = c.id
    join active_athletes aa
      on aa.id = cb.user_id
    where c.gym_id = v_actor.gym_id
      and cb.user_id is not null
      and not coalesce(cb.is_guest, false)
      and cb.status in ('booked', 'attended', 'no_show')
    group by cb.user_id
  ),
  candidates as (
    select
      aa.*,
      la.last_starts_at
    from active_athletes aa
    left join last_activity la
      on la.user_id = aa.id
    where la.last_starts_at is null
      or la.last_starts_at < now() - make_interval(days => p_inactive_days)
  ),
  paged as (
    select
      candidates.*,
      count(*) over () as matching_count
    from candidates
    order by
      (last_starts_at is null) desc,
      last_starts_at asc nulls first,
      member_name asc,
      id asc
    limit p_limit
    offset p_offset
  )
  select
    pg.id,
    pg.member_name,
    pg.member_avatar_url,
    pg.member_phone,
    pg.member_email,
    usable.plan_name,
    pg.last_starts_at,
    case
      when pg.last_starts_at is null then null
      else floor(
        extract(epoch from (now() - pg.last_starts_at)) / 86400
      )::integer
    end,
    pg.last_starts_at is null,
    pg.matching_count
  from paged pg
  left join lateral (
    select mp.name as plan_name
    from public.member_memberships mm
    join public.membership_plans mp
      on mp.id = mm.plan_id
    where mm.user_id = pg.id
      and mm.gym_id = v_actor.gym_id
      and mm.is_active
      and mm.status = 'active'
      and coalesce(mm.starts_at, mm.created_at) <= now()
      and (
        coalesce(mm.expires_at, mm.ends_at) is null
        or coalesce(mm.expires_at, mm.ends_at) > now()
      )
      and (
        mp.plan_type = 'unlimited'
        or (
          mp.plan_type = 'class_pack'
          and mm.credits_remaining > 0
        )
      )
    order by
      case when mp.plan_type = 'unlimited' then 0 else 1 end,
      coalesce(
        mm.expires_at,
        mm.ends_at,
        'infinity'::timestamptz
      ),
      mm.created_at,
      mm.id
    limit 1
  ) usable on true
  order by
    (pg.last_starts_at is null) desc,
    pg.last_starts_at asc nulls first,
    pg.member_name asc,
    pg.id asc;
end;
$function$;
revoke all on function public.list_members_without_recent_bookings(
  integer,
  integer,
  integer
) from public;
revoke all on function public.list_members_without_recent_bookings(
  integer,
  integer,
  integer
) from anon;
grant execute on function public.list_members_without_recent_bookings(
  integer,
  integer,
  integer
) to authenticated;
