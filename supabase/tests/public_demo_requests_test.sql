begin;

set local role anon;
select public.submit_public_demo_request(
  '  Demo Person  ', 'DEMO@EXAMPLE.COM', null, ' Demo Gym ', 120,
  'Please contact me.', 'es-ES'
);

do $$ begin
  begin perform public.submit_public_demo_request('', 'bad', null, '', -1, repeat('x', 1001), 'xx');
    raise exception 'invalid payload accepted';
  exception when others then
    if sqlerrm = 'invalid payload accepted' then raise; end if;
  end;
  begin perform * from public.public_demo_requests;
    raise exception 'anon select allowed';
  exception when insufficient_privilege then null; end;
  begin update public.public_demo_requests set status='new';
    raise exception 'anon update allowed';
  exception when insufficient_privilege then null; end;
  begin delete from public.public_demo_requests;
    raise exception 'anon delete allowed';
  exception when insufficient_privilege then null; end;
end $$;

reset role;
do $$ begin
  if not exists (
    select 1 from public.public_demo_requests
    where full_name='Demo Person' and email='demo@example.com'
      and gym_name='Demo Gym' and locale='es' and status='new'
  ) then raise exception 'normalized request missing'; end if;
end $$;

do $$ begin
  if has_table_privilege('authenticated', 'public.public_demo_requests', 'select')
    or has_table_privilege('authenticated', 'public.public_demo_requests', 'insert')
    or has_table_privilege('authenticated', 'public.public_demo_requests', 'update')
    or has_table_privilege('authenticated', 'public.public_demo_requests', 'delete')
  then raise exception 'authenticated table access allowed'; end if;
  if has_function_privilege(
    'authenticated',
    'public.submit_public_demo_request(text,text,text,text,integer,text,text)',
    'execute'
  ) then raise exception 'authenticated RPC allowed'; end if;
end $$;

rollback;
