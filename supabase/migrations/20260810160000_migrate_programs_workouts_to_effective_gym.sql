-- Vertical 3E: Programs, Workouts, Explore and interactions use one effective gym.
-- Registered Web sessions are session-scoped; legacy Flutter sessions retain
-- the profiles fallback already implemented by effective_gym_*().

begin;
create index if not exists workout_comments_workout_created_idx
on public.workout_comments(workout_id,created_at desc,id desc);
create or replace function public.can_read_effective_workout_gym(p_gym_id uuid)
returns boolean language sql stable security definer set search_path=public,pg_temp
as $$ select auth.uid() is not null and p_gym_id is not null and p_gym_id=public.effective_gym_id() $$;
create or replace function public.can_interact_effective_workout_gym(p_gym_id uuid)
returns boolean language sql stable security definer set search_path=public,pg_temp
as $$
  select public.can_read_effective_workout_gym(p_gym_id) and case
    when public.is_registered_web_session() then public.effective_gym_id() is not null
    else coalesce((select p.is_active from public.profiles p where p.id=auth.uid()),false)
  end
$$;
create or replace function public.can_manage_effective_workout_gym(p_gym_id uuid)
returns boolean language sql stable security definer set search_path=public,pg_temp
as $$
  select public.can_interact_effective_workout_gym(p_gym_id)
    and public.effective_gym_role() in ('admin','owner')
$$;
drop policy if exists "programs gym members can read" on public.programs;
drop policy if exists "programs admins can manage" on public.programs;
drop policy if exists "programs legacy admins can insert" on public.programs;
drop policy if exists "programs legacy admins can update" on public.programs;
drop policy if exists "programs legacy admins can delete" on public.programs;
create policy "effective members read programs" on public.programs for select to authenticated
using (public.can_read_effective_workout_gym(gym_id));
create policy "effective admins insert programs" on public.programs for insert to authenticated
with check (public.can_manage_effective_workout_gym(gym_id));
create policy "effective admins update programs" on public.programs for update to authenticated
using (public.can_manage_effective_workout_gym(gym_id))
with check (public.can_manage_effective_workout_gym(gym_id));
create policy "effective admins delete programs" on public.programs for delete to authenticated
using (public.can_manage_effective_workout_gym(gym_id));
drop policy if exists "workouts gym members can read" on public.workouts;
drop policy if exists "workouts admins can manage" on public.workouts;
create policy "effective members read workouts" on public.workouts for select to authenticated
using (public.can_read_effective_workout_gym(gym_id));
create policy "effective admins insert workouts" on public.workouts for insert to authenticated
with check (public.can_manage_effective_workout_gym(gym_id));
create policy "effective admins update workouts" on public.workouts for update to authenticated
using (public.can_manage_effective_workout_gym(gym_id))
with check (public.can_manage_effective_workout_gym(gym_id));
create policy "effective admins delete workouts" on public.workouts for delete to authenticated
using (public.can_manage_effective_workout_gym(gym_id));
drop policy if exists "workout likes gym members can read" on public.workout_likes;
drop policy if exists "workout likes users can manage own" on public.workout_likes;
create policy "effective members read workout likes" on public.workout_likes for select to authenticated
using (exists(select 1 from public.workouts w where w.id=workout_id and public.can_read_effective_workout_gym(w.gym_id)));
create policy "effective members insert own workout likes" on public.workout_likes for insert to authenticated
with check (user_id=auth.uid() and exists(select 1 from public.workouts w where w.id=workout_id and public.can_interact_effective_workout_gym(w.gym_id)));
create policy "effective members delete own workout likes" on public.workout_likes for delete to authenticated
using (user_id=auth.uid() and exists(select 1 from public.workouts w where w.id=workout_id and public.can_interact_effective_workout_gym(w.gym_id)));
drop policy if exists "workout comments gym members can read" on public.workout_comments;
drop policy if exists "workout comments users can create own" on public.workout_comments;
drop policy if exists "workout comments users can delete own" on public.workout_comments;
drop policy if exists "workout comments admins can delete gym comments" on public.workout_comments;
create policy "effective members read workout comments" on public.workout_comments for select to authenticated
using (exists(select 1 from public.workouts w where w.id=workout_id and public.can_read_effective_workout_gym(w.gym_id)));
create policy "effective members insert own workout comments" on public.workout_comments for insert to authenticated
with check (user_id=auth.uid() and exists(select 1 from public.workouts w where w.id=workout_id and public.can_interact_effective_workout_gym(w.gym_id)));
create policy "effective members delete own workout comments" on public.workout_comments for delete to authenticated
using (user_id=auth.uid() and exists(select 1 from public.workouts w where w.id=workout_id and public.can_interact_effective_workout_gym(w.gym_id)));
create policy "effective admins delete gym workout comments" on public.workout_comments for delete to authenticated
using (exists(select 1 from public.workouts w where w.id=workout_id
  and public.can_interact_effective_workout_gym(w.gym_id) and public.effective_gym_role()='admin'));
