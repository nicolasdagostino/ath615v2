begin;

do $$
declare
  gym_a uuid := 'd1000000-0000-0000-0000-000000000001';
  gym_b uuid := 'd1000000-0000-0000-0000-000000000002';
  owner_a uuid := 'd2000000-0000-0000-0000-000000000001';
  admin_a uuid := 'd2000000-0000-0000-0000-000000000002';
  athlete_a uuid := 'd2000000-0000-0000-0000-000000000003';
  coach_a uuid := 'd2000000-0000-0000-0000-000000000004';
  admin_b uuid := 'd2000000-0000-0000-0000-000000000005';
  inactive_admin uuid := 'd2000000-0000-0000-0000-000000000006';
begin
  insert into auth.users(id,email,raw_user_meta_data) values
    (owner_a,'documents-owner@example.test','{}'),
    (admin_a,'documents-admin@example.test','{}'),
    (athlete_a,'documents-athlete@example.test','{}'),
    (coach_a,'documents-coach@example.test','{}'),
    (admin_b,'documents-admin-b@example.test','{}'),
    (inactive_admin,'documents-inactive-admin@example.test','{}');
  insert into public.gyms(id,name,owner_id) values
    (gym_a,'Documents Gym A',owner_a),(gym_b,'Documents Gym B',admin_b);
  update public.gyms set stripe_account_id='acct_documents_a',
    stripe_onboarding_complete=true,stripe_charges_enabled=true,
    stripe_payouts_enabled=true where id=gym_a;
  update public.profiles set gym_id=gym_a,is_active=true,
    role=case id when owner_a then 'owner' when admin_a then 'admin'
      when coach_a then 'coach' else 'athlete' end,
    is_coach=id=coach_a where id in(owner_a,admin_a,athlete_a,coach_a);
  update public.profiles set gym_id=gym_b,is_active=true,role='admin' where id=admin_b;
  update public.profiles set gym_id=gym_a,is_active=false,role='admin' where id=inactive_admin;
  insert into public.gym_members(gym_id,user_id,role,is_active,is_coach,joined_at) values
    (gym_a,owner_a,'admin',true,false,now()),(gym_a,admin_a,'admin',true,false,now()),
    (gym_a,athlete_a,'athlete',true,false,now()),(gym_a,coach_a,'coach',true,true,now()),
    (gym_b,admin_b,'admin',true,false,now()),
    (gym_a,inactive_admin,'admin',false,false,now());
  insert into public.membership_plans(id,gym_id,name,plan_type,credits,price,currency,duration_days,is_active)
  values('d3000000-0000-0000-0000-000000000001',gym_a,'Documents Pack','class_pack',5,35,'EUR',30,true);
  insert into public.membership_plans(id,gym_id,name,plan_type,credits,price,currency,duration_days,is_active)
  values('d3000000-0000-0000-0000-000000000002',gym_a,'Documents Pack 2','class_pack',5,40,'EUR',30,true);
end $$;

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);

-- Admin creates, edits and publishes an immutable deterministic version.
select set_config('request.jwt.claim.sub','d2000000-0000-0000-0000-000000000002',true);
do $$
declare v1 uuid; h1 text; h2 text; doc uuid;
begin
  v1:=public.create_effective_gym_document(' Waiver ',' Body ','required');
  perform public.update_effective_gym_document_draft(v1,'Waiver','Body','required');
  h1:=public.publish_effective_gym_document_version(v1);
  select document_id into doc from public.gym_document_versions where id=v1;
  h2:=encode(extensions.digest(
    convert_to('1'||E'\n'||'Waiver'||E'\n'||'Body'||E'\n'||'required','UTF8'),
    'sha256'
  ),'hex');
  if h1<>h2 or (select current_version_id from public.gym_documents where id=doc)<>v1 then
    raise exception 'publish/hash/current version failed';
  end if;
  begin
    perform public.update_effective_gym_document_draft(v1,'Changed','Changed','required');
    raise exception 'published version was editable';
  exception when sqlstate 'P0001' then null; end;
  begin delete from public.gym_document_versions where id=v1;
    raise exception 'published version was deletable';
  exception when others then null; end;
end $$;

-- Informational drafts are never accepted and unpublished drafts are deletable.
do $$ declare info uuid; begin
  info:=public.create_effective_gym_document('Information','Read only','informational');
  perform public.delete_effective_gym_document_draft(info);
  if exists(select 1 from public.gym_document_versions where id=info) then
    raise exception 'draft was not deleted'; end if;
end $$;

-- Coach/athlete cannot administer; other-gym admin cannot access Gym A documents.
select set_config('request.jwt.claim.sub','d2000000-0000-0000-0000-000000000004',true);
do $$ begin
  if jsonb_array_length(public.list_effective_published_gym_documents())<>1 then
    raise exception 'active coach could not read published document'; end if;
  begin perform public.create_effective_gym_document('No','No','required');
    raise exception 'coach administered documents'; exception when insufficient_privilege then null; end;
  begin perform public.get_effective_member_document_status('d2000000-0000-0000-0000-000000000003');
    raise exception 'coach read another member acceptance status'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','d2000000-0000-0000-0000-000000000003',true);
