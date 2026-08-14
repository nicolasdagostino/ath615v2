-- Vertical 3D: Membership catalog, CRUD and requests use one effective gym.
-- Registered Web sessions are relational; unregistered Flutter sessions keep
-- the profiles-based fallback implemented by effective_gym_*().

begin;
create or replace function public.membership_actor_is_active()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when auth.uid() is null then false
    when public.is_registered_web_session() then public.effective_gym_id() is not null
    else coalesce((select p.is_active from public.profiles p where p.id=auth.uid()),false)
  end;
$$;
create or replace function public.membership_actor_can_manage()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.membership_actor_is_active()
    and public.effective_gym_id() is not null
    and public.effective_gym_role() in ('admin','owner');
$$;
create or replace function public.validate_membership_plan_row()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  new.name:=btrim(new.name);
  new.currency:=upper(btrim(new.currency));
  if new.name='' then raise exception 'invalid_plan_name' using errcode='22023'; end if;
  if new.plan_type not in ('class_pack','unlimited') then raise exception 'invalid_plan_type' using errcode='22023'; end if;
  if new.plan_type='class_pack' and (new.credits is null or new.credits<=0) then
    raise exception 'invalid_plan_credits' using errcode='22023';
  end if;
  if new.plan_type='unlimited' then new.credits:=null; end if;
  if new.price is not null and new.price<0 then raise exception 'invalid_plan_price' using errcode='22023'; end if;
  if new.currency='' then raise exception 'invalid_plan_currency' using errcode='22023'; end if;
  if new.duration_days<1 then raise exception 'invalid_plan_duration' using errcode='22023'; end if;
  return new;
