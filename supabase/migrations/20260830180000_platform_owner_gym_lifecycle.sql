-- Platform Owner gym lifecycle. Operational access is centrally disabled by
-- effective_gym_id() whenever the selected gym is not active.

alter table public.gyms add column if not exists lifecycle_status text not null default 'active';
alter table public.gyms add column if not exists suspended_at timestamptz;
alter table public.gyms add column if not exists archived_at timestamptz;
alter table public.gyms add constraint gyms_lifecycle_status_check
  check (lifecycle_status in ('active','suspended','archived'));
create index if not exists gyms_lifecycle_status_name_idx on public.gyms(lifecycle_status,lower(name),id);

create or replace function public.platform_owner_active()
returns boolean language sql stable security definer set search_path=public,pg_temp
as $function$
  select coalesce(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='owner' and p.is_active=true),false)
$function$;

-- Creating a gym must not implicitly leave Platform Owner mode. Entering a
-- gym remains an explicit, separate action.
create or replace function public.create_gym(gym_name text)
returns uuid language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_user_id uuid:=auth.uid(); v_gym_id uuid; v_name text:=nullif(btrim(gym_name),'');
begin
  if not public.platform_owner_active() then raise exception using errcode='42501',message='owner_required'; end if;
  if v_name is null or char_length(v_name)>100 then raise exception using errcode='22023',message='invalid_gym_name'; end if;
  insert into public.gyms(name,owner_id) values(v_name,v_user_id) returning id into v_gym_id;
  insert into public.gym_members(gym_id,user_id,role,is_active,is_coach,joined_at,invited_by)
  values(v_gym_id,v_user_id,'admin',true,false,clock_timestamp(),v_user_id)
  on conflict(gym_id,user_id) do update set is_active=true,role='admin';
  return v_gym_id;
end;
$function$;

create or replace function public.effective_gym_id()
returns uuid language plpgsql stable security definer set search_path=public,pg_temp
as $function$
declare v_user_id uuid:=auth.uid(); v_session_id uuid:=public.auth_session_id(); v_gym_id uuid; v_web boolean:=false;
begin
  if v_user_id is null then return null; end if;
  if v_session_id is not null then
    select true,w.active_gym_id into v_web,v_gym_id from public.web_app_session_preferences w
    where w.session_id=v_session_id and w.user_id=v_user_id;
  end if;
  if not v_web then select p.gym_id into v_gym_id from public.profiles p where p.id=v_user_id; end if;
  if v_gym_id is null or not exists(select 1 from public.gyms g where g.id=v_gym_id and g.lifecycle_status='active') then return null; end if;
  if v_web and not exists(select 1 from public.gym_members gm where gm.user_id=v_user_id and gm.gym_id=v_gym_id and gm.is_active) then return null; end if;
  return v_gym_id;
end;
$function$;

create or replace function public.select_effective_gym(p_gym_id uuid)
returns uuid language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_user_id uuid:=auth.uid(); v_session_id uuid:=public.auth_session_id();
begin
  if v_user_id is null or p_gym_id is null or not exists(
    select 1 from public.gym_members gm join public.gyms g on g.id=gm.gym_id
    where gm.user_id=v_user_id and gm.gym_id=p_gym_id and gm.is_active and g.lifecycle_status='active'
  ) then raise exception using errcode='42501',message='gym_access_denied'; end if;
  update public.profiles set gym_id=p_gym_id where id=v_user_id;
  insert into public.user_app_preferences(user_id,active_gym_id) values(v_user_id,p_gym_id)
  on conflict(user_id) do update set active_gym_id=excluded.active_gym_id;
  if public.is_registered_web_session() then
    update public.web_app_session_preferences
    set active_gym_id=p_gym_id,selection_required=false,updated_at=now()
    where session_id=v_session_id and user_id=v_user_id;
  end if;
  return p_gym_id;
end;
$function$;

create or replace function public.get_selected_gym_access_context()
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp
as $function$
declare v_user_id uuid:=auth.uid(); v_selected uuid; v_result jsonb;
begin
  if v_user_id is null then raise exception using errcode='42501',message='unauthenticated'; end if;
  if public.is_registered_web_session() then
    select w.active_gym_id into v_selected from public.web_app_session_preferences w
    where w.session_id=public.auth_session_id() and w.user_id=v_user_id;
  else
    select p.gym_id into v_selected from public.profiles p where p.id=v_user_id;
  end if;
  select jsonb_build_object(
    'selected_gym_id',v_selected,'selected_gym_name',g.name,
    'status',coalesce(g.lifecycle_status,'active'),
    'active_gyms',coalesce((select jsonb_agg(jsonb_build_object('id',ag.id,'name',ag.name) order by lower(ag.name))
      from public.gym_members gm join public.gyms ag on ag.id=gm.gym_id
      where gm.user_id=v_user_id and gm.is_active and ag.lifecycle_status='active' and ag.id is distinct from v_selected),'[]'::jsonb)
  ) into v_result from public.gyms g where g.id=v_selected;
  return coalesce(v_result,jsonb_build_object('selected_gym_id',null,'status',null,'active_gyms','[]'::jsonb));
