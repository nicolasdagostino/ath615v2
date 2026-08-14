-- Delete the current user's application data atomically.
-- Auth and Storage deletion remain Edge Function phases because they are
-- external to the PostgreSQL transaction.

do $prerequisite$
declare
  v_table text;
begin
  foreach v_table in array array[
    'profiles',
    'device_tokens',
    'notifications',
    'workout_likes',
    'workout_comments',
    'class_waitlist',
    'class_bookings',
    'membership_credit_logs',
    'member_memberships',
    'membership_requests',
    'gym_join_requests',
    'personal_records'
  ]
  loop
    if to_regclass('public.' || v_table) is null then
      raise exception 'deployment_prerequisite_missing: public.%', v_table;
    end if;
  end loop;
end;
$prerequisite$;
create or replace function public.delete_current_user_data()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_profile public.profiles%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode = 'P0001', message = 'unauthenticated';
  end if;

  select *
  into v_profile
  from public.profiles
  where id = v_user_id
  for update;

  -- A retry after the database phase is intentionally successful.
  if not found then
    return jsonb_build_object('status', 'success');
  end if;

  if v_profile.role = 'owner' then
    raise exception using errcode = 'P0001', message = 'owner_not_allowed';
  end if;

  delete from public.device_tokens where user_id = v_user_id;
  delete from public.notifications where user_id = v_user_id;
  delete from public.workout_likes where user_id = v_user_id;
  delete from public.workout_comments where user_id = v_user_id;
  delete from public.class_waitlist where user_id = v_user_id;
  delete from public.class_bookings where user_id = v_user_id;
  delete from public.membership_credit_logs where user_id = v_user_id;
  delete from public.member_memberships where user_id = v_user_id;
  delete from public.membership_requests where user_id = v_user_id;
  delete from public.gym_join_requests where user_id = v_user_id;
  delete from public.personal_records where user_id = v_user_id;
  delete from public.profiles where id = v_user_id;

  return jsonb_build_object('status', 'success');
end;
$function$;
revoke all on function public.delete_current_user_data() from public;
revoke all on function public.delete_current_user_data() from anon;
revoke all on function public.delete_current_user_data() from authenticated;
grant execute on function public.delete_current_user_data()
  to authenticated;
