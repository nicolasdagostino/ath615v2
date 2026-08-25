-- Versioned legal documents and auditable consent for membership acquisition.
-- Payment rows remain authoritative; this layer only gates creation of a new
-- card or in-person request when an active required document exists.

create table if not exists public.membership_legal_documents (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid references public.gyms(id) on delete cascade,
  document_type text not null,
  version text not null,
  url text not null,
  is_required boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint membership_legal_documents_type_check
    check (document_type in ('privacy', 'terms', 'waiver', 'sales_refund')),
  constraint membership_legal_documents_version_check
    check (nullif(btrim(version), '') is not null),
  constraint membership_legal_documents_url_check
    check (url ~ '^https://')
);

create unique index if not exists membership_legal_documents_active_scope_idx
on public.membership_legal_documents (
  coalesce(gym_id, '00000000-0000-0000-0000-000000000000'::uuid),
  document_type
)
where is_active;

create table if not exists public.membership_legal_acceptances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  gym_id uuid not null references public.gyms(id) on delete cascade,
  plan_id uuid not null references public.membership_plans(id) on delete cascade,
  document_id uuid not null references public.membership_legal_documents(id),
  document_type text not null,
  document_version text not null,
  document_url text not null,
  accepted_at timestamptz not null default now(),
  constraint membership_legal_acceptances_document_type_check
    check (document_type in ('terms', 'waiver', 'sales_refund')),
  unique (user_id, gym_id, plan_id, document_id, document_version)
);

create table if not exists public.membership_request_legal_acceptances (
  request_id uuid not null references public.membership_requests(id) on delete cascade,
  acceptance_id uuid not null references public.membership_legal_acceptances(id),
  primary key (request_id, acceptance_id)
);

alter table public.membership_legal_documents enable row level security;
alter table public.membership_legal_acceptances enable row level security;
alter table public.membership_request_legal_acceptances enable row level security;

drop policy if exists "authenticated read active membership legal documents"
on public.membership_legal_documents;
create policy "authenticated read active membership legal documents"
on public.membership_legal_documents for select to authenticated
using (
  is_active
  and (gym_id is null or gym_id = public.effective_gym_id())
);

drop policy if exists "users read own membership legal acceptances"
on public.membership_legal_acceptances;
create policy "users read own membership legal acceptances"
on public.membership_legal_acceptances for select to authenticated
using (user_id = auth.uid() and gym_id = public.effective_gym_id());

drop policy if exists "users read own request legal acceptances"
on public.membership_request_legal_acceptances;
create policy "users read own request legal acceptances"
on public.membership_request_legal_acceptances for select to authenticated
using (
  exists (
    select 1 from public.membership_requests mr
    where mr.id = request_id and mr.user_id = auth.uid()
      and mr.gym_id = public.effective_gym_id()
  )
);

insert into public.membership_legal_documents (
  gym_id, document_type, version, url, is_required, is_active
)
values
  (null, 'privacy', '2026-08-25', 'https://athlete615.com/privacy-policy', false, true),
  (null, 'terms', '2026-08-25', 'https://athlete615.com/terms-and-conditions', true, true)
on conflict do nothing;

create or replace function public.get_membership_checkout_context(p_plan_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_gym_id uuid := public.effective_gym_id();
  v_plan public.membership_plans%rowtype;
  v_gym public.gyms%rowtype;
begin
  if v_user_id is null or v_gym_id is null or not public.membership_actor_is_active() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  select * into v_plan from public.membership_plans
  where id = p_plan_id and gym_id = v_gym_id and is_active = true;
  if not found then raise exception 'plan_not_found' using errcode = 'P0001'; end if;
  select * into v_gym from public.gyms where id = v_gym_id;
  return jsonb_build_object(
    'gym', jsonb_build_object(
      'id', v_gym.id, 'name', v_gym.name, 'businessName', v_gym.business_name,
      'address', v_gym.address, 'email', v_gym.email, 'phone', v_gym.phone,
      'website', v_gym.website
    ),
    'plan', jsonb_build_object(
      'id', v_plan.id, 'name', v_plan.name, 'planType', v_plan.plan_type,
      'credits', v_plan.credits, 'durationDays', v_plan.duration_days,
      'price', v_plan.price, 'currency', v_plan.currency
    ),
    'documents', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'type', d.document_type, 'version', d.version,
        'url', d.url, 'required', d.is_required
      ) order by d.is_required desc, d.document_type)
      from public.membership_legal_documents d
      where d.is_active and (d.gym_id is null or d.gym_id = v_gym_id)
    ), '[]'::jsonb)
  );