end;
$function$;

drop function if exists public.list_owner_gym_overview();
create function public.list_owner_gym_overview()
returns table(gym_id uuid,gym_name text,lifecycle_status text,created_at timestamptz,last_activity_at timestamptz,
 active_member_count bigint,admin_count bigint,coach_count bigint,athlete_count bigint,active_membership_count bigint,
 stripe_account_id text,stripe_onboarding_complete boolean,stripe_charges_enabled boolean,stripe_payouts_enabled boolean)
language plpgsql stable security definer set search_path=public,pg_temp
as $function$
begin
  if not public.platform_owner_active() then raise exception using errcode='42501',message='platform_owner_required'; end if;
  return query with mc as (
    select gm.gym_id,count(*) filter(where gm.is_active) members,count(*) filter(where gm.is_active and gm.role='admin') admins,
      count(*) filter(where gm.is_active and (gm.role='coach' or gm.is_coach)) coaches,
      count(*) filter(where gm.is_active and gm.role='athlete') athletes from public.gym_members gm group by gm.gym_id
  ),mm as (select m.gym_id,count(*) memberships from public.member_memberships m where m.is_active and m.status='active' group by m.gym_id),
  activity as (select e.gym_id,max(e.occurred_at) last_at from public.gym_activity_events e group by e.gym_id)
  select g.id,g.name,g.lifecycle_status,g.created_at,a.last_at,coalesce(mc.members,0),coalesce(mc.admins,0),coalesce(mc.coaches,0),
    coalesce(mc.athletes,0),coalesce(mm.memberships,0),g.stripe_account_id,coalesce(g.stripe_onboarding_complete,false),
    coalesce(g.stripe_charges_enabled,false),coalesce(g.stripe_payouts_enabled,false)
  from public.gyms g left join mc on mc.gym_id=g.id left join mm on mm.gym_id=g.id left join activity a on a.gym_id=g.id
  order by lower(g.name),g.id;
end;
$function$;

