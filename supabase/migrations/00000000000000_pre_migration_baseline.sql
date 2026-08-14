-- Reconstructed baseline for the schema that predates Supabase migration
-- tracking in this project. The remote history starts at 001, but that
-- migration already references these tables. Keep this file limited to the
-- pre-001 objects; every later change remains owned by its original migration.

create extension if not exists pg_cron with schema pg_catalog;

-- Supabase's original Dashboard-created schema granted API roles access at
-- the table layer and relied on RLS for row authorization. Preserve those
-- default privileges so later migration-created objects behave the same way.
alter default privileges for role postgres in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  grant all on sequences to anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  grant all on functions to anon, authenticated, service_role;

create table public.gyms (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid,
  created_at timestamptz default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role text default 'athlete',
  gym_id uuid references public.gyms(id) on delete set null,
  created_at timestamptz default now(),
  birth_date date,
  is_active boolean default true,
  email text
);

alter table public.gyms
  add constraint gyms_owner_id_fkey
  foreign key (owner_id) references public.profiles(id) on delete set null;

create table public.classes (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  title text not null,
  starts_at timestamptz not null,
  duration_minutes integer default 60,
  capacity integer default 12,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz default now(),
  recurring_id uuid
);

create table public.membership_plans (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  name text not null,
  plan_type text not null,
  credits integer,
  is_active boolean default true,
  created_at timestamptz default now(),
  price numeric,
  currency text not null default 'EUR'
);

create table public.member_memberships (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade,
  gym_id uuid references public.gyms(id) on delete cascade,
  status text not null default 'active',
  starts_at timestamptz default now(),
  ends_at timestamptz,
  created_at timestamptz default now(),
  expires_at timestamptz,
  is_active boolean not null default true,
  plan_id uuid references public.membership_plans(id) on delete set null,
  credits_remaining integer
);

create table public.membership_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  gym_id uuid not null references public.gyms(id) on delete cascade,
  plan_id uuid not null references public.membership_plans(id) on delete restrict,
  status text not null default 'pending',
  created_at timestamptz not null default now()
);

create table public.class_bookings (
  id uuid primary key default gen_random_uuid(),
  class_id uuid references public.classes(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  status text default 'booked',
  created_at timestamptz default now(),
  unique (class_id, user_id)
);

create table public.membership_credit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  gym_id uuid not null references public.gyms(id) on delete cascade,
  membership_id uuid references public.member_memberships(id) on delete set null,
  amount integer not null,
  reason text not null,
  class_id uuid references public.classes(id) on delete set null,
  created_at timestamptz default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade,
  title text,
  body text,
  type text,
  data jsonb,
  scheduled_for timestamptz,
  sent_at timestamptz,
  read_at timestamptz
);

create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null unique,
  platform text,
  created_at timestamptz default now()
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles(id, email, full_name)
  values (
    new.id,
    new.email,
    nullif(btrim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

alter table public.gyms enable row level security;
alter table public.profiles enable row level security;
alter table public.classes enable row level security;
alter table public.class_bookings enable row level security;
alter table public.membership_plans enable row level security;
alter table public.member_memberships enable row level security;
alter table public.membership_requests enable row level security;
alter table public.membership_credit_logs enable row level security;
alter table public.notifications enable row level security;
alter table public.device_tokens enable row level security;

grant all on all tables in schema public
to anon, authenticated, service_role;
grant all on all sequences in schema public
to anon, authenticated, service_role;
