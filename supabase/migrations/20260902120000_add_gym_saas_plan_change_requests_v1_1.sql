-- SaaS Plans V1.1: commercial catalog and manually reviewed plan changes.
-- Entitlements only. No billing, checkout, invoices or payment state.

alter table public.saas_plans
  add column monthly_price_eur integer;

update public.saas_plans set monthly_price_eur=case code
  when 'free' then 0 when 'starter' then 19 when 'growth' then 39
  when 'pro' then 59 when 'unlimited' then 79 end;

alter table public.saas_plans
  alter column monthly_price_eur set not null,
  add constraint saas_plans_monthly_price_eur_check check(monthly_price_eur>=0);

create table public.gym_saas_plan_change_requests (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  requested_by uuid not null references public.profiles(id) on delete restrict,
  current_plan_code text not null references public.saas_plans(code),
  requested_plan_code text not null references public.saas_plans(code),
  status text not null default 'pending' check(status in('pending','approved','rejected','cancelled')),
  requested_at timestamptz not null default clock_timestamp(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete set null,
  rejection_reason text,
  constraint gym_saas_plan_change_different_check check(current_plan_code<>requested_plan_code),
  constraint gym_saas_plan_change_review_check check(
    (status='pending' and reviewed_at is null and reviewed_by is null)
    or (status='cancelled' and reviewed_at is not null)
    or (status in('approved','rejected') and reviewed_at is not null and reviewed_by is not null)
  )
);

create unique index gym_saas_plan_change_one_pending_idx
  on public.gym_saas_plan_change_requests(gym_id) where status='pending';
create index gym_saas_plan_change_pending_requested_idx
  on public.gym_saas_plan_change_requests(status,requested_at);

alter table public.gym_saas_plan_change_requests enable row level security;
revoke all on table public.gym_saas_plan_change_requests from public,anon,authenticated;

create function public.request_effective_gym_saas_plan_change(p_requested_plan_code text)
returns public.gym_saas_plan_change_requests
language plpgsql security definer set search_path=public,pg_temp as $function$
declare
  v_gym_id uuid:=public.effective_gym_id();
  v_current text; v_requested text:=lower(btrim(p_requested_plan_code)); v_limit integer; v_active bigint;
  v_request public.gym_saas_plan_change_requests;
begin
  if v_gym_id is null or public.effective_gym_role()<>'admin' then
    raise exception using errcode='42501',message='forbidden';
  end if;
  if not exists(select 1 from public.gyms where id=v_gym_id and lifecycle_status='active') then
    raise exception using errcode='P0001',message='saas_plan_change_lifecycle_invalid';
  end if;
  select p.code,p.active_member_limit into v_requested,v_limit
  from public.saas_plans p where p.code=v_requested and p.is_active;
  if not found then raise exception using errcode='P0001',message='saas_plan_not_found'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_gym_id::text,615));
  select plan_code into v_current from public.gym_saas_subscriptions where gym_id=v_gym_id for update;
  if v_current=v_requested then raise exception using errcode='P0001',message='saas_plan_unchanged'; end if;
  if exists(select 1 from public.gym_saas_plan_change_requests where gym_id=v_gym_id and status='pending') then
    raise exception using errcode='P0001',message='saas_plan_change_pending';
  end if;
  select active_athlete_count into v_active from public.gym_saas_usage_for(v_gym_id);
  if v_limit is not null and v_active>v_limit then
    raise exception using errcode='P0001',message='saas_plan_capacity_too_low';
  end if;
  insert into public.gym_saas_plan_change_requests(gym_id,requested_by,current_plan_code,requested_plan_code)
  values(v_gym_id,auth.uid(),v_current,v_requested) returning * into v_request;
  return v_request;
end $function$;

create function public.get_effective_gym_pending_saas_plan_change()
returns table(id uuid,gym_id uuid,current_plan_code text,requested_plan_code text,status text,requested_at timestamptz)
language plpgsql stable security definer set search_path=public,pg_temp as $function$
declare v_gym_id uuid:=public.effective_gym_id();
begin
  if v_gym_id is null or public.effective_gym_role()<>'admin' then
    raise exception using errcode='42501',message='forbidden';
  end if;
  return query select r.id,r.gym_id,r.current_plan_code,r.requested_plan_code,r.status,r.requested_at
  from public.gym_saas_plan_change_requests r where r.gym_id=v_gym_id and r.status='pending';
end $function$;

