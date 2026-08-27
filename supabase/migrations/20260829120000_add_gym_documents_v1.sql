-- Documents V1: immutable, versioned, gym-scoped text documents.
-- Existing membership_legal_* tables remain the platform/Stripe legal source.

begin;

create table public.gym_documents (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id),
  title text not null,
  status text not null default 'active',
  current_version_id uuid,
  created_by uuid,
  created_at timestamptz not null default now(),
  archived_at timestamptz,
  constraint gym_documents_title_check
    check (length(btrim(title)) between 1 and 160),
  constraint gym_documents_status_check
    check (status in ('active', 'archived')),
  constraint gym_documents_archive_check check (
    (status = 'active' and archived_at is null)
    or (status = 'archived' and archived_at is not null)
  )
);

create table public.gym_document_versions (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.gym_documents(id),
  version_number integer not null,
  title_snapshot text not null,
  body text not null,
  acceptance_mode text not null,
  status text not null default 'draft',
  content_sha256 text,
  created_by uuid,
  created_at timestamptz not null default now(),
  published_by uuid,
  published_at timestamptz,
  constraint gym_document_versions_number_check check (version_number > 0),
  constraint gym_document_versions_title_check
    check (length(btrim(title_snapshot)) between 1 and 160),
  constraint gym_document_versions_body_check
    check (length(btrim(body)) between 1 and 20000),
  constraint gym_document_versions_acceptance_check
    check (acceptance_mode in ('required', 'informational')),
  constraint gym_document_versions_status_check
    check (status in ('draft', 'published')),
  constraint gym_document_versions_publication_check check (
    (status = 'draft' and content_sha256 is null
      and published_by is null and published_at is null)
    or (status = 'published' and content_sha256 ~ '^[0-9a-f]{64}$'
      and published_at is not null)
  ),
  unique (document_id, version_number)
);

alter table public.gym_documents add constraint gym_documents_id_gym_unique
  unique (id, gym_id);
alter table public.gym_document_versions add constraint gym_document_versions_id_document_unique
  unique (id, document_id);

alter table public.gym_documents
  add constraint gym_documents_current_version_fkey
  foreign key (current_version_id) references public.gym_document_versions(id);
alter table public.gym_documents
  add constraint gym_documents_current_version_ownership_fkey
  foreign key (current_version_id,id)
  references public.gym_document_versions(id,document_id);

create unique index gym_document_versions_one_draft_idx
on public.gym_document_versions(document_id)
where status = 'draft';
create index gym_documents_gym_status_idx
on public.gym_documents(gym_id, status, created_at desc);
create index gym_document_versions_document_status_idx
on public.gym_document_versions(document_id, status, version_number desc);

-- user_id intentionally has no profile FK. Account deletion currently removes
-- profiles; retaining the immutable UUID preserves technical evidence without
-- blocking that established workflow or cascading acceptances away.
create table public.gym_document_acceptances (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id),
  document_id uuid not null references public.gym_documents(id),
  version_id uuid not null references public.gym_document_versions(id),
  user_id uuid not null,
  accepted_at timestamptz not null default now(),
  source text not null,
  created_at timestamptz not null default now(),
  constraint gym_document_acceptances_source_check
    check (source in ('profile', 'checkout')),
  unique (user_id, version_id)
);
alter table public.gym_document_acceptances
  add constraint gym_document_acceptances_document_gym_fkey
  foreign key (document_id,gym_id) references public.gym_documents(id,gym_id);
alter table public.gym_document_acceptances
  add constraint gym_document_acceptances_version_document_fkey
  foreign key (version_id,document_id)
  references public.gym_document_versions(id,document_id);
create index gym_document_acceptances_gym_user_idx
on public.gym_document_acceptances(gym_id, user_id, accepted_at desc);
create index gym_document_acceptances_version_idx
on public.gym_document_acceptances(version_id, accepted_at desc);

