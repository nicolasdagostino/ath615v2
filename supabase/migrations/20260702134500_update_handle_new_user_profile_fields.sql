create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
as $function$
begin
  insert into public.profiles (
    id,
    email,
    full_name,
    role,
    gym_id,
    phone,
    birth_date
  )
  values (
    new.id,
    new.email,
    nullif(trim(coalesce(new.raw_user_meta_data->>'full_name', new.email)), ''),
    coalesce(new.raw_user_meta_data->>'role', 'athlete'),
    nullif(new.raw_user_meta_data->>'gym_id', '')::uuid,
    nullif(trim(new.raw_user_meta_data->>'phone'), ''),
    nullif(new.raw_user_meta_data->>'birth_date', '')::date
  )
  on conflict (id) do update
  set email = excluded.email,
      full_name = excluded.full_name,
      role = excluded.role,
      gym_id = excluded.gym_id,
      phone = excluded.phone,
      birth_date = excluded.birth_date;

  return new;
end;
$function$;
