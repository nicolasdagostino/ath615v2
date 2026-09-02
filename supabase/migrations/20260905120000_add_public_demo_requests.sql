create table if not exists public.public_demo_requests (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  full_name text not null,
  email text not null,
  phone text,
  gym_name text not null,
  approx_member_count integer,
  message text,
  locale text not null default 'en',
  status text not null default 'new' check (status = 'new')
);

alter table public.public_demo_requests enable row level security;
revoke all on table public.public_demo_requests from public, anon, authenticated;

create or replace function public.submit_public_demo_request(
  p_full_name text,
  p_email text,
  p_phone text,
  p_gym_name text,
  p_approx_member_count integer,
  p_message text,
  p_locale text
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_name text := btrim(coalesce(p_full_name, ''));
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_phone text := nullif(btrim(coalesce(p_phone, '')), '');
  v_gym text := btrim(coalesce(p_gym_name, ''));
  v_message text := nullif(btrim(coalesce(p_message, '')), '');
  v_locale text := case when lower(coalesce(p_locale, '')) like 'es%' then 'es' else 'en' end;
begin
  if length(v_name) < 2 or length(v_name) > 160 then raise exception 'invalid_demo_request'; end if;
  if length(v_gym) < 2 or length(v_gym) > 160 then raise exception 'invalid_demo_request'; end if;
  if length(v_email) > 254 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'invalid_demo_request'; end if;
  if v_phone is not null and length(v_phone) > 40 then raise exception 'invalid_demo_request'; end if;
  if v_message is not null and length(v_message) > 1000 then raise exception 'invalid_demo_request'; end if;
  if p_approx_member_count is not null and (p_approx_member_count < 0 or p_approx_member_count > 1000000) then raise exception 'invalid_demo_request'; end if;

  insert into public.public_demo_requests(full_name,email,phone,gym_name,approx_member_count,message,locale)
  values(v_name,v_email,v_phone,v_gym,p_approx_member_count,v_message,v_locale)
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.submit_public_demo_request(text,text,text,text,integer,text,text) from public, authenticated;
grant execute on function public.submit_public_demo_request(text,text,text,text,integer,text,text) to anon;

comment on table public.public_demo_requests is 'Public A615 demo leads; no client-readable policies.';
