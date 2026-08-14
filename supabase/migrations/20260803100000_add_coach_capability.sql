-- Transitional Coach capability. The legacy `role = 'coach'` contract remains
-- supported for Flutter and existing web authorization.
alter table public.profiles
  add column if not exists is_coach boolean not null default false;
update public.profiles
set is_coach = true
where role = 'coach'
  and is_coach is not true;
create or replace function public.validate_class_coach_assignment()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if new.coach_id is null then
    return new;
  end if;

  -- Preserve an existing historical assignment when another class field is
  -- edited after that coach has become inactive or unavailable.
  if tg_op = 'UPDATE'
     and new.coach_id is not distinct from old.coach_id
     and new.gym_id is not distinct from old.gym_id then
    return new;
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = new.coach_id
      and p.gym_id = new.gym_id
      and (p.is_coach = true or p.role = 'coach')
      and p.is_active = true
  ) then
    raise exception 'invalid_class_coach' using errcode = '22023';
  end if;

  return new;
end;
$$;
revoke all on function public.validate_class_coach_assignment() from public;
revoke all on function public.validate_class_coach_assignment() from anon;
revoke all on function public.validate_class_coach_assignment() from authenticated;
create or replace function public.set_member_coach_capability(
  p_member_id uuid,
  p_is_coach boolean
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor public.profiles%rowtype;
  v_member public.profiles%rowtype;
begin
  if auth.uid() is null then
    raise exception using errcode = 'P0001', message = 'unauthenticated';
  end if;
  if p_member_id is null or p_is_coach is null then
    raise exception using errcode = '22023', message = 'invalid_parameters';
  end if;

  select * into v_actor
  from public.profiles
  where id = auth.uid();

  if not found or not coalesce(v_actor.is_active, false) then
    raise exception using errcode = 'P0001', message = 'unauthorized';
  end if;
  if v_actor.role not in ('admin', 'owner') then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  if v_actor.gym_id is null then
    raise exception using errcode = 'P0001', message = 'gym_not_found';
  end if;

  select * into v_member
  from public.profiles
  where id = p_member_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'member_not_found';
  end if;
  if v_member.gym_id is distinct from v_actor.gym_id then
    raise exception using errcode = 'P0001', message = 'cross_gym_forbidden';
  end if;
  if v_member.role = 'owner' then
    raise exception using errcode = 'P0001', message = 'owner_protected';
  end if;

  update public.profiles
  set is_coach = p_is_coach
  where id = v_member.id;

  return true;
end;
$$;
revoke all on function public.set_member_coach_capability(uuid, boolean) from public;
revoke all on function public.set_member_coach_capability(uuid, boolean) from anon;
revoke all on function public.set_member_coach_capability(uuid, boolean) from authenticated;
revoke all on function public.set_member_coach_capability(uuid, boolean) from service_role;
grant execute on function public.set_member_coach_capability(uuid, boolean) to authenticated;
create or replace function public.get_coach_class_summary(
  p_period text default 'week'
)
returns table (
  coach_id uuid,
  coach_name text,
  scheduled_count bigint,
  completed_count bigint
)
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_actor public.profiles%rowtype;
  v_local_now timestamp := now() at time zone 'Europe/Madrid';
  v_start timestamptz;
  v_end timestamptz;
begin
  if p_period not in ('week', 'month') then
    raise exception 'invalid_period' using errcode = '22023';
  end if;
  select * into v_actor from public.profiles where id = auth.uid();
  if v_actor.id is null or v_actor.is_active is not true
     or v_actor.role not in ('admin', 'owner') or v_actor.gym_id is null then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_period = 'week' then
    v_start := date_trunc('week', v_local_now) at time zone 'Europe/Madrid';
    v_end := (date_trunc('week', v_local_now) + interval '1 week') at time zone 'Europe/Madrid';
  else
    v_start := date_trunc('month', v_local_now) at time zone 'Europe/Madrid';
    v_end := (date_trunc('month', v_local_now) + interval '1 month') at time zone 'Europe/Madrid';
  end if;
  return query
  select p.id, coalesce(nullif(btrim(p.full_name), ''), '—'),
    count(c.id), count(c.id) filter (where c.starts_at < now())
  from public.profiles p
  join public.classes c on c.coach_id = p.id
    and c.gym_id = v_actor.gym_id and c.starts_at >= v_start and c.starts_at < v_end
  where p.gym_id = v_actor.gym_id
    and (p.is_coach = true or p.role = 'coach')
    and p.is_active = true
  group by p.id, p.full_name
  order by coalesce(nullif(btrim(p.full_name), ''), '—'), p.id;
end;
$$;
revoke all on function public.get_coach_class_summary(text) from public;
revoke all on function public.get_coach_class_summary(text) from anon;
grant execute on function public.get_coach_class_summary(text) to authenticated;
-- Keep Owner RPC signatures and result contracts unchanged while counting the
-- new capability and each profile only once.
create or replace function public.list_owner_gyms(
  p_search text default null, p_limit integer default 20, p_offset integer default 0
)
returns table (
  gym_id uuid, name text, logo_url text, gym_code text, business_name text,
  created_at timestamptz, administrator_count bigint, active_member_count bigint,
  active_athlete_count bigint, active_coach_count bigint,
  class_count_current_month bigint, active_membership_count bigint, total_count bigint
)
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_search text := nullif(btrim(coalesce(p_search, '')), '');
begin
  if auth.uid() is null then raise exception using errcode='P0001', message='unauthenticated'; end if;
  if not exists (select 1 from public.profiles p where p.id=auth.uid() and p.role='owner' and p.is_active=true) then raise exception using errcode='P0001', message='forbidden'; end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 or p_offset is null or p_offset < 0 or char_length(coalesce(v_search,'')) > 100 then raise exception using errcode='22023', message='invalid_parameters'; end if;
  return query
  with owned as (
    select g.* from public.gyms g where g.owner_id=auth.uid()
      and (v_search is null or g.name ilike '%'||v_search||'%' or coalesce(g.business_name,'') ilike '%'||v_search||'%')
  ), page as (
    select o.*, count(*) over() filtered_total from owned o order by o.created_at desc,o.id desc limit p_limit offset p_offset
  ), profile_counts as (
    select x.gym_id,
      count(*) filter (where x.role='admin') administrators,
      count(*) filter (where x.role in ('athlete','coach','admin') and x.is_active=true) active_members,
      count(*) filter (where x.role='athlete' and x.is_active=true) athletes,
      count(*) filter (where (x.is_coach=true or x.role='coach') and x.is_active=true) coaches
    from public.profiles x join page pg on pg.id=x.gym_id group by x.gym_id
  ), class_counts as (
    select c.gym_id,count(*) classes from public.classes c join page pg on pg.id=c.gym_id
    where c.starts_at>=date_trunc('month',now()) and c.starts_at<date_trunc('month',now())+interval '1 month' group by c.gym_id
  ), membership_counts as (
    select m.gym_id,count(*) memberships from public.member_memberships m join page pg on pg.id=m.gym_id
    where m.status='active' and m.is_active=true group by m.gym_id
  )
  select p.id,p.name,p.logo_url,p.gym_code,p.business_name,p.created_at,
    coalesce(pc.administrators,0),coalesce(pc.active_members,0),coalesce(pc.athletes,0),coalesce(pc.coaches,0),
    coalesce(cc.classes,0),coalesce(mc.memberships,0),p.filtered_total
  from page p left join profile_counts pc on pc.gym_id=p.id left join class_counts cc on cc.gym_id=p.id
  left join membership_counts mc on mc.gym_id=p.id order by p.created_at desc,p.id desc;
end;
$$;
create or replace function public.get_owner_gym(p_gym_id uuid)
returns table (
  gym_id uuid,name text,logo_url text,gym_code text,business_name text,phone text,email text,website text,address text,
  created_at timestamptz,administrator_count bigint,active_member_count bigint,active_athlete_count bigint,
  active_coach_count bigint,class_count_current_month bigint,active_membership_count bigint,administrators jsonb
)
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then raise exception using errcode='P0001',message='unauthenticated'; end if;
  if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='owner' and p.is_active=true) then raise exception using errcode='P0001',message='forbidden'; end if;
  return query select g.id,g.name,g.logo_url,g.gym_code,g.business_name,g.phone,g.email,g.website,g.address,g.created_at,
    (select count(*) from public.profiles p where p.gym_id=g.id and p.role='admin'),
    (select count(*) from public.profiles p where p.gym_id=g.id and p.role in ('athlete','coach','admin') and p.is_active=true),
    (select count(*) from public.profiles p where p.gym_id=g.id and p.role='athlete' and p.is_active=true),
    (select count(*) from public.profiles p where p.gym_id=g.id and (p.is_coach=true or p.role='coach') and p.is_active=true),
    (select count(*) from public.classes c where c.gym_id=g.id and c.starts_at>=date_trunc('month',now()) and c.starts_at<date_trunc('month',now())+interval '1 month'),
    (select count(*) from public.member_memberships m where m.gym_id=g.id and m.status='active' and m.is_active=true),
    coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'email',p.email,'avatar_url',p.avatar_url,'is_active',p.is_active) order by p.full_name nulls last,p.id) from public.profiles p where p.gym_id=g.id and p.role='admin'),'[]'::jsonb)
  from public.gyms g where g.id=p_gym_id and g.owner_id=auth.uid();