end;
$function$;
drop trigger if exists validate_membership_plan_row on public.membership_plans;
create trigger validate_membership_plan_row
before insert or update on public.membership_plans
for each row execute function public.validate_membership_plan_row();
drop policy if exists "admins can manage membership plans" on public.membership_plans;
drop policy if exists "members can read active membership plans" on public.membership_plans;
create policy "effective admins manage membership plans"
on public.membership_plans for all to authenticated
using (gym_id=public.effective_gym_id() and public.membership_actor_can_manage())
with check (gym_id=public.effective_gym_id() and public.membership_actor_can_manage());
create policy "effective members read active membership plans"
on public.membership_plans for select to authenticated
using (
  gym_id=public.effective_gym_id() and is_active=true
  and public.membership_actor_is_active()
);
drop policy if exists "admin manage gym memberships" on public.member_memberships;
drop policy if exists "admin read gym memberships" on public.member_memberships;
drop policy if exists "admins can manage member memberships" on public.member_memberships;
drop policy if exists "read own memberships" on public.member_memberships;
create policy "effective admins read gym memberships"
on public.member_memberships for select to authenticated
using (gym_id=public.effective_gym_id() and public.membership_actor_can_manage());
create policy "effective members read own memberships"
on public.member_memberships for select to authenticated
using (user_id=auth.uid() and gym_id=public.effective_gym_id());
drop policy if exists "admins can read gym credit logs" on public.membership_credit_logs;
drop policy if exists "members can read own credit logs" on public.membership_credit_logs;
create policy "effective admins read gym credit logs"
on public.membership_credit_logs for select to authenticated
using (gym_id=public.effective_gym_id() and public.membership_actor_can_manage());
create policy "effective members read own credit logs"
on public.membership_credit_logs for select to authenticated
using (user_id=auth.uid() and gym_id=public.effective_gym_id());
drop policy if exists "Users can create own membership requests" on public.membership_requests;
drop policy if exists "Admins can read gym membership requests" on public.membership_requests;
drop policy if exists "Users can read own membership requests" on public.membership_requests;
drop policy if exists "Admins can update gym membership requests" on public.membership_requests;
create policy "effective members create own membership requests"
on public.membership_requests for insert to authenticated
with check (
  user_id=auth.uid()
  and gym_id=public.effective_gym_id()
  and public.membership_actor_is_active()
  and status='pending'
  and payment_method in ('cash','card')
  and payment_status='pending'
  and stripe_checkout_session_id is null
  and stripe_payment_intent_id is null
  and paid_at is null
  and exists (
    select 1 from public.membership_plans mp
    where mp.id=membership_requests.plan_id
      and mp.gym_id=membership_requests.gym_id
      and mp.is_active=true
  )
);
create policy "effective admins read gym membership requests"
on public.membership_requests for select to authenticated
using (gym_id=public.effective_gym_id() and public.membership_actor_can_manage());
create policy "effective members read own membership requests"
on public.membership_requests for select to authenticated
using (user_id=auth.uid() and gym_id=public.effective_gym_id());
-- Flutter currently rejects requests through a direct UPDATE. Keep that
-- contract, but replace its legacy authority with the one effective gym.
create policy "effective admins update gym membership requests"
on public.membership_requests for update to authenticated
using (gym_id=public.effective_gym_id() and public.membership_actor_can_manage())
with check (gym_id=public.effective_gym_id() and public.membership_actor_can_manage());
create unique index if not exists membership_requests_one_pending_plan_idx
on public.membership_requests(user_id,gym_id,plan_id)
where status='pending';
create or replace function public.list_membership_plan_catalog(
  p_search text default null,
  p_status text default 'all',
  p_plan_type text default 'all',
  p_limit integer default 12,
  p_offset integer default 0
)
returns table(
  plan_id uuid,name text,plan_type text,credits integer,price numeric,currency text,
  duration_days integer,is_active boolean,created_at timestamptz,
  active_memberships bigint,scheduled_memberships bigint,
  historical_memberships bigint,pending_requests bigint,total_count bigint
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id(); v_search text:=nullif(btrim(coalesce(p_search,'')),'');
begin
  if auth.uid() is null or v_gym_id is null or not public.membership_actor_can_manage() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  if p_status not in ('all','active','inactive') or p_plan_type not in ('all','class_pack','unlimited')
     or p_limit<1 or p_limit>50 or p_offset<0 then
    raise exception 'invalid_parameters' using errcode='22023';
  end if;
  return query
  with filtered as (
    select mp.*,count(*) over() matched_count
    from public.membership_plans mp
    where mp.gym_id=v_gym_id
      and (v_search is null or mp.name ilike '%'||v_search||'%')
      and (p_status='all' or mp.is_active=(p_status='active'))
      and (p_plan_type='all' or mp.plan_type=p_plan_type)
    order by mp.is_active desc,mp.created_at desc,mp.id
    limit p_limit offset p_offset
  ), mc as (
    select mm.plan_id,
      count(*) filter(where mm.status='active' and mm.is_active) active_count,
      count(*) filter(where mm.status='scheduled' and mm.is_active) scheduled_count,
      count(*) filter(where mm.status not in ('active','scheduled') or not mm.is_active) historical_count
    from public.member_memberships mm
    where mm.gym_id=v_gym_id and mm.plan_id in(select f.id from filtered f)
    group by mm.plan_id
  ), rc as (
    select mr.plan_id,count(*) pending_count from public.membership_requests mr
    where mr.gym_id=v_gym_id and mr.status='pending' and mr.plan_id in(select f.id from filtered f)
    group by mr.plan_id
  )
  select f.id,f.name,f.plan_type,f.credits,f.price,f.currency,f.duration_days,
    coalesce(f.is_active,false),f.created_at,coalesce(mc.active_count,0),
    coalesce(mc.scheduled_count,0),coalesce(mc.historical_count,0),
    coalesce(rc.pending_count,0),f.matched_count
  from filtered f left join mc on mc.plan_id=f.id left join rc on rc.plan_id=f.id
  order by f.is_active desc,f.created_at desc,f.id;
end;
$function$;
create or replace function public.list_effective_available_membership_plans()
returns table(plan_id uuid,name text,plan_type text,credits integer,price numeric,currency text,duration_days integer,created_at timestamptz)
language plpgsql stable security definer set search_path=public,pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id();
begin
  if auth.uid() is null or v_gym_id is null or not public.membership_actor_is_active() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  return query select mp.id,mp.name,mp.plan_type,mp.credits,mp.price,mp.currency,mp.duration_days,mp.created_at
  from public.membership_plans mp where mp.gym_id=v_gym_id and mp.is_active=true
  order by mp.created_at,mp.id;
end;
$function$;
create or replace function public.get_effective_membership_access()
returns text language plpgsql stable security definer set search_path=public,pg_temp
as $function$
begin
  if auth.uid() is null or public.effective_gym_id() is null or not public.membership_actor_is_active() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  return case when public.membership_actor_can_manage() then 'admin' else 'personal' end;
end;
$function$;
create or replace function public.list_effective_memberships(
  p_status text default 'all', p_limit integer default 12, p_offset integer default 0
)
returns table(
  user_id uuid,plan_id uuid,credits_remaining integer,starts_at timestamptz,
  expires_at timestamptz,status text,is_active boolean,created_at timestamptz,
  full_name text,email text,plan_name text,plan_type text,plan_credits integer,total_count bigint
)
language plpgsql stable security definer set search_path=public,pg_temp
as $function$
declare v_user_id uuid:=auth.uid(); v_gym_id uuid:=public.effective_gym_id();
begin
  if v_user_id is null or v_gym_id is null or not public.membership_actor_is_active()
     or p_status not in ('all','active','scheduled','exhausted','expired','cancelled','replaced')
     or p_limit<1 or p_limit>50 or p_offset<0 then
    raise exception 'forbidden' using errcode='42501';
  end if;
  return query
  select mm.user_id,mm.plan_id,mm.credits_remaining,mm.starts_at,mm.expires_at,
    mm.status,mm.is_active,mm.created_at,p.full_name,p.email,mp.name,mp.plan_type,
    mp.credits,count(*) over()
  from public.member_memberships mm
  left join public.profiles p on p.id=mm.user_id
  left join public.membership_plans mp on mp.id=mm.plan_id and mp.gym_id=mm.gym_id
  where mm.user_id=v_user_id and mm.gym_id=v_gym_id
    and (p_status='all' or mm.status=p_status)
  order by mm.created_at desc,mm.id desc limit p_limit offset p_offset;
end;
$function$;
create or replace function public.create_effective_membership_plan(
  p_name text,p_plan_type text,p_credits integer,p_price numeric,p_currency text,p_duration_days integer
)
returns uuid language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id(); v_id uuid;
begin
  if auth.uid() is null or v_gym_id is null or not public.membership_actor_can_manage() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  insert into public.membership_plans(gym_id,name,plan_type,credits,price,currency,duration_days,is_active)
  values(v_gym_id,p_name,p_plan_type,p_credits,p_price,p_currency,p_duration_days,true)
  returning id into v_id;
  return v_id;
end;
$function$;
create or replace function public.update_effective_membership_plan(
  p_plan_id uuid,p_name text,p_plan_type text,p_credits integer,p_price numeric,p_currency text,p_duration_days integer
)
returns boolean language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id();
begin
  if auth.uid() is null or v_gym_id is null or not public.membership_actor_can_manage() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  update public.membership_plans set name=p_name,plan_type=p_plan_type,credits=p_credits,
    price=p_price,currency=p_currency,duration_days=p_duration_days
  where id=p_plan_id and gym_id=v_gym_id;
  return found;
end;
$function$;
create or replace function public.toggle_effective_membership_plan(p_plan_id uuid)
returns boolean language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id(); v_active boolean;
begin
  if auth.uid() is null or v_gym_id is null or not public.membership_actor_can_manage() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  update public.membership_plans set is_active=not coalesce(is_active,false)
  where id=p_plan_id and gym_id=v_gym_id returning is_active into v_active;
  if not found then raise exception 'plan_not_found' using errcode='P0001'; end if;
  return true;
end;
$function$;
create or replace function public.delete_unused_membership_plan(p_plan_id uuid)
returns text language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id(); v_plan public.membership_plans%rowtype;
begin
  if auth.uid() is null or v_gym_id is null or not public.membership_actor_can_manage() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_plan_id::text,617));
  select * into v_plan from public.membership_plans where id=p_plan_id and gym_id=v_gym_id for update;
  if not found then return 'not_found'; end if;
  if exists(select 1 from public.member_memberships where plan_id=v_plan.id)
     or exists(select 1 from public.membership_requests where plan_id=v_plan.id) then return 'in_use'; end if;
  delete from public.membership_plans where id=v_plan.id and gym_id=v_gym_id;
  return 'deleted';
