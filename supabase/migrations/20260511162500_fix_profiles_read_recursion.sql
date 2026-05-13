drop policy if exists "profiles gym members can read basic profiles" on public.profiles;

create or replace function public.same_gym_as_current_user(target_gym_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.gym_id = target_gym_id
  );
$$;

grant execute on function public.same_gym_as_current_user(uuid) to authenticated;

create policy "profiles gym members can read basic profiles"
on public.profiles for select
using (
  public.same_gym_as_current_user(gym_id)
);