create or replace function public.validate_workout_program_gym()
returns trigger language plpgsql security invoker set search_path=public,pg_temp
as $function$
begin
  if not exists(select 1 from public.programs p where p.id=new.program_id and p.gym_id=new.gym_id) then
    raise exception 'invalid_workout_program' using errcode='23514';
  end if;
  new.description:=btrim(new.description);
  if new.description='' then raise exception 'invalid_workout_description' using errcode='22023'; end if;
  return new;
end;
$function$;
drop trigger if exists validate_workout_program_gym on public.workouts;
create trigger validate_workout_program_gym before insert or update of gym_id,program_id,description on public.workouts
for each row execute function public.validate_workout_program_gym();
create or replace function public.validate_workout_comment_body()
returns trigger language plpgsql security invoker set search_path=public,pg_temp
as $function$
begin
  new.body:=btrim(new.body);
  if new.body='' then raise exception 'invalid_comment' using errcode='22023'; end if;
  return new;
end;
$function$;
drop trigger if exists validate_workout_comment_body on public.workout_comments;
create trigger validate_workout_comment_body before insert or update of body on public.workout_comments
for each row execute function public.validate_workout_comment_body();
-- Workout notifications were historically scheduled for profiles.gym_id. Use
-- the workout as the origin and active relational memberships as recipients.
create or replace function public.schedule_workout_notifications(w_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_workout public.workouts%rowtype;
begin
  select * into v_workout from public.workouts w where w.id=w_id;
  if not found or not public.can_manage_effective_workout_gym(v_workout.gym_id) then
    raise exception 'not_found' using errcode='P0001';
  end if;
  delete from public.notifications n where n.type='workout_published'
    and n.data->>'workoutId'=w_id::text and n.sent_at is null;
  insert into public.notifications(user_id,gym_id,title,body,type,data,scheduled_for)
  select gm.user_id,v_workout.gym_id,'Workout del día 💪','Ya está disponible el WOD de hoy.',
    'workout_published',jsonb_build_object('workoutId',v_workout.id),
    (v_workout.workout_date+time '06:00') at time zone 'Europe/Madrid'
  from public.gym_members gm
  where gm.gym_id=v_workout.gym_id and gm.is_active and gm.role in ('admin','athlete','coach')
    and (v_workout.workout_date+time '06:00') at time zone 'Europe/Madrid'>now()
    and not exists(select 1 from public.notifications n where n.user_id=gm.user_id
      and n.type='workout_published' and n.data->>'workoutId'=v_workout.id::text and n.sent_at is not null);
end;
$function$;
create or replace function public.set_notification_gym_id()
returns trigger language plpgsql security definer set search_path=public,pg_temp
as $function$
begin
  if new.type='workout_published' then
    select w.gym_id into new.gym_id from public.workouts w where w.id::text=new.data->>'workoutId';
    if new.gym_id is null then raise exception 'invalid_notification_origin'; end if;
    return new;
  end if;
  if new.type='waitlist_promoted' then
    select c.gym_id into new.gym_id from public.classes c where c.id::text=new.data->>'classId';
    if new.gym_id is null then raise exception 'invalid_notification_origin'; end if;
    return new;
  end if;
  if new.type in ('membership_scheduled','membership_approved','membership_payment_completed') and new.data?'requestId' then
    select mr.gym_id into new.gym_id from public.membership_requests mr where mr.id::text=new.data->>'requestId';
    if new.gym_id is null then raise exception 'invalid_notification_origin'; end if;
    return new;
  end if;
  select p.gym_id into new.gym_id from public.profiles p where p.id=new.user_id;
  if new.gym_id is null and new.type='gym_join_rejected' then
    select r.gym_id into new.gym_id from public.gym_join_requests r where r.user_id=new.user_id
      and r.status='rejected' and r.gym_id::text=new.data->>'gymId'
    order by r.approved_at desc nulls last,r.created_at desc limit 1;
  end if;
  return new;
end;
$function$;
create or replace function public.get_effective_workout_access()
returns text language plpgsql stable security definer set search_path=public,pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id();
begin
  if auth.uid() is null or v_gym_id is null then raise exception 'forbidden' using errcode='42501'; end if;
  return case when public.can_manage_effective_workout_gym(v_gym_id) then 'admin' else 'member' end;
end;
$function$;
create or replace function public.create_effective_program(p_name text)
returns uuid language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id(); v_id uuid;
begin
  if not public.can_manage_effective_workout_gym(v_gym_id) then raise exception 'forbidden' using errcode='42501'; end if;
  if nullif(btrim(p_name),'') is null then raise exception 'invalid_program_name' using errcode='22023'; end if;
  insert into public.programs(gym_id,name,is_active) values(v_gym_id,btrim(p_name),true) returning id into v_id;
  return v_id;
end;
$function$;
create or replace function public.rename_effective_program(p_program_id uuid,p_name text)
returns boolean language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id();
begin
  if not public.can_manage_effective_workout_gym(v_gym_id) then raise exception 'forbidden' using errcode='42501'; end if;
  if nullif(btrim(p_name),'') is null then raise exception 'invalid_program_name' using errcode='22023'; end if;
  update public.programs set name=btrim(p_name) where id=p_program_id and gym_id=v_gym_id;
  return found;
end;
$function$;
create or replace function public.toggle_effective_program(p_program_id uuid)
returns boolean language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id();
begin
  if not public.can_manage_effective_workout_gym(v_gym_id) then raise exception 'forbidden' using errcode='42501'; end if;
  update public.programs set is_active=not is_active where id=p_program_id and gym_id=v_gym_id;
  return found;
end;
$function$;
create or replace function public.delete_effective_program(p_program_id uuid)
returns text language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id(); v_locked_id uuid;
begin
  if not public.can_manage_effective_workout_gym(v_gym_id) then raise exception 'forbidden' using errcode='42501'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_program_id::text,619));
  select p.id into v_locked_id from public.programs p where p.id=p_program_id and p.gym_id=v_gym_id for update;
  if v_locked_id is null then return 'not_found'; end if;
  if exists(select 1 from public.workouts w where w.program_id=p_program_id) then return 'in_use'; end if;
  delete from public.programs where id=p_program_id and gym_id=v_gym_id;
  return 'deleted';
