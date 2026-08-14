-- Final Web activation: expose the caller's own relational gym context after
-- the session has explicitly been registered as a Web session.

alter table public.web_app_session_preferences
  add column if not exists selection_required boolean not null default false;
create or replace function public.set_web_active_gym(p_gym_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_session_id uuid := public.auth_session_id();
begin
  if v_user_id is null or v_session_id is null then
    raise exception using errcode = '42501', message = 'unauthenticated';
  end if;
  if p_gym_id is null then
    raise exception using errcode = '22023', message = 'invalid_gym';
  end if;

  perform 1 from public.web_app_session_preferences wsp
  where wsp.session_id = v_session_id and wsp.user_id = v_user_id
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'web_session_not_registered';
  end if;

  perform 1 from public.gym_members gm
  where gm.user_id = v_user_id and gm.gym_id = p_gym_id and gm.is_active = true
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'gym_access_denied';
  end if;

  update public.web_app_session_preferences
  set active_gym_id = p_gym_id, selection_required = false
  where session_id = v_session_id and user_id = v_user_id;
  return p_gym_id;
end;
$function$;
create or replace function public.get_web_app_gym_relations()
returns table (
  active_gym_id uuid,
  selection_required boolean,
  relations jsonb
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_session_id uuid := public.auth_session_id();
begin
  if v_user_id is null or v_session_id is null then
    raise exception using errcode = '42501', message = 'unauthenticated';
  end if;

  if not exists (
    select 1
    from public.web_app_session_preferences wsp
    where wsp.session_id = v_session_id
      and wsp.user_id = v_user_id
  ) then
    raise exception using errcode = '42501', message = 'web_session_not_registered';
  end if;

  return query
  select
    wsp.active_gym_id,
    wsp.selection_required,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'relation_id', gm.id,
          'gym_id', gm.gym_id,
          'gym_name', g.name,
          'gym_logo_url', g.logo_url,
          'role', gm.role,
          'is_coach', (gm.is_coach or gm.role = 'coach'),
          'is_active', gm.is_active
        )
        order by gm.is_active desc, lower(g.name), gm.gym_id
      ) filter (where gm.id is not null),
      '[]'::jsonb
    )
  from public.web_app_session_preferences wsp
  left join public.gym_members gm
    on gm.user_id = wsp.user_id
  left join public.gyms g
    on g.id = gm.gym_id
  where wsp.session_id = v_session_id
    and wsp.user_id = v_user_id
  group by wsp.active_gym_id, wsp.selection_required;
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
    update public.web_app_session_preferences
    set active_gym_id=null,selection_required=true,updated_at=now()
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
revoke all on function public.get_web_app_gym_relations() from public;
revoke all on function public.get_web_app_gym_relations() from anon;
revoke all on function public.get_web_app_gym_relations() from authenticated;
grant execute on function public.get_web_app_gym_relations() to authenticated;
comment on function public.get_web_app_gym_relations() is
  'Returns the registered Web session selection and only the caller own gym relations for AppContext bootstrap.';