create or replace function public.get_platform_gym_detail(p_gym_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp
as $function$
declare v jsonb;
begin
  if not public.platform_owner_active() then raise exception using errcode='42501',message='platform_owner_required'; end if;
  select to_jsonb(x) into v from public.list_owner_gym_overview() x where x.gym_id=p_gym_id;
  if v is null then raise exception using errcode='P0002',message='gym_not_found'; end if;
  return v;
end;
$function$;

create or replace function public.platform_set_gym_status(p_gym_id uuid,p_status text)
returns text language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_status text:=lower(btrim(coalesce(p_status,'')));
begin
  if not public.platform_owner_active() then raise exception using errcode='42501',message='platform_owner_required'; end if;
  if v_status not in('active','suspended','archived') then raise exception using errcode='22023',message='invalid_gym_status'; end if;
  update public.gyms set lifecycle_status=v_status,
    suspended_at=case when v_status='suspended' then clock_timestamp() else null end,
    archived_at=case when v_status='archived' then clock_timestamp() else null end
  where id=p_gym_id;
  if not found then raise exception using errcode='P0002',message='gym_not_found'; end if;
  return v_status;
end;
$function$;

create or replace function public.platform_gym_delete_eligibility(p_gym_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp
as $function$
declare v jsonb;
begin
  if not public.platform_owner_active() then raise exception using errcode='42501',message='platform_owner_required'; end if;
  select jsonb_build_object('can_delete',g.lifecycle_status='archived' and
      g.stripe_account_id is null and
      not exists(select 1 from public.membership_requests r where r.gym_id=g.id and r.payment_status='paid') and
      not exists(select 1 from public.stripe_webhook_events e where e.gym_id=g.id) and
      not exists(select 1 from public.membership_legal_acceptances a where a.gym_id=g.id) and
      not exists(select 1 from public.membership_legal_documents d where d.gym_id=g.id) and
      not exists(select 1 from public.gym_document_acceptances a where a.gym_id=g.id) and
      not exists(select 1 from public.gym_document_versions v join public.gym_documents d on d.id=v.document_id where d.gym_id=g.id and v.status='published'),
    'status',g.lifecycle_status,'has_stripe_account',g.stripe_account_id is not null,
    'has_paid_requests',exists(select 1 from public.membership_requests r where r.gym_id=g.id and r.payment_status='paid'),
    'has_stripe_events',exists(select 1 from public.stripe_webhook_events e where e.gym_id=g.id),
    'has_legal_acceptances',exists(select 1 from public.membership_legal_acceptances a where a.gym_id=g.id) or exists(select 1 from public.gym_document_acceptances a where a.gym_id=g.id),
    'has_legal_documents',exists(select 1 from public.membership_legal_documents d where d.gym_id=g.id),
    'has_published_documents',exists(select 1 from public.gym_document_versions v join public.gym_documents d on d.id=v.document_id where d.gym_id=g.id and v.status='published')) into v
  from public.gyms g where g.id=p_gym_id;
  if v is null then raise exception using errcode='P0002',message='gym_not_found'; end if;
  return v;
end;
$function$;

create or replace function public.platform_delete_gym(p_gym_id uuid,p_confirmation_name text)
returns void language plpgsql security definer set search_path=public,pg_temp
as $function$
declare g public.gyms%rowtype; eligibility jsonb;
begin
  if not public.platform_owner_active() then raise exception using errcode='42501',message='platform_owner_required'; end if;
  select * into g from public.gyms where id=p_gym_id for update;
  if not found then raise exception using errcode='P0002',message='gym_not_found'; end if;
  if p_confirmation_name is distinct from g.name then raise exception using errcode='22023',message='confirmation_name_mismatch'; end if;
  eligibility:=public.platform_gym_delete_eligibility(p_gym_id);
  if not coalesce((eligibility->>'can_delete')::boolean,false) then raise exception using errcode='23503',message='gym_has_protected_audit_data'; end if;
  delete from public.notifications where gym_id=p_gym_id;
  delete from public.gym_document_versions v using public.gym_documents d where v.document_id=d.id and d.gym_id=p_gym_id;
  delete from public.gym_documents where gym_id=p_gym_id;
  delete from public.gym_members where gym_id=p_gym_id;
  delete from public.gyms where id=p_gym_id;
end;
$function$;

create or replace function public.select_owner_effective_gym(p_gym_id uuid)
returns uuid language plpgsql security definer set search_path=public,pg_temp
as $function$
begin
  if not public.platform_owner_active() or not exists(select 1 from public.gyms g where g.id=p_gym_id and g.lifecycle_status='active') then
    raise exception using errcode='42501',message='gym_access_denied'; end if;
  update public.profiles set gym_id=p_gym_id where id=auth.uid();
  insert into public.user_app_preferences(user_id,active_gym_id) values(auth.uid(),p_gym_id)
  on conflict(user_id) do update set active_gym_id=excluded.active_gym_id;
  if public.is_registered_web_session() then
    update public.web_app_session_preferences
    set active_gym_id=p_gym_id,selection_required=false,updated_at=now()
    where session_id=public.auth_session_id() and user_id=auth.uid();
  end if;
  return p_gym_id;
end;
$function$;

create or replace function public.leave_owner_gym_inspection()
returns void language plpgsql security definer set search_path=public,pg_temp
as $function$
begin
  if not public.platform_owner_active() then raise exception using errcode='42501',message='platform_owner_required'; end if;
  update public.profiles set gym_id=null where id=auth.uid();
  update public.user_app_preferences set active_gym_id=null where user_id=auth.uid();
  if public.is_registered_web_session() then
    update public.web_app_session_preferences
    set active_gym_id=null,selection_required=false,updated_at=now()
    where session_id=public.auth_session_id() and user_id=auth.uid();
  end if;
end;
$function$;

revoke all on function public.platform_owner_active() from public,anon,authenticated;
revoke all on function public.create_gym(text) from public,anon,authenticated;
revoke all on function public.select_effective_gym(uuid) from public,anon,authenticated;
revoke all on function public.get_selected_gym_access_context() from public,anon,authenticated;
revoke all on function public.list_owner_gym_overview() from public,anon,authenticated;
revoke all on function public.get_platform_gym_detail(uuid) from public,anon,authenticated;
revoke all on function public.platform_set_gym_status(uuid,text) from public,anon,authenticated;
revoke all on function public.platform_gym_delete_eligibility(uuid) from public,anon,authenticated;
revoke all on function public.platform_delete_gym(uuid,text) from public,anon,authenticated;
revoke all on function public.leave_owner_gym_inspection() from public,anon,authenticated;
grant execute on function public.select_effective_gym(uuid),public.get_selected_gym_access_context(),public.list_owner_gym_overview(),
 public.get_platform_gym_detail(uuid),public.platform_set_gym_status(uuid,text),public.platform_gym_delete_eligibility(uuid),
 public.platform_delete_gym(uuid,text),public.leave_owner_gym_inspection() to authenticated;
grant execute on function public.create_gym(text) to authenticated;