do $$ begin
  begin perform public.create_effective_gym_document('No','No','required');
    raise exception 'athlete administered documents'; exception when insufficient_privilege then null; end;
  begin perform public.get_effective_member_document_status(auth.uid());
    raise exception 'athlete read administrative acceptance status'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','d2000000-0000-0000-0000-000000000006',true);
do $$ begin
  begin perform public.create_effective_gym_document('No','No','required');
    raise exception 'inactive admin administered documents'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','d2000000-0000-0000-0000-000000000005',true);
do $$ begin
  if jsonb_array_length(public.list_effective_gym_documents_admin())<>0 then
    raise exception 'cross gym document leak'; end if;
  begin
    perform public.accept_effective_gym_document_version(
      (select id from public.gym_document_versions where title_snapshot='Waiver')
    );
    raise exception 'cross gym acceptance succeeded';
  exception when sqlstate 'P0001' then null; end;
end $$;

-- Acceptance is unique/idempotent and accepted_at remains immutable.
select set_config('request.jwt.claim.sub','d2000000-0000-0000-0000-000000000003',true);
do $$
declare v1 uuid; a1 uuid; t1 timestamptz; t2 timestamptz;
begin
  select current_version_id into v1 from public.gym_documents where gym_id='d1000000-0000-0000-0000-000000000001';
  a1:=public.accept_effective_gym_document_version(v1);
  select accepted_at into t1 from public.gym_document_acceptances where id=a1;
  perform pg_sleep(0.01);
  if public.accept_effective_gym_document_version(v1)<>a1 then raise exception 'accept retry duplicated'; end if;
  select accepted_at into t2 from public.gym_document_acceptances where id=a1;
  if t1<>t2 then raise exception 'accepted_at changed on retry'; end if;
end $$;

-- Snapshot race: v2 before operation rejects v1; v2 accepted creates one fixed link.
select set_config('request.jwt.claim.sub','d2000000-0000-0000-0000-000000000002',true);
do $$ declare doc uuid; v2 uuid; begin
  select id into doc from public.gym_documents where gym_id='d1000000-0000-0000-0000-000000000001';
  v2:=public.create_effective_gym_document_version(doc);
  perform public.update_effective_gym_document_draft(v2,'Waiver v2','Body v2','required');
  perform public.publish_effective_gym_document_version(v2);
end $$;
select set_config('request.jwt.claim.sub','d2000000-0000-0000-0000-000000000003',true);
do $$ declare terms uuid; v1 uuid; before_count integer; begin
  select id into terms from public.membership_legal_documents where document_type='terms' and gym_id is null and is_active;
  select id into v1 from public.gym_document_versions where version_number=1 and document_id in
    (select id from public.gym_documents where gym_id='d1000000-0000-0000-0000-000000000001');
  select count(*) into before_count from public.membership_requests;
  begin
    perform public.create_consented_cash_membership_request(
      'd3000000-0000-0000-0000-000000000001',array[terms],array[v1]);
    raise exception 'stale v1 created request';
  exception when sqlstate 'P0001' then
    if sqlerrm<>'documents_changed' then raise; end if;
  end;
  if (select count(*) from public.membership_requests)<>before_count then
    raise exception 'failed snapshot left request'; end if;
end $$;
do $$ declare terms uuid; v2 uuid; req uuid; accepted_at_before timestamptz; prepared record; begin
  select id into terms from public.membership_legal_documents where document_type='terms' and gym_id is null and is_active;
  select current_version_id into v2 from public.gym_documents where gym_id='d1000000-0000-0000-0000-000000000001';
  perform public.accept_membership_checkout_document_snapshot(
    'd3000000-0000-0000-0000-000000000001',array[terms],array[v2]);
  select * into prepared from public.prepare_card_membership_checkout(
    'd3000000-0000-0000-0000-000000000001');
  req:=prepared.request_id;
  select a.accepted_at into accepted_at_before from public.membership_request_gym_document_acceptances l
    join public.gym_document_acceptances a on a.id=l.acceptance_id where l.request_id=req;
  if not exists(select 1 from public.membership_request_gym_document_acceptances l
    join public.gym_document_acceptances a on a.id=l.acceptance_id where l.request_id=req and a.version_id=v2)
  then raise exception 'request lacks v2 snapshot'; end if;
end $$;