-- request_id is an immutable audit identifier rather than a cascading FK.
-- Existing account deletion removes membership_requests; the snapshot link is
-- deliberately retained together with the acceptance.
create table public.membership_request_gym_document_acceptances (
  request_id uuid not null,
  acceptance_id uuid not null references public.gym_document_acceptances(id),
  created_at timestamptz not null default now(),
  primary key (request_id, acceptance_id)
);
create index membership_request_gym_docs_acceptance_idx
on public.membership_request_gym_document_acceptances(acceptance_id);

alter table public.gym_documents enable row level security;
alter table public.gym_document_versions enable row level security;
alter table public.gym_document_acceptances enable row level security;
alter table public.membership_request_gym_document_acceptances enable row level security;

create or replace function public.documents_actor_can_manage()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$ select public.membership_actor_can_manage(); $$;

create or replace function public.documents_actor_is_active()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and public.effective_gym_id() is not null
    and public.membership_actor_is_active();
$$;

create policy "effective members read published gym documents"
on public.gym_documents for select to authenticated
using (
  gym_id = public.effective_gym_id()
  and public.documents_actor_is_active()
  and (status = 'active' or public.documents_actor_can_manage() or exists(
    select 1 from public.gym_document_acceptances a
    where a.document_id=gym_documents.id and a.user_id=auth.uid()
  ))
);
create policy "effective members read gym document versions"
on public.gym_document_versions for select to authenticated
using (exists (
  select 1 from public.gym_documents d
  where d.id = document_id and d.gym_id = public.effective_gym_id()
    and public.documents_actor_is_active()
    and (public.documents_actor_can_manage() or (
      gym_document_versions.status = 'published' and (
        (d.status='active' and d.current_version_id=gym_document_versions.id)
        or exists(select 1 from public.gym_document_acceptances a
          where a.version_id=gym_document_versions.id and a.user_id=auth.uid())
      )
    ))
));
create policy "users and admins read gym document acceptances"
on public.gym_document_acceptances for select to authenticated
using (
  gym_id = public.effective_gym_id()
  and (user_id = auth.uid() or public.documents_actor_can_manage())
);
create policy "users and admins read request document links"
on public.membership_request_gym_document_acceptances for select to authenticated
using (exists (
  select 1 from public.gym_document_acceptances a
  where a.id = acceptance_id and a.gym_id = public.effective_gym_id()
    and (a.user_id = auth.uid() or public.documents_actor_can_manage())
));

create or replace function public.canonical_gym_document_hash(
  p_version_number integer,
  p_title text,
  p_body text,
  p_acceptance_mode text
)
returns text
language sql immutable
set search_path = public, pg_temp
as $$
  select encode(extensions.digest(convert_to(
    p_version_number::text || E'\n' || btrim(p_title) || E'\n'
      || btrim(p_body) || E'\n' || p_acceptance_mode,
    'UTF8'), 'sha256'), 'hex');
$$;

create or replace function public.protect_gym_document_version()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $function$
begin
  if tg_op = 'DELETE' then
    if old.status = 'published' then
      raise exception 'published_version_immutable' using errcode = '55000';
    end if;
    return old;
  end if;
  if tg_op = 'UPDATE' and old.status = 'published' then
    raise exception 'published_version_immutable' using errcode = '55000';
  end if;
  new.title_snapshot := btrim(new.title_snapshot);
  new.body := btrim(new.body);
  if tg_op = 'INSERT' and new.status <> 'draft' then
    raise exception 'version_must_start_as_draft' using errcode = '22023';
  end if;
  if tg_op = 'UPDATE' and old.status = 'draft' and new.status = 'published' then
    new.content_sha256 := public.canonical_gym_document_hash(
      new.version_number, new.title_snapshot, new.body, new.acceptance_mode
    );
    new.published_by := auth.uid();
    new.published_at := clock_timestamp();
  elsif new.status = 'draft' then
    new.content_sha256 := null;
    new.published_by := null;
    new.published_at := null;
  end if;
  return new;
end;
$function$;
create trigger protect_gym_document_version_trigger
before insert or update or delete on public.gym_document_versions
for each row execute function public.protect_gym_document_version();

create or replace function public.protect_gym_document_acceptance()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $function$
begin
  raise exception 'document_acceptance_immutable' using errcode = '55000';
end;
$function$;
create trigger protect_gym_document_acceptance_trigger
before update or delete on public.gym_document_acceptances
for each row execute function public.protect_gym_document_acceptance();