end;
$function$;

create or replace function public.accept_membership_checkout_documents(
  p_plan_id uuid,
  p_document_ids uuid[]
)
returns integer
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_gym_id uuid := public.effective_gym_id();
  v_count integer;
begin
  if v_user_id is null or v_gym_id is null or not public.membership_actor_is_active() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if not exists (select 1 from public.membership_plans
    where id = p_plan_id and gym_id = v_gym_id and is_active = true) then
    raise exception 'plan_not_found' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.membership_legal_documents d
    where d.is_active and d.is_required
      and (d.gym_id is null or d.gym_id = v_gym_id)
      and not (d.id = any(coalesce(p_document_ids, '{}'::uuid[])))
  ) then
    raise exception 'required_consent_missing' using errcode = 'P0001';
  end if;
  insert into public.membership_legal_acceptances (
    user_id, gym_id, plan_id, document_id, document_type,
    document_version, document_url, accepted_at
  )
  select v_user_id, v_gym_id, p_plan_id, d.id, d.document_type,
    d.version, d.url, clock_timestamp()
  from public.membership_legal_documents d
  where d.id = any(coalesce(p_document_ids, '{}'::uuid[]))
    and d.is_active and d.is_required
    and d.document_type in ('terms', 'waiver', 'sales_refund')
    and (d.gym_id is null or d.gym_id = v_gym_id)
  on conflict (user_id, gym_id, plan_id, document_id, document_version)
  do update set accepted_at = excluded.accepted_at,
    document_type = excluded.document_type, document_url = excluded.document_url;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

create or replace function public.create_consented_cash_membership_request(
  p_plan_id uuid,
  p_document_ids uuid[]
)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare v_request_id uuid;
begin
  perform public.accept_membership_checkout_documents(p_plan_id, p_document_ids);
  v_request_id := public.create_cash_membership_request(p_plan_id);
  return v_request_id;
end;
$function$;

create or replace function public.link_membership_request_consents()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $function$
begin
  if new.payment_method in ('cash', 'card') then
    insert into public.membership_request_legal_acceptances(request_id, acceptance_id)
    select new.id, a.id from public.membership_legal_acceptances a
    join public.membership_legal_documents d on d.id = a.document_id
    where a.user_id = new.user_id and a.gym_id = new.gym_id
      and a.plan_id = new.plan_id and d.is_active and d.is_required
      and a.document_version = d.version
    on conflict do nothing;
  end if;
  return new;
end;
$function$;

drop trigger if exists membership_requests_link_consents on public.membership_requests;
create trigger membership_requests_link_consents
after insert on public.membership_requests
for each row execute function public.link_membership_request_consents();

revoke all on table public.membership_legal_documents from anon, authenticated;
revoke all on table public.membership_legal_acceptances from anon, authenticated;
revoke all on table public.membership_request_legal_acceptances from anon, authenticated;
grant select on table public.membership_legal_documents to authenticated;
grant select on table public.membership_legal_acceptances to authenticated;
grant select on table public.membership_request_legal_acceptances to authenticated;

revoke all on function public.get_membership_checkout_context(uuid) from public, anon, authenticated, service_role;
revoke all on function public.accept_membership_checkout_documents(uuid, uuid[]) from public, anon, authenticated, service_role;
revoke all on function public.create_consented_cash_membership_request(uuid, uuid[]) from public, anon, authenticated, service_role;
revoke all on function public.link_membership_request_consents() from public;
grant execute on function public.get_membership_checkout_context(uuid) to authenticated, service_role;
grant execute on function public.accept_membership_checkout_documents(uuid, uuid[]) to authenticated, service_role;
grant execute on function public.create_consented_cash_membership_request(uuid, uuid[]) to authenticated, service_role;
