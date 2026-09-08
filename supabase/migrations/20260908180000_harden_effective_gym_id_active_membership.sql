-- A selected profile gym is not authority on its own. Native/non-Web users
-- must still have an active gym_members relation. Platform Owner inspection
-- remains an explicit, session-scoped exception.
create or replace function public.effective_gym_id()
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_session_id uuid := public.auth_session_id();
  v_selected_gym_id uuid;
  v_is_web_session boolean := false;
  v_profile_role text;
begin
  if v_user_id is null then
    return null;
  end if;

  if v_session_id is not null then
    select true, w.active_gym_id
    into v_is_web_session, v_selected_gym_id
    from public.web_app_session_preferences w
    where w.session_id = v_session_id
      and w.user_id = v_user_id;
  end if;

  if v_is_web_session then
    if v_selected_gym_id is null or not exists (
      select 1
      from public.gyms g
      where g.id = v_selected_gym_id
        and g.lifecycle_status = 'active'
    ) then
      return null;
    end if;

    if exists (
      select 1
      from public.gym_members gm
      where gm.user_id = v_user_id
        and gm.gym_id = v_selected_gym_id
        and gm.is_active
    ) or public.platform_owner_inspection_gym_id() = v_selected_gym_id then
      return v_selected_gym_id;
    end if;

    return null;
  end if;

  select p.gym_id, p.role
  into v_selected_gym_id, v_profile_role
  from public.profiles p
  where p.id = v_user_id;

  if v_selected_gym_id is null or not exists (
    select 1
    from public.gyms g
    where g.id = v_selected_gym_id
      and g.lifecycle_status = 'active'
  ) then
    return null;
  end if;

  if v_profile_role = 'owner' then
    if public.platform_owner_inspection_gym_id() = v_selected_gym_id then
      return v_selected_gym_id;
    end if;
    return null;
  end if;

  if exists (
    select 1
    from public.gym_members gm
    where gm.user_id = v_user_id
      and gm.gym_id = v_selected_gym_id
      and gm.is_active
  ) then
    return v_selected_gym_id;
  end if;

  return null;
end;
$function$;

comment on function public.effective_gym_id() is
  'Returns an active selected gym backed by active gym membership, or a validated Platform Owner inspection.';