end;
$function$;
create or replace function public.create_effective_workout(p_program_id uuid,p_workout_date date,p_description text)
returns uuid language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id(); v_id uuid;
begin
  if not public.can_manage_effective_workout_gym(v_gym_id) then raise exception 'forbidden' using errcode='42501'; end if;
  if not exists(select 1 from public.programs p where p.id=p_program_id and p.gym_id=v_gym_id and p.is_active) then raise exception 'program_not_found' using errcode='P0001'; end if;
  insert into public.workouts(gym_id,program_id,workout_date,description,created_by)
  values(v_gym_id,p_program_id,p_workout_date,p_description,auth.uid()) returning id into v_id;
  return v_id;
end;
$function$;
create or replace function public.update_effective_workout(p_workout_id uuid,p_program_id uuid,p_workout_date date,p_description text)
returns boolean language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id();
begin
  if not public.can_manage_effective_workout_gym(v_gym_id) then raise exception 'forbidden' using errcode='42501'; end if;
  if not exists(select 1 from public.programs p where p.id=p_program_id and p.gym_id=v_gym_id and p.is_active) then return false; end if;
  update public.workouts set program_id=p_program_id,workout_date=p_workout_date,description=p_description,updated_at=now()
  where id=p_workout_id and gym_id=v_gym_id;
  return found;
end;
$function$;
create or replace function public.delete_effective_workout(p_workout_id uuid)
returns boolean language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id();
begin
  if not public.can_manage_effective_workout_gym(v_gym_id) then raise exception 'forbidden' using errcode='42501'; end if;
  delete from public.workouts where id=p_workout_id and gym_id=v_gym_id;
  return found;
