-- Internal, gym-scoped staff notes. Athletes never receive table access through
-- profile/member APIs. Active coaches may read; effective admins/owners manage.

create table public.member_staff_notes (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  member_user_id uuid not null references public.profiles(id) on delete cascade,
  author_user_id uuid references public.profiles(id) on delete set null,
  body text not null,
  is_pinned boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint member_staff_notes_body_check
    check (length(btrim(body)) between 1 and 2000)
);

create index member_staff_notes_member_recent_idx
on public.member_staff_notes(gym_id, member_user_id, created_at desc);

create index member_staff_notes_pinned_lookup_idx
on public.member_staff_notes(gym_id, member_user_id, is_pinned, updated_at desc);

create unique index member_staff_notes_one_pinned_idx
on public.member_staff_notes(gym_id, member_user_id)
where is_pinned;

create or replace function public.member_staff_notes_can_read()
returns boolean language sql stable security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and public.effective_gym_id() is not null
    and public.membership_actor_is_active()
    and (public.membership_actor_can_manage() or public.effective_gym_is_coach());
$$;

create or replace function public.member_staff_notes_touch_updated_at()
returns trigger language plpgsql
set search_path = public, pg_temp
as $function$
begin
  new.body := btrim(new.body);
  new.updated_at := clock_timestamp();
  return new;
end;
$function$;

create trigger member_staff_notes_touch_updated_at
before insert or update on public.member_staff_notes
for each row execute function public.member_staff_notes_touch_updated_at();

alter table public.member_staff_notes enable row level security;

create policy "authorized staff read effective gym member notes"
on public.member_staff_notes for select to authenticated
using (gym_id = public.effective_gym_id() and public.member_staff_notes_can_read());

create policy "effective admins insert member notes"
on public.member_staff_notes for insert to authenticated
with check (
  gym_id = public.effective_gym_id()
  and author_user_id = auth.uid()
  and public.membership_actor_can_manage()
  and exists (
    select 1 from public.gym_members gm
    where gm.gym_id = public.effective_gym_id()
      and gm.user_id = member_user_id and gm.is_active
  )
);

create policy "effective admins update member notes"
on public.member_staff_notes for update to authenticated
using (gym_id = public.effective_gym_id() and public.membership_actor_can_manage())
with check (
  gym_id = public.effective_gym_id()
  and public.membership_actor_can_manage()
  and exists (
    select 1 from public.gym_members gm
    where gm.gym_id = public.effective_gym_id()
      and gm.user_id = member_user_id and gm.is_active
  )
);

create policy "effective admins delete member notes"
on public.member_staff_notes for delete to authenticated
using (gym_id = public.effective_gym_id() and public.membership_actor_can_manage());

create or replace function public.list_effective_member_staff_notes(p_member_user_id uuid)
returns table(
  note_id uuid, member_user_id uuid, body text, is_pinned boolean,
  author_user_id uuid, author_name text, created_at timestamptz, updated_at timestamptz
)
language plpgsql stable security definer
set search_path = public, pg_temp
as $function$
declare v_gym_id uuid := public.effective_gym_id();
begin
  if v_gym_id is null or not public.member_staff_notes_can_read() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if not exists (select 1 from public.gym_members gm
    where gm.gym_id = v_gym_id and gm.user_id = p_member_user_id and gm.is_active) then
    raise exception 'member_not_found' using errcode = 'P0002';
  end if;
  return query
  select n.id, n.member_user_id, n.body, n.is_pinned, n.author_user_id,
    coalesce(nullif(btrim(p.full_name), ''), p.email, 'Staff'),
    n.created_at, n.updated_at
  from public.member_staff_notes n
  left join public.profiles p on p.id = n.author_user_id
  where n.gym_id = v_gym_id and n.member_user_id = p_member_user_id
  order by n.is_pinned desc, n.updated_at desc, n.id;
end;
$function$;

