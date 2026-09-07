begin;
select plan(1);
do $$
declare owner_id uuid:='fa100000-0000-0000-0000-000000000001'; user_id uuid:='fa100000-0000-0000-0000-000000000002'; sid uuid; cid uuid; did uuid; inbox jsonb;
begin
 insert into auth.users(id,email) values(owner_id,'help-owner@test.invalid'),(user_id,'help-user@test.invalid');
 update profiles set role=case when id=owner_id then 'owner' else 'athlete' end,is_active=true where id in(owner_id,user_id);
 perform set_config('request.jwt.claim.role','anon',true);perform set_config('request.jwt.claim.sub','',true);
 sid:=submit_public_support_request('Test Person','support@test.invalid',null,'booking','Booking','A booking failed safely','2.0.2','132','ios','iOS test','es-ES');
 cid:=submit_public_contact_request('Test Person','contact@test.invalid',null,'Question','A sufficiently long question','xx');
 did:=submit_public_demo_request('Demo Person','owner-demo@test.invalid',null,'Demo Gym',20,null,'en');
 if has_table_privilege('anon','public.public_support_requests','select') or has_table_privilege('anon','public.public_contact_requests','update')
  or has_table_privilege('anon','public.public_support_requests','delete') then raise exception 'anon table access';end if;
 begin perform submit_public_support_request('x','bad',null,'bad',null,'short',null,null,null,null,'en');raise exception 'invalid support accepted';exception when others then if sqlerrm='invalid support accepted' then raise;end if;end;
 perform set_config('request.jwt.claim.role','authenticated',true);perform set_config('request.jwt.claim.sub',user_id::text,true);
 begin perform get_platform_owner_requests('all');raise exception 'normal user inbox';exception when sqlstate '42501' then null;end;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 inbox:=get_platform_owner_requests('all');
 if (inbox->'counts'->>'demo')::int<1 or (inbox->'counts'->>'support')::int<1 or (inbox->'counts'->>'other')::int<1 then raise exception 'bad counts';end if;
 perform update_platform_owner_request('demo',did,'contacted','Called lead');
 perform update_platform_owner_request('support',sid,'resolved','Fixed');
 perform update_platform_owner_request('other',cid,'closed','Answered');
 if get_platform_owner_request('demo',did)->>'status'<>'contacted' then raise exception 'demo workflow failed';end if;
 if not exists(select 1 from storage.buckets where id='support-attachments' and not public and file_size_limit=5242880) then raise exception 'private bucket missing';end if;
 insert into storage.objects(bucket_id,name) values('support-attachments',sid::text||'/owner-only.png');
 update public_support_requests set attachment_path=sid::text||'/owner-only.png' where id=sid;
 if not authorize_platform_owner_support_attachment(sid::text||'/owner-only.png') then raise exception 'owner attachment authorization denied';end if;
 if has_table_privilege('authenticated','public.public_support_requests','select') then raise exception 'table leakage';end if;
 if jsonb_array_length(get_platform_owner_requests('new')->'items')<>0 then raise exception 'filter failed';end if;
 if (select count(*) from get_public_saas_plan_catalog())<>5 then raise exception 'catalog incorrect';end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','fa100000-0000-0000-0000-000000000002',true);
do $$ begin
 if exists(select 1 from storage.objects where bucket_id='support-attachments') then raise exception 'normal user attachment leakage';end if;
 begin perform authorize_platform_owner_support_attachment('anything');raise exception 'normal user attachment authorization';exception when sqlstate '42501' then null;end;
 begin insert into storage.objects(bucket_id,name) values('support-attachments','forbidden.png');raise exception 'authenticated attachment upload';exception when insufficient_privilege then null;end;
end $$;
reset role;
set local role anon;
do $$ begin
 if exists(select 1 from storage.objects where bucket_id='support-attachments') then raise exception 'anon attachment leakage';end if;
 begin insert into storage.objects(bucket_id,name) values('support-attachments','anon.png');raise exception 'anon attachment upload';exception when insufficient_privilege then null;end;
end $$;
reset role;
select pass('Help Center V2 submissions, workflows, catalog and Owner isolation hold');
select * from finish();
rollback;
