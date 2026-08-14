-- Vertical 3G1: relational Join + Leave. Invitations remain a separate 3G2.

drop index if exists public.gym_join_requests_one_pending_per_user_idx;
create unique index if not exists gym_join_requests_one_pending_per_user_gym_idx
on public.gym_join_requests(user_id,gym_id) where status='pending';
drop policy if exists "gym join requests users can read own" on public.gym_join_requests;
drop policy if exists "gym join requests users can create own" on public.gym_join_requests;
drop policy if exists "gym join requests admins can read gym requests" on public.gym_join_requests;
drop policy if exists "gym join requests admins can update gym requests" on public.gym_join_requests;
create policy "users read own gym join requests"
on public.gym_join_requests for select to authenticated
using(user_id=auth.uid());
create policy "users create own pending gym join requests"
on public.gym_join_requests for insert to authenticated
with check(
  user_id=auth.uid() and status='pending' and approved_at is null
  and approved_by is null
  and not exists(
    select 1 from public.gym_members gm
    where gm.user_id=auth.uid() and gm.gym_id=gym_join_requests.gym_id
      and gm.is_active
  )
);
create policy "effective admins read gym join requests"
on public.gym_join_requests for select to authenticated
using(
  gym_id=public.effective_gym_id()
  and (public.effective_gym_role()='admin' or (
    not public.is_registered_web_session() and public.effective_gym_role()='owner'
  ))
);
drop policy if exists "profiles admins can read join request profiles" on public.profiles;
create or replace function public.lookup_gym_by_code(p_gym_code text)
returns table(gym_id uuid,gym_name text,gym_logo_url text)
language plpgsql stable security definer
set search_path=public,pg_temp
as $function$
declare v_code text:=upper(btrim(coalesce(p_gym_code,'')));
begin
  if auth.uid() is null then raise exception using errcode='P0001',message='unauthenticated'; end if;
  if v_code='' or length(v_code)>40 then return; end if;
  return query select g.id,g.name,g.logo_url from public.gyms g
  where upper(g.gym_code)=v_code limit 1;
end;
$function$;
create or replace function public.create_gym_join_request(
  p_gym_code text,
  p_phone text default null,
  p_birth_date date default null
)
returns table(result text,gym_name text)
language plpgsql security definer
set search_path=public,pg_temp
as $function$
declare
  v_user_id uuid:=auth.uid(); v_code text:=upper(btrim(coalesce(p_gym_code,'')));
  v_gym public.gyms%rowtype; v_existing public.gym_members%rowtype;
begin
  if v_user_id is null then raise exception using errcode='P0001',message='unauthenticated'; end if;
  if v_code='' or length(v_code)>40 then return query select 'not_found'::text,null::text; return; end if;
  select * into v_gym from public.gyms g where upper(g.gym_code)=v_code;
  if not found then return query select 'not_found'::text,null::text; return; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user_id::text||':'||v_gym.id::text,617)
  );
  select * into v_existing from public.gym_members gm
  where gm.user_id=v_user_id and gm.gym_id=v_gym.id for update;
  if found and v_existing.is_active then
    return query select 'already_member'::text,v_gym.name; return;
  end if;
  if exists(select 1 from public.gym_join_requests r where r.user_id=v_user_id and r.gym_id=v_gym.id and r.status='pending') then
    return query select 'pending'::text,v_gym.name; return;
  end if;
  update public.profiles p set
    phone=coalesce(p.phone,nullif(btrim(p_phone),'')),
    birth_date=coalesce(p.birth_date,p_birth_date)
  where p.id=v_user_id;
  insert into public.gym_join_requests(user_id,gym_id,status)
  values(v_user_id,v_gym.id,'pending');
  return query select 'created'::text,v_gym.name;
end;
$function$;
create or replace function public.list_effective_gym_join_requests()
returns table(request_id uuid,user_id uuid,full_name text,email text,phone text,
  avatar_url text,created_at timestamptz)
language plpgsql stable security definer
set search_path=public,pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id();
begin
  if auth.uid() is null then raise exception using errcode='P0001',message='unauthenticated'; end if;
  if v_gym_id is null or not (public.effective_gym_role()='admin' or (
    not public.is_registered_web_session() and public.effective_gym_role()='owner'
  )) then
    raise exception using errcode='42501',message='forbidden';
  end if;
  return query select r.id,p.id,p.full_name,p.email,p.phone,p.avatar_url,r.created_at
  from public.gym_join_requests r join public.profiles p on p.id=r.user_id
  where r.gym_id=v_gym_id and r.status='pending'
  order by r.created_at desc,r.id desc;
