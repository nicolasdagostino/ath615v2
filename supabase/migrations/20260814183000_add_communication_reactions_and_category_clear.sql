create or replace function public.clear_effective_notifications_by_category(
  p_category text
)
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
  if p_category not in ('communication', 'notification') then
    raise exception using errcode = '22023', message = 'invalid_category';
  end if;
  if v_user_id is null or v_gym_id is null then return 0; end if;

  delete from public.notifications n
  where n.sent_at is not null
    and n.user_id = v_user_id
    and (n.gym_id = v_gym_id or (not v_is_web and n.gym_id is null))
    and (
      (p_category = 'communication' and n.type = 'communication')
      or (
        p_category = 'notification'
        and n.type is distinct from 'communication'
      )
    );

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.clear_effective_notifications_by_category(text)
from public;
grant execute on function public.clear_effective_notifications_by_category(text)
to authenticated, service_role;

create table if not exists public.communication_reactions (
  notification_id uuid not null references public.notifications(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  reaction text not null check (reaction in ('thumbs_up', 'heart')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (notification_id, user_id)
);

alter table public.communication_reactions enable row level security;

drop trigger if exists communication_reactions_touch_updated_at
on public.communication_reactions;
create trigger communication_reactions_touch_updated_at
before update on public.communication_reactions
for each row execute function public.touch_multi_gym_updated_at();

drop policy if exists "users read own effective communication reaction"
on public.communication_reactions;
create policy "users read own effective communication reaction"
on public.communication_reactions
for select to authenticated
using (
  user_id = auth.uid()
  and exists (
    select 1
    from public.notifications n
    where n.id = notification_id
      and n.user_id = auth.uid()
      and n.type = 'communication'
      and n.sent_at is not null
      and (
        n.gym_id = public.effective_gym_id()
        or (not public.is_registered_web_session() and n.gym_id is null)
      )
  )
);

drop policy if exists "users insert own effective communication reaction"
on public.communication_reactions;
create policy "users insert own effective communication reaction"
on public.communication_reactions
for insert to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.notifications n
    where n.id = notification_id
      and n.user_id = auth.uid()
      and n.type = 'communication'
      and n.sent_at is not null
      and (
        n.gym_id = public.effective_gym_id()
        or (not public.is_registered_web_session() and n.gym_id is null)
      )
  )
);

drop policy if exists "users update own effective communication reaction"
on public.communication_reactions;
create policy "users update own effective communication reaction"
on public.communication_reactions
for update to authenticated
using (user_id = auth.uid())
with check (
  user_id = auth.uid()
  and reaction in ('thumbs_up', 'heart')
  and exists (
    select 1
    from public.notifications n
    where n.id = notification_id
      and n.user_id = auth.uid()
      and n.type = 'communication'
      and n.sent_at is not null
      and (
        n.gym_id = public.effective_gym_id()
        or (not public.is_registered_web_session() and n.gym_id is null)
      )
  )
);

drop policy if exists "users delete own effective communication reaction"
on public.communication_reactions;
create policy "users delete own effective communication reaction"
on public.communication_reactions
for delete to authenticated
using (
  user_id = auth.uid()
  and exists (
    select 1
    from public.notifications n
    where n.id = notification_id
      and n.user_id = auth.uid()
      and n.type = 'communication'
      and n.sent_at is not null
      and (
        n.gym_id = public.effective_gym_id()
        or (not public.is_registered_web_session() and n.gym_id is null)
      )
  )
);

create or replace function public.get_communication_reactions(
  p_notification_id uuid
)
returns table (
  thumbs_up_count bigint,
  heart_count bigint,
  my_reaction text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_notification public.notifications%rowtype;
  v_group_id text;
begin
  select n.* into v_notification
  from public.notifications n
  where n.id = p_notification_id
    and n.user_id = auth.uid()
    and n.type = 'communication'
    and n.sent_at is not null
    and (
      n.gym_id = public.effective_gym_id()
      or (not public.is_registered_web_session() and n.gym_id is null)
    );

  if not found then
    raise exception using errcode = '42501', message = 'forbidden';
  end if;

  v_group_id := coalesce(
    nullif(v_notification.data ->> 'communicationId', ''),
    v_notification.id::text
  );

  return query
  select
    count(*) filter (where cr.reaction = 'thumbs_up'),
    count(*) filter (where cr.reaction = 'heart'),
    max(cr.reaction) filter (where cr.user_id = auth.uid())
  from public.communication_reactions cr
  join public.notifications n on n.id = cr.notification_id
  where n.type = 'communication'
    and n.gym_id is not distinct from v_notification.gym_id
    and coalesce(nullif(n.data ->> 'communicationId', ''), n.id::text)
      = v_group_id;
end;
$$;

create or replace function public.set_communication_reaction(
  p_notification_id uuid,
  p_reaction text
)
returns table (
  thumbs_up_count bigint,
  heart_count bigint,
  my_reaction text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_notification public.notifications%rowtype;
  v_existing text;
begin
  if p_reaction is not null and p_reaction not in ('thumbs_up', 'heart') then
    raise exception using errcode = '22023', message = 'invalid_reaction';
  end if;

  select n.* into v_notification
  from public.notifications n
  where n.id = p_notification_id
    and n.user_id = auth.uid()
    and n.type = 'communication'
    and n.sent_at is not null
    and (
      n.gym_id = public.effective_gym_id()
      or (not public.is_registered_web_session() and n.gym_id is null)
    );

  if not found then
    raise exception using errcode = '42501', message = 'forbidden';
  end if;

  select cr.reaction into v_existing
  from public.communication_reactions cr
  where cr.notification_id = p_notification_id
    and cr.user_id = auth.uid();

  if p_reaction is null or v_existing = p_reaction then
    delete from public.communication_reactions cr
    where cr.notification_id = p_notification_id
      and cr.user_id = auth.uid();
  else
    insert into public.communication_reactions(notification_id, user_id, reaction)
    values (p_notification_id, auth.uid(), p_reaction)
    on conflict (notification_id, user_id)
    do update set reaction = excluded.reaction;
  end if;

  return query
  select * from public.get_communication_reactions(p_notification_id);
end;
$$;

revoke all on function public.get_communication_reactions(uuid) from public;
revoke all on function public.set_communication_reaction(uuid, text) from public;
grant execute on function public.get_communication_reactions(uuid)
to authenticated, service_role;
grant execute on function public.set_communication_reaction(uuid, text)
to authenticated, service_role;

revoke all on table public.communication_reactions from public, anon;
grant select, insert, update, delete on table public.communication_reactions
to authenticated;
grant all on table public.communication_reactions to service_role;

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
  v_communication_id uuid := gen_random_uuid();
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
      'createdBy', auth.uid(),
      'communicationId', v_communication_id
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

revoke all on function public.send_effective_gym_communication(text, text, text, uuid)
from public;
grant execute on function public.send_effective_gym_communication(text, text, text, uuid)
to authenticated, service_role;
