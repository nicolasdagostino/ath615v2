-- Multi-gym Classes authority. Registered Web sessions use their session gym;
-- unregistered legacy sessions (including Flutter) keep profiles.gym_id through
-- effective_gym_*(). AppContextScope is intentionally unchanged in this phase.

create or replace function public.can_manage_effective_classes_gym(p_gym_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select auth.uid() is not null
    and p_gym_id is not null
    and p_gym_id = public.effective_gym_id()
    and public.effective_gym_role() = 'admin'
    and (
      exists (
        select 1 from public.web_app_session_preferences wsp
        where wsp.session_id = public.auth_session_id()
          and wsp.user_id = auth.uid()
      )
      or exists (
        select 1 from public.profiles p
        where p.id = auth.uid() and p.is_active = true
      )
    );
$function$;
revoke all on function public.can_manage_effective_classes_gym(uuid) from public;
revoke all on function public.can_manage_effective_classes_gym(uuid) from anon;
grant execute on function public.can_manage_effective_classes_gym(uuid) to authenticated;
-- Replace, rather than supplement, every permissive Classes policy so a Web
-- session cannot retain access to its legacy profile gym.
drop policy if exists "gym classes read" on public.classes;
drop policy if exists "admin create classes" on public.classes;
drop policy if exists "classes admins can update" on public.classes;
drop policy if exists "classes admins can delete" on public.classes;
create policy "gym classes read"
on public.classes for select to authenticated
using (gym_id = public.effective_gym_id());
create policy "admin create classes"
on public.classes for insert to authenticated
with check (public.can_manage_effective_classes_gym(gym_id));
create policy "classes admins can update"
on public.classes for update to authenticated
using (public.can_manage_effective_classes_gym(gym_id))
with check (public.can_manage_effective_classes_gym(gym_id));
create policy "classes admins can delete"
on public.classes for delete to authenticated
using (public.can_manage_effective_classes_gym(gym_id));
-- Programs CRUD remains legacy in this phase, but its ALL policy must be split
-- because ALL also grants SELECT and would otherwise reopen the legacy gym.
drop policy if exists "programs gym members can read" on public.programs;
drop policy if exists "programs admins can manage" on public.programs;
drop policy if exists "programs legacy admins can insert" on public.programs;
drop policy if exists "programs legacy admins can update" on public.programs;
drop policy if exists "programs legacy admins can delete" on public.programs;
create policy "programs gym members can read"
on public.programs for select to authenticated
using (gym_id = public.effective_gym_id());
create policy "programs legacy admins can insert"
on public.programs for insert to authenticated
with check (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.gym_id = programs.gym_id
      and p.role in ('admin', 'owner')
  )
);
create policy "programs legacy admins can update"
on public.programs for update to authenticated
using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.gym_id = programs.gym_id
      and p.role in ('admin', 'owner')
  )
)
with check (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.gym_id = programs.gym_id
      and p.role in ('admin', 'owner')
  )
);
create policy "programs legacy admins can delete"
on public.programs for delete to authenticated
using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.gym_id = programs.gym_id
      and p.role in ('admin', 'owner')
  )
);
-- Program validation and title fallback are server-side defenses for both
-- direct inserts and recurring RPCs.
create or replace function public.validate_class_program_assignment()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $function$
declare
  v_program_name text;
begin
  if new.program_id is null then
    if nullif(btrim(new.title), '') is null then
      raise exception 'invalid_class_program' using errcode = '22023';
    end if;
    new.title := btrim(new.title);
    return new;
  end if;

  select p.name into v_program_name
  from public.programs p
  where p.id = new.program_id
    and p.gym_id = new.gym_id
    and (
      p.is_active = true
      or (tg_op = 'UPDATE' and new.program_id is not distinct from old.program_id)
    );

  if not found then
    raise exception 'invalid_class_program' using errcode = '22023';
  end if;

  new.title := coalesce(nullif(btrim(new.title), ''), btrim(v_program_name));
  return new;
