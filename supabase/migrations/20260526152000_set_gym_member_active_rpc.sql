create or replace function public.set_gym_member_active(
  p_member_id uuid,
  p_is_active boolean
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin profiles%rowtype;
  v_member profiles%rowtype;
  v_updated profiles%rowtype;
begin
  select *
  into v_admin
  from public.profiles
  where profiles.id = auth.uid();

  if v_admin.id is null then
    raise exception 'Unauthorized';
  end if;

  if v_admin.role not in ('admin', 'owner') then
    raise exception 'Only admins can update member status';
  end if;

  select *
  into v_member
  from public.profiles
  where profiles.id = p_member_id;

  if v_member.id is null then
    raise exception 'Member not found';
  end if;

  if v_member.gym_id is distinct from v_admin.gym_id then
    raise exception 'Member belongs to another gym';
  end if;

  update public.profiles
  set is_active = p_is_active
  where profiles.id = p_member_id
  returning *
  into v_updated;

  return v_updated;
end;
$$;

grant execute on function public.set_gym_member_active(uuid, boolean) to authenticated;
