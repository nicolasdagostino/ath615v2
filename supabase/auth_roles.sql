create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name, role, gym_id)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    coalesce(new.raw_user_meta_data->>'role', 'athlete'),
    nullif(new.raw_user_meta_data->>'gym_id', '')::uuid
  )
  on conflict (id) do update
  set full_name = excluded.full_name,
      role = excluded.role,
      gym_id = excluded.gym_id;

  return new;
end;
$$ language plpgsql security definer;

drop policy if exists "owners can update gym profiles" on profiles;

create policy "owners can update gym profiles"
on profiles for update
using (
  exists (
    select 1
    from profiles owner_profile
    where owner_profile.id = auth.uid()
      and owner_profile.role = 'owner'
      and owner_profile.gym_id = profiles.gym_id
  )
);
