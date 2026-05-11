create or replace function public.update_gym_member_profile(
  p_member_id uuid,
  p_full_name text,
  p_phone text,
  p_birth_date date
)
returns table (
  id uuid,
  full_name text,
  email text,
  role text,
  gym_id uuid,
  phone text,
  birth_date date,
  is_active boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin profiles%rowtype;
  v_member profiles%rowtype;
begin
  select *
  into v_admin
  from public.profiles
  where profiles.id = auth.uid();

  if v_admin.id is null or v_admin.role not in ('admin', 'owner') then
    raise exception 'Not allowed';
  end if;

  select *
  into v_member
  from public.profiles
  where profiles.id = p_member_id;

  if v_member.id is null then
    raise exception 'Member not found';
  end if;

  if v_member.role = 'owner' then
    raise exception 'Cannot edit owner profile';
  end if;

  if v_member.gym_id is distinct from v_admin.gym_id then
    raise exception 'Member belongs to a different gym';
  end if;

  return query
  update public.profiles
  set
    full_name = nullif(trim(p_full_name), ''),
    phone = nullif(trim(p_phone), ''),
    birth_date = p_birth_date
  where profiles.id = p_member_id
  returning
    profiles.id,
    profiles.full_name,
    profiles.email,
    profiles.role,
    profiles.gym_id,
    profiles.phone,
    profiles.birth_date,
    profiles.is_active,
    profiles.created_at;
end;
$$;

grant execute on function public.update_gym_member_profile(uuid, text, text, date) to authenticated;
