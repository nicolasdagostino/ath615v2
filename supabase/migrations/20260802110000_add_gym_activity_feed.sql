create table if not exists public.gym_activity_events (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  kind text not null check (kind in (
    'booking',
    'booking_cancelled',
    'attendance',
    'no_show',
    'waitlist_joined',
    'membership_assigned',
    'membership_requested',
    'workout_comment',
    'workout_like',
    'guest_added',
    'guest_cancelled'
  )),
  source_table text not null check (source_table in (
    'class_bookings',
    'class_waitlist',
    'member_memberships',
    'membership_requests',
    'workout_comments',
    'workout_likes'
  )),
  source_ref text not null,
  occurred_at timestamptz not null default now(),
  member_id uuid references public.profiles(id) on delete set null,
  guest_name text,
  class_id uuid references public.classes(id) on delete set null,
  workout_id uuid references public.workouts(id) on delete set null,
  membership_id uuid references public.member_memberships(id) on delete set null,
  membership_request_id uuid references public.membership_requests(id) on delete set null
);
create unique index if not exists gym_activity_events_source_kind_uidx
on public.gym_activity_events (source_table, source_ref, kind);
create index if not exists gym_activity_events_gym_occurred_idx
on public.gym_activity_events (gym_id, occurred_at desc, id desc);
comment on table public.gym_activity_events is
  'Append-only operational activity. Stores references and the minimum guest display name; never comment bodies, email, phone, tokens, addresses, or payment data.';
comment on column public.gym_activity_events.source_ref is
  'Stable source operation identity used with source_table and kind for deduplication.';
alter table public.gym_activity_events enable row level security;
drop policy if exists "active gym admins view activity events"
on public.gym_activity_events;
create policy "active gym admins view activity events"
on public.gym_activity_events
for select
using (
  exists (
    select 1
    from public.profiles actor
    where actor.id = auth.uid()
      and actor.gym_id = gym_activity_events.gym_id
      and actor.role = any (array['admin'::text, 'owner'::text])
      and actor.is_active = true
  )
);
revoke all on table public.gym_activity_events from public, anon, authenticated;
grant select on table public.gym_activity_events to authenticated;
-- Only events with a trustworthy native creation timestamp are backfilled.
-- Historical status transitions cannot be reconstructed because
-- class_bookings did not previously store a status-change timestamp.
insert into public.gym_activity_events (
  gym_id, kind, source_table, source_ref, occurred_at, member_id, guest_name, class_id
)
select
  c.gym_id,
  case when cb.is_guest then 'guest_added' else 'booking' end,
  'class_bookings',
  cb.id::text,
  coalesce(cb.created_at, now()),
  case when cb.is_guest then null else cb.user_id end,
  case when cb.is_guest then nullif(btrim(cb.guest_name), '') else null end,
  cb.class_id
from public.class_bookings cb
join public.classes c on c.id = cb.class_id
where (cb.is_guest = true and nullif(btrim(cb.guest_name), '') is not null)
   or (cb.is_guest = false and cb.user_id is not null)
on conflict (source_table, source_ref, kind) do nothing;
insert into public.gym_activity_events (
  gym_id, kind, source_table, source_ref, occurred_at, member_id, class_id
)
select c.gym_id, 'waitlist_joined', 'class_waitlist', cw.id::text, cw.created_at, cw.user_id, cw.class_id
from public.class_waitlist cw
join public.classes c on c.id = cw.class_id
on conflict (source_table, source_ref, kind) do nothing;
insert into public.gym_activity_events (
  gym_id, kind, source_table, source_ref, occurred_at, member_id, membership_id
)
select mm.gym_id, 'membership_assigned', 'member_memberships', mm.id::text, coalesce(mm.created_at, now()), mm.user_id, mm.id
from public.member_memberships mm
where mm.user_id is not null and mm.gym_id is not null
on conflict (source_table, source_ref, kind) do nothing;
insert into public.gym_activity_events (
  gym_id, kind, source_table, source_ref, occurred_at, member_id, membership_request_id
)
select mr.gym_id, 'membership_requested', 'membership_requests', mr.id::text, mr.created_at, mr.user_id, mr.id
from public.membership_requests mr
on conflict (source_table, source_ref, kind) do nothing;
insert into public.gym_activity_events (
  gym_id, kind, source_table, source_ref, occurred_at, member_id, workout_id
)
select w.gym_id, 'workout_comment', 'workout_comments', wc.id::text, wc.created_at, wc.user_id, wc.workout_id
from public.workout_comments wc
join public.workouts w on w.id = wc.workout_id
on conflict (source_table, source_ref, kind) do nothing;
insert into public.gym_activity_events (
  gym_id, kind, source_table, source_ref, occurred_at, member_id, workout_id
)
select w.gym_id, 'workout_like', 'workout_likes', wl.workout_id::text || ':' || wl.user_id::text || ':' || wl.created_at::text, wl.created_at, wl.user_id, wl.workout_id
from public.workout_likes wl
join public.workouts w on w.id = wl.workout_id
on conflict (source_table, source_ref, kind) do nothing;
create or replace function public.capture_gym_activity_event()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_gym_id uuid;
  v_kind text;
