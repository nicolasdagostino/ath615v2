-- A615 public Help Center V2. Public writes use validated RPCs; reads remain Owner-only.

alter table public.public_demo_requests drop constraint if exists public_demo_requests_status_check;
alter table public.public_demo_requests
  add column if not exists owner_notes text,
  add column if not exists updated_at timestamptz not null default clock_timestamp(),
  add constraint public_demo_requests_status_check
    check (status in ('new','contacted','demo_scheduled','won','lost')),
  add constraint public_demo_requests_owner_notes_check
    check (owner_notes is null or length(owner_notes) <= 4000);

create function public.prevent_rapid_duplicate_demo_request() returns trigger
language plpgsql set search_path=public,pg_temp as $$
begin
 if exists(select 1 from public.public_demo_requests r where r.email=new.email and r.gym_name=new.gym_name
  and r.created_at>clock_timestamp()-interval '60 seconds') then raise exception 'duplicate_request'; end if;
 return new;
end $$;
create trigger prevent_rapid_duplicate_demo_request before insert on public.public_demo_requests
for each row execute function public.prevent_rapid_duplicate_demo_request();

create table public.public_support_requests (
  id uuid primary key default gen_random_uuid(), created_at timestamptz not null default clock_timestamp(),
  full_name text not null, email text not null, gym_name text, issue_type text not null,
  screen_name text, description text not null, attachment_path text,
  app_version text, build_number text, platform text, os_version text, locale text not null default 'en',
  user_id uuid references public.profiles(id) on delete set null, gym_id uuid references public.gyms(id) on delete set null,
  status text not null default 'new' check(status in('new','in_progress','resolved','closed')),
  owner_notes text, updated_at timestamptz not null default clock_timestamp(),
  check(issue_type in('login','booking','memberships','workouts','notifications','profile','administration','other')),
  check(owner_notes is null or length(owner_notes)<=4000)
);

create table public.public_contact_requests (
  id uuid primary key default gen_random_uuid(), created_at timestamptz not null default clock_timestamp(),
  full_name text not null, email text not null, gym_name text, subject text not null, message text not null,
  locale text not null default 'en', user_id uuid references public.profiles(id) on delete set null,
  gym_id uuid references public.gyms(id) on delete set null,
  status text not null default 'new' check(status in('new','in_progress','resolved','closed')),
  owner_notes text, updated_at timestamptz not null default clock_timestamp(),
  check(owner_notes is null or length(owner_notes)<=4000)
);

alter table public.public_support_requests enable row level security;
alter table public.public_contact_requests enable row level security;
create index public_demo_requests_email_created_idx on public.public_demo_requests(email,created_at desc);
create index public_support_requests_email_created_idx on public.public_support_requests(email,created_at desc);
create index public_contact_requests_email_created_idx on public.public_contact_requests(email,created_at desc);
create index public_demo_requests_created_idx on public.public_demo_requests(created_at desc);
create index public_support_requests_created_idx on public.public_support_requests(created_at desc);
create index public_contact_requests_created_idx on public.public_contact_requests(created_at desc);
revoke all on public.public_demo_requests, public.public_support_requests, public.public_contact_requests from public,anon,authenticated;

create or replace function public.help_request_locale(p_locale text) returns text
language sql immutable set search_path=public,pg_temp as $$
  select case when lower(coalesce(p_locale,'')) like 'es%' then 'es' else 'en' end
$$;

create function public.submit_public_support_request(
  p_full_name text,p_email text,p_gym_name text,p_issue_type text,p_screen_name text,p_description text,
  p_app_version text,p_build_number text,p_platform text,p_os_version text,p_locale text
) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_name text:=btrim(coalesce(p_full_name,'')); v_email text:=lower(btrim(coalesce(p_email,'')));
  v_gym text:=nullif(btrim(coalesce(p_gym_name,'')),''); v_screen text:=nullif(btrim(coalesce(p_screen_name,'')),'');
  v_description text:=btrim(coalesce(p_description,'')); v_user uuid:=auth.uid(); v_gym_id uuid;
begin
  if length(v_name) not between 2 and 160 or length(v_email)>254 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    or p_issue_type not in('login','booking','memberships','workouts','notifications','profile','administration','other')
    or length(v_description) not between 10 and 4000 or length(coalesce(v_gym,''))>160 or length(coalesce(v_screen,''))>160
    or length(coalesce(p_app_version,''))>32 or length(coalesce(p_build_number,''))>32
    or length(coalesce(p_platform,''))>24 or length(coalesce(p_os_version,''))>160 then raise exception 'invalid_support_request'; end if;
  if exists(select 1 from public.public_support_requests r where r.email=v_email and r.description=v_description
    and r.created_at>clock_timestamp()-interval '60 seconds') then raise exception 'duplicate_request'; end if;
  if v_user is not null then v_gym_id:=public.effective_gym_id(); end if;
  insert into public.public_support_requests(full_name,email,gym_name,issue_type,screen_name,description,
    app_version,build_number,platform,os_version,locale,user_id,gym_id)
  values(v_name,v_email,v_gym,p_issue_type,v_screen,v_description,nullif(btrim(p_app_version),''),nullif(btrim(p_build_number),''),
    nullif(btrim(p_platform),''),nullif(btrim(p_os_version),''),public.help_request_locale(p_locale),v_user,v_gym_id) returning id into v_id;
  return v_id;
end $$;