create or replace function public.list_effective_member_pinned_notes(p_member_user_ids uuid[])
returns table(member_user_id uuid, body text, updated_at timestamptz)
language plpgsql stable security definer
set search_path = public, pg_temp
as $function$
declare v_gym_id uuid := public.effective_gym_id();
begin
  if v_gym_id is null or not public.member_staff_notes_can_read() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if coalesce(cardinality(p_member_user_ids), 0) > 100 then
    raise exception 'too_many_members' using errcode = '22023';
  end if;
  return query
  select n.member_user_id, n.body, n.updated_at
  from public.member_staff_notes n
  join public.gym_members gm on gm.gym_id = n.gym_id
    and gm.user_id = n.member_user_id and gm.is_active
  where n.gym_id = v_gym_id and n.is_pinned
    and n.member_user_id = any(coalesce(p_member_user_ids, '{}'::uuid[]));
end;
$function$;

create or replace function public.save_member_staff_note(
  p_member_user_id uuid,
  p_body text,
  p_is_pinned boolean default false,
  p_note_id uuid default null
)
returns uuid language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare
  v_actor uuid := auth.uid();
  v_gym_id uuid := public.effective_gym_id();
  v_note_id uuid;
  v_body text := btrim(coalesce(p_body, ''));
begin
  if v_actor is null or v_gym_id is null or not public.membership_actor_can_manage() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if length(v_body) not between 1 and 2000 then
    raise exception 'invalid_note_body' using errcode = '22023';
  end if;
  if not exists (select 1 from public.gym_members gm
    where gm.gym_id = v_gym_id and gm.user_id = p_member_user_id and gm.is_active) then
    raise exception 'member_not_found' using errcode = 'P0002';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_gym_id::text || ':' || p_member_user_id::text, 731)
  );
  if coalesce(p_is_pinned, false) then
    update public.member_staff_notes set is_pinned = false
    where gym_id = v_gym_id and member_user_id = p_member_user_id and is_pinned
      and (p_note_id is null or id <> p_note_id);
  end if;
  if p_note_id is null then
    insert into public.member_staff_notes(
      gym_id, member_user_id, author_user_id, body, is_pinned
    ) values (v_gym_id, p_member_user_id, v_actor, v_body, coalesce(p_is_pinned, false))
    returning id into v_note_id;
  else
    update public.member_staff_notes
    set body = v_body, is_pinned = coalesce(p_is_pinned, false)
    where id = p_note_id and gym_id = v_gym_id and member_user_id = p_member_user_id
    returning id into v_note_id;
    if v_note_id is null then raise exception 'note_not_found' using errcode = 'P0002'; end if;
  end if;
  return v_note_id;
end;
$function$;

create or replace function public.delete_member_staff_note(p_note_id uuid)
returns boolean language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare v_gym_id uuid := public.effective_gym_id(); v_deleted integer;
begin
  if auth.uid() is null or v_gym_id is null or not public.membership_actor_can_manage() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  delete from public.member_staff_notes where id = p_note_id and gym_id = v_gym_id;
  get diagnostics v_deleted = row_count;
  return v_deleted > 0;
end;
$function$;

revoke all on table public.member_staff_notes from anon, authenticated;
-- Mutations are intentionally RPC-only so clients cannot reassign gym/member/author.
grant select on table public.member_staff_notes to authenticated;
revoke all on function public.member_staff_notes_can_read() from public, anon, authenticated, service_role;
revoke all on function public.list_effective_member_staff_notes(uuid) from public, anon, authenticated, service_role;
revoke all on function public.list_effective_member_pinned_notes(uuid[]) from public, anon, authenticated, service_role;
revoke all on function public.save_member_staff_note(uuid,text,boolean,uuid) from public, anon, authenticated, service_role;
revoke all on function public.delete_member_staff_note(uuid) from public, anon, authenticated, service_role;
grant execute on function public.member_staff_notes_can_read() to authenticated, service_role;
grant execute on function public.list_effective_member_staff_notes(uuid) to authenticated, service_role;
grant execute on function public.list_effective_member_pinned_notes(uuid[]) to authenticated, service_role;
grant execute on function public.save_member_staff_note(uuid,text,boolean,uuid) to authenticated, service_role;
grant execute on function public.delete_member_staff_note(uuid) to authenticated, service_role;
