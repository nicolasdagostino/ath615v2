-- Owner V1 overview and safe effective-gym selection.

create or replace function public.create_gym(gym_name text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare v_user_id uuid := auth.uid(); v_gym_id uuid; v_name text := nullif(btrim(gym_name), '');
begin
  if v_user_id is null then raise exception using errcode='42501', message='unauthenticated'; end if;
  if not exists(select 1 from public.profiles where id=v_user_id and role='owner' and is_active=true) then
    raise exception using errcode='42501', message='owner_required';
  end if;
  if v_name is null or char_length(v_name)>100 then raise exception using errcode='22023', message='invalid_gym_name'; end if;
  insert into public.gyms(name, owner_id) values(v_name, v_user_id) returning id into v_gym_id;
  insert into public.gym_members(gym_id,user_id,role,is_active,is_coach,joined_at,invited_by)
  values(v_gym_id,v_user_id,'admin',true,false,clock_timestamp(),v_user_id)
  on conflict(gym_id,user_id) do update set is_active=true, role='admin';
  update public.profiles set gym_id=v_gym_id where id=v_user_id;
  insert into public.user_app_preferences(user_id,active_gym_id) values(v_user_id,v_gym_id)
  on conflict(user_id) do update set active_gym_id=excluded.active_gym_id;
  return v_gym_id;
end;
$function$;

create or replace function public.list_owner_gym_overview()
returns table(
  gym_id uuid, gym_name text, active_member_count bigint, admin_count bigint,
  coach_count bigint, athlete_count bigint, active_membership_count bigint,
  stripe_account_id text, stripe_onboarding_complete boolean,
  stripe_charges_enabled boolean, stripe_payouts_enabled boolean
)
language sql stable security definer set search_path=public,pg_temp
as $function$
  with accessible as (
    select g.* from public.gyms g
    where g.owner_id=auth.uid()
       or exists(select 1 from public.gym_members own where own.gym_id=g.id and own.user_id=auth.uid() and own.is_active and own.role='admin')
  ), member_counts as (
    select gm.gym_id,
      count(*) filter(where gm.is_active) active_members,
      count(*) filter(where gm.is_active and gm.role='admin') admins,
      count(*) filter(where gm.is_active and (gm.role='coach' or gm.is_coach)) coaches,
      count(*) filter(where gm.is_active and gm.role='athlete') athletes
    from public.gym_members gm join accessible a on a.id=gm.gym_id group by gm.gym_id
  ), membership_counts as (
    select mm.gym_id,count(*) active_memberships from public.member_memberships mm
    join accessible a on a.id=mm.gym_id where mm.is_active and mm.status='active' group by mm.gym_id
  )
  select a.id,a.name,coalesce(mc.active_members,0),coalesce(mc.admins,0),coalesce(mc.coaches,0),
    coalesce(mc.athletes,0),coalesce(mmc.active_memberships,0),a.stripe_account_id,
    coalesce(a.stripe_onboarding_complete,false),coalesce(a.stripe_charges_enabled,false),coalesce(a.stripe_payouts_enabled,false)
  from accessible a left join member_counts mc on mc.gym_id=a.id
  left join membership_counts mmc on mmc.gym_id=a.id order by lower(a.name),a.id;
$function$;

revoke all on function public.list_owner_gym_overview() from public,anon,authenticated;
grant execute on function public.list_owner_gym_overview() to authenticated;
comment on function public.list_owner_gym_overview() is 'One owner-scoped aggregate query; no caller gym id and no per-gym queries.';

create or replace function public.select_owner_effective_gym(p_gym_id uuid)
returns uuid language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_user_id uuid:=auth.uid();
begin
  if v_user_id is null or p_gym_id is null then raise exception using errcode='42501',message='gym_access_denied'; end if;
  if not exists(
    select 1 from public.gyms g where g.id=p_gym_id and
      (g.owner_id=v_user_id or exists(select 1 from public.gym_members gm where gm.gym_id=g.id and gm.user_id=v_user_id and gm.is_active and gm.role='admin'))
  ) then raise exception using errcode='42501',message='gym_access_denied'; end if;
  update public.profiles set gym_id=p_gym_id where id=v_user_id;
  insert into public.user_app_preferences(user_id,active_gym_id) values(v_user_id,p_gym_id)
  on conflict(user_id) do update set active_gym_id=excluded.active_gym_id;
  return p_gym_id;
end;
$function$;
revoke all on function public.select_owner_effective_gym(uuid) from public,anon,authenticated;
grant execute on function public.select_owner_effective_gym(uuid) to authenticated;

-- An email is contact information, not a person's display name. Invitation
-- metadata may fill a missing name, but never replaces an existing one.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_invitation_id uuid;
begin
  insert into public.profiles(id,email,full_name,role,gym_id,phone,birth_date)
  values(new.id,new.email,nullif(trim(new.raw_user_meta_data->>'full_name'),''),
    coalesce(new.raw_user_meta_data->>'role','athlete'),
    nullif(new.raw_user_meta_data->>'gym_id','')::uuid,
    nullif(trim(new.raw_user_meta_data->>'phone'),''),
    nullif(new.raw_user_meta_data->>'birth_date','')::date)
  on conflict(id) do update set email=excluded.email,
    full_name=coalesce(nullif(btrim(public.profiles.full_name),''),excluded.full_name),
    role=excluded.role,gym_id=excluded.gym_id,
    phone=coalesce(excluded.phone,public.profiles.phone),
    birth_date=coalesce(excluded.birth_date,public.profiles.birth_date);
  for v_invitation_id in select i.id from public.gym_invitations i
    where i.email_normalized=lower(btrim(new.email)) and i.status in('dispatching','failed') order by i.created_at,i.id
  loop perform public.materialize_owner_admin_invitation(v_invitation_id,new.id); end loop;
  return new;
end;
$function$;