end;
$function$;
create or replace function public.set_effective_workout_like(p_workout_id uuid,p_liked boolean)
returns boolean language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_user_id uuid:=auth.uid();
begin
  if v_user_id is null or p_liked is null or not exists(
    select 1 from public.workouts w where w.id=p_workout_id and public.can_interact_effective_workout_gym(w.gym_id)
  ) then raise exception 'not_found' using errcode='P0001'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_workout_id::text||':'||v_user_id::text,620));
  if p_liked then
    insert into public.workout_likes(workout_id,user_id) values(p_workout_id,v_user_id) on conflict do nothing;
  else
    delete from public.workout_likes where workout_id=p_workout_id and user_id=v_user_id;
  end if;
  return p_liked;
end;
$function$;
create or replace function public.create_effective_workout_comment(p_workout_id uuid,p_body text)
returns uuid language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_user_id uuid:=auth.uid(); v_id uuid;
begin
  if v_user_id is null or not exists(select 1 from public.workouts w where w.id=p_workout_id and public.can_interact_effective_workout_gym(w.gym_id)) then
    raise exception 'not_found' using errcode='P0001';
  end if;
  insert into public.workout_comments(workout_id,user_id,body) values(p_workout_id,v_user_id,p_body) returning id into v_id;
  return v_id;
end;
$function$;
create or replace function public.delete_effective_workout_comment(p_workout_id uuid,p_comment_id uuid)
returns boolean language plpgsql security definer set search_path=public,pg_temp
as $function$
declare v_user_id uuid:=auth.uid(); v_gym_id uuid:=public.effective_gym_id();
begin
  if v_user_id is null or v_gym_id is null then raise exception 'forbidden' using errcode='42501'; end if;
  delete from public.workout_comments wc using public.workouts w
  where wc.id=p_comment_id and wc.workout_id=p_workout_id and w.id=wc.workout_id and w.gym_id=v_gym_id
    and (wc.user_id=v_user_id or (public.can_interact_effective_workout_gym(w.gym_id) and public.effective_gym_role()='admin'));
  return found;
end;
$function$;
create or replace function public.list_effective_workout_comment_authors(p_workout_id uuid)
returns table(user_id uuid,full_name text,avatar_url text)
language plpgsql stable security definer set search_path=public,pg_temp
as $function$
begin
  if not exists(select 1 from public.workouts w where w.id=p_workout_id and public.can_read_effective_workout_gym(w.gym_id)) then
    raise exception 'not_found' using errcode='P0001';
  end if;
  return query select distinct p.id,p.full_name,p.avatar_url from public.workout_comments wc join public.profiles p on p.id=wc.user_id where wc.workout_id=p_workout_id;
end;
$function$;
create or replace function public.list_effective_explore_workouts(
  p_today date,p_future boolean default false,p_query text default null,p_program_id uuid default null,p_limit integer default 60
)
returns table(id uuid,program_id uuid,workout_date date,description text,image_url text,program_name text,like_count bigint,comment_count bigint)
language plpgsql stable security definer set search_path=public,pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id(); v_limit integer:=least(greatest(coalesce(p_limit,60),1),100); v_query text:=nullif(btrim(p_query),'');
begin
  if not public.can_read_effective_workout_gym(v_gym_id) then raise exception 'forbidden' using errcode='42501'; end if;
  if coalesce(p_future,false) and not public.can_manage_effective_workout_gym(v_gym_id) then raise exception 'forbidden' using errcode='42501'; end if;
  return query
  select w.id,w.program_id,w.workout_date,w.description,w.image_url,p.name,
    (select count(*) from public.workout_likes wl where wl.workout_id=w.id),
    (select count(*) from public.workout_comments wc where wc.workout_id=w.id)
  from public.workouts w join public.programs p on p.id=w.program_id and p.gym_id=w.gym_id
  where w.gym_id=v_gym_id
    and case when coalesce(p_future,false) then w.workout_date>p_today else w.workout_date<p_today end
    and (p_program_id is null or w.program_id=p_program_id)
    and (v_query is null or w.description ilike '%'||v_query||'%' or p.name ilike '%'||v_query||'%')
  order by case when coalesce(p_future,false) then w.workout_date end asc,
    case when not coalesce(p_future,false) then w.workout_date end desc,w.id desc
  limit v_limit;
