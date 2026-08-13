create table if not exists public.notification_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  communications_push_enabled boolean not null default true,
  notifications_push_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.notification_preferences enable row level security;

drop policy if exists "notification preferences read own"
  on public.notification_preferences;
create policy "notification preferences read own"
  on public.notification_preferences
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "notification preferences insert own"
  on public.notification_preferences;
create policy "notification preferences insert own"
  on public.notification_preferences
  for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "notification preferences update own"
  on public.notification_preferences;
create policy "notification preferences update own"
  on public.notification_preferences
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

revoke all on table public.notification_preferences from public, anon;
grant select, insert, update on table public.notification_preferences
  to authenticated;
grant all on table public.notification_preferences to service_role;