begin
  if tg_table_name = 'class_bookings' then
    select c.gym_id into v_gym_id
    from public.classes c
    where c.id = new.class_id;

    if v_gym_id is null then return new; end if;

    if tg_op = 'INSERT' then
      v_kind := case when new.is_guest then 'guest_added' else 'booking' end;
    elsif new.status is distinct from old.status then
      v_kind := case
        when new.is_guest and new.status = 'cancelled' then 'guest_cancelled'
        when not new.is_guest and new.status = 'cancelled' then 'booking_cancelled'
        when not new.is_guest and new.status = 'attended' then 'attendance'
        when not new.is_guest and new.status = 'no_show' then 'no_show'
        else null
      end;
    end if;

    if v_kind is not null then
      insert into public.gym_activity_events (
        gym_id, kind, source_table, source_ref, occurred_at, member_id, guest_name, class_id
      ) values (
        v_gym_id,
        v_kind,
        'class_bookings',
        new.id::text,
        case when tg_op = 'INSERT' then coalesce(new.created_at, now()) else now() end,
        case when new.is_guest then null else new.user_id end,
        case when new.is_guest then nullif(btrim(new.guest_name), '') else null end,
        new.class_id
      ) on conflict (source_table, source_ref, kind) do nothing;
    end if;
  elsif tg_table_name = 'class_waitlist' then
    select c.gym_id into v_gym_id from public.classes c where c.id = new.class_id;
    if v_gym_id is not null then
      insert into public.gym_activity_events (gym_id, kind, source_table, source_ref, occurred_at, member_id, class_id)
      values (v_gym_id, 'waitlist_joined', 'class_waitlist', new.id::text, coalesce(new.created_at, now()), new.user_id, new.class_id)
      on conflict (source_table, source_ref, kind) do nothing;
    end if;
  elsif tg_table_name = 'member_memberships' then
    if new.gym_id is not null and new.user_id is not null then
      insert into public.gym_activity_events (gym_id, kind, source_table, source_ref, occurred_at, member_id, membership_id)
      values (new.gym_id, 'membership_assigned', 'member_memberships', new.id::text, coalesce(new.created_at, now()), new.user_id, new.id)
      on conflict (source_table, source_ref, kind) do nothing;
    end if;
  elsif tg_table_name = 'membership_requests' then
    insert into public.gym_activity_events (gym_id, kind, source_table, source_ref, occurred_at, member_id, membership_request_id)
    values (new.gym_id, 'membership_requested', 'membership_requests', new.id::text, coalesce(new.created_at, now()), new.user_id, new.id)
    on conflict (source_table, source_ref, kind) do nothing;
  elsif tg_table_name = 'workout_comments' then
    select w.gym_id into v_gym_id from public.workouts w where w.id = new.workout_id;
    if v_gym_id is not null then
      insert into public.gym_activity_events (gym_id, kind, source_table, source_ref, occurred_at, member_id, workout_id)
      values (v_gym_id, 'workout_comment', 'workout_comments', new.id::text, coalesce(new.created_at, now()), new.user_id, new.workout_id)
      on conflict (source_table, source_ref, kind) do nothing;
    end if;
  elsif tg_table_name = 'workout_likes' then
    select w.gym_id into v_gym_id from public.workouts w where w.id = new.workout_id;
    if v_gym_id is not null then
      insert into public.gym_activity_events (gym_id, kind, source_table, source_ref, occurred_at, member_id, workout_id)
      values (v_gym_id, 'workout_like', 'workout_likes', new.workout_id::text || ':' || new.user_id::text || ':' || new.created_at::text, coalesce(new.created_at, now()), new.user_id, new.workout_id)
      on conflict (source_table, source_ref, kind) do nothing;
    end if;
  end if;
  return new;