end;
$$;
create or replace function public.get_owner_statistics()
returns table(total_gyms bigint,total_active_members bigint,total_athletes bigint,total_coaches bigint,total_administrators bigint,total_active_memberships bigint,total_classes_current_month bigint)
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then raise exception using errcode='P0001',message='unauthenticated'; end if;
  if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='owner' and p.is_active=true) then raise exception using errcode='P0001',message='forbidden'; end if;
  return query with owned as(select id from public.gyms where owner_id=auth.uid()) select
    (select count(*) from owned),
    (select count(*) from public.profiles p join owned o on o.id=p.gym_id where p.role in ('athlete','coach','admin') and p.is_active=true),
    (select count(*) from public.profiles p join owned o on o.id=p.gym_id where p.role='athlete' and p.is_active=true),
    (select count(*) from public.profiles p join owned o on o.id=p.gym_id where (p.is_coach=true or p.role='coach') and p.is_active=true),
    (select count(*) from public.profiles p join owned o on o.id=p.gym_id where p.role='admin'),
    (select count(*) from public.member_memberships m join owned o on o.id=m.gym_id where m.status='active' and m.is_active=true),
    (select count(*) from public.classes c join owned o on o.id=c.gym_id where c.starts_at>=date_trunc('month',now()) and c.starts_at<date_trunc('month',now())+interval '1 month');
end;
$$;
revoke all on function public.list_owner_gyms(text,integer,integer) from public,anon;
revoke all on function public.get_owner_gym(uuid) from public,anon;
revoke all on function public.get_owner_statistics() from public,anon;
grant execute on function public.list_owner_gyms(text,integer,integer) to authenticated;
grant execute on function public.get_owner_gym(uuid) to authenticated;
grant execute on function public.get_owner_statistics() to authenticated;
