alter table public.gyms
  add column if not exists gym_code text;

create unique index if not exists gyms_gym_code_unique_idx
on public.gyms (upper(gym_code))
where gym_code is not null;

create table if not exists public.gym_join_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  gym_id uuid not null references public.gyms(id) on delete cascade,
  status text not null default 'pending',
  message text,
  approved_at timestamptz,
  approved_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint gym_join_requests_status_check
    check (status in ('pending', 'approved', 'rejected', 'cancelled'))
);

create index if not exists gym_join_requests_user_id_idx
on public.gym_join_requests (user_id);

create index if not exists gym_join_requests_gym_id_status_idx
on public.gym_join_requests (gym_id, status);

create unique index if not exists gym_join_requests_one_pending_per_user_idx
on public.gym_join_requests (user_id)
where status = 'pending';

alter table public.gym_join_requests enable row level security;

drop policy if exists "gym join requests users can read own" on public.gym_join_requests;
create policy "gym join requests users can read own"
on public.gym_join_requests
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "gym join requests users can create own" on public.gym_join_requests;
create policy "gym join requests users can create own"
on public.gym_join_requests
for insert
to authenticated
with check (
  auth.uid() = user_id
  and status = 'pending'
);

drop policy if exists "gym join requests admins can read gym requests" on public.gym_join_requests;
create policy "gym join requests admins can read gym requests"
on public.gym_join_requests
for select
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.gym_id = gym_join_requests.gym_id
      and p.role in ('admin', 'owner')
  )
);

drop policy if exists "gym join requests admins can update gym requests" on public.gym_join_requests;
create policy "gym join requests admins can update gym requests"
on public.gym_join_requests
for update
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.gym_id = gym_join_requests.gym_id
      and p.role in ('admin', 'owner')
  )
)
with check (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.gym_id = gym_join_requests.gym_id
      and p.role in ('admin', 'owner')
  )
);