create trigger protect_membership_request_gym_document_snapshot_trigger
before update or delete on public.membership_request_gym_document_acceptances
for each row execute function public.protect_gym_document_acceptance();

create or replace function public.protect_published_gym_document()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $function$
begin
  if exists (select 1 from public.gym_document_versions v
    where v.document_id = old.id and v.status = 'published') then
    raise exception 'published_document_must_be_archived' using errcode = '55000';
  end if;
  return old;
end;
$function$;
create trigger protect_published_gym_document_trigger
before delete on public.gym_documents
for each row execute function public.protect_published_gym_document();

create or replace function public.lock_effective_gym_documents(p_gym_id uuid)
returns void
language sql volatile security definer
set search_path = public, pg_temp
as $$
  select pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('gym-documents:' || p_gym_id::text, 615)
  );
$$;

create or replace function public.create_effective_gym_document(
  p_title text, p_body text, p_acceptance_mode text
)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare v_gym_id uuid := public.effective_gym_id(); v_document_id uuid; v_version_id uuid;
begin
  if v_gym_id is null or not public.documents_actor_can_manage() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  perform public.lock_effective_gym_documents(v_gym_id);
  insert into public.gym_documents(gym_id,title,created_by)
  values(v_gym_id,btrim(p_title),auth.uid()) returning id into v_document_id;
  insert into public.gym_document_versions(
    document_id,version_number,title_snapshot,body,acceptance_mode,created_by
  ) values(v_document_id,1,btrim(p_title),btrim(p_body),p_acceptance_mode,auth.uid())
  returning id into v_version_id;
  return v_version_id;
end;
$function$;

create or replace function public.update_effective_gym_document_draft(
  p_version_id uuid, p_title text, p_body text, p_acceptance_mode text
)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare v_gym_id uuid := public.effective_gym_id(); v_document_id uuid;
begin
  if v_gym_id is null or not public.documents_actor_can_manage() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  perform public.lock_effective_gym_documents(v_gym_id);
  select d.id into v_document_id from public.gym_document_versions v
  join public.gym_documents d on d.id=v.document_id
  where v.id=p_version_id and v.status='draft' and d.gym_id=v_gym_id
    and d.status='active' for update of d,v;
  if not found then raise exception 'draft_not_found' using errcode='P0001'; end if;
  update public.gym_document_versions set title_snapshot=btrim(p_title),
    body=btrim(p_body), acceptance_mode=p_acceptance_mode where id=p_version_id;
  update public.gym_documents set title=btrim(p_title) where id=v_document_id;
end;
$function$;

create or replace function public.create_effective_gym_document_version(p_document_id uuid)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare v_gym_id uuid := public.effective_gym_id(); v_document public.gym_documents%rowtype;
  v_current public.gym_document_versions%rowtype; v_version_id uuid; v_next integer;
begin
  if v_gym_id is null or not public.documents_actor_can_manage() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  perform public.lock_effective_gym_documents(v_gym_id);
  select * into v_document from public.gym_documents
  where id=p_document_id and gym_id=v_gym_id and status='active' for update;
  if not found or v_document.current_version_id is null then
    raise exception 'published_document_not_found' using errcode='P0001';
  end if;
  if exists(select 1 from public.gym_document_versions
    where document_id=p_document_id and status='draft') then
    raise exception 'draft_already_exists' using errcode='P0001';
  end if;
  select * into v_current from public.gym_document_versions
  where id=v_document.current_version_id and document_id=p_document_id and status='published';
  select coalesce(max(version_number),0)+1 into v_next
  from public.gym_document_versions where document_id=p_document_id;
  insert into public.gym_document_versions(
    document_id,version_number,title_snapshot,body,acceptance_mode,created_by
  ) values(p_document_id,v_next,v_current.title_snapshot,v_current.body,
    v_current.acceptance_mode,auth.uid()) returning id into v_version_id;
  return v_version_id;
end;
$function$;

