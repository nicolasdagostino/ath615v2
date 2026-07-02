drop policy if exists "notifications admins can insert gym member notifications" on public.notifications;

create policy "notifications admins can insert gym member notifications"
on public.notifications
for insert
to authenticated
with check (
  exists (
    select 1
    from public.profiles admin_profile
    join public.profiles target_profile
      on target_profile.gym_id = admin_profile.gym_id
    where admin_profile.id = auth.uid()
      and admin_profile.role in ('admin', 'owner')
      and target_profile.id = notifications.user_id
  )
);