end;
$function$;
create or replace function public.list_effective_membership_requests(p_own boolean default false,p_limit integer default 50)
returns table(
  request_id uuid,user_id uuid,plan_id uuid,status text,payment_method text,payment_status text,
  created_at timestamptz,member_name text,member_email text,plan_name text,plan_type text,
  plan_price numeric,currency text
)
language plpgsql stable security definer set search_path=public,pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id();
begin
  if auth.uid() is null or v_gym_id is null or not public.membership_actor_is_active()
     or p_limit<1 or p_limit>100 then raise exception 'forbidden' using errcode='42501'; end if;
  if not p_own and not public.membership_actor_can_manage() then raise exception 'forbidden' using errcode='42501'; end if;
  return query
  select mr.id,mr.user_id,mr.plan_id,mr.status,mr.payment_method,mr.payment_status,mr.created_at,
    case when p_own then null else p.full_name end,
    case when p_own then null else p.email end,
    mp.name,mp.plan_type,mp.price,mp.currency
  from public.membership_requests mr
  join public.membership_plans mp on mp.id=mr.plan_id and mp.gym_id=mr.gym_id
  left join public.profiles p on p.id=mr.user_id
  where mr.gym_id=v_gym_id and (not p_own or mr.user_id=auth.uid())
    and (p_own or mr.status='pending')
  order by mr.created_at desc,mr.id desc limit p_limit;
