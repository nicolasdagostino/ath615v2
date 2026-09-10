create or replace function public.list_effective_recent_activity(
  p_limit integer default 5
)
returns table (
  event_id uuid,
  kind text,
  occurred_at timestamptz,
  member_id uuid,
  member_name text,
  class_id uuid,
  class_title text,
  class_starts_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_gym_id uuid := public.effective_gym_id();
begin
  if auth.uid() is null then
    raise exception using errcode = 'P0001', message = 'unauthenticated';
  end if;
  if v_gym_id is null or not public.membership_actor_can_manage() then
    raise exception using errcode = '42501', message = 'forbidden';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 50 then
    raise exception using errcode = '22023', message = 'invalid_limit';
  end if;

  return query
  select
    e.id,
    e.kind,
    e.occurred_at,
    e.member_id,
    coalesce(nullif(btrim(p.full_name), ''), nullif(btrim(p.email), '')),
    e.class_id,
    c.title,
    c.starts_at
  from public.gym_activity_events e
  left join public.profiles p on p.id = e.member_id
  left join public.classes c on c.id = e.class_id and c.gym_id = e.gym_id
  where e.gym_id = v_gym_id
    and e.kind in ('booking', 'booking_cancelled', 'attendance', 'no_show')
  order by e.occurred_at desc, e.id desc
  limit p_limit;
end;
$$;

revoke all on function public.list_effective_recent_activity(integer)
from public, anon;
grant execute on function public.list_effective_recent_activity(integer)
to authenticated, service_role;
