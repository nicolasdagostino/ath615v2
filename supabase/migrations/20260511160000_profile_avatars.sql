alter table public.profiles
add column if not exists avatar_url text;

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = true;

drop policy if exists "avatars public read" on storage.objects;
create policy "avatars public read"
on storage.objects for select
using (bucket_id = 'avatars');

drop policy if exists "users upload own avatar" on storage.objects;
create policy "users upload own avatar"
on storage.objects for insert
with check (
  bucket_id = 'avatars'
  and auth.uid()::text = split_part(name, '.', 1)
);

drop policy if exists "users update own avatar" on storage.objects;
create policy "users update own avatar"
on storage.objects for update
using (
  bucket_id = 'avatars'
  and auth.uid()::text = split_part(name, '.', 1)
)
with check (
  bucket_id = 'avatars'
  and auth.uid()::text = split_part(name, '.', 1)
);