exception when others then
  raise warning 'gym_activity_capture_failed table=% operation=% state=%',
    tg_table_name, tg_op, sqlstate;
  return new;
end;
$$;
revoke all on function public.capture_gym_activity_event() from public, anon, authenticated;
drop trigger if exists capture_class_booking_activity on public.class_bookings;
create trigger capture_class_booking_activity
after insert or update of status on public.class_bookings
for each row execute function public.capture_gym_activity_event();
drop trigger if exists capture_waitlist_activity on public.class_waitlist;
create trigger capture_waitlist_activity
after insert on public.class_waitlist
for each row execute function public.capture_gym_activity_event();
drop trigger if exists capture_membership_activity on public.member_memberships;
create trigger capture_membership_activity
after insert on public.member_memberships
for each row execute function public.capture_gym_activity_event();
drop trigger if exists capture_membership_request_activity on public.membership_requests;
create trigger capture_membership_request_activity
after insert on public.membership_requests
for each row execute function public.capture_gym_activity_event();
drop trigger if exists capture_workout_comment_activity on public.workout_comments;
create trigger capture_workout_comment_activity
after insert on public.workout_comments
for each row execute function public.capture_gym_activity_event();
drop trigger if exists capture_workout_like_activity on public.workout_likes;
create trigger capture_workout_like_activity
after insert on public.workout_likes
for each row execute function public.capture_gym_activity_event();
create or replace function public.list_gym_activity(
  p_limit integer default 25,
  p_offset integer default 0
)
returns table (
  event_id uuid,
  kind text,
  occurred_at timestamptz,
  member_id uuid,
  member_name text,
  guest_name text,
  class_id uuid,
  class_title text,
  workout_id uuid,
  workout_program_name text,
  membership_name text,
  total_count bigint
)
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_actor public.profiles%rowtype;
begin
  if auth.uid() is null then
    raise exception using errcode = 'P0001', message = 'unauthenticated';
  end if;
  select * into v_actor from public.profiles where id = auth.uid();
  if not found or not coalesce(v_actor.is_active, false) then
    raise exception using errcode = 'P0001', message = 'unauthorized';
  end if;
  if v_actor.role <> all (array['admin'::text, 'owner'::text]) then
    raise exception using errcode = 'P0001', message = 'forbidden';
  end if;
  if v_actor.gym_id is null then
    raise exception using errcode = 'P0001', message = 'gym_not_found';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100
     or p_offset is null or p_offset < 0 then
    raise exception using errcode = '22023', message = 'invalid_parameters';
  end if;

  return query
  select
    e.id,
    e.kind,
    e.occurred_at,
    e.member_id,
    coalesce(nullif(btrim(p.full_name), ''), nullif(btrim(p.email), '')),
    e.guest_name,
    e.class_id,
    c.title,
    e.workout_id,
    pr.name,
    coalesce(mp.name, requested_plan.name),
    count(*) over()
  from public.gym_activity_events e
  left join public.profiles p on p.id = e.member_id and p.gym_id = e.gym_id
  left join public.classes c on c.id = e.class_id and c.gym_id = e.gym_id
  left join public.workouts w on w.id = e.workout_id and w.gym_id = e.gym_id
  left join public.programs pr on pr.id = w.program_id and pr.gym_id = e.gym_id
  left join public.member_memberships mm on mm.id = e.membership_id and mm.gym_id = e.gym_id
  left join public.membership_plans mp on mp.id = mm.plan_id and mp.gym_id = e.gym_id
  left join public.membership_requests mr on mr.id = e.membership_request_id and mr.gym_id = e.gym_id
  left join public.membership_plans requested_plan on requested_plan.id = mr.plan_id and requested_plan.gym_id = e.gym_id
  where e.gym_id = v_actor.gym_id
  order by e.occurred_at desc, e.id desc
  limit p_limit offset p_offset;
end;
$$;
revoke all on function public.list_gym_activity(integer, integer) from public, anon;
grant execute on function public.list_gym_activity(integer, integer) to authenticated;