create or replace function public.publish_effective_gym_document_version(p_version_id uuid)
returns text
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare v_gym_id uuid := public.effective_gym_id(); v_document_id uuid; v_hash text;
begin
  if v_gym_id is null or not public.documents_actor_can_manage() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  perform public.lock_effective_gym_documents(v_gym_id);
  select d.id into v_document_id from public.gym_document_versions v
  join public.gym_documents d on d.id=v.document_id
  where v.id=p_version_id and v.status='draft' and d.gym_id=v_gym_id
    and d.status='active' for update of d,v;
  if not found then raise exception 'draft_not_found' using errcode='P0001'; end if;
  update public.gym_document_versions set status='published' where id=p_version_id
  returning content_sha256 into v_hash;
  update public.gym_documents set current_version_id=p_version_id,
    title=(select title_snapshot from public.gym_document_versions where id=p_version_id)
  where id=v_document_id;
  return v_hash;
end;
$function$;

create or replace function public.delete_effective_gym_document_draft(p_version_id uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare v_gym_id uuid := public.effective_gym_id(); v_document_id uuid; v_has_published boolean;
begin
  if v_gym_id is null or not public.documents_actor_can_manage() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  perform public.lock_effective_gym_documents(v_gym_id);
  select d.id into v_document_id from public.gym_document_versions v
  join public.gym_documents d on d.id=v.document_id
  where v.id=p_version_id and v.status='draft' and d.gym_id=v_gym_id for update of d,v;
  if not found then raise exception 'draft_not_found' using errcode='P0001'; end if;
  select exists(select 1 from public.gym_document_versions
    where document_id=v_document_id and status='published') into v_has_published;
  delete from public.gym_document_versions where id=p_version_id;
  if not v_has_published then delete from public.gym_documents where id=v_document_id; end if;
end;
$function$;

create or replace function public.archive_effective_gym_document(p_document_id uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare v_gym_id uuid := public.effective_gym_id();
begin
  if v_gym_id is null or not public.documents_actor_can_manage() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  perform public.lock_effective_gym_documents(v_gym_id);
  update public.gym_documents set status='archived',archived_at=clock_timestamp()
  where id=p_document_id and gym_id=v_gym_id and status='active';
  if not found then raise exception 'document_not_found' using errcode='P0001'; end if;
end;
$function$;

create or replace function public.list_effective_gym_documents_admin()
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $function$
declare v_gym_id uuid := public.effective_gym_id(); v_result jsonb;
begin
  if v_gym_id is null or not public.documents_actor_can_manage() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',d.id,'title',d.title,'status',d.status,'archivedAt',d.archived_at,
    'currentVersion',case when cv.id is null then null else jsonb_build_object(
      'id',cv.id,'versionNumber',cv.version_number,'title',cv.title_snapshot,
      'body',cv.body,'acceptanceMode',cv.acceptance_mode,'status',cv.status,
      'contentSha256',cv.content_sha256,'publishedAt',cv.published_at) end,
    'draftVersion',case when dv.id is null then null else jsonb_build_object(
      'id',dv.id,'versionNumber',dv.version_number,'title',dv.title_snapshot,
      'body',dv.body,'acceptanceMode',dv.acceptance_mode,'status',dv.status) end
  ) order by (d.status='archived'),d.created_at desc),'[]'::jsonb) into v_result
  from public.gym_documents d
  left join public.gym_document_versions cv on cv.id=d.current_version_id
  left join public.gym_document_versions dv on dv.document_id=d.id and dv.status='draft'
  where d.gym_id=v_gym_id;
  return v_result;
end;
$function$;