create function public.submit_public_contact_request(p_full_name text,p_email text,p_gym_name text,p_subject text,p_message text,p_locale text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_name text:=btrim(coalesce(p_full_name,'')); v_email text:=lower(btrim(coalesce(p_email,'')));
 v_gym text:=nullif(btrim(coalesce(p_gym_name,'')),''); v_subject text:=btrim(coalesce(p_subject,''));
 v_message text:=btrim(coalesce(p_message,'')); v_user uuid:=auth.uid(); v_gym_id uuid;
begin
 if length(v_name) not between 2 and 160 or length(v_email)>254 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  or length(v_subject) not between 2 and 200 or length(v_message) not between 10 and 4000 or length(coalesce(v_gym,''))>160
  then raise exception 'invalid_contact_request'; end if;
 if exists(select 1 from public.public_contact_requests r where r.email=v_email and r.subject=v_subject and r.message=v_message
  and r.created_at>clock_timestamp()-interval '60 seconds') then raise exception 'duplicate_request'; end if;
 if v_user is not null then v_gym_id:=public.effective_gym_id(); end if;
 insert into public.public_contact_requests(full_name,email,gym_name,subject,message,locale,user_id,gym_id)
 values(v_name,v_email,v_gym,v_subject,v_message,public.help_request_locale(p_locale),v_user,v_gym_id) returning id into v_id; return v_id;
end $$;

create function public.get_public_saas_plan_catalog() returns table(code text,name text,active_member_limit integer,monthly_price_eur integer,sort_order integer)
language sql stable security definer set search_path=public,pg_temp as $$
 select p.code,p.name,p.active_member_limit,p.monthly_price_eur,p.sort_order from public.saas_plans p where p.is_active order by p.sort_order
$$;

create function public.get_platform_owner_requests(p_filter text default 'all') returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare result jsonb;
begin
 if not public.platform_owner_active() then raise exception using errcode='42501',message='platform_owner_required'; end if;
 with all_requests as (
  select 'demo'::text type,id,created_at,full_name,email,gym_name,status,null::text issue_type from public.public_demo_requests
  union all select 'support',id,created_at,full_name,email,gym_name,status,issue_type from public.public_support_requests
  union all select 'other',id,created_at,full_name,email,gym_name,status,null from public.public_contact_requests
 ), filtered as (select * from all_requests where p_filter='all' or p_filter=type or (p_filter='new' and status='new'))
 select jsonb_build_object('counts',jsonb_build_object(
  'new',(select count(*) from all_requests where status='new'),'demo',(select count(*) from all_requests where type='demo'),
  'support',(select count(*) from all_requests where type='support'),'other',(select count(*) from all_requests where type='other')),
  'items',coalesce((select jsonb_agg(to_jsonb(f) order by created_at desc) from (select * from filtered order by created_at desc limit 100) f),'[]'::jsonb)) into result;
 return result;
end $$;

create function public.get_platform_owner_request(p_type text,p_id uuid) returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare result jsonb;
begin
 if not public.platform_owner_active() then raise exception using errcode='42501',message='platform_owner_required'; end if;
 if p_type='demo' then select to_jsonb(r)||jsonb_build_object('type','demo') into result from public.public_demo_requests r where id=p_id;
 elsif p_type='support' then select to_jsonb(r)||jsonb_build_object('type','support') into result from public.public_support_requests r where id=p_id;
 elsif p_type='other' then select to_jsonb(r)||jsonb_build_object('type','other') into result from public.public_contact_requests r where id=p_id;
 else raise exception 'invalid_request_type'; end if;
 return result;
end $$;

create function public.update_platform_owner_request(p_type text,p_id uuid,p_status text,p_owner_notes text) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare notes text:=nullif(btrim(coalesce(p_owner_notes,'')),'');
begin
 if not public.platform_owner_active() then raise exception using errcode='42501',message='platform_owner_required'; end if;
 if length(coalesce(notes,''))>4000 then raise exception 'invalid_owner_notes'; end if;
 if p_type='demo' and p_status in('new','contacted','demo_scheduled','won','lost') then update public.public_demo_requests set status=p_status,owner_notes=notes,updated_at=clock_timestamp() where id=p_id;
 elsif p_type='support' and p_status in('new','in_progress','resolved','closed') then update public.public_support_requests set status=p_status,owner_notes=notes,updated_at=clock_timestamp() where id=p_id;
 elsif p_type='other' and p_status in('new','in_progress','resolved','closed') then update public.public_contact_requests set status=p_status,owner_notes=notes,updated_at=clock_timestamp() where id=p_id;
 else raise exception 'invalid_request_status'; end if;
 if not found then raise exception 'request_not_found'; end if;
end $$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('support-attachments','support-attachments',false,5242880,array['image/png','image/jpeg','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create function public.authorize_platform_owner_support_attachment(p_path text) returns boolean
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not public.platform_owner_active() then raise exception using errcode='42501',message='platform_owner_required'; end if;
 return exists(select 1 from public.public_support_requests where attachment_path=p_path);
end $$;

revoke all on function public.submit_public_support_request(text,text,text,text,text,text,text,text,text,text,text),
 public.submit_public_contact_request(text,text,text,text,text,text),public.get_public_saas_plan_catalog(),
 public.get_platform_owner_requests(text),public.get_platform_owner_request(text,uuid),
 public.update_platform_owner_request(text,uuid,text,text),public.authorize_platform_owner_support_attachment(text) from public,anon,authenticated;
revoke all on function public.help_request_locale(text),public.prevent_rapid_duplicate_demo_request() from public,anon,authenticated;
grant execute on function public.submit_public_support_request(text,text,text,text,text,text,text,text,text,text,text),
 public.submit_public_contact_request(text,text,text,text,text,text),public.get_public_saas_plan_catalog() to anon,authenticated;
grant execute on function public.get_platform_owner_requests(text),public.get_platform_owner_request(text,uuid),
 public.update_platform_owner_request(text,uuid,text,text),public.authorize_platform_owner_support_attachment(text) to authenticated;
