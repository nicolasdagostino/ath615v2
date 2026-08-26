-- Device clients display classes in local time, while cancellation messages
-- were formatting their timestamptz values explicitly as UTC. Persist an IANA
-- timezone per gym so server-produced messages can follow DST safely.
alter table public.gyms
  add column if not exists timezone text not null default 'Europe/Madrid';

create or replace function public.validate_gym_timezone()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $function$
begin
  if not exists (
    select 1 from pg_catalog.pg_timezone_names tz where tz.name = new.timezone
  ) then
    raise exception using errcode = '22023', message = 'invalid_gym_timezone';
  end if;
  return new;
end;
$function$;

drop trigger if exists validate_gym_timezone_trigger on public.gyms;
create trigger validate_gym_timezone_trigger
before insert or update of timezone on public.gyms
for each row execute function public.validate_gym_timezone();

create or replace function public.localize_class_cancelled_notification()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_starts_at timestamptz;
  v_timezone text;
begin
  if new.type is distinct from 'class_cancelled' then return new; end if;

  begin
    v_starts_at := (new.data ->> 'startsAt')::timestamptz;
  exception when others then
    return new;
  end;
  if v_starts_at is null then return new; end if;

  select g.timezone into v_timezone
  from public.gyms g where g.id = new.gym_id;
  v_timezone := coalesce(v_timezone, 'Europe/Madrid');

  -- Preserve the already-localized copy and refund/waitlist wording, replacing
  -- only the date and time tokens previously rendered in UTC.
  new.body := replace(
    replace(
      new.body,
      to_char(v_starts_at at time zone 'UTC', 'DD/MM/YYYY'),
      to_char(v_starts_at at time zone v_timezone, 'DD/MM/YYYY')
    ),
    to_char(v_starts_at at time zone 'UTC', 'HH24:MI'),
    to_char(v_starts_at at time zone v_timezone, 'HH24:MI')
  );
  return new;
end;
$function$;

drop trigger if exists localize_class_cancelled_notification_trigger
  on public.notifications;
create trigger localize_class_cancelled_notification_trigger
before insert on public.notifications
for each row execute function public.localize_class_cancelled_notification();

-- Atomic attendance action. Guests deliberately remain untouched because their
-- attendance lifecycle is separate from member milestones.
create or replace function public.admin_mark_all_class_attended(p_class_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_class public.classes%rowtype;
  v_updated integer;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if public.effective_gym_role() <> 'admin' then
    raise exception using errcode = '42501', message = 'Not allowed';
  end if;

  select c.* into v_class
  from public.classes c
  where c.id = p_class_id
    and c.gym_id = public.effective_gym_id()
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'Class not found'; end if;
  if v_class.starts_at > now() then
    raise exception using errcode = '22023', message = 'class_not_started';
  end if;

  perform 1 from public.class_bookings cb
  where cb.class_id = v_class.id and cb.status = 'booked'
  order by cb.id for update;

  update public.class_bookings cb
  set status = 'attended'
  where cb.class_id = v_class.id
    and cb.status = 'booked'
    and not coalesce(cb.is_guest, false);
  get diagnostics v_updated = row_count;
  return v_updated;
end;
$function$;

revoke all on function public.admin_mark_all_class_attended(uuid)
  from public, anon;
grant execute on function public.admin_mark_all_class_attended(uuid)
  to authenticated, service_role;
revoke execute on function public.finish_class_attendance(uuid)
  from authenticated;
grant execute on function public.finish_class_attendance(uuid)
  to service_role;
revoke all on function public.localize_class_cancelled_notification()
  from public, anon, authenticated;
revoke all on function public.validate_gym_timezone()
  from public, anon, authenticated;