end;
$function$;
create or replace function public.approve_gym_join_request(p_request_id uuid)
returns void language plpgsql security definer
set search_path=public,pg_temp
as $function$
declare
  v_gym_id uuid:=public.effective_gym_id(); v_request public.gym_join_requests%rowtype;
  v_gym_name text; v_is_web boolean:=public.is_registered_web_session();
begin
  if auth.uid() is null then raise exception using errcode='P0001',message='unauthenticated'; end if;
  if v_gym_id is null or not (public.effective_gym_role()='admin' or (
    not v_is_web and public.effective_gym_role()='owner'
  )) then
    raise exception using errcode='42501',message='forbidden';
  end if;
  select * into v_request from public.gym_join_requests r where r.id=p_request_id for update;
  if not found or v_request.gym_id is distinct from v_gym_id then
    raise exception using errcode='P0001',message='request_not_found';
  end if;
  if v_request.status='approved' then return; end if;
  if v_request.status<>'pending' then raise exception using errcode='P0001',message='request_resolved'; end if;
  insert into public.gym_members(gym_id,user_id,role,is_active,is_coach,joined_at,invited_by)
  values(v_gym_id,v_request.user_id,'athlete',true,false,now(),auth.uid())
  on conflict(gym_id,user_id) do update set role='athlete',is_active=true,is_coach=false;
  if not v_is_web then
    update public.profiles set gym_id=v_gym_id,role='athlete',is_active=true,is_coach=false
    where id=v_request.user_id;
  end if;
  update public.gym_join_requests set status='approved',approved_at=now(),approved_by=auth.uid()
  where id=v_request.id;
  select g.name into v_gym_name from public.gyms g where g.id=v_gym_id;
  insert into public.notifications(user_id,gym_id,title,body,type,data,scheduled_for)
  values(v_request.user_id,v_gym_id,'🎉 Welcome!',format('You now have access to %s.',coalesce(v_gym_name,'your gym')),
    'gym_join_approved',jsonb_build_object('gymId',v_gym_id,'requestId',v_request.id),now());
end;
$function$;
create or replace function public.reject_gym_join_request(p_request_id uuid)
returns void language plpgsql security definer
set search_path=public,pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id(); v_request public.gym_join_requests%rowtype; v_gym_name text;
  v_is_web boolean:=public.is_registered_web_session();
begin
  if auth.uid() is null then raise exception using errcode='P0001',message='unauthenticated'; end if;
  if v_gym_id is null or not (public.effective_gym_role()='admin' or (
    not v_is_web and public.effective_gym_role()='owner'
  )) then
    raise exception using errcode='42501',message='forbidden';
  end if;
  select * into v_request from public.gym_join_requests r where r.id=p_request_id for update;
  if not found or v_request.gym_id is distinct from v_gym_id then
    raise exception using errcode='P0001',message='request_not_found';
  end if;
  if v_request.status='rejected' then return; end if;
  if v_request.status<>'pending' then raise exception using errcode='P0001',message='request_resolved'; end if;
  update public.gym_join_requests set status='rejected',approved_at=now(),approved_by=auth.uid()
  where id=v_request.id;
  select g.name into v_gym_name from public.gyms g where g.id=v_gym_id;
  insert into public.notifications(user_id,gym_id,title,body,type,data,scheduled_for)
  values(v_request.user_id,v_gym_id,'Join request update',format('Your request to join %s was not approved.',coalesce(v_gym_name,'this gym')),
    'gym_join_rejected',jsonb_build_object('gymId',v_gym_id,'requestId',v_request.id),now());
end;
$function$;
create or replace function public.set_notification_gym_id()
returns trigger language plpgsql security definer
set search_path=public,pg_temp
as $function$
begin
  if new.type='workout_published' then
    select w.gym_id into new.gym_id from public.workouts w where w.id::text=new.data->>'workoutId';
    if new.gym_id is null then raise exception 'invalid_notification_origin'; end if;
    return new;
  end if;
  if new.type='waitlist_promoted' then
    select c.gym_id into new.gym_id from public.classes c where c.id::text=new.data->>'classId';
    if new.gym_id is null then raise exception 'invalid_notification_origin'; end if;
    return new;
  end if;
  if new.type in ('membership_scheduled','membership_approved','membership_payment_completed') and new.data?'requestId' then
    select mr.gym_id into new.gym_id from public.membership_requests mr where mr.id::text=new.data->>'requestId';
    if new.gym_id is null then raise exception 'invalid_notification_origin'; end if;
    return new;
  end if;
  if new.type in ('gym_join_approved','gym_join_rejected') and new.data?'requestId' then
    select r.gym_id into new.gym_id from public.gym_join_requests r where r.id::text=new.data->>'requestId';
    if new.gym_id is null then raise exception 'invalid_notification_origin'; end if;
    return new;
  end if;
  select p.gym_id into new.gym_id from public.profiles p where p.id=new.user_id;
  return new;