create or replace function public.list_effective_published_gym_documents()
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $function$
declare v_gym_id uuid := public.effective_gym_id(); v_result jsonb;
begin
  if v_gym_id is null or not public.documents_actor_is_active() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'documentId',d.id,'versionId',v.id,'title',v.title_snapshot,
    'body',v.body,'versionNumber',v.version_number,
    'acceptanceMode',v.acceptance_mode,'contentSha256',v.content_sha256,
    'publishedAt',v.published_at,'acceptedAt',current_a.accepted_at,
    'acceptedVersionNumber',previous_a.version_number,
    'previousAcceptedAt',previous_a.accepted_at
  ) order by v.acceptance_mode desc,v.title_snapshot),'[]'::jsonb) into v_result
  from public.gym_documents d
  join public.gym_document_versions v on v.id=d.current_version_id and v.status='published'
  left join public.gym_document_acceptances current_a
    on current_a.version_id=v.id and current_a.user_id=auth.uid()
  left join lateral (
    select pv.version_number,a.accepted_at from public.gym_document_acceptances a
    join public.gym_document_versions pv on pv.id=a.version_id
    where a.document_id=d.id and a.user_id=auth.uid() and a.version_id<>v.id
    order by pv.version_number desc limit 1
  ) previous_a on true
  where d.gym_id=v_gym_id and d.status='active';
  return v_result;
end;
$function$;

create or replace function public.get_effective_member_document_status(p_member_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $function$
declare v_gym_id uuid := public.effective_gym_id(); v_result jsonb;
begin
  if v_gym_id is null or not public.documents_actor_can_manage() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  if not exists(select 1 from public.gym_members gm where gm.gym_id=v_gym_id
    and gm.user_id=p_member_id and gm.is_active) then
    raise exception 'member_not_found' using errcode='P0001';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'documentId',d.id,'versionId',v.id,'title',v.title_snapshot,
    'versionNumber',v.version_number,'acceptanceMode',v.acceptance_mode,
    'publishedAt',v.published_at,'acceptedAt',current_a.accepted_at,
    'acceptedVersionNumber',previous_a.version_number,
    'previousAcceptedAt',previous_a.accepted_at
  ) order by v.acceptance_mode desc,v.title_snapshot),'[]'::jsonb) into v_result
  from public.gym_documents d
  join public.gym_document_versions v on v.id=d.current_version_id and v.status='published'
  left join public.gym_document_acceptances current_a
    on current_a.version_id=v.id and current_a.user_id=p_member_id
  left join lateral (
    select pv.version_number,a.accepted_at from public.gym_document_acceptances a
    join public.gym_document_versions pv on pv.id=a.version_id
    where a.document_id=d.id and a.user_id=p_member_id and a.version_id<>v.id
    order by pv.version_number desc limit 1
  ) previous_a on true
  where d.gym_id=v_gym_id and d.status='active';
  return v_result;
end;
$function$;

create or replace function public.accept_effective_gym_document_version(p_version_id uuid)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id(); v_acceptance_id uuid;
begin
  if v_gym_id is null or not public.documents_actor_is_active()
    or not exists(select 1 from public.gym_members gm where gm.gym_id=v_gym_id
      and gm.user_id=auth.uid() and gm.is_active) then
    raise exception 'forbidden' using errcode='42501';
  end if;
  perform public.lock_effective_gym_documents(v_gym_id);
  insert into public.gym_document_acceptances(
    gym_id,document_id,version_id,user_id,source
  ) select v_gym_id,d.id,v.id,auth.uid(),'profile'
  from public.gym_documents d join public.gym_document_versions v
    on v.id=d.current_version_id
  where d.gym_id=v_gym_id and d.status='active' and v.id=p_version_id
    and v.status='published' and v.acceptance_mode='required'
  on conflict (user_id,version_id) do nothing
  returning id into v_acceptance_id;
  if v_acceptance_id is null then
    select id into v_acceptance_id from public.gym_document_acceptances
    where user_id=auth.uid() and version_id=p_version_id;
  end if;
  if v_acceptance_id is null then
    raise exception 'documents_changed' using errcode='P0001';
  end if;
  return v_acceptance_id;
end;
$function$;

create or replace function public.accept_membership_checkout_document_snapshot(
  p_plan_id uuid,
  p_document_ids uuid[],
  p_gym_document_version_ids uuid[]
)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id(); v_user_id uuid:=auth.uid();
  v_required_ids uuid[]; v_submitted uuid[]; v_existing_request_id uuid;
