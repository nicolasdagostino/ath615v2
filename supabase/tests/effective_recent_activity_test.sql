begin;

do $$
begin
  if to_regprocedure('public.list_effective_recent_activity(integer)') is null then
    raise exception 'list_effective_recent_activity(integer) is missing';
  end if;
  if has_function_privilege('anon', 'public.list_effective_recent_activity(integer)', 'EXECUTE') then
    raise exception 'anon must not execute list_effective_recent_activity';
  end if;
  if not has_function_privilege('authenticated', 'public.list_effective_recent_activity(integer)', 'EXECUTE') then
    raise exception 'authenticated role must have the scoped RPC grant';
  end if;
  if pg_get_functiondef('public.list_effective_recent_activity(integer)'::regprocedure)
      not like '%membership_actor_can_manage()%' then
    raise exception 'recent activity must use the existing administrative authority helper';
  end if;
end;
$$;

rollback;
