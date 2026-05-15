create or replace function public.update_member_role(
  p_member_id uuid,
  p_role text
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_gym_id uuid;
  v_member profiles;
begin
  select gym_id
  into v_admin_gym_id
  from public.profiles
  where id = auth.uid();

  if v_admin_gym_id is null then
    raise exception 'Gym not found';
  end if;

  if p_role not in ('admin', 'athlete') then
    raise exception 'Invalid role';
  end if;

  update public.profiles
  set role = p_role
  where id = p_member_id
    and gym_id = v_admin_gym_id
    and role <> 'owner'
  returning *
  into v_member;

  return v_member;
end;
$$;

grant execute on function public.update_member_role(uuid, text)
to authenticated;
