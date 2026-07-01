drop policy if exists "notifications users can delete own sent" on public.notifications;

create policy "notifications users can delete own sent"
on public.notifications
for delete
to authenticated
using (
  auth.uid() = user_id
  and sent_at is not null
);
