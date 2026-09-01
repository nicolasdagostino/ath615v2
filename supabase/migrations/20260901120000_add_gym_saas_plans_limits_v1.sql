-- SaaS Plans & Limits V1. Entitlements only: no billing, prices or payment state.

create table public.saas_plans (
  code text primary key,
  name text not null,
  active_member_limit integer,
  is_active boolean not null default true,
  sort_order integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint saas_plans_code_check check (code=lower(code)),
  constraint saas_plans_limit_check check (active_member_limit is null or active_member_limit>=0)
);

insert into public.saas_plans(code,name,active_member_limit,sort_order) values
  ('free','FREE',10,10),('starter','STARTER',40,20),('growth','GROWTH',100,30),
  ('pro','PRO',250,40),('unlimited','UNLIMITED',null,50);

create table public.gym_saas_subscriptions (
  gym_id uuid primary key references public.gyms(id) on delete cascade,
  plan_code text not null references public.saas_plans(code),
  status text not null default 'active' check(status in('active','trialing','paused')),
  override_member_limit integer check(override_member_limit is null or override_member_limit>=0),
  started_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  changed_by uuid references public.profiles(id) on delete set null
);

create table public.gym_saas_member_slot_reservations (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  created_by uuid not null references public.profiles(id) on delete cascade,
  email_normalized text not null,
  expires_at timestamptz not null default (now()+interval '15 minutes'),
  consumed_at timestamptz,
  released_at timestamptz,
  created_at timestamptz not null default now(),
  constraint gym_saas_slot_reservation_email_check check(email_normalized=lower(btrim(email_normalized))),
  constraint gym_saas_slot_reservation_state_check check(consumed_at is null or released_at is null)
);
create index gym_saas_slot_reservations_active_idx
  on public.gym_saas_member_slot_reservations(gym_id,expires_at)
  where consumed_at is null and released_at is null;

create function public.saas_plan_code_for_active_athletes(p_count bigint)
returns text language sql immutable set search_path=public,pg_temp as $function$
  select case when p_count<=10 then 'free' when p_count<=40 then 'starter'
    when p_count<=100 then 'growth' when p_count<=250 then 'pro' else 'unlimited' end
$function$;

-- Existing gyms receive the smallest natural tier that covers current use.
-- Overrides remain NULL and no operational/member data is changed.
insert into public.gym_saas_subscriptions(gym_id,plan_code,override_member_limit)
select g.id,public.saas_plan_code_for_active_athletes(
  count(gm.user_id) filter(where gm.role='athlete' and gm.is_active)),null
from public.gyms g left join public.gym_members gm on gm.gym_id=g.id group by g.id;

create function public.assign_default_gym_saas_subscription()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $function$
begin
  insert into public.gym_saas_subscriptions(gym_id,plan_code) values(new.id,'free')
  on conflict(gym_id) do nothing;
  return new;
end $function$;
create trigger assign_default_gym_saas_subscription
after insert on public.gyms for each row execute function public.assign_default_gym_saas_subscription();

create function public.gym_saas_usage_for(p_gym_id uuid)
returns table(plan_code text,plan_name text,active_member_limit integer,active_athlete_count bigint,
  remaining_slots bigint,limit_reached boolean,over_limit boolean,plan_status text)
language sql stable security definer set search_path=public,pg_temp as $function$
  select s.plan_code,p.name,coalesce(s.override_member_limit,p.active_member_limit),
    count(gm.user_id) filter(where gm.role='athlete' and gm.is_active),
    case when coalesce(s.override_member_limit,p.active_member_limit) is null then null
      else greatest(coalesce(s.override_member_limit,p.active_member_limit)-count(gm.user_id) filter(where gm.role='athlete' and gm.is_active),0) end,
    coalesce(s.override_member_limit,p.active_member_limit) is not null and
      count(gm.user_id) filter(where gm.role='athlete' and gm.is_active)=coalesce(s.override_member_limit,p.active_member_limit),
    coalesce(s.override_member_limit,p.active_member_limit) is not null and
      count(gm.user_id) filter(where gm.role='athlete' and gm.is_active)>coalesce(s.override_member_limit,p.active_member_limit),s.status
  from public.gym_saas_subscriptions s join public.saas_plans p on p.code=s.plan_code
  left join public.gym_members gm on gm.gym_id=s.gym_id where s.gym_id=p_gym_id
  group by s.plan_code,p.name,s.override_member_limit,p.active_member_limit,s.status