end;
$function$;
revoke all on function public.validate_class_program_assignment() from public;
revoke all on function public.validate_class_program_assignment() from anon;
revoke all on function public.validate_class_program_assignment() from authenticated;
drop trigger if exists validate_class_program_assignment on public.classes;
create trigger validate_class_program_assignment
before insert or update of gym_id, program_id, title on public.classes
for each row execute function public.validate_class_program_assignment();
create or replace function public.validate_class_coach_assignment()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  if new.coach_id is null then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and new.coach_id is not distinct from old.coach_id
     and new.gym_id is not distinct from old.gym_id then
    return new;
  end if;

  if not exists (
    select 1 from public.gym_members gm
    where gm.gym_id = new.gym_id
      and gm.user_id = new.coach_id
      and gm.is_active = true
      and (gm.is_coach = true or gm.role = 'coach')
  ) then
    raise exception 'invalid_class_coach' using errcode = '22023';
  end if;

  return new;
end;
$function$;
revoke all on function public.validate_class_coach_assignment() from public;
revoke all on function public.validate_class_coach_assignment() from anon;
revoke all on function public.validate_class_coach_assignment() from authenticated;
create or replace function public.list_assignable_class_coaches()
returns table (coach_id uuid, coach_name text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
begin
  if not public.can_manage_effective_classes_gym(v_gym_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  return query
  select gm.user_id, coalesce(nullif(btrim(p.full_name), ''), '—')
  from public.gym_members gm
  join public.profiles p on p.id = gm.user_id
  where gm.gym_id = v_gym_id
    and gm.is_active = true
    and (gm.is_coach = true or gm.role = 'coach')
  order by coalesce(nullif(btrim(p.full_name), ''), '—'), gm.user_id;
end;
$function$;
create or replace function public.is_assignable_class_coach(p_coach_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
begin
  if not public.can_manage_effective_classes_gym(v_gym_id) then
    return false;
  end if;

  return p_coach_id is not null and exists (
    select 1 from public.gym_members gm
    where gm.gym_id = v_gym_id and gm.user_id = p_coach_id
      and gm.is_active = true
      and (gm.is_coach = true or gm.role = 'coach')
  );
end;
$function$;
revoke all on function public.list_assignable_class_coaches() from public;
revoke all on function public.list_assignable_class_coaches() from anon;
grant execute on function public.list_assignable_class_coaches() to authenticated;
revoke all on function public.is_assignable_class_coach(uuid) from public;
revoke all on function public.is_assignable_class_coach(uuid) from anon;
grant execute on function public.is_assignable_class_coach(uuid) to authenticated;
-- Classes cards need active occupancy. Keep booking RLS untouched in 3A and
-- expose only rows belonging to classes in the single effective gym.
create or replace function public.list_effective_class_bookings(p_class_ids uuid[])
returns table (class_id uuid, user_id uuid)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
begin
  if auth.uid() is null or v_gym_id is null then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_class_ids is null or cardinality(p_class_ids) > 100 then
    raise exception 'invalid_class_ids' using errcode = '22023';
  end if;

  return query
  select b.class_id, b.user_id
  from public.class_bookings b
  join public.classes c on c.id = b.class_id
  where b.class_id = any(p_class_ids)
    and b.status <> 'cancelled'
    and c.gym_id = v_gym_id
  order by b.class_id, b.id;
end;
$function$;
revoke all on function public.list_effective_class_bookings(uuid[]) from public;
revoke all on function public.list_effective_class_bookings(uuid[]) from anon;
grant execute on function public.list_effective_class_bookings(uuid[]) to authenticated;
-- Shared implementation for all five public recurring signatures.
create or replace function public.create_recurring_classes_authorized(
  p_gym_id uuid,
  p_program_id uuid,
  p_title text,
  p_first_start timestamptz,
  p_time time,
  p_start_date date,
  p_days integer[],
  p_duration_minutes integer,
  p_capacity integer,
  p_weeks integer,
  p_coach_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_recurring_id uuid := gen_random_uuid();
  v_base_date date := coalesce(p_start_date, (now() at time zone 'Europe/Madrid')::date);
  v_target_date date;
  v_day integer;
begin
  if not public.can_manage_effective_classes_gym(p_gym_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_weeks is null or p_weeks < 1 or p_weeks > 104
     or p_duration_minutes is null or p_duration_minutes < 1
     or p_capacity is null or p_capacity < 1 then
    raise exception 'invalid_class_parameters' using errcode = '22023';
  end if;

  if p_days is null then
    if p_first_start is null then
      raise exception 'invalid_class_parameters' using errcode = '22023';
    end if;
    for v_week in 0..p_weeks - 1 loop
      insert into public.classes (
        gym_id, program_id, title, starts_at, duration_minutes, capacity,
        recurring_id, created_by, coach_id
      ) values (
        p_gym_id, p_program_id, p_title,
        p_first_start + (v_week * interval '1 week'),
        p_duration_minutes, p_capacity, v_recurring_id, auth.uid(), p_coach_id
      );
    end loop;
    return;
  end if;

  if p_time is null or cardinality(p_days) < 1
     or exists (select 1 from unnest(p_days) d where d not between 1 and 7) then
    raise exception 'invalid_class_parameters' using errcode = '22023';
  end if;

  for v_week in 0..p_weeks - 1 loop
    foreach v_day in array p_days loop
      v_target_date := v_base_date
        + ((v_day - extract(isodow from v_base_date)::integer + 7) % 7)
        + (v_week * 7);
      if p_start_date is null
         or (v_target_date + p_time) at time zone 'Europe/Madrid' > now() then
        insert into public.classes (
          gym_id, program_id, title, starts_at, duration_minutes, capacity,
          recurring_id, created_by, coach_id
        ) values (
          p_gym_id, p_program_id, p_title,
          (v_target_date + p_time) at time zone 'Europe/Madrid',
          p_duration_minutes, p_capacity, v_recurring_id, auth.uid(), p_coach_id
        );
      end if;
    end loop;
  end loop;
end;
$function$;
revoke all on function public.create_recurring_classes_authorized(
  uuid, uuid, text, timestamptz, time, date, integer[], integer, integer, integer, uuid
) from public, anon, authenticated;
create or replace function public.create_recurring_classes(
  p_gym_id uuid, p_program_id uuid, p_title text, p_starts_at timestamptz,
  p_duration_minutes integer, p_capacity integer, p_weeks integer default 8
)
returns void language plpgsql security definer set search_path = public, pg_temp
as $function$
begin
  perform public.create_recurring_classes_authorized(
    p_gym_id,p_program_id,p_title,p_starts_at,null,null,null,
    p_duration_minutes,p_capacity,p_weeks,null
  );
end;
$function$;
create or replace function public.create_recurring_classes(
  p_gym_id uuid, p_program_id uuid, p_title text, p_starts_at timestamptz,
  p_duration_minutes integer, p_capacity integer, p_weeks integer, p_coach_id uuid
)
returns void language plpgsql security definer set search_path = public, pg_temp
as $function$
begin
  perform public.create_recurring_classes_authorized(
    p_gym_id,p_program_id,p_title,p_starts_at,null,null,null,
    p_duration_minutes,p_capacity,p_weeks,p_coach_id
  );
end;
$function$;
create or replace function public.create_recurring_classes_multi(
  p_gym_id uuid, p_program_id uuid, p_title text, p_time time,
  p_days integer[], p_duration_minutes integer, p_capacity integer,
  p_weeks integer default 8
)
returns void language plpgsql security definer set search_path = public, pg_temp
as $function$
begin
  perform public.create_recurring_classes_authorized(
    p_gym_id,p_program_id,p_title,null,p_time,null,p_days,
    p_duration_minutes,p_capacity,p_weeks,null
  );
end;
$function$;
create or replace function public.create_recurring_classes_multi(
  p_gym_id uuid, p_program_id uuid, p_title text, p_time time,
  p_start_date date, p_days integer[], p_duration_minutes integer,
  p_capacity integer, p_weeks integer default 8
)
returns void language plpgsql security definer set search_path = public, pg_temp
as $function$
begin
  perform public.create_recurring_classes_authorized(
    p_gym_id,p_program_id,p_title,null,p_time,p_start_date,p_days,
    p_duration_minutes,p_capacity,p_weeks,null
  );
end;
$function$;
create or replace function public.create_recurring_classes_multi(
  p_gym_id uuid, p_program_id uuid, p_title text, p_time time,
  p_start_date date, p_days integer[], p_duration_minutes integer,
  p_capacity integer, p_weeks integer, p_coach_id uuid
)
returns void language plpgsql security definer set search_path = public, pg_temp
as $function$
begin
  perform public.create_recurring_classes_authorized(
    p_gym_id,p_program_id,p_title,null,p_time,p_start_date,p_days,
    p_duration_minutes,p_capacity,p_weeks,p_coach_id
  );
end;
$function$;
revoke all on function public.create_recurring_classes(uuid,uuid,text,timestamptz,integer,integer,integer) from public, anon;
revoke all on function public.create_recurring_classes(uuid,uuid,text,timestamptz,integer,integer,integer,uuid) from public, anon;
revoke all on function public.create_recurring_classes_multi(uuid,uuid,text,time,integer[],integer,integer,integer) from public, anon;
revoke all on function public.create_recurring_classes_multi(uuid,uuid,text,time,date,integer[],integer,integer,integer) from public, anon;
revoke all on function public.create_recurring_classes_multi(uuid,uuid,text,time,date,integer[],integer,integer,integer,uuid) from public, anon;
grant execute on function public.create_recurring_classes(uuid,uuid,text,timestamptz,integer,integer,integer) to authenticated;
grant execute on function public.create_recurring_classes(uuid,uuid,text,timestamptz,integer,integer,integer,uuid) to authenticated;
grant execute on function public.create_recurring_classes_multi(uuid,uuid,text,time,integer[],integer,integer,integer) to authenticated;
grant execute on function public.create_recurring_classes_multi(uuid,uuid,text,time,date,integer[],integer,integer,integer) to authenticated;
grant execute on function public.create_recurring_classes_multi(uuid,uuid,text,time,date,integer[],integer,integer,integer,uuid) to authenticated;
-- Deletion remains a Classes contract. It inspects bookings internally so the
-- user-facing blocked rule is correct without migrating booking RLS in 3A.
create or replace function public.delete_class_for_effective_gym(
  p_class_id uuid,
  p_delete_future boolean default false
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_class public.classes%rowtype;
  v_deleted integer;
begin
  if p_class_id is null then
    return 'not_found';
  end if;

  select * into v_class from public.classes c
  where c.id = p_class_id and c.gym_id = public.effective_gym_id()
  for update;
  if not found then
    return 'not_found';
  end if;
  if not public.can_manage_effective_classes_gym(v_class.gym_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if p_delete_future and v_class.recurring_id is null then
    return 'not_found';
  end if;

  if exists (
    select 1 from public.class_bookings b
    join public.classes c on c.id = b.class_id
    where b.status <> 'cancelled'
      and c.gym_id = v_class.gym_id
      and (
        (not p_delete_future and c.id = v_class.id)
        or (p_delete_future and c.recurring_id = v_class.recurring_id
            and c.starts_at >= v_class.starts_at)
      )
  ) then
    return 'blocked';
  end if;

  if p_delete_future then
    delete from public.classes c
    where c.gym_id = v_class.gym_id
      and c.recurring_id = v_class.recurring_id
      and c.starts_at >= v_class.starts_at;
  else
    delete from public.classes c where c.id = v_class.id;
  end if;
  get diagnostics v_deleted = row_count;
  return case when v_deleted > 0 then 'success' else 'not_found' end;
exception
  when foreign_key_violation then return 'blocked';
end;
$function$;
revoke all on function public.delete_class_for_effective_gym(uuid,boolean) from public;
revoke all on function public.delete_class_for_effective_gym(uuid,boolean) from anon;
grant execute on function public.delete_class_for_effective_gym(uuid,boolean) to authenticated;
