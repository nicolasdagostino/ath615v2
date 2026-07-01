create table if not exists public.class_waitlist (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (class_id, user_id)
);

create index if not exists class_waitlist_class_id_created_at_idx
on public.class_waitlist (class_id, created_at);

create index if not exists class_waitlist_user_id_idx
on public.class_waitlist (user_id);

alter table public.class_waitlist enable row level security;

drop policy if exists "athletes view own waitlist" on public.class_waitlist;
create policy "athletes view own waitlist"
on public.class_waitlist
for select
using (user_id = auth.uid());

drop policy if exists "admins view gym waitlist" on public.class_waitlist;
create policy "admins view gym waitlist"
on public.class_waitlist
for select
using (
  exists (
    select 1
    from public.classes c
    join public.profiles p on p.gym_id = c.gym_id
    where c.id = class_waitlist.class_id
      and p.id = auth.uid()
      and p.role = any (array['admin'::text, 'owner'::text])
  )
);

drop policy if exists "athletes join own waitlist" on public.class_waitlist;
create policy "athletes join own waitlist"
on public.class_waitlist
for insert
with check (user_id = auth.uid());

drop policy if exists "athletes leave own waitlist" on public.class_waitlist;
create policy "athletes leave own waitlist"
on public.class_waitlist
for delete
using (user_id = auth.uid());

drop policy if exists "admins manage gym waitlist" on public.class_waitlist;
create policy "admins manage gym waitlist"
on public.class_waitlist
for delete
using (
  exists (
    select 1
    from public.classes c
    join public.profiles p on p.gym_id = c.gym_id
    where c.id = class_waitlist.class_id
      and p.id = auth.uid()
      and p.role = any (array['admin'::text, 'owner'::text])
  )
);