$function$;

create function public.get_effective_gym_saas_usage()
returns table(plan_code text,plan_name text,active_member_limit integer,active_athlete_count bigint,
  remaining_slots bigint,limit_reached boolean,over_limit boolean,plan_status text)
language plpgsql stable security definer set search_path=public,pg_temp as $function$
declare v_gym_id uuid:=public.effective_gym_id();
begin
  if v_gym_id is null or public.effective_gym_role()<>'admin' then
    raise exception using errcode='42501',message='forbidden';
  end if;
  return query select * from public.gym_saas_usage_for(v_gym_id);
end $function$;

create function public.reserve_effective_gym_athlete_slot(p_email text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $function$
declare v_gym_id uuid:=public.effective_gym_id(); v_email text:=lower(btrim(coalesce(p_email,'')));
  v_limit integer; v_active bigint; v_reserved bigint; v_id uuid;
begin
  if v_gym_id is null or public.effective_gym_role()<>'admin' then
    raise exception using errcode='42501',message='forbidden';
  end if;
  if v_email='' or length(v_email)>254 then raise exception using errcode='22023',message='invalid_email'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_gym_id::text,615));
  select r.id into v_id from public.gym_saas_member_slot_reservations r
    where r.gym_id=v_gym_id and r.created_by=auth.uid() and r.email_normalized=v_email
      and r.consumed_at is null and r.released_at is null and r.expires_at>clock_timestamp()
    order by r.created_at desc limit 1;
  if v_id is not null then return v_id; end if;
  select active_member_limit,active_athlete_count into v_limit,v_active from public.gym_saas_usage_for(v_gym_id);
  select count(*) into v_reserved from public.gym_saas_member_slot_reservations r
    where r.gym_id=v_gym_id and r.consumed_at is null and r.released_at is null and r.expires_at>clock_timestamp();
  if v_limit is not null and v_active+v_reserved>=v_limit then
    raise exception using errcode='P0001',message='gym_member_limit_reached';
  end if;
  insert into public.gym_saas_member_slot_reservations(gym_id,created_by,email_normalized)
    values(v_gym_id,auth.uid(),v_email) returning id into v_id;
  return v_id;
end $function$;

create function public.release_gym_athlete_slot_reservation(p_reservation_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $function$
begin
  update public.gym_saas_member_slot_reservations set released_at=clock_timestamp()
  where id=p_reservation_id and consumed_at is null and released_at is null
    and (created_by=auth.uid() or auth.role()='service_role');
end $function$;

create function public.materialize_reserved_gym_athlete(p_reservation_id uuid,p_user_id uuid,p_invited_by uuid)
returns text language plpgsql security definer set search_path=public,pg_temp as $function$
declare r public.gym_saas_member_slot_reservations%rowtype; existing public.gym_members%rowtype; action text; user_email text;
begin
  if auth.role()<>'service_role' then raise exception using errcode='42501',message='forbidden'; end if;
  select * into r from public.gym_saas_member_slot_reservations where id=p_reservation_id for update;
  if not found or r.created_by is distinct from p_invited_by or r.consumed_at is not null
    or r.released_at is not null or r.expires_at<=clock_timestamp() then
    raise exception using errcode='P0001',message='invalid_or_expired_slot_reservation';
  end if;
  select lower(btrim(u.email)) into user_email from auth.users u where u.id=p_user_id;
  if user_email is null or user_email<>r.email_normalized then
    raise exception using errcode='42501',message='reservation_identity_mismatch';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(r.gym_id::text,615));
  perform set_config('app.saas_reservation_id',r.id::text,true);
  select * into existing from public.gym_members where gym_id=r.gym_id and user_id=p_user_id for update;
  action:=case when not found then 'created' when existing.role='athlete' and existing.is_active then 'already_active'
    when not existing.is_active then 'reactivated' else 'converted' end;
  insert into public.gym_members(gym_id,user_id,role,is_active,is_coach,joined_at,invited_by)
  values(r.gym_id,p_user_id,'athlete',true,coalesce(existing.is_coach,false),clock_timestamp(),p_invited_by)
  on conflict(gym_id,user_id) do update set role='athlete',is_active=true,
    is_coach=public.gym_members.is_coach,invited_by=excluded.invited_by,updated_at=clock_timestamp();
  update public.gym_saas_member_slot_reservations set consumed_at=clock_timestamp() where id=r.id;
  return action;
