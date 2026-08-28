-- Restore the pre-lifecycle effective-gym contract and add an explicit,
-- session-scoped Platform Owner inspection capability. The persistent profile
-- role remains owner; only the effective role inside the validated inspection
-- session is administrative.

create table public.platform_owner_gym_inspections (
  session_id uuid not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  gym_id uuid not null references public.gyms(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(session_id,user_id)
);
create index platform_owner_gym_inspections_gym_idx
  on public.platform_owner_gym_inspections(gym_id,user_id);
alter table public.platform_owner_gym_inspections enable row level security;
revoke all on table public.platform_owner_gym_inspections from public,anon,authenticated;

create or replace function public.platform_owner_inspection_gym_id()
returns uuid language plpgsql stable security definer set search_path=public,pg_temp
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_session_id uuid:=public.auth_session_id();
  v_gym_id uuid;
begin
  if v_user_id is null or v_session_id is null then return null; end if;
  select i.gym_id into v_gym_id
  from public.platform_owner_gym_inspections i
  join public.profiles p on p.id=i.user_id and p.role='owner' and p.is_active
  join public.gyms g on g.id=i.gym_id and g.lifecycle_status='active'
  where i.session_id=v_session_id and i.user_id=v_user_id;
  if v_gym_id is null then return null; end if;
  if public.is_registered_web_session() then
    if exists(select 1 from public.web_app_session_preferences w
      where w.session_id=v_session_id and w.user_id=v_user_id and w.active_gym_id=v_gym_id)
    then return v_gym_id; end if;
    return null;
  end if;
  if exists(select 1 from public.profiles p where p.id=v_user_id and p.gym_id=v_gym_id)
  then return v_gym_id; end if;
  return null;
end;
$function$;

create or replace function public.platform_owner_inspection_active()
returns boolean language sql stable security definer set search_path=public,pg_temp
as $function$
  select public.platform_owner_inspection_gym_id() is not null
$function$;

create or replace function public.effective_gym_id()
returns uuid language plpgsql stable security definer set search_path=public,pg_temp
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_session_id uuid:=public.auth_session_id();
  v_selected_gym_id uuid;
  v_is_web_session boolean:=false;
  v_profile_role text;
begin
  if v_user_id is null then return null; end if;
  if v_session_id is not null then
    select true,w.active_gym_id into v_is_web_session,v_selected_gym_id
    from public.web_app_session_preferences w
    where w.session_id=v_session_id and w.user_id=v_user_id;
  end if;
  if v_is_web_session then
    if v_selected_gym_id is null or not exists(select 1 from public.gyms g
      where g.id=v_selected_gym_id and g.lifecycle_status='active') then return null; end if;
    if exists(select 1 from public.gym_members gm
      where gm.user_id=v_user_id and gm.gym_id=v_selected_gym_id and gm.is_active)
      or public.platform_owner_inspection_gym_id()=v_selected_gym_id
    then return v_selected_gym_id; end if;
    return null;
  end if;
  select p.gym_id,p.role into v_selected_gym_id,v_profile_role
  from public.profiles p where p.id=v_user_id;
  if v_selected_gym_id is null or not exists(select 1 from public.gyms g
    where g.id=v_selected_gym_id and g.lifecycle_status='active') then return null; end if;
  if v_profile_role='owner' and public.platform_owner_inspection_gym_id() is distinct from v_selected_gym_id
  then return null; end if;
  return v_selected_gym_id;
end;
$function$;

create or replace function public.effective_gym_role()
returns text language plpgsql stable security definer set search_path=public,pg_temp
as $function$
declare v_user_id uuid:=auth.uid(); v_gym_id uuid:=public.effective_gym_id();
begin
  if v_user_id is null or v_gym_id is null then return null; end if;
  if public.platform_owner_inspection_gym_id()=v_gym_id then return 'admin'; end if;
  if public.is_registered_web_session() then
    return (select gm.role from public.gym_members gm
      where gm.user_id=v_user_id and gm.gym_id=v_gym_id and gm.is_active);
  end if;
  return (select p.role from public.profiles p where p.id=v_user_id);
end;
$function$;

create or replace function public.select_owner_effective_gym(p_gym_id uuid)
returns uuid language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_user_id uuid:=auth.uid(); v_session_id uuid:=public.auth_session_id();
begin
  if v_session_id is null then raise exception using errcode='42501',message='session_required'; end if;
  if not public.platform_owner_active() or not exists(select 1 from public.gyms g
    where g.id=p_gym_id and g.lifecycle_status='active') then
    raise exception using errcode='42501',message='gym_access_denied';
  end if;
  insert into public.platform_owner_gym_inspections(session_id,user_id,gym_id)
  values(v_session_id,v_user_id,p_gym_id)
  on conflict(session_id,user_id) do update set gym_id=excluded.gym_id,created_at=now();
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

create or replace function public.leave_owner_gym_inspection()
returns void language plpgsql security definer set search_path=public,pg_temp
as $function$
begin
  if not public.platform_owner_active() then raise exception using errcode='42501',message='platform_owner_required'; end if;
  delete from public.platform_owner_gym_inspections
  where session_id=public.auth_session_id() and user_id=auth.uid();
  update public.profiles set gym_id=null where id=auth.uid();
  update public.user_app_preferences set active_gym_id=null where user_id=auth.uid();
  if public.is_registered_web_session() then
    update public.web_app_session_preferences
    set active_gym_id=null,selection_required=false,updated_at=now()
    where session_id=public.auth_session_id() and user_id=auth.uid();
  end if;
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
  if v_status<>'active' then
    delete from public.platform_owner_gym_inspections where gym_id=p_gym_id;
  end if;
  return v_status;
end;
$function$;

revoke all on function public.platform_owner_inspection_gym_id() from public,anon,authenticated;
revoke all on function public.platform_owner_inspection_active() from public,anon,authenticated;
grant execute on function public.platform_owner_inspection_gym_id(),public.platform_owner_inspection_active() to authenticated;
comment on function public.platform_owner_inspection_gym_id() is
  'Returns only the active gym explicitly selected for this Platform Owner auth session.';
comment on function public.effective_gym_role() is
  'Returns session-effective administrative capability for a validated Platform Owner inspection without mutating profiles.role.';
