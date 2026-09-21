-- Profile fields select legacy context but never grant gym membership or role.
-- Keep the existing, session-scoped Platform Owner inspection exception.
begin;

create or replace function public.same_gym_as_current_user(target_gym_id uuid)
returns boolean language sql stable security definer
set search_path = public, pg_temp
as $function$
  select coalesce(target_gym_id = public.effective_gym_id(), false);
$function$;

create or replace function public.effective_gym_role()
returns text language plpgsql stable security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_gym_id uuid := public.effective_gym_id();
begin
  if v_user_id is null or v_gym_id is null then return null; end if;
  if public.platform_owner_inspection_gym_id() = v_gym_id then
    return 'admin';
  end if;
  return (
    select gm.role from public.gym_members gm
    where gm.user_id = v_user_id and gm.gym_id = v_gym_id and gm.is_active
  );
end;
$function$;

drop policy if exists "profiles gym members can read basic profiles" on public.profiles;
create policy "profiles gym members can read basic profiles"
on public.profiles for select to authenticated
using (public.same_gym_as_current_user(gym_id));

-- This legacy Dashboard policy exists in production but not historical SQL.
-- Replacing it is essential: permissive SELECT policies combine with OR.
drop policy if exists "admin read gym profiles" on public.profiles;
create policy "admin read gym profiles"
on public.profiles for select to authenticated
using (
  id = auth.uid()
  or (gym_id = public.effective_gym_id() and public.membership_actor_can_manage())
);

drop policy if exists "personal records gym admins can read" on public.personal_records;
create policy "personal records gym admins can read"
on public.personal_records for select to authenticated
using (gym_id = public.effective_gym_id() and public.membership_actor_can_manage());

-- Existing self-profile and own-personal-record policies remain in force.
commit;