end $function$;

create function public.assert_effective_gym_athlete_slot()
returns void language plpgsql security definer set search_path=public,pg_temp as $function$
declare v_gym_id uuid:=public.effective_gym_id(); v_limit integer; v_count bigint; v_reserved bigint;
begin
  if v_gym_id is null or public.effective_gym_role()<>'admin' then
    raise exception using errcode='42501',message='forbidden';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_gym_id::text,615));
  select active_member_limit,active_athlete_count into v_limit,v_count from public.gym_saas_usage_for(v_gym_id);
  select count(*) into v_reserved from public.gym_saas_member_slot_reservations r where r.gym_id=v_gym_id
    and r.consumed_at is null and r.released_at is null and r.expires_at>clock_timestamp();
  if v_limit is not null and v_count+v_reserved>=v_limit then
    raise exception using errcode='P0001',message='gym_member_limit_reached';
  end if;
end $function$;

create function public.enforce_gym_active_athlete_limit()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $function$
declare v_limit integer; v_count bigint; v_reserved bigint; v_current_reservation uuid;
begin
  if new.role='athlete' and new.is_active and
    (tg_op='INSERT' or old.role is distinct from 'athlete' or old.is_active is distinct from true) then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.gym_id::text,615));
    select active_member_limit,active_athlete_count into v_limit,v_count from public.gym_saas_usage_for(new.gym_id);
    begin v_current_reservation:=nullif(current_setting('app.saas_reservation_id',true),'')::uuid;
    exception when invalid_text_representation then v_current_reservation:=null; end;
    select count(*) into v_reserved from public.gym_saas_member_slot_reservations r where r.gym_id=new.gym_id
      and r.consumed_at is null and r.released_at is null and r.expires_at>clock_timestamp()
      and r.id is distinct from v_current_reservation;
    if v_limit is not null and v_count+v_reserved>=v_limit then
      raise exception using errcode='P0001',message='gym_member_limit_reached';
    end if;
  end if;
  return new;
end $function$;
create trigger enforce_gym_active_athlete_limit before insert or update of role,is_active on public.gym_members
for each row execute function public.enforce_gym_active_athlete_limit();

create function public.platform_set_gym_saas_subscription(p_gym_id uuid,p_plan_code text,p_override_member_limit integer default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $function$
begin
  if not public.platform_owner_active() then raise exception using errcode='42501',message='platform_owner_required'; end if;
  if not exists(select 1 from public.saas_plans where code=p_plan_code and is_active) then
    raise exception using errcode='22023',message='invalid_saas_plan'; end if;
  if p_override_member_limit is not null and p_override_member_limit<0 then
    raise exception using errcode='22023',message='invalid_member_limit_override'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_gym_id::text,615));
  update public.gym_saas_subscriptions set plan_code=p_plan_code,
    override_member_limit=p_override_member_limit,updated_at=clock_timestamp(),changed_by=auth.uid()
  where gym_id=p_gym_id;
  if not found then raise exception using errcode='P0002',message='gym_not_found'; end if;
end $function$;

