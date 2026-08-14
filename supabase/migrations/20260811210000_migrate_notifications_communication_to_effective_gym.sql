-- Vertical 3H: Notifications and Communication use the session-effective gym.

create or replace function public.can_administer_effective_communication()
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_profile public.profiles%rowtype;
begin
  if auth.uid() is null then return false; end if;

  if public.is_registered_web_session() then
    return public.effective_gym_id() is not null
      and public.effective_gym_role() = 'admin';
  end if;

  select * into v_profile from public.profiles where id = auth.uid();
  return found
    and v_profile.gym_id is not null
    and coalesce(v_profile.is_active, false)
    and v_profile.role in ('admin', 'owner');
end;
$$;
drop policy if exists "users can read own notifications" on public.notifications;
drop policy if exists "users can update own notification read state" on public.notifications;
drop policy if exists "notifications users can delete own sent" on public.notifications;
drop policy if exists "notifications admins can insert gym member notifications" on public.notifications;
drop policy if exists "users read own effective gym notifications" on public.notifications;
drop policy if exists "users update own effective gym notification read state" on public.notifications;
drop policy if exists "users delete own effective gym sent notifications" on public.notifications;
create policy "users read own effective gym notifications"
on public.notifications for select to authenticated
using (
  user_id = auth.uid()
  and (
    gym_id = public.effective_gym_id()
    or (not public.is_registered_web_session() and gym_id is null)
  )
);
create policy "users update own effective gym notification read state"
on public.notifications for update to authenticated
using (
  user_id = auth.uid()
  and (
    gym_id = public.effective_gym_id()
    or (not public.is_registered_web_session() and gym_id is null)
  )
)
with check (
  user_id = auth.uid()
  and (
    gym_id = public.effective_gym_id()
    or (not public.is_registered_web_session() and gym_id is null)
  )
);
create policy "users delete own effective gym sent notifications"
on public.notifications for delete to authenticated
using (
  sent_at is not null
  and user_id = auth.uid()
  and (
    gym_id = public.effective_gym_id()
    or (not public.is_registered_web_session() and gym_id is null)
  )
);
revoke insert on public.notifications from authenticated;
revoke update on public.notifications from authenticated;
grant update(read_at) on public.notifications to authenticated;
create or replace function public.list_effective_notifications()
returns table(
  id uuid,
  title text,
  body text,
  type text,
  data jsonb,
  scheduled_for timestamptz,
  sent_at timestamptz,
  read_at timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select n.id, n.title, n.body, n.type, n.data, n.scheduled_for, n.sent_at, n.read_at
  from public.notifications n
  where n.user_id = auth.uid()
    and (
      n.gym_id = public.effective_gym_id()
      or (not public.is_registered_web_session() and n.gym_id is null)
    )
    and n.sent_at is not null
  order by n.sent_at desc, n.id desc;
$$;
create or replace function public.get_effective_notification_unread_count()
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select count(*)
  from public.notifications n
  where n.user_id = auth.uid()
    and (
      n.gym_id = public.effective_gym_id()
      or (not public.is_registered_web_session() and n.gym_id is null)
    )
    and n.sent_at is not null
    and n.read_at is null;
$$;
create or replace function public.mark_effective_notification_read(p_notification_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_gym_id uuid := public.effective_gym_id();
  v_is_web boolean := public.is_registered_web_session();
begin
  if v_user_id is null or v_gym_id is null then return false; end if;
  if p_notification_id is null then return false; end if;
  update public.notifications n
  set read_at = coalesce(n.read_at, clock_timestamp())
  where n.id = p_notification_id
    and n.user_id = v_user_id
    and (n.gym_id = v_gym_id or (not v_is_web and n.gym_id is null))
    and n.sent_at is not null
  ;
  return found;
end;
$$;
create or replace function public.mark_all_effective_notifications_read()
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count bigint;
  v_user_id uuid := auth.uid();
  v_gym_id uuid := public.effective_gym_id();
  v_is_web boolean := public.is_registered_web_session();
begin
  if v_user_id is null or v_gym_id is null then return 0; end if;
  update public.notifications n
  set read_at = clock_timestamp()
  where n.sent_at is not null
    and n.read_at is null
    and n.user_id = v_user_id
    and (n.gym_id = v_gym_id or (not v_is_web and n.gym_id is null));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
create or replace function public.clear_effective_notifications()
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count bigint;
  v_user_id uuid := auth.uid();
  v_gym_id uuid := public.effective_gym_id();
  v_is_web boolean := public.is_registered_web_session();
begin
  if v_user_id is null or v_gym_id is null then return 0; end if;
  delete from public.notifications n
  where n.sent_at is not null
    and n.user_id = v_user_id
    and (n.gym_id = v_gym_id or (not v_is_web and n.gym_id is null));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
create or replace function public.list_effective_communication_recipients()
returns table(
  user_id uuid,
  full_name text,
  avatar_url text,
  role text,
  is_coach boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v_gym_id uuid := public.effective_gym_id();
begin
  if not public.can_administer_effective_communication() or v_gym_id is null then
    raise exception using errcode = '42501', message = 'forbidden';
  end if;
  return query
  select gm.user_id, p.full_name, p.avatar_url, gm.role,
    (gm.is_coach or gm.role = 'coach')
  from public.gym_members gm
  join public.profiles p on p.id = gm.user_id
  where gm.gym_id = v_gym_id and gm.is_active
  order by lower(coalesce(p.full_name, '')), gm.user_id;
end;
$$;
create or replace function public.send_effective_gym_communication(
  p_title text,
  p_body text,
  p_audience text default 'all',
  p_recipient_id uuid default null
)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_gym_id uuid := public.effective_gym_id();
  v_title text := btrim(coalesce(p_title, ''));
  v_body text := btrim(coalesce(p_body, ''));
  v_audience text := lower(btrim(coalesce(p_audience, 'all')));
  v_count bigint;
begin
  if not public.can_administer_effective_communication() or v_gym_id is null then
    raise exception using errcode = '42501', message = 'forbidden';
  end if;
  if length(v_title) < 1 or length(v_title) > 120
    or length(v_body) < 1 or length(v_body) > 2000 then
    raise exception using errcode = 'P0001', message = 'invalid_payload';
  end if;
  if v_audience not in ('all', 'admin', 'athlete', 'coach', 'user') then
    raise exception using errcode = 'P0001', message = 'invalid_audience';
  end if;
  if (v_audience = 'user') <> (p_recipient_id is not null) then
    raise exception using errcode = 'P0001', message = 'invalid_recipient';
  end if;

  insert into public.notifications(
    user_id, gym_id, title, body, type, data, scheduled_for
  )
  select distinct gm.user_id, v_gym_id, v_title, v_body, 'communication',
    jsonb_build_object(
      'channel', 'admin',
      'audience', v_audience,
      'createdBy', auth.uid()
    ),
    clock_timestamp()
  from public.gym_members gm
  where gm.gym_id = v_gym_id
    and gm.is_active
    and (
      v_audience = 'all'
      or (v_audience = 'admin' and gm.role = 'admin')
      or (v_audience = 'athlete' and gm.role = 'athlete')
      or (v_audience = 'coach' and (gm.is_coach or gm.role = 'coach'))
      or (v_audience = 'user' and gm.user_id = p_recipient_id)
    );
  get diagnostics v_count = row_count;

  if v_audience = 'user' and v_count = 0 then
    raise exception using errcode = 'P0001', message = 'recipient_not_found';
  end if;
  return v_count;
end;
$$;
create or replace function public.set_notification_gym_id()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_source_gym_id uuid;
begin
  if new.type = 'workout_published' and new.data ? 'workoutId' then
    select w.gym_id into v_source_gym_id from public.workouts w
    where w.id::text = new.data->>'workoutId';
  elsif new.type in ('waitlist_promoted', 'class_reminder', 'post_score_reminder')
      and new.data ? 'classId' then
    select c.gym_id into v_source_gym_id from public.classes c
    where c.id::text = new.data->>'classId';
  elsif new.type in ('membership_scheduled', 'membership_approved', 'membership_payment_completed')
      and new.data ? 'requestId' then
    select mr.gym_id into v_source_gym_id from public.membership_requests mr
    where mr.id::text = new.data->>'requestId';
  elsif new.type in ('gym_join_approved', 'gym_join_rejected')
      and new.data ? 'requestId' then
    select r.gym_id into v_source_gym_id from public.gym_join_requests r
    where r.id::text = new.data->>'requestId';
  elsif new.type in ('gym_join_approved', 'gym_join_rejected')
      and new.data ? 'gymId' then
    select g.id into v_source_gym_id from public.gyms g
    where g.id::text = new.data->>'gymId';
  elsif new.type = 'gym_admin_added' and new.data ? 'invitationId' then
    select i.gym_id into v_source_gym_id from public.gym_invitations i
    where i.id::text = new.data->>'invitationId';
  elsif new.type = 'communication' then
    v_source_gym_id := new.gym_id;
  elsif new.type = 'birthday' then
    -- Birthday is a legacy gym notification, not a platform-global message.
    select p.gym_id into v_source_gym_id from public.profiles p where p.id = new.user_id;
  else
    -- Preserve unknown legacy producers, but never overwrite an explicit origin.
    v_source_gym_id := new.gym_id;
    if v_source_gym_id is null then
      select p.gym_id into v_source_gym_id from public.profiles p where p.id = new.user_id;
    end if;
  end if;

  if v_source_gym_id is null then
    raise exception using errcode = 'P0001', message = 'invalid_notification_origin';
  end if;
  if new.gym_id is not null and new.gym_id is distinct from v_source_gym_id then
    raise exception using errcode = 'P0001', message = 'notification_origin_mismatch';
  end if;
  new.gym_id := v_source_gym_id;
  return new;
end;
$$;
-- Repair only historical rows whose origin remains provable from immutable
-- source references. Ambiguous legacy communication/birthday/test rows stay
-- NULL and remain visible only to unregistered legacy sessions.
update public.notifications n
set gym_id = w.gym_id
from public.workouts w
where n.type = 'workout_published'
  and w.id::text = n.data->>'workoutId'
  and n.gym_id is distinct from w.gym_id;
update public.notifications n
set gym_id = c.gym_id
from public.classes c
where n.type in ('waitlist_promoted', 'class_reminder', 'post_score_reminder')
  and c.id::text = n.data->>'classId'
  and n.gym_id is distinct from c.gym_id;
update public.notifications n
set gym_id = g.id
from public.gyms g
where n.type in ('gym_join_approved', 'gym_join_rejected')
  and g.id::text = n.data->>'gymId'
  and n.gym_id is distinct from g.id;
create index if not exists notifications_user_gym_sent_idx
on public.notifications(user_id, gym_id, sent_at desc, id desc)
where sent_at is not null;
create index if not exists notifications_user_gym_unread_idx
on public.notifications(user_id, gym_id)
where sent_at is not null and read_at is null;
revoke all on function public.can_administer_effective_communication() from public, anon, authenticated;
revoke all on function public.list_effective_notifications() from public, anon;
revoke all on function public.get_effective_notification_unread_count() from public, anon;
revoke all on function public.mark_effective_notification_read(uuid) from public, anon;
revoke all on function public.mark_all_effective_notifications_read() from public, anon;
revoke all on function public.clear_effective_notifications() from public, anon;
revoke all on function public.list_effective_communication_recipients() from public, anon;
revoke all on function public.send_effective_gym_communication(text, text, text, uuid) from public, anon;
revoke all on function public.set_notification_gym_id() from public, anon, authenticated;
grant execute on function public.can_administer_effective_communication() to service_role;
grant execute on function public.list_effective_notifications() to authenticated, service_role;
grant execute on function public.get_effective_notification_unread_count() to authenticated, service_role;
grant execute on function public.mark_effective_notification_read(uuid) to authenticated, service_role;
grant execute on function public.mark_all_effective_notifications_read() to authenticated, service_role;
grant execute on function public.clear_effective_notifications() to authenticated, service_role;
grant execute on function public.list_effective_communication_recipients() to authenticated, service_role;
grant execute on function public.send_effective_gym_communication(text, text, text, uuid) to authenticated, service_role;
grant execute on function public.set_notification_gym_id() to service_role;