end;
$function$;
create or replace function public.list_effective_explore_program_counts(p_today date,p_future boolean default false)
returns table(program_id uuid,workout_count bigint)
language plpgsql stable security definer set search_path=public,pg_temp
as $function$
declare v_gym_id uuid:=public.effective_gym_id();
begin
  if not public.can_read_effective_workout_gym(v_gym_id) then raise exception 'forbidden' using errcode='42501'; end if;
  if coalesce(p_future,false) and not public.can_manage_effective_workout_gym(v_gym_id) then raise exception 'forbidden' using errcode='42501'; end if;
  return query select w.program_id,count(*) from public.workouts w where w.gym_id=v_gym_id
    and case when coalesce(p_future,false) then w.workout_date>p_today else w.workout_date<p_today end group by w.program_id;
end;
$function$;
revoke all on function public.can_read_effective_workout_gym(uuid) from public,anon,authenticated,service_role;
revoke all on function public.can_interact_effective_workout_gym(uuid) from public,anon,authenticated,service_role;
revoke all on function public.can_manage_effective_workout_gym(uuid) from public,anon,authenticated,service_role;
revoke all on function public.validate_workout_program_gym() from public,anon,authenticated,service_role;
revoke all on function public.validate_workout_comment_body() from public,anon,authenticated,service_role;
revoke all on function public.schedule_workout_notifications(uuid) from public,anon,authenticated,service_role;
revoke all on function public.get_effective_workout_access() from public,anon,authenticated,service_role;
revoke all on function public.create_effective_program(text) from public,anon,authenticated,service_role;
revoke all on function public.rename_effective_program(uuid,text) from public,anon,authenticated,service_role;
revoke all on function public.toggle_effective_program(uuid) from public,anon,authenticated,service_role;
revoke all on function public.delete_effective_program(uuid) from public,anon,authenticated,service_role;
revoke all on function public.create_effective_workout(uuid,date,text) from public,anon,authenticated,service_role;
revoke all on function public.update_effective_workout(uuid,uuid,date,text) from public,anon,authenticated,service_role;
revoke all on function public.delete_effective_workout(uuid) from public,anon,authenticated,service_role;
revoke all on function public.set_effective_workout_like(uuid,boolean) from public,anon,authenticated,service_role;
revoke all on function public.create_effective_workout_comment(uuid,text) from public,anon,authenticated,service_role;
revoke all on function public.delete_effective_workout_comment(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function public.list_effective_workout_comment_authors(uuid) from public,anon,authenticated,service_role;
revoke all on function public.list_effective_explore_workouts(date,boolean,text,uuid,integer) from public,anon,authenticated,service_role;
revoke all on function public.list_effective_explore_program_counts(date,boolean) from public,anon,authenticated,service_role;
grant execute on function public.can_read_effective_workout_gym(uuid) to authenticated,service_role;
grant execute on function public.can_interact_effective_workout_gym(uuid) to authenticated,service_role;
grant execute on function public.can_manage_effective_workout_gym(uuid) to authenticated,service_role;
grant execute on function public.schedule_workout_notifications(uuid) to authenticated,service_role;
grant execute on function public.get_effective_workout_access() to authenticated,service_role;
grant execute on function public.create_effective_program(text) to authenticated,service_role;
grant execute on function public.rename_effective_program(uuid,text) to authenticated,service_role;
grant execute on function public.toggle_effective_program(uuid) to authenticated,service_role;
grant execute on function public.delete_effective_program(uuid) to authenticated,service_role;
grant execute on function public.create_effective_workout(uuid,date,text) to authenticated,service_role;
grant execute on function public.update_effective_workout(uuid,uuid,date,text) to authenticated,service_role;
grant execute on function public.delete_effective_workout(uuid) to authenticated,service_role;
grant execute on function public.set_effective_workout_like(uuid,boolean) to authenticated,service_role;
grant execute on function public.create_effective_workout_comment(uuid,text) to authenticated,service_role;
grant execute on function public.delete_effective_workout_comment(uuid,uuid) to authenticated,service_role;
grant execute on function public.list_effective_workout_comment_authors(uuid) to authenticated,service_role;
grant execute on function public.list_effective_explore_workouts(date,boolean,text,uuid,integer) to authenticated,service_role;
grant execute on function public.list_effective_explore_program_counts(date,boolean) to authenticated,service_role;
commit;