end;
$function$;
create or replace function public.leave_current_gym()
returns void language plpgsql security definer
set search_path=public,pg_temp
as $function$
declare
  v_user_id uuid:=auth.uid(); v_is_web boolean:=public.is_registered_web_session();
  v_gym_id uuid; v_role text; v_profile public.profiles%rowtype; v_booking record;
begin
  if v_user_id is null then raise exception using errcode='P0001',message='unauthenticated'; end if;
  select * into v_profile from public.profiles where id=v_user_id for update;
  if not found then raise exception using errcode='P0001',message='profile_not_found'; end if;
  if v_is_web then
    v_gym_id:=public.effective_gym_id(); v_role:=public.effective_gym_role();
    if v_gym_id is null then raise exception using errcode='P0001',message='gym_not_found'; end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_gym_id::text,615));
    select gm.role into v_role from public.gym_members gm
    where gm.gym_id=v_gym_id and gm.user_id=v_user_id and gm.is_active for update;
    if not found then raise exception using errcode='P0001',message='gym_not_found'; end if;
    if v_role='admin' and not exists(
      select 1 from public.gym_members gm where gm.gym_id=v_gym_id
        and gm.role='admin' and gm.is_active and gm.user_id<>v_user_id
    ) then raise exception using errcode='P0001',message='last_admin_not_allowed'; end if;
    update public.gym_members set is_active=false where gym_id=v_gym_id and user_id=v_user_id;
    update public.gym_join_requests set status='cancelled'
    where gym_id=v_gym_id and user_id=v_user_id and status='pending';
    update public.web_app_session_preferences set active_gym_id=null,updated_at=now()
    where session_id=public.auth_session_id() and user_id=v_user_id;
    return;
  end if;
  v_gym_id:=v_profile.gym_id; v_role:=v_profile.role;
  if v_gym_id is null then return; end if;
  if v_role in ('admin','owner') then raise exception using errcode='42501',message='forbidden'; end if;
  for v_booking in select cb.class_id from public.class_bookings cb join public.classes c on c.id=cb.class_id
    where cb.user_id=v_user_id and c.gym_id=v_gym_id and cb.status='booked' and c.starts_at>now()
  loop perform public.cancel_my_booking(v_booking.class_id); end loop;
  delete from public.class_waitlist cw using public.classes c
  where cw.class_id=c.id and cw.user_id=v_user_id and c.gym_id=v_gym_id;
  update public.member_memberships set is_active=false,status='cancelled'
  where user_id=v_user_id and gym_id=v_gym_id and is_active;
  update public.gym_join_requests set status='cancelled'
  where user_id=v_user_id and gym_id=v_gym_id and status='pending';
  update public.gym_members set is_active=false where gym_id=v_gym_id and user_id=v_user_id;
  update public.profiles set gym_id=null,role='athlete',is_active=true,is_coach=false where id=v_user_id;
end;
$function$;
revoke all on function public.lookup_gym_by_code(text) from public,anon;
revoke all on function public.create_gym_join_request(text,text,date) from public,anon;
revoke all on function public.list_effective_gym_join_requests() from public,anon;
revoke all on function public.approve_gym_join_request(uuid) from public,anon;
revoke all on function public.reject_gym_join_request(uuid) from public,anon;
revoke all on function public.leave_current_gym() from public,anon;
grant execute on function public.lookup_gym_by_code(text) to authenticated,service_role;
grant execute on function public.create_gym_join_request(text,text,date) to authenticated,service_role;
grant execute on function public.list_effective_gym_join_requests() to authenticated,service_role;
grant execute on function public.approve_gym_join_request(uuid) to authenticated,service_role;
grant execute on function public.reject_gym_join_request(uuid) to authenticated,service_role;
grant execute on function public.leave_current_gym() to authenticated,service_role;