create function public.cancel_effective_gym_saas_plan_change(p_request_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $function$
declare v_gym_id uuid:=public.effective_gym_id();
begin
  if v_gym_id is null or public.effective_gym_role()<>'admin' then
    raise exception using errcode='42501',message='forbidden';
  end if;
  update public.gym_saas_plan_change_requests set status='cancelled',reviewed_at=clock_timestamp()
  where id=p_request_id and gym_id=v_gym_id and requested_by=auth.uid() and status='pending';
  if not found then raise exception using errcode='P0001',message='saas_plan_change_not_pending'; end if;
end $function$;

create function public.list_platform_saas_plan_change_requests(p_status text default 'pending')
returns table(id uuid,gym_id uuid,gym_name text,current_plan_code text,current_plan_name text,current_price_eur integer,
 requested_plan_code text,requested_plan_name text,requested_price_eur integer,requested_member_limit integer,
 active_athlete_count bigint,status text,requested_at timestamptz,requested_by uuid,reviewed_at timestamptz,
 reviewed_by uuid,rejection_reason text)
language plpgsql stable security definer set search_path=public,pg_temp as $function$
begin
  if not public.platform_owner_active() then raise exception using errcode='42501',message='platform_owner_required'; end if;
  return query select r.id,r.gym_id,g.name,r.current_plan_code,cp.name,cp.monthly_price_eur,
    r.requested_plan_code,rp.name,rp.monthly_price_eur,rp.active_member_limit,u.active_athlete_count,
    r.status,r.requested_at,r.requested_by,r.reviewed_at,r.reviewed_by,r.rejection_reason
  from public.gym_saas_plan_change_requests r join public.gyms g on g.id=r.gym_id
  join public.saas_plans cp on cp.code=r.current_plan_code join public.saas_plans rp on rp.code=r.requested_plan_code
  cross join lateral public.gym_saas_usage_for(r.gym_id) u
  where p_status is null or r.status=p_status order by r.requested_at;
end $function$;

create function public.platform_review_saas_plan_change(p_request_id uuid,p_approve boolean,p_rejection_reason text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $function$
declare r public.gym_saas_plan_change_requests%rowtype; v_limit integer; v_active bigint;
begin
  if not public.platform_owner_active() then raise exception using errcode='42501',message='platform_owner_required'; end if;
  select * into r from public.gym_saas_plan_change_requests where id=p_request_id for update;
  if not found or r.status<>'pending' then raise exception using errcode='P0001',message='saas_plan_change_not_pending'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(r.gym_id::text,615));
  if p_approve then
    if not exists(select 1 from public.gyms where id=r.gym_id and lifecycle_status='active') then
      raise exception using errcode='P0001',message='saas_plan_change_lifecycle_invalid';
    end if;
    select active_member_limit into v_limit from public.saas_plans where code=r.requested_plan_code and is_active;
    if not found then raise exception using errcode='P0001',message='saas_plan_not_found'; end if;
    select active_athlete_count into v_active from public.gym_saas_usage_for(r.gym_id);
    if v_limit is not null and v_active>v_limit then
      raise exception using errcode='P0001',message='saas_plan_capacity_too_low';
    end if;
    update public.gym_saas_subscriptions set plan_code=r.requested_plan_code,override_member_limit=null,
      updated_at=clock_timestamp(),changed_by=auth.uid() where gym_id=r.gym_id;
    update public.gym_saas_plan_change_requests set status='approved',reviewed_at=clock_timestamp(),
      reviewed_by=auth.uid(),rejection_reason=null where id=r.id;
  else
    update public.gym_saas_plan_change_requests set status='rejected',reviewed_at=clock_timestamp(),
      reviewed_by=auth.uid(),rejection_reason=nullif(btrim(p_rejection_reason),'') where id=r.id;
  end if;
end $function$;

revoke all on function public.request_effective_gym_saas_plan_change(text) from public,anon,authenticated;
revoke all on function public.get_effective_gym_pending_saas_plan_change() from public,anon,authenticated;
revoke all on function public.cancel_effective_gym_saas_plan_change(uuid) from public,anon,authenticated;
revoke all on function public.list_platform_saas_plan_change_requests(text) from public,anon,authenticated;
revoke all on function public.platform_review_saas_plan_change(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.request_effective_gym_saas_plan_change(text),
 public.get_effective_gym_pending_saas_plan_change(),public.cancel_effective_gym_saas_plan_change(uuid) to authenticated;
grant execute on function public.list_platform_saas_plan_change_requests(text),
 public.platform_review_saas_plan_change(uuid,boolean,text) to authenticated;
