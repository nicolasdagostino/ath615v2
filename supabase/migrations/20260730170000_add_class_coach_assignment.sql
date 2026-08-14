-- Add an optional primary coach to classes without changing existing consumers.
alter table public.classes
  add column if not exists coach_id uuid null;
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'classes_coach_id_fkey'
      and conrelid = 'public.classes'::regclass
  ) then
    alter table public.classes
      add constraint classes_coach_id_fkey
      foreign key (coach_id)
      references public.profiles(id)
      on delete set null;
  end if;
end;
$$;
create index if not exists classes_gym_coach_starts_idx
  on public.classes (gym_id, coach_id, starts_at)
  where coach_id is not null;
create or replace function public.validate_class_coach_assignment()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if new.coach_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = new.coach_id
      and p.gym_id = new.gym_id
      and p.role = 'coach'
      and p.is_active = true
  ) then
    raise exception 'invalid_class_coach' using errcode = '22023';
  end if;

  return new;
end;
$$;
revoke all on function public.validate_class_coach_assignment() from public;
revoke all on function public.validate_class_coach_assignment() from anon;
revoke all on function public.validate_class_coach_assignment() from authenticated;
drop trigger if exists validate_class_coach_assignment on public.classes;
create trigger validate_class_coach_assignment
before insert or update of gym_id, coach_id on public.classes
for each row execute function public.validate_class_coach_assignment();
-- Overload used by the web. The existing seven-argument Flutter signature remains unchanged.
create or replace function public.create_recurring_classes(
  p_gym_id uuid,
  p_program_id uuid,
  p_title text,
  p_starts_at timestamptz,
  p_duration_minutes integer,
  p_capacity integer,
  p_weeks integer,
  p_coach_id uuid
)
returns void
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_actor public.profiles%rowtype;
  v_recurring_id uuid := gen_random_uuid();
begin
  select *
  into v_actor
  from public.profiles
  where id = auth.uid();

  if v_actor.id is null
     or v_actor.is_active is not true
     or v_actor.role not in ('admin', 'owner')
     or v_actor.gym_id is distinct from p_gym_id then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  for i in 0..greatest(p_weeks - 1, 0) loop
    insert into public.classes (
      gym_id, program_id, title, starts_at, duration_minutes, capacity,
      recurring_id, created_by, coach_id
    )
    values (
      p_gym_id, p_program_id, p_title, p_starts_at + (i * interval '1 week'),
      p_duration_minutes, p_capacity, v_recurring_id, auth.uid(), p_coach_id
    );
  end loop;
end;
$$;
revoke all on function public.create_recurring_classes(
  uuid, uuid, text, timestamptz, integer, integer, integer, uuid
) from public;
revoke all on function public.create_recurring_classes(
  uuid, uuid, text, timestamptz, integer, integer, integer, uuid
) from anon;
grant execute on function public.create_recurring_classes(
  uuid, uuid, text, timestamptz, integer, integer, integer, uuid
) to authenticated;
-- Overload used by the web. Both existing Flutter multi-day signatures remain unchanged.
create or replace function public.create_recurring_classes_multi(
  p_gym_id uuid,
  p_program_id uuid,
  p_title text,
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
security invoker
set search_path = public, pg_temp
as $$
declare
  v_actor public.profiles%rowtype;
  v_recurring_id uuid := gen_random_uuid();
  d integer;
  target_date date;
begin
  select *
  into v_actor
  from public.profiles
  where id = auth.uid();

  if v_actor.id is null
     or v_actor.is_active is not true
     or v_actor.role not in ('admin', 'owner')
     or v_actor.gym_id is distinct from p_gym_id then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  for i in 0..greatest(p_weeks - 1, 0) loop
    foreach d in array p_days loop
      target_date :=
        p_start_date
        + ((d - extract(isodow from p_start_date)::integer + 7) % 7)
        + (i * 7);

      if (target_date + p_time) at time zone 'Europe/Madrid' > now() then
        insert into public.classes (
          gym_id, program_id, title, starts_at, duration_minutes, capacity,
          recurring_id, created_by, coach_id
        )
        values (
          p_gym_id, p_program_id, p_title,
          (target_date + p_time) at time zone 'Europe/Madrid',
          p_duration_minutes, p_capacity, v_recurring_id, auth.uid(), p_coach_id
        );
      end if;
    end loop;
  end loop;
end;
$$;
revoke all on function public.create_recurring_classes_multi(
  uuid, uuid, text, time, date, integer[], integer, integer, integer, uuid
) from public;
revoke all on function public.create_recurring_classes_multi(
  uuid, uuid, text, time, date, integer[], integer, integer, integer, uuid
) from anon;
grant execute on function public.create_recurring_classes_multi(
  uuid, uuid, text, time, date, integer[], integer, integer, integer, uuid
) to authenticated;
create or replace function public.get_coach_class_summary(
  p_period text default 'week'
)
returns table (
  coach_id uuid,
  coach_name text,
  scheduled_count bigint,
  completed_count bigint
)
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_actor public.profiles%rowtype;
  v_local_now timestamp := now() at time zone 'Europe/Madrid';
  v_start timestamptz;
  v_end timestamptz;
begin
  if p_period not in ('week', 'month') then
    raise exception 'invalid_period' using errcode = '22023';
  end if;

  select *
  into v_actor
  from public.profiles
  where id = auth.uid();

  if v_actor.id is null
     or v_actor.is_active is not true
     or v_actor.role not in ('admin', 'owner')
     or v_actor.gym_id is null then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if p_period = 'week' then
    v_start := (
      date_trunc('week', v_local_now) at time zone 'Europe/Madrid'
    );
    v_end := (
      (date_trunc('week', v_local_now) + interval '1 week')
      at time zone 'Europe/Madrid'
    );
  else
    v_start := (
      date_trunc('month', v_local_now) at time zone 'Europe/Madrid'
    );
    v_end := (
      (date_trunc('month', v_local_now) + interval '1 month')
      at time zone 'Europe/Madrid'
    );
  end if;

  return query
  select
    p.id,
    coalesce(nullif(btrim(p.full_name), ''), '—'),
    count(c.id),
    count(c.id) filter (where c.starts_at < now())
  from public.profiles p
  join public.classes c
    on c.coach_id = p.id
   and c.gym_id = v_actor.gym_id
   and c.starts_at >= v_start
   and c.starts_at < v_end
  where p.gym_id = v_actor.gym_id
    and p.role = 'coach'
    and p.is_active = true
  group by p.id, p.full_name
  order by coalesce(nullif(btrim(p.full_name), ''), '—'), p.id;
end;
$$;
revoke all on function public.get_coach_class_summary(text) from public;
revoke all on function public.get_coach_class_summary(text) from anon;
grant execute on function public.get_coach_class_summary(text) to authenticated;
