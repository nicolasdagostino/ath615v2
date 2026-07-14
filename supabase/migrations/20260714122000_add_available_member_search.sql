create or replace function public.search_members_available_for_class(
  p_class_id uuid,
  p_query text default null
)
returns table (
  user_id uuid,
  full_name text,
  email text,
  avatar_url text,
  membership_id uuid,
  plan_name text,
  plan_type text,
  credits_remaining integer,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_admin public.profiles%rowtype;
  v_class public.classes%rowtype;
  v_query text := lower(trim(coalesce(p_query, '')));
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if p_class_id is null then
    raise exception 'Missing class id';
  end if;

  select *
  into v_admin
  from public.profiles
  where id = auth.uid();

  if v_admin.id is null
     or v_admin.role not in ('admin', 'owner')
     or v_admin.gym_id is null then
    raise exception 'Only gym admins can search members';
  end if;

  select *
  into v_class
  from public.classes
  where id = p_class_id;

  if v_class.id is null then
    raise exception 'Class not found';
  end if;

  if v_class.gym_id is distinct from v_admin.gym_id then
    raise exception 'Class belongs to another gym';
  end if;

  return query
  select
    p.id,
    p.full_name,
    p.email,
    p.avatar_url,
    mm.id,
    mp.name,
    mp.plan_type,
    mm.credits_remaining,
    coalesce(mm.expires_at, mm.ends_at)
  from public.profiles p
  join lateral public.select_usable_membership(
    p.id,
    v_class.gym_id
  ) mm on true
  join public.membership_plans mp
    on mp.id = mm.plan_id
  where p.gym_id = v_class.gym_id
    and p.is_active = true
    and p.role in ('athlete', 'admin', 'owner')
    and not exists (
      select 1
      from public.class_bookings cb
      where cb.class_id = p_class_id
        and cb.user_id = p.id
        and cb.status <> 'cancelled'
    )
    and (
      v_query = ''
      or lower(coalesce(p.full_name, '')) like '%' || v_query || '%'
      or lower(coalesce(p.email, '')) like '%' || v_query || '%'
    )
  order by
    coalesce(nullif(trim(p.full_name), ''), p.email, '') asc,
    p.created_at asc
  limit 30;
end;
$function$;


revoke all on function public.search_members_available_for_class(
  uuid,
  text
) from public;

revoke all on function public.search_members_available_for_class(
  uuid,
  text
) from anon;

revoke all on function public.search_members_available_for_class(
  uuid,
  text
) from authenticated;

grant execute on function public.search_members_available_for_class(
  uuid,
  text
) to authenticated, service_role;
