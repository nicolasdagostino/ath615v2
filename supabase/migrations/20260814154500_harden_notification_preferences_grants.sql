revoke all on table public.notification_preferences
  from public, anon, authenticated;
grant select, insert, update on table public.notification_preferences
  to authenticated;
grant all on table public.notification_preferences to service_role;
