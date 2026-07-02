drop policy if exists "profiles admins can read join request profiles" on public.profiles;

create policy "profiles admins can read join request profiles"
on public.profiles
for select
to authenticated
using (
  exists (
    select 1
    from public.profiles admin_profile
    join public.gym_join_requests gjr
      on gjr.gym_id = admin_profile.gym_id
     and gjr.user_id = profiles.id
     and gjr.status = 'pending'
    where admin_profile.id = auth.uid()
      and admin_profile.role in ('admin', 'owner')
  )
);