begin
  if v_gym_id is null or v_user_id is null or not public.documents_actor_is_active() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  if not exists(select 1 from public.membership_plans where id=p_plan_id
    and gym_id=v_gym_id and is_active) then
    raise exception 'plan_not_found' using errcode='P0001';
  end if;
  perform public.lock_effective_gym_documents(v_gym_id);

  -- A pending card request is already a legally snapshotted operation. A later
  -- publication must not invalidate its Stripe retry/session reuse path.
  select mr.id into v_existing_request_id
  from public.membership_requests mr
  where mr.user_id=v_user_id and mr.gym_id=v_gym_id and mr.plan_id=p_plan_id
    and mr.payment_method='card' and mr.status='pending'
  order by mr.created_at desc limit 1;
  if v_existing_request_id is not null then
    return jsonb_build_object(
      'status','existing_operation',
      'requestId',v_existing_request_id,
      'gymVersionIds',coalesce((select jsonb_agg(a.version_id order by a.version_id)
        from public.membership_request_gym_document_acceptances l
        join public.gym_document_acceptances a on a.id=l.acceptance_id
        where l.request_id=v_existing_request_id),'[]'::jsonb)
    );
  end if;

  perform public.accept_membership_checkout_documents(p_plan_id,p_document_ids);

  select coalesce(array_agg(v.id order by v.id),'{}'::uuid[]) into v_required_ids
  from public.gym_documents d join public.gym_document_versions v on v.id=d.current_version_id
  where d.gym_id=v_gym_id and d.status='active' and v.status='published'
    and v.acceptance_mode='required';
  select coalesce(array_agg(distinct x order by x),'{}'::uuid[]) into v_submitted
  from unnest(coalesce(p_gym_document_version_ids,'{}'::uuid[])) x;
  if exists(select 1 from unnest(v_submitted) x where not (x=any(v_required_ids))) then
    raise exception 'documents_changed' using errcode='P0001';
  end if;
  insert into public.gym_document_acceptances(
    gym_id,document_id,version_id,user_id,source
  ) select v_gym_id,d.id,v.id,v_user_id,'checkout'
  from public.gym_documents d join public.gym_document_versions v on v.id=d.current_version_id
  where d.gym_id=v_gym_id and d.status='active' and v.status='published'
    and v.acceptance_mode='required' and v.id=any(v_submitted)
  on conflict (user_id,version_id) do nothing;
  if exists(select 1 from unnest(v_required_ids) x where not exists(
    select 1 from public.gym_document_acceptances a
    where a.user_id=v_user_id and a.gym_id=v_gym_id and a.version_id=x
  )) then
    raise exception 'documents_changed' using errcode='P0001';
  end if;
  return jsonb_build_object('status','accepted','gymVersionIds',v_required_ids);
end;
$function$;

-- Preserve legacy legal tables while making an existing acceptance reusable.
create or replace function public.accept_membership_checkout_documents(
  p_plan_id uuid, p_document_ids uuid[]
)
returns integer
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare v_user_id uuid:=auth.uid(); v_gym_id uuid:=public.effective_gym_id(); v_count integer;
begin
  if v_user_id is null or v_gym_id is null or not public.membership_actor_is_active() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  if not exists(select 1 from public.membership_plans where id=p_plan_id
    and gym_id=v_gym_id and is_active) then
    raise exception 'plan_not_found' using errcode='P0001';
  end if;
  if exists(select 1 from public.membership_legal_documents d
    where d.is_active and d.is_required and (d.gym_id is null or d.gym_id=v_gym_id)
      and not (d.id=any(coalesce(p_document_ids,'{}'::uuid[])))
      and not exists(select 1 from public.membership_legal_acceptances a
        where a.user_id=v_user_id and a.gym_id=v_gym_id and a.plan_id=p_plan_id
          and a.document_id=d.id and a.document_version=d.version)) then
    raise exception 'required_consent_missing' using errcode='P0001';
  end if;
  insert into public.membership_legal_acceptances(
    user_id,gym_id,plan_id,document_id,document_type,
    document_version,document_url,accepted_at
  ) select v_user_id,v_gym_id,p_plan_id,d.id,d.document_type,d.version,d.url,clock_timestamp()
  from public.membership_legal_documents d
  where d.id=any(coalesce(p_document_ids,'{}'::uuid[])) and d.is_active and d.is_required
    and d.document_type in ('terms','waiver','sales_refund')
    and (d.gym_id is null or d.gym_id=v_gym_id)
  on conflict (user_id,gym_id,plan_id,document_id,document_version) do nothing;
  get diagnostics v_count=row_count;
  return v_count;