end;
$function$;
create or replace function public.create_cash_membership_request(p_plan_id uuid)
returns uuid language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_user_id uuid:=auth.uid(); v_gym_id uuid:=public.effective_gym_id(); v_request_id uuid;
begin
  if v_user_id is null or v_gym_id is null or not public.membership_actor_is_active() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user_id::text||':'||v_gym_id::text||':'||p_plan_id::text,618));
  if not exists(select 1 from public.membership_plans where id=p_plan_id and gym_id=v_gym_id and is_active=true) then
    raise exception 'plan_not_found' using errcode='P0001';
  end if;
  if exists(select 1 from public.membership_requests where user_id=v_user_id and gym_id=v_gym_id and plan_id=p_plan_id and status='pending') then
    raise exception 'request_pending' using errcode='P0001';
  end if;
  insert into public.membership_requests(user_id,gym_id,plan_id,status,payment_method,payment_status)
  values(v_user_id,v_gym_id,p_plan_id,'pending','cash','pending') returning id into v_request_id;
  return v_request_id;
end;
$function$;
create or replace function public.reject_membership_request(p_request_id uuid)
returns boolean language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id();
begin
  if auth.uid() is null or v_gym_id is null or not public.membership_actor_can_manage() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  update public.membership_requests set status='rejected'
  where id=p_request_id and gym_id=v_gym_id and status='pending';
  return found;
end;
$function$;
create or replace function public.cancel_my_membership_request(p_request_id uuid)
returns boolean language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_user_id uuid:=auth.uid(); v_gym_id uuid:=public.effective_gym_id();
begin
  if v_user_id is null or v_gym_id is null or not public.membership_actor_is_active() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  update public.membership_requests set status='cancelled',payment_status='cancelled'
  where id=p_request_id and user_id=v_user_id and gym_id=v_gym_id
    and status='pending' and payment_method='cash' and payment_status='pending';
  return found;
