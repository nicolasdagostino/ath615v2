create index if not exists gyms_owner_created_idx
on public.gyms (owner_id, created_at desc, id);
create index if not exists profiles_gym_role_active_idx
on public.profiles (gym_id, role, is_active);
create or replace function public.create_gym(gym_name text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor public.profiles%rowtype;
  v_name text := btrim(coalesce(gym_name, ''));
  v_gym_id uuid;
begin
  if auth.uid() is null then
    raise exception using errcode = 'P0001', message = 'unauthenticated';
  end if;
  select * into v_actor from public.profiles where id = auth.uid();
  if not found or not coalesce(v_actor.is_active, false) then
    raise exception using errcode = 'P0001', message = 'unauthorized';
  end if;
  if v_actor.role <> 'owner' then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  if v_name = '' or char_length(v_name) > 100 then
    raise exception using errcode = '22023', message = 'invalid_gym_name';
  end if;

  insert into public.gyms (name, owner_id)
  values (v_name, auth.uid())
  returning id into v_gym_id;

  -- Flutter compatibility: its Owner flow expects the newly created gym here.
  update public.profiles set gym_id = v_gym_id where id = auth.uid();
  return v_gym_id;
end;
$$;
revoke all on function public.create_gym(text) from public;
revoke all on function public.create_gym(text) from anon;
grant execute on function public.create_gym(text) to authenticated;
create or replace function public.list_owner_gyms(
  p_search text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  gym_id uuid,
  name text,
  logo_url text,
  gym_code text,
  business_name text,
  created_at timestamptz,
  administrator_count bigint,
  active_member_count bigint,
  active_athlete_count bigint,
  active_coach_count bigint,
  class_count_current_month bigint,
  active_membership_count bigint,
  total_count bigint
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_search text := nullif(btrim(coalesce(p_search, '')), '');
begin
  if auth.uid() is null then raise exception using errcode = 'P0001', message = 'unauthenticated'; end if;
  if not exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'owner' and p.is_active = true) then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 or p_offset is null or p_offset < 0 or char_length(coalesce(v_search, '')) > 100 then
    raise exception using errcode = '22023', message = 'invalid_parameters';
  end if;

  return query
  with owned as (
    select g.* from public.gyms g
    where g.owner_id = auth.uid()
      and (v_search is null or g.name ilike '%' || v_search || '%' or coalesce(g.business_name, '') ilike '%' || v_search || '%')
  ), page as (
    select o.*, count(*) over() as filtered_total
    from owned o order by o.created_at desc, o.id desc limit p_limit offset p_offset
  ), profile_counts as (
    select x.gym_id,
      count(*) filter (where x.role = 'admin') as administrators,
      count(*) filter (where x.role in ('athlete','coach','admin') and x.is_active = true) as active_members,
      count(*) filter (where x.role = 'athlete' and x.is_active = true) as athletes,
      count(*) filter (where x.role = 'coach' and x.is_active = true) as coaches
    from public.profiles x join page pg on pg.id = x.gym_id group by x.gym_id
  ), class_counts as (
    select c.gym_id, count(*) as classes
    from public.classes c join page pg on pg.id = c.gym_id
    where c.starts_at >= date_trunc('month', now())
      and c.starts_at < date_trunc('month', now()) + interval '1 month'
    group by c.gym_id
  ), membership_counts as (
    select m.gym_id, count(*) as memberships
    from public.member_memberships m join page pg on pg.id = m.gym_id
    where m.status = 'active' and m.is_active = true group by m.gym_id
  )
  select p.id, p.name, p.logo_url, p.gym_code, p.business_name, p.created_at,
    coalesce(pc.administrators, 0), coalesce(pc.active_members, 0),
    coalesce(pc.athletes, 0), coalesce(pc.coaches, 0),
    coalesce(cc.classes, 0), coalesce(mc.memberships, 0),
    p.filtered_total
  from page p
  left join profile_counts pc on pc.gym_id = p.id
  left join class_counts cc on cc.gym_id = p.id
  left join membership_counts mc on mc.gym_id = p.id
  order by p.created_at desc, p.id desc;
end;
$$;
create or replace function public.get_owner_gym(p_gym_id uuid)
returns table (
  gym_id uuid, name text, logo_url text, gym_code text, business_name text,
  phone text, email text, website text, address text, created_at timestamptz,
  administrator_count bigint, active_member_count bigint, active_athlete_count bigint,
  active_coach_count bigint, class_count_current_month bigint,
  active_membership_count bigint, administrators jsonb
)
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then raise exception using errcode = 'P0001', message = 'unauthenticated'; end if;
  if not exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'owner' and p.is_active = true) then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  return query
  select g.id, g.name, g.logo_url, g.gym_code, g.business_name, g.phone, g.email, g.website, g.address, g.created_at,
    (select count(*) from public.profiles p where p.gym_id = g.id and p.role = 'admin'),
    (select count(*) from public.profiles p where p.gym_id = g.id and p.role in ('athlete','coach','admin') and p.is_active = true),
    (select count(*) from public.profiles p where p.gym_id = g.id and p.role = 'athlete' and p.is_active = true),
    (select count(*) from public.profiles p where p.gym_id = g.id and p.role = 'coach' and p.is_active = true),
    (select count(*) from public.classes c where c.gym_id = g.id and c.starts_at >= date_trunc('month', now()) and c.starts_at < date_trunc('month', now()) + interval '1 month'),
    (select count(*) from public.member_memberships m where m.gym_id = g.id and m.status = 'active' and m.is_active = true),
    coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'email',p.email,'avatar_url',p.avatar_url,'is_active',p.is_active) order by p.full_name nulls last, p.id) from public.profiles p where p.gym_id = g.id and p.role = 'admin'), '[]'::jsonb)
  from public.gyms g where g.id = p_gym_id and g.owner_id = auth.uid();