end;
$function$;

-- Add gym documents and existing acceptance state to the proven checkout context.
create or replace function public.get_membership_checkout_context(p_plan_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $function$
declare v_user_id uuid:=auth.uid(); v_gym_id uuid:=public.effective_gym_id();
  v_plan public.membership_plans%rowtype; v_gym public.gyms%rowtype;
begin
  if v_user_id is null or v_gym_id is null or not public.membership_actor_is_active() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  select * into v_plan from public.membership_plans
  where id=p_plan_id and gym_id=v_gym_id and is_active;
  if not found then raise exception 'plan_not_found' using errcode='P0001'; end if;
  select * into v_gym from public.gyms where id=v_gym_id;
  return jsonb_build_object(
    'gym',jsonb_build_object('id',v_gym.id,'name',v_gym.name,
      'businessName',v_gym.business_name,'address',v_gym.address,
      'email',v_gym.email,'phone',v_gym.phone,'website',v_gym.website),
    'plan',jsonb_build_object('id',v_plan.id,'name',v_plan.name,
      'planType',v_plan.plan_type,'credits',v_plan.credits,
      'durationDays',v_plan.duration_days,'price',v_plan.price,'currency',v_plan.currency),
    'documents',coalesce((select jsonb_agg(jsonb_build_object(
      'id',d.id,'type',d.document_type,'version',d.version,'url',d.url,
      'required',d.is_required,'accepted',exists(select 1
        from public.membership_legal_acceptances a where a.user_id=v_user_id
          and a.gym_id=v_gym_id and a.plan_id=p_plan_id and a.document_id=d.id
          and a.document_version=d.version)) order by d.is_required desc,d.document_type)
      from public.membership_legal_documents d where d.is_active
        and (d.gym_id is null or d.gym_id=v_gym_id)),'[]'::jsonb),
    'gymDocuments',coalesce((select jsonb_agg(jsonb_build_object(
      'documentId',d.id,'versionId',v.id,'title',v.title_snapshot,'body',v.body,
      'versionNumber',v.version_number,'acceptanceMode',v.acceptance_mode,
      'contentSha256',v.content_sha256,'publishedAt',v.published_at,
      'accepted',exists(select 1 from public.gym_document_acceptances a
        where a.user_id=v_user_id and a.gym_id=v_gym_id and a.version_id=v.id))
      order by v.acceptance_mode desc,v.title_snapshot)
      from public.gym_documents d join public.gym_document_versions v on v.id=d.current_version_id
      where d.gym_id=v_gym_id and d.status='active' and v.status='published'),'[]'::jsonb)
  );
end;
$function$;

-- Every new cash/card request is checked under the same lock used by publish.
-- Existing pending requests are not revalidated: they retain their legal snapshot.
create or replace function public.validate_membership_request_document_snapshot()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $function$
begin
  if new.payment_method not in ('cash','card') or new.status<>'pending' then
    return new;
  end if;
  perform public.lock_effective_gym_documents(new.gym_id);
  if exists(select 1 from public.membership_legal_documents d
    where d.is_active and d.is_required and (d.gym_id is null or d.gym_id=new.gym_id)
      and not exists(select 1 from public.membership_legal_acceptances a
        where a.user_id=new.user_id and a.gym_id=new.gym_id and a.plan_id=new.plan_id
          and a.document_id=d.id and a.document_version=d.version)) then
    raise exception 'required_consent_missing' using errcode='P0001';
  end if;
  if exists(select 1 from public.gym_documents d
    join public.gym_document_versions v on v.id=d.current_version_id
    where d.gym_id=new.gym_id and d.status='active' and v.status='published'
      and v.acceptance_mode='required' and not exists(select 1
        from public.gym_document_acceptances a where a.user_id=new.user_id
          and a.gym_id=new.gym_id and a.version_id=v.id)) then
    raise exception 'documents_changed' using errcode='P0001';
  end if;
  return new;
end;
$function$;
create trigger validate_membership_request_document_snapshot_trigger
before insert on public.membership_requests
for each row execute function public.validate_membership_request_document_snapshot();

create or replace function public.link_membership_request_gym_document_snapshot()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $function$
begin
  if new.payment_method in ('cash','card') and new.status='pending' then
    insert into public.membership_request_gym_document_acceptances(request_id,acceptance_id)
    select new.id,a.id from public.gym_documents d
    join public.gym_document_versions v on v.id=d.current_version_id
    join public.gym_document_acceptances a on a.version_id=v.id
      and a.user_id=new.user_id and a.gym_id=new.gym_id
    where d.gym_id=new.gym_id and d.status='active' and v.status='published'
      and v.acceptance_mode='required'
    on conflict do nothing;
  end if;
  return new;
end;
$function$;
create trigger membership_requests_link_gym_document_snapshot
after insert on public.membership_requests
for each row execute function public.link_membership_request_gym_document_snapshot();

create or replace function public.create_consented_cash_membership_request(
  p_plan_id uuid, p_document_ids uuid[], p_gym_document_version_ids uuid[]
)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare v_request_id uuid;
begin
  perform public.accept_membership_checkout_document_snapshot(
    p_plan_id,p_document_ids,p_gym_document_version_ids
  );
  v_request_id:=public.create_cash_membership_request(p_plan_id);
  return v_request_id;
end;
$function$;

revoke all on table public.gym_documents from anon,authenticated;
revoke all on table public.gym_document_versions from anon,authenticated;
revoke all on table public.gym_document_acceptances from anon,authenticated;
revoke all on table public.membership_request_gym_document_acceptances from anon,authenticated;
grant select on table public.gym_documents to authenticated;
grant select on table public.gym_document_versions to authenticated;
grant select on table public.gym_document_acceptances to authenticated;
grant select on table public.membership_request_gym_document_acceptances to authenticated;

revoke all on function public.documents_actor_can_manage() from public,anon,authenticated,service_role;
revoke all on function public.documents_actor_is_active() from public,anon,authenticated,service_role;
revoke all on function public.lock_effective_gym_documents(uuid) from public,anon,authenticated,service_role;
revoke all on function public.canonical_gym_document_hash(integer,text,text,text) from public,anon,authenticated,service_role;
revoke all on function public.protect_gym_document_version() from public;
revoke all on function public.protect_gym_document_acceptance() from public;
revoke all on function public.protect_published_gym_document() from public;
revoke all on function public.validate_membership_request_document_snapshot() from public;
revoke all on function public.link_membership_request_gym_document_snapshot() from public;

grant execute on function public.documents_actor_can_manage() to authenticated,service_role;
grant execute on function public.documents_actor_is_active() to authenticated,service_role;

do $grants$
declare v_signature text;
begin
  foreach v_signature in array array[
    'create_effective_gym_document(text,text,text)',
    'update_effective_gym_document_draft(uuid,text,text,text)',
    'create_effective_gym_document_version(uuid)',
    'publish_effective_gym_document_version(uuid)',
    'delete_effective_gym_document_draft(uuid)',
    'archive_effective_gym_document(uuid)',
    'list_effective_gym_documents_admin()',
    'list_effective_published_gym_documents()',
    'get_effective_member_document_status(uuid)',
    'accept_effective_gym_document_version(uuid)',
    'accept_membership_checkout_document_snapshot(uuid,uuid[],uuid[])',
    'create_consented_cash_membership_request(uuid,uuid[],uuid[])'
  ] loop
    execute format('revoke all on function public.%s from public,anon,authenticated,service_role',v_signature);
    execute format('grant execute on function public.%s to authenticated,service_role',v_signature);
  end loop;
end;
$grants$;

comment on table public.gym_document_versions is
  'Drafts are editable; published text, metadata and server SHA-256 are immutable. Author UUIDs are retained after account deletion.';
comment on table public.gym_document_acceptances is
  'Immutable acceptance evidence. user_id is retained as an audit UUID after account deletion.';
comment on table public.membership_request_gym_document_acceptances is
  'Immutable legal snapshot links retained independently of membership request deletion.';

commit;
