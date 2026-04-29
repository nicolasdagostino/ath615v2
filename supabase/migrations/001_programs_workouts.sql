-- Programs shared by booking classes and workouts.
create table if not exists public.programs (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (gym_id, name)
);

alter table public.classes
  add column if not exists program_id uuid references public.programs(id) on delete set null;

create table if not exists public.workouts (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  program_id uuid not null references public.programs(id) on delete restrict,
  workout_date date not null,
  description text not null,
  image_url text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (gym_id, program_id, workout_date)
);

create table if not exists public.workout_likes (
  workout_id uuid not null references public.workouts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (workout_id, user_id)
);

create table if not exists public.workout_comments (
  id uuid primary key default gen_random_uuid(),
  workout_id uuid not null references public.workouts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);

alter table public.programs enable row level security;
alter table public.workouts enable row level security;
alter table public.workout_likes enable row level security;
alter table public.workout_comments enable row level security;

drop policy if exists "programs gym members can read" on public.programs;

create policy "programs gym members can read"
on public.programs for select
using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.gym_id = programs.gym_id
  )
);

drop policy if exists "programs admins can manage" on public.programs;

create policy "programs admins can manage"
on public.programs for all
using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.gym_id = programs.gym_id
      and p.role in ('admin', 'owner')
  )
)
with check (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.gym_id = programs.gym_id
      and p.role in ('admin', 'owner')
  )
);

drop policy if exists "workouts gym members can read" on public.workouts;

create policy "workouts gym members can read"
on public.workouts for select
using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.gym_id = workouts.gym_id
  )
);

drop policy if exists "workouts admins can manage" on public.workouts;

create policy "workouts admins can manage"
on public.workouts for all
using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.gym_id = workouts.gym_id
      and p.role in ('admin', 'owner')
  )
)
with check (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.gym_id = workouts.gym_id
      and p.role in ('admin', 'owner')
  )
);

drop policy if exists "workout likes gym members can read" on public.workout_likes;

create policy "workout likes gym members can read"
on public.workout_likes for select
using (
  exists (
    select 1
    from public.workouts w
    join public.profiles p on p.gym_id = w.gym_id
    where w.id = workout_likes.workout_id
      and p.id = auth.uid()
  )
);

drop policy if exists "workout likes users can manage own" on public.workout_likes;

create policy "workout likes users can manage own"
on public.workout_likes for all
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "workout comments gym members can read" on public.workout_comments;

create policy "workout comments gym members can read"
on public.workout_comments for select
using (
  exists (
    select 1
    from public.workouts w
    join public.profiles p on p.gym_id = w.gym_id
    where w.id = workout_comments.workout_id
      and p.id = auth.uid()
  )
);

drop policy if exists "workout comments users can create own" on public.workout_comments;

create policy "workout comments users can create own"
on public.workout_comments for insert
with check (user_id = auth.uid());

drop policy if exists "workout comments users can delete own" on public.workout_comments;

create policy "workout comments users can delete own"
on public.workout_comments for delete
using (user_id = auth.uid());
