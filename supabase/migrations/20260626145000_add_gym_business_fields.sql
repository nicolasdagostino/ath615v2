alter table public.gyms
  add column if not exists business_name text,
  add column if not exists phone text,
  add column if not exists email text,
  add column if not exists website text,
  add column if not exists address text;