end;
$function$;
create or replace function public.approve_cash_membership_request(p_request_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp
as $function$
declare
  v_gym_id uuid:=public.effective_gym_id(); v_request public.membership_requests%rowtype;
  v_member public.profiles%rowtype; v_plan public.membership_plans%rowtype;
  v_membership public.member_memberships%rowtype; v_is_spanish boolean;
begin
  if auth.uid() is null or v_gym_id is null or not public.membership_actor_can_manage() then
    raise exception 'Only gym admins can approve membership requests';
  end if;
  select * into v_request from public.membership_requests
  where id=p_request_id and gym_id=v_gym_id for update;
  if not found or v_request.status<>'pending' then raise exception 'Pending membership request not found'; end if;
  if v_request.payment_method<>'cash' then raise exception 'Only cash membership requests can be approved manually'; end if;
  if v_request.payment_status<>'pending' then raise exception 'Cash membership request is not pending payment'; end if;
  if not exists(select 1 from public.gym_members gm where gm.gym_id=v_gym_id and gm.user_id=v_request.user_id) then
    raise exception 'Member not found';
  end if;
  select * into v_member from public.profiles where id=v_request.user_id for update;
  if not found then raise exception 'Member not found'; end if;
  select * into v_plan from public.membership_plans where id=v_request.plan_id and gym_id=v_gym_id;
  if not found then raise exception 'Plan not found'; end if;
  select * into v_membership from public.create_member_membership_from_plan(v_request.user_id,v_request.plan_id,'assigned',v_gym_id);
  update public.membership_requests set status='approved' where id=v_request.id;
  v_is_spanish:=coalesce(v_member.preferred_locale,'en')='es';
  insert into public.notifications(user_id,title,body,type,data,scheduled_for,gym_id)
  values(v_request.user_id,
    case when v_membership.status='scheduled' and v_is_spanish then '🗓️ Membresía programada'
         when v_membership.status='scheduled' then '🗓️ Membership scheduled'
         when v_is_spanish then '🎉 Membresía activada' else '🎉 Membership activated' end,
    case when v_membership.status='scheduled' and v_is_spanish then 'Tu nuevo plan comenzará cuando termine tu plan Unlimited actual.'
         when v_membership.status='scheduled' then 'Your new plan will start when your current Unlimited plan ends.'
         when v_is_spanish then 'Tu plan ya está activo. Ya puedes reservar clases.'
         else 'Your plan is now active. You can start booking classes.' end,
    case when v_membership.status='scheduled' then 'membership_scheduled' else 'membership_approved' end,
    jsonb_build_object('planId',v_plan.id,'requestId',v_request.id,'paymentMethod','cash','membershipId',v_membership.id,'membershipStatus',v_membership.status,'startsAt',v_membership.starts_at),
    now(),v_gym_id);
end;
$function$;
create or replace function public.get_current_usable_membership()
returns table(membership_id uuid,plan_id uuid,plan_name text,plan_type text,credits_remaining integer,starts_at timestamptz,expires_at timestamptz,status text)
language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_user_id uuid:=auth.uid(); v_gym_id uuid:=public.effective_gym_id(); v_membership public.member_memberships%rowtype;
begin
  if v_user_id is null then raise exception 'Not authenticated'; end if;
  if v_gym_id is null then return; end if;
  select * into v_membership from public.select_usable_membership(v_user_id,v_gym_id);
  if v_membership.id is null then return; end if;
  return query select v_membership.id,mp.id,mp.name,mp.plan_type,v_membership.credits_remaining,
    v_membership.starts_at,coalesce(v_membership.expires_at,v_membership.ends_at),v_membership.status
  from public.membership_plans mp where mp.id=v_membership.plan_id and mp.gym_id=v_gym_id;
end;
$function$;
create or replace function public.assign_effective_membership_plan_by_email(p_email text,p_plan_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id(); v_member_id uuid;
begin
  if auth.uid() is null or v_gym_id is null or not public.membership_actor_can_manage() then raise exception 'forbidden' using errcode='42501'; end if;
  select gm.user_id into v_member_id from public.gym_members gm join public.profiles p on p.id=gm.user_id
  where gm.gym_id=v_gym_id and gm.is_active=true and lower(p.email)=lower(btrim(p_email)) and p.role<>'owner'
  limit 1;
  if v_member_id is null then raise exception 'Member not found'; end if;
  perform public.assign_membership_plan(v_member_id,p_plan_id);
end;
$function$;
-- Membership notifications must inherit their request origin, never the
-- recipient's legacy profiles.gym_id.
create or replace function public.set_notification_gym_id()
returns trigger language plpgsql security definer set search_path=public,pg_temp
as $function$
begin
  if new.type='waitlist_promoted' then
    select c.gym_id into new.gym_id from public.classes c where c.id::text=new.data->>'classId';
    if new.gym_id is null then raise exception 'invalid_notification_origin'; end if;
    return new;
  end if;
  if new.type in ('membership_scheduled','membership_approved','membership_payment_completed')
     and new.data ? 'requestId' then
    select mr.gym_id into new.gym_id from public.membership_requests mr where mr.id::text=new.data->>'requestId';
    if new.gym_id is null then raise exception 'invalid_notification_origin'; end if;
    return new;
  end if;
  select p.gym_id into new.gym_id from public.profiles p where p.id=new.user_id;
  if new.gym_id is null and new.type='gym_join_rejected' then
    select r.gym_id into new.gym_id from public.gym_join_requests r
    where r.user_id=new.user_id and r.status='rejected' and r.gym_id::text=new.data->>'gymId'
    order by r.approved_at desc nulls last,r.created_at desc limit 1;
  end if;
  return new;
end;
$function$;
-- Card completion remains service-role-only and keeps its Stripe signature.
-- It now validates relational membership and creates the membership in the
-- request gym through the 3C2 helper. Checkout creation remains legacy Flutter.
create or replace function public.complete_card_membership_request(
  p_checkout_session_id text,p_payment_intent_id text,p_amount_total integer,p_currency text,p_stripe_account_id text
)
returns void language plpgsql security definer set search_path=public,pg_temp
as $function$
declare
  v_request public.membership_requests%rowtype; v_member public.profiles%rowtype;
  v_plan public.membership_plans%rowtype; v_gym public.gyms%rowtype;
  v_membership public.member_memberships%rowtype; v_is_spanish boolean;
begin
  if nullif(btrim(p_checkout_session_id),'') is null then raise exception 'Missing checkout session id'; end if;
  if nullif(btrim(p_payment_intent_id),'') is null then raise exception 'Missing payment intent id'; end if;
  if nullif(btrim(p_stripe_account_id),'') is null then raise exception 'Missing Stripe account id'; end if;
  select * into v_request from public.membership_requests where stripe_checkout_session_id=p_checkout_session_id for update;
  if not found then raise exception 'Membership request not found'; end if;
  if v_request.payment_method<>'card' then raise exception 'Membership request is not a card payment'; end if;
  if v_request.status='approved' and v_request.payment_status='paid' then return; end if;
  if v_request.status<>'pending' or v_request.payment_status<>'pending' then raise exception 'Membership request is not pending'; end if;
  if p_amount_total is null or v_request.amount_total is null or p_amount_total<>v_request.amount_total then raise exception 'Payment amount does not match membership request'; end if;
  if p_currency is null or v_request.currency is null or lower(p_currency)<>lower(v_request.currency) then raise exception 'Payment currency does not match membership request'; end if;
  select * into v_gym from public.gyms where id=v_request.gym_id;
  if not found then raise exception 'Gym not found'; end if;
  if v_gym.stripe_account_id is distinct from p_stripe_account_id then raise exception 'Stripe account does not match gym'; end if;
  if not exists(select 1 from public.gym_members gm where gm.gym_id=v_request.gym_id and gm.user_id=v_request.user_id) then raise exception 'Member not found'; end if;
  select * into v_member from public.profiles where id=v_request.user_id for update;
  if not found then raise exception 'Member not found'; end if;
  select * into v_plan from public.membership_plans where id=v_request.plan_id and gym_id=v_request.gym_id;
  if not found then raise exception 'Plan not found'; end if;
  select * into v_membership from public.create_member_membership_from_plan(v_request.user_id,v_request.plan_id,'paid',v_request.gym_id);
  update public.membership_requests set status='approved',payment_status='paid',stripe_payment_intent_id=p_payment_intent_id,
    amount_total=p_amount_total,currency=lower(p_currency),paid_at=now() where id=v_request.id;
  v_is_spanish:=coalesce(v_member.preferred_locale,'en')='es';
  insert into public.notifications(user_id,title,body,type,data,scheduled_for,gym_id)
  values(v_request.user_id,
    case when v_membership.status='scheduled' and v_is_spanish then '🗓️ Membresía programada'
         when v_membership.status='scheduled' then '🗓️ Membership scheduled'
         when v_is_spanish then '🎉 Membresía activada' else '🎉 Membership activated' end,
    case when v_membership.status='scheduled' and v_is_spanish then 'Tu pago fue confirmado. El nuevo plan comenzará cuando termine tu Unlimited actual.'
         when v_membership.status='scheduled' then 'Your payment was confirmed. The new plan will start when your current Unlimited plan ends.'
         when v_is_spanish then 'Tu pago fue confirmado y tu plan ya está activo.'
         else 'Your payment was confirmed and your plan is now active.' end,
    case when v_membership.status='scheduled' then 'membership_scheduled' else 'membership_payment_completed' end,
    jsonb_build_object('planId',v_plan.id,'requestId',v_request.id,'paymentMethod','card','checkoutSessionId',p_checkout_session_id,'membershipId',v_membership.id,'membershipStatus',v_membership.status,'startsAt',v_membership.starts_at),
    now(),v_request.gym_id);
end;
$function$;
revoke all on function public.membership_actor_is_active() from public,anon,authenticated,service_role;
revoke all on function public.membership_actor_can_manage() from public,anon,authenticated,service_role;
revoke all on function public.validate_membership_plan_row() from public,anon,authenticated,service_role;
revoke all on function public.list_membership_plan_catalog(text,text,text,integer,integer) from public,anon,authenticated,service_role;
revoke all on function public.list_effective_available_membership_plans() from public,anon,authenticated,service_role;
revoke all on function public.get_effective_membership_access() from public,anon,authenticated,service_role;
revoke all on function public.list_effective_memberships(text,integer,integer) from public,anon,authenticated,service_role;
revoke all on function public.create_effective_membership_plan(text,text,integer,numeric,text,integer) from public,anon,authenticated,service_role;
revoke all on function public.update_effective_membership_plan(uuid,text,text,integer,numeric,text,integer) from public,anon,authenticated,service_role;
revoke all on function public.toggle_effective_membership_plan(uuid) from public,anon,authenticated,service_role;
revoke all on function public.delete_unused_membership_plan(uuid) from public,anon,authenticated,service_role;
revoke all on function public.list_effective_membership_requests(boolean,integer) from public,anon,authenticated,service_role;
revoke all on function public.create_cash_membership_request(uuid) from public,anon,authenticated,service_role;
revoke all on function public.reject_membership_request(uuid) from public,anon,authenticated,service_role;
revoke all on function public.cancel_my_membership_request(uuid) from public,anon,authenticated,service_role;
revoke all on function public.approve_cash_membership_request(uuid) from public,anon,authenticated,service_role;
revoke all on function public.get_current_usable_membership() from public,anon,authenticated,service_role;
revoke all on function public.assign_effective_membership_plan_by_email(text,uuid) from public,anon,authenticated,service_role;
revoke all on function public.complete_card_membership_request(text,text,integer,text,text) from public,anon,authenticated,service_role;
grant execute on function public.membership_actor_is_active() to authenticated,service_role;
grant execute on function public.membership_actor_can_manage() to authenticated,service_role;
grant execute on function public.list_membership_plan_catalog(text,text,text,integer,integer) to authenticated,service_role;
grant execute on function public.list_effective_available_membership_plans() to authenticated,service_role;
grant execute on function public.get_effective_membership_access() to authenticated,service_role;
grant execute on function public.list_effective_memberships(text,integer,integer) to authenticated,service_role;
grant execute on function public.create_effective_membership_plan(text,text,integer,numeric,text,integer) to authenticated,service_role;
grant execute on function public.update_effective_membership_plan(uuid,text,text,integer,numeric,text,integer) to authenticated,service_role;
grant execute on function public.toggle_effective_membership_plan(uuid) to authenticated,service_role;
grant execute on function public.delete_unused_membership_plan(uuid) to authenticated,service_role;
grant execute on function public.list_effective_membership_requests(boolean,integer) to authenticated,service_role;
grant execute on function public.create_cash_membership_request(uuid) to authenticated,service_role;
grant execute on function public.reject_membership_request(uuid) to authenticated,service_role;
grant execute on function public.cancel_my_membership_request(uuid) to authenticated,service_role;
grant execute on function public.approve_cash_membership_request(uuid) to authenticated,service_role;
grant execute on function public.get_current_usable_membership() to authenticated,service_role;
grant execute on function public.assign_effective_membership_plan_by_email(text,uuid) to authenticated,service_role;
grant execute on function public.complete_card_membership_request(text,text,integer,text,text) to service_role;
commit;