end;
$$;
create or replace function public.update_owner_gym(
  p_gym_id uuid, p_name text, p_business_name text default null, p_phone text default null,
  p_email text default null, p_website text default null, p_address text default null
)
returns boolean language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_name text := btrim(coalesce(p_name, ''));
begin
  if auth.uid() is null then raise exception using errcode = 'P0001', message = 'unauthenticated'; end if;
  if not exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'owner' and p.is_active = true) then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  if v_name = '' or char_length(v_name) > 100 then raise exception using errcode = '22023', message = 'invalid_gym_name'; end if;
  update public.gyms set
    name = v_name,
    business_name = nullif(btrim(coalesce(p_business_name, '')), ''),
    phone = nullif(btrim(coalesce(p_phone, '')), ''),
    email = nullif(lower(btrim(coalesce(p_email, ''))), ''),
    website = nullif(btrim(coalesce(p_website, '')), ''),
    address = nullif(btrim(coalesce(p_address, '')), '')
  where id = p_gym_id and owner_id = auth.uid();
  if not found then raise exception using errcode = 'P0001', message = 'gym_not_found'; end if;
  return true;
end;
$$;
create or replace function public.get_owner_statistics()
returns table (total_gyms bigint, total_active_members bigint, total_athletes bigint, total_coaches bigint, total_administrators bigint, total_active_memberships bigint, total_classes_current_month bigint)
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then raise exception using errcode = 'P0001', message = 'unauthenticated'; end if;
  if not exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'owner' and p.is_active = true) then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  return query
  with owned as (select id from public.gyms where owner_id = auth.uid())
  select
    (select count(*) from owned),
    (select count(*) from public.profiles p join owned o on o.id=p.gym_id where p.role in ('athlete','coach','admin') and p.is_active=true),
    (select count(*) from public.profiles p join owned o on o.id=p.gym_id where p.role='athlete' and p.is_active=true),
    (select count(*) from public.profiles p join owned o on o.id=p.gym_id where p.role='coach' and p.is_active=true),
    (select count(*) from public.profiles p join owned o on o.id=p.gym_id where p.role='admin'),
    (select count(*) from public.member_memberships m join owned o on o.id=m.gym_id where m.status='active' and m.is_active=true),
    (select count(*) from public.classes c join owned o on o.id=c.gym_id where c.starts_at >= date_trunc('month',now()) and c.starts_at < date_trunc('month',now())+interval '1 month');
end;
$$;
revoke all on function public.list_owner_gyms(text, integer, integer) from public, anon;
revoke all on function public.get_owner_gym(uuid) from public, anon;
revoke all on function public.update_owner_gym(uuid, text, text, text, text, text, text) from public, anon;
revoke all on function public.get_owner_statistics() from public, anon;
grant execute on function public.list_owner_gyms(text, integer, integer) to authenticated;
grant execute on function public.get_owner_gym(uuid) to authenticated;
grant execute on function public.update_owner_gym(uuid, text, text, text, text, text, text) to authenticated;
grant execute on function public.get_owner_statistics() to authenticated;