drop function public.list_owner_gym_overview();
create function public.list_owner_gym_overview()
returns table(gym_id uuid,gym_name text,lifecycle_status text,created_at timestamptz,last_activity_at timestamptz,
 active_member_count bigint,admin_count bigint,coach_count bigint,athlete_count bigint,active_membership_count bigint,
 stripe_account_id text,stripe_onboarding_complete boolean,stripe_charges_enabled boolean,stripe_payouts_enabled boolean,
 saas_plan_code text,saas_plan_name text,saas_active_member_limit integer,saas_active_athlete_count bigint,
 saas_remaining_slots bigint,saas_limit_reached boolean,saas_over_limit boolean,saas_plan_status text)
language plpgsql stable security definer set search_path=public,pg_temp as $function$
begin
 if not public.platform_owner_active() then raise exception using errcode='42501',message='platform_owner_required'; end if;
 return query with mc as (
  select gm.gym_id,count(*) filter(where gm.is_active) members,count(*) filter(where gm.is_active and gm.role='admin') admins,
   count(*) filter(where gm.is_active and (gm.role='coach' or gm.is_coach)) coaches,
   count(*) filter(where gm.is_active and gm.role='athlete') athletes from public.gym_members gm group by gm.gym_id),
 mm as(select m.gym_id,count(*) memberships from public.member_memberships m where m.is_active and m.status='active' group by m.gym_id),
 activity as(select e.gym_id,max(e.occurred_at) last_at from public.gym_activity_events e group by e.gym_id)
 select g.id,g.name,g.lifecycle_status,g.created_at,a.last_at,coalesce(mc.members,0),coalesce(mc.admins,0),coalesce(mc.coaches,0),
  coalesce(mc.athletes,0),coalesce(mm.memberships,0),g.stripe_account_id,coalesce(g.stripe_onboarding_complete,false),
  coalesce(g.stripe_charges_enabled,false),coalesce(g.stripe_payouts_enabled,false),u.plan_code,u.plan_name,u.active_member_limit,
  u.active_athlete_count,u.remaining_slots,u.limit_reached,u.over_limit,u.plan_status
 from public.gyms g left join mc on mc.gym_id=g.id left join mm on mm.gym_id=g.id left join activity a on a.gym_id=g.id
 cross join lateral public.gym_saas_usage_for(g.id) u order by lower(g.name),g.id;
end $function$;

alter table public.saas_plans enable row level security;
alter table public.gym_saas_subscriptions enable row level security;
alter table public.gym_saas_member_slot_reservations enable row level security;
revoke all on table public.saas_plans,public.gym_saas_subscriptions,public.gym_saas_member_slot_reservations from public,anon,authenticated;
grant select on table public.saas_plans to authenticated;
create policy "authenticated read active SaaS catalog" on public.saas_plans
  for select to authenticated using(is_active);
revoke all on function public.saas_plan_code_for_active_athletes(bigint) from public,anon,authenticated,service_role;
revoke all on function public.gym_saas_usage_for(uuid) from public,anon,authenticated,service_role;
revoke all on function public.assert_effective_gym_athlete_slot() from public,anon,authenticated;
revoke all on function public.get_effective_gym_saas_usage() from public,anon,authenticated;
revoke all on function public.platform_set_gym_saas_subscription(uuid,text,integer) from public,anon,authenticated;
grant execute on function public.assert_effective_gym_athlete_slot() to authenticated,service_role;
grant execute on function public.get_effective_gym_saas_usage() to authenticated,service_role;
grant execute on function public.platform_set_gym_saas_subscription(uuid,text,integer) to authenticated;
grant execute on function public.list_owner_gym_overview() to authenticated;
revoke all on function public.reserve_effective_gym_athlete_slot(text) from public,anon,authenticated;
revoke all on function public.release_gym_athlete_slot_reservation(uuid) from public,anon,authenticated;
revoke all on function public.materialize_reserved_gym_athlete(uuid,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.reserve_effective_gym_athlete_slot(text) to authenticated;
grant execute on function public.release_gym_athlete_slot_reservation(uuid) to authenticated,service_role;
grant execute on function public.materialize_reserved_gym_athlete(uuid,uuid,uuid) to service_role;