-- Publishing v3 after the request preserves v2; a later operation requires v3.
select set_config('request.jwt.claim.sub','d2000000-0000-0000-0000-000000000002',true);
do $$ declare doc uuid; v3 uuid; begin
  select id into doc from public.gym_documents where gym_id='d1000000-0000-0000-0000-000000000001';
  v3:=public.create_effective_gym_document_version(doc);
  perform public.update_effective_gym_document_draft(v3,'Waiver v3','Body v3','required');
  perform public.publish_effective_gym_document_version(v3);
  if exists(select 1 from public.membership_request_gym_document_acceptances l
    join public.gym_document_acceptances a on a.id=l.acceptance_id where a.version_id=v3)
  then raise exception 'existing request changed silently to v3'; end if;
end $$;

select set_config('request.jwt.claim.sub','d2000000-0000-0000-0000-000000000003',true);
do $$ declare terms uuid; v2 uuid; v3 uuid; req uuid; retry_result jsonb; existing_request uuid; begin
  select id into terms from public.membership_legal_documents where document_type='terms' and gym_id is null and is_active;
  select id into v2 from public.gym_document_versions where version_number=2 and document_id in
    (select id from public.gym_documents where gym_id='d1000000-0000-0000-0000-000000000001');
  select current_version_id into v3 from public.gym_documents where gym_id='d1000000-0000-0000-0000-000000000001';
  select id into existing_request from public.membership_requests
    where plan_id='d3000000-0000-0000-0000-000000000001' and payment_method='card';
  retry_result:=public.accept_membership_checkout_document_snapshot(
    'd3000000-0000-0000-0000-000000000001',array[terms],array[v2]);
  if retry_result->>'status'<>'existing_operation'
    or (retry_result->>'requestId')::uuid<>existing_request then
    raise exception 'existing card operation was invalidated by v3'; end if;
  if not exists(select 1 from public.membership_request_gym_document_acceptances l
    join public.gym_document_acceptances a on a.id=l.acceptance_id
    where l.request_id=existing_request and a.version_id=v2) then
    raise exception 'existing card snapshot no longer points to v2'; end if;
  if exists(select 1 from public.membership_request_gym_document_acceptances l
    join public.gym_document_acceptances a on a.id=l.acceptance_id
    where l.request_id=existing_request and a.version_id=v3) then
    raise exception 'existing card snapshot changed silently to v3'; end if;
  begin
    perform public.create_consented_cash_membership_request(
      'd3000000-0000-0000-0000-000000000002',array[terms],array[v2]);
    raise exception 'new operation accepted superseded v2';
  exception when sqlstate 'P0001' then
    if sqlerrm<>'documents_changed' then raise; end if;
  end;
  req:=public.create_consented_cash_membership_request(
    'd3000000-0000-0000-0000-000000000002',array[terms],array[v3]);
  if not exists(select 1 from public.membership_request_gym_document_acceptances l
    join public.gym_document_acceptances a on a.id=l.acceptance_id
    where l.request_id=req and a.version_id=v3) then
    raise exception 'new operation did not snapshot v3'; end if;
  begin
    update public.gym_document_acceptances set accepted_at=clock_timestamp()
    where version_id=v2 and user_id=auth.uid();
    raise exception 'accepted_at was mutable';
  exception when insufficient_privilege then null; end;
end $$;

-- Owner can administer; archive preserves versions and acceptances.
select set_config('request.jwt.claim.sub','d2000000-0000-0000-0000-000000000001',true);
do $$ declare doc uuid; versions_before integer; acceptances_before integer; begin
  if jsonb_array_length(public.get_effective_member_document_status(
    'd2000000-0000-0000-0000-000000000003'))<>1 then
    raise exception 'owner could not read member document status'; end if;
  select id into doc from public.gym_documents where gym_id='d1000000-0000-0000-0000-000000000001';
  select count(*) into versions_before from public.gym_document_versions where document_id=doc;
  select count(*) into acceptances_before from public.gym_document_acceptances where document_id=doc;
  perform public.archive_effective_gym_document(doc);
  if (select count(*) from public.gym_document_versions where document_id=doc)<>versions_before
    or (select count(*) from public.gym_document_acceptances where document_id=doc)<>acceptances_before
  then raise exception 'archive destroyed history'; end if;
end $$;

-- Established account deletion succeeds while immutable legal evidence remains.
select set_config('request.jwt.claim.sub','d2000000-0000-0000-0000-000000000003',true);
do $$ begin perform public.delete_current_user_data(); end $$;
set local role postgres;
do $$ begin
  if exists(select 1 from public.profiles where id='d2000000-0000-0000-0000-000000000003') then
    raise exception 'account deletion did not complete'; end if;
  if not exists(select 1 from public.gym_document_acceptances
    where user_id='d2000000-0000-0000-0000-000000000003') then
    raise exception 'account deletion destroyed legal acceptances'; end if;
  if not exists(select 1 from public.membership_request_gym_document_acceptances) then
    raise exception 'account deletion destroyed request legal snapshot'; end if;
end $$;

rollback;
