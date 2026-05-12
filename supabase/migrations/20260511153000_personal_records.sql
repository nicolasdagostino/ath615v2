create table if not exists public.personal_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  gym_id uuid not null references public.gyms(id) on delete cascade,
  exercise_name text not null,
  weight_kg numeric not null,
  achieved_at date not null default current_date,
  notes text,
  created_at timestamptz not null default now()
);

alter table public.personal_records enable row level security;

drop policy if exists "personal records users can read own" on public.personal_records;
create policy "personal records users can read own"
on public.personal_records for select
using (user_id = auth.uid());

drop policy if exists "personal records users can manage own" on public.personal_records;
create policy "personal records users can manage own"
on public.personal_records for all
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "personal records gym admins can read" on public.personal_records;
create policy "personal records gym admins can read"
on public.personal_records for select
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.gym_id = personal_records.gym_id
      and p.role in ('admin', 'owner')
  )
);
