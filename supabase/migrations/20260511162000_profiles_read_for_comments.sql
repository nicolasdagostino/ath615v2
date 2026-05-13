drop policy if exists "profiles users can read self" on public.profiles;
create policy "profiles users can read self"
on public.profiles for select
using (id = auth.uid());

drop policy if exists "profiles gym members can read basic profiles" on public.profiles;
create policy "profiles gym members can read basic profiles"
on public.profiles for select
using (
  exists (
    select 1
    from public.profiles me
    where me.id = auth.uid()
      and me.gym_id = profiles.gym_id
  )
);
