-- Membership Operations V1: auditable void/cancel and expiration changes.

begin;

alter table public.member_memberships
  add column if not exists credits_total integer;

update public.member_memberships mm
set credits_total = case when mp.plan_type = 'class_pack' then mp.credits else null end
from public.membership_plans mp
where mp.id = mm.plan_id and mm.credits_total is null;

alter table public.member_memberships
  drop constraint if exists member_memberships_credits_total_nonnegative_check;
alter table public.member_memberships
  add constraint member_memberships_credits_total_nonnegative_check
  check (credits_total is null or credits_total >= 0);

alter table public.member_memberships
  drop constraint if exists member_memberships_status_check;
alter table public.member_memberships
  add constraint member_memberships_status_check
  check (status in ('active','scheduled','exhausted','expired','cancelled','voided','replaced'));

alter table public.member_memberships
  drop constraint if exists member_memberships_status_active_consistency_check;
alter table public.member_memberships
  add constraint member_memberships_status_active_consistency_check
  check (
    (status in ('active','scheduled') and is_active = true)
    or (status in ('exhausted','expired','cancelled','voided','replaced') and is_active = false)
  );

create or replace function public.snapshot_member_membership_credits_total()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_type text; v_credits integer;
begin
  select plan_type, credits into v_type, v_credits
  from public.membership_plans where id = new.plan_id;
  if not found then return new; end if;
  new.credits_total := case when v_type = 'class_pack' then v_credits else null end;
  return new;
end;
$$;

drop trigger if exists snapshot_member_membership_credits_total_trigger
on public.member_memberships;
create trigger snapshot_member_membership_credits_total_trigger
before insert on public.member_memberships
for each row execute function public.snapshot_member_membership_credits_total();

create table public.membership_admin_events (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  membership_id uuid not null references public.member_memberships(id) on delete restrict,
  user_id uuid not null references public.profiles(id) on delete restrict,
  operation_type text not null check (operation_type in ('void','cancel','expiration_change')),
  reason_code text not null,
  reason_note text,
  performed_by uuid not null references public.profiles(id) on delete restrict,
  performed_at timestamptz not null default clock_timestamp(),
  old_status text not null,
  new_status text not null,
  old_is_active boolean not null,
  new_is_active boolean not null,
  old_expires_at timestamptz,
  new_expires_at timestamptz,
  old_credits_remaining integer,
  new_credits_remaining integer,
  cancelled_booking_count integer not null default 0 check (cancelled_booking_count >= 0),
  metadata jsonb not null default '{}'::jsonb,
  check (reason_note is null or length(reason_note) <= 1000),
  check (
    (operation_type = 'void' and reason_code in ('assigned_by_mistake','requested_by_mistake','plan_change','other'))
    or (operation_type = 'cancel' and reason_code in ('member_request','injury','plan_change','administrative','other'))
    or (operation_type = 'expiration_change' and reason_code in ('injury','gym_closure','commercial_extension','administrative_correction','other'))
  ),
  check (reason_code <> 'other' or length(btrim(coalesce(reason_note,''))) >= 2)
);

create index membership_admin_events_membership_performed_idx
on public.membership_admin_events(membership_id, performed_at desc, id desc);
create index membership_admin_events_gym_performed_idx
on public.membership_admin_events(gym_id, performed_at desc, id desc);
create index class_bookings_membership_future_status_idx
on public.class_bookings(membership_id, status, class_id)
where membership_id is not null and status = 'booked';

alter table public.membership_admin_events enable row level security;
revoke all on public.membership_admin_events from public, anon, authenticated;
grant select on public.membership_admin_events to authenticated;
create policy "effective membership managers read admin events"
on public.membership_admin_events for select to authenticated
using (gym_id = public.effective_gym_id() and public.membership_actor_can_manage());

alter table public.gym_activity_events drop constraint if exists gym_activity_events_kind_check;
alter table public.gym_activity_events add constraint gym_activity_events_kind_check check (kind in (
  'booking','booking_cancelled','attendance','no_show','waitlist_joined',
  'membership_assigned','membership_requested','membership_voided',
  'membership_cancelled','membership_expiration_changed','workout_comment',
  'workout_like','guest_added','guest_cancelled'
));
alter table public.gym_activity_events drop constraint if exists gym_activity_events_source_table_check;
alter table public.gym_activity_events add constraint gym_activity_events_source_table_check check (source_table in (
  'class_bookings','class_waitlist','member_memberships','membership_requests',
  'membership_admin_events','workout_comments','workout_likes'
));

create function public.get_member_membership_operation_preview(
  p_membership_id uuid,
  p_new_expires_at timestamptz default null
) returns jsonb language plpgsql stable security definer
set search_path = public, pg_temp as $$
declare
  v_gym_id uuid := public.effective_gym_id();
  v_membership public.member_memberships%rowtype;
  v_plan public.membership_plans%rowtype;
  v_attended integer; v_no_show integer; v_future integer; v_conflicting integer;
  v_bookings jsonb; v_chained boolean;
begin
  if auth.uid() is null or v_gym_id is null or not public.membership_actor_can_manage() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  select * into v_membership from public.member_memberships
  where id = p_membership_id and gym_id = v_gym_id;
  if not found then raise exception 'membership_not_found' using errcode = 'P0002'; end if;
  select * into v_plan from public.membership_plans
  where id = v_membership.plan_id and gym_id = v_gym_id;
  if not found then raise exception 'plan_not_found' using errcode = 'P0002'; end if;

  select count(*) filter(where cb.status = 'attended'),
    count(*) filter(where cb.status = 'no_show'),
    count(*) filter(where cb.status = 'booked' and c.starts_at > clock_timestamp()),
    count(*) filter(where cb.status = 'booked' and p_new_expires_at is not null
      and c.starts_at >= p_new_expires_at)
  into v_attended, v_no_show, v_future, v_conflicting
  from public.class_bookings cb join public.classes c on c.id = cb.class_id
  where cb.membership_id = v_membership.id and c.gym_id = v_gym_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'booking_id', x.booking_id, 'class_id', x.class_id,
    'title', x.title, 'starts_at', x.starts_at
  ) order by x.starts_at), '[]'::jsonb) into v_bookings
  from (
    select cb.id booking_id, c.id class_id, c.title, c.starts_at
    from public.class_bookings cb join public.classes c on c.id = cb.class_id
    where cb.membership_id = v_membership.id and cb.status = 'booked'
      and c.gym_id = v_gym_id and c.starts_at > clock_timestamp()
      and (p_new_expires_at is null or c.starts_at >= p_new_expires_at)
    order by c.starts_at limit 50
  ) x;

  v_chained := v_plan.plan_type = 'unlimited' and exists(
    select 1 from public.member_memberships next_mm
    join public.membership_plans next_mp on next_mp.id = next_mm.plan_id
    where next_mm.user_id = v_membership.user_id and next_mm.gym_id = v_gym_id
      and next_mm.id <> v_membership.id and next_mm.status = 'scheduled'
      and next_mm.is_active and next_mp.plan_type = 'unlimited'
      and coalesce(next_mm.starts_at, next_mm.created_at) > coalesce(v_membership.starts_at, v_membership.created_at)
  );

  return jsonb_build_object(
    'membership_id', v_membership.id, 'plan_id', v_plan.id,
    'plan_name', v_plan.name, 'plan_type', v_plan.plan_type,
    'status', v_membership.status, 'is_active', v_membership.is_active,
    'starts_at', v_membership.starts_at,
    'expires_at', coalesce(v_membership.expires_at, v_membership.ends_at),
    'credits_remaining', v_membership.credits_remaining,
    'credits_total', v_membership.credits_total,
    'attended_count', coalesce(v_attended,0), 'no_show_count', coalesce(v_no_show,0),
    'future_booked_count', coalesce(v_future,0),
    'conflicting_booking_count', coalesce(v_conflicting,0),
    'future_bookings', v_bookings, 'has_chained_unlimited', v_chained
  );
end;
$$;

create function public.cancel_membership_future_bookings(
  p_membership_id uuid,
  p_gym_id uuid,
  p_not_before timestamptz default null
) returns integer language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_booking record; v_membership public.member_memberships%rowtype; v_count integer := 0;
begin
  select * into v_membership from public.member_memberships
  where id = p_membership_id and gym_id = p_gym_id for update;
  if not found then raise exception 'membership_not_found' using errcode = 'P0002'; end if;
  for v_booking in
    select cb.id, cb.class_id from public.class_bookings cb
    join public.classes c on c.id = cb.class_id
    where cb.membership_id = v_membership.id and cb.status = 'booked'
      and c.gym_id = p_gym_id and c.starts_at > clock_timestamp()
      and (p_not_before is null or c.starts_at >= p_not_before)
    order by c.starts_at, cb.id for update of cb
  loop
    update public.class_bookings set status = 'cancelled'
    where id = v_booking.id and status = 'booked';
    if found then
      v_count := v_count + 1;
      if v_membership.credits_remaining is not null then
        update public.member_memberships set credits_remaining = credits_remaining + 1
        where id = v_membership.id;
        v_membership.credits_remaining := v_membership.credits_remaining + 1;
        insert into public.membership_credit_logs(user_id,gym_id,membership_id,amount,reason,class_id)
        values(v_membership.user_id,p_gym_id,v_membership.id,1,'cancelled',v_booking.class_id);
      end if;
      -- Defensive cleanup for legacy/racy data: the cancelled member must not
      -- be immediately re-promoted for the same class.
      delete from public.class_waitlist
      where class_id = v_booking.class_id and user_id = v_membership.user_id;
      perform public.promote_first_waitlisted_user(v_booking.class_id);
    end if;
  end loop;
  return v_count;
end;
$$;

create function public.record_membership_admin_event(
  p_membership public.member_memberships,
  p_operation text, p_reason text, p_note text,
  p_new_status text, p_new_active boolean, p_new_expires timestamptz,
  p_new_credits integer, p_cancelled_count integer
) returns uuid language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_id uuid;
begin
  insert into public.membership_admin_events(
    gym_id,membership_id,user_id,operation_type,reason_code,reason_note,performed_by,
    old_status,new_status,old_is_active,new_is_active,old_expires_at,new_expires_at,
    old_credits_remaining,new_credits_remaining,cancelled_booking_count
  ) values(
    p_membership.gym_id,p_membership.id,p_membership.user_id,p_operation,p_reason,
    nullif(btrim(coalesce(p_note,'')),''),auth.uid(),p_membership.status,p_new_status,
    p_membership.is_active,p_new_active,coalesce(p_membership.expires_at,p_membership.ends_at),
    p_new_expires,p_membership.credits_remaining,p_new_credits,p_cancelled_count
  ) returning id into v_id;
  insert into public.gym_activity_events(
    gym_id,kind,source_table,source_ref,occurred_at,member_id,membership_id
  ) values(
    p_membership.gym_id,
    case p_operation when 'void' then 'membership_voided'
      when 'cancel' then 'membership_cancelled' else 'membership_expiration_changed' end,
    'membership_admin_events',v_id::text,clock_timestamp(),p_membership.user_id,p_membership.id
  );
  return v_id;
end;
$$;

create function public.void_member_membership(
  p_membership_id uuid, p_reason text, p_reason_note text default null
) returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_gym_id uuid := public.effective_gym_id(); v_old public.member_memberships%rowtype;
  v_used integer; v_cancelled integer; v_new_credits integer; v_event uuid;
begin
  if auth.uid() is null or v_gym_id is null or not public.membership_actor_can_manage() then
    raise exception 'forbidden' using errcode='42501'; end if;
  if p_reason not in ('assigned_by_mistake','requested_by_mistake','plan_change','other')
    or (p_reason='other' and length(btrim(coalesce(p_reason_note,'')))<2)
    or length(coalesce(p_reason_note,''))>1000 then
    raise exception 'invalid_reason' using errcode='22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_membership_id::text,617));
  select * into v_old from public.member_memberships
  where id=p_membership_id and gym_id=v_gym_id for update;
  if not found then raise exception 'membership_not_found' using errcode='P0002'; end if;
  if v_old.status='voided' then return jsonb_build_object('membership_id',v_old.id,'status','voided','already_applied',true); end if;
  if v_old.status in ('cancelled','replaced') then raise exception 'membership_terminal' using errcode='P0001'; end if;
  select count(*) into v_used from public.class_bookings
  where membership_id=v_old.id and status in ('attended','no_show');
  if v_used>0 then raise exception 'membership_has_usage' using errcode='P0001'; end if;
  update public.member_memberships set status='voided',is_active=false where id=v_old.id;
  v_cancelled := public.cancel_membership_future_bookings(v_old.id,v_gym_id,null);
  select credits_remaining into v_new_credits from public.member_memberships where id=v_old.id;
  v_event := public.record_membership_admin_event(v_old,'void',p_reason,p_reason_note,
    'voided',false,coalesce(v_old.expires_at,v_old.ends_at),v_new_credits,v_cancelled);
  return jsonb_build_object('membership_id',v_old.id,'status','voided',
    'cancelled_booking_count',v_cancelled,'event_id',v_event,'already_applied',false);
end;
$$;

create function public.cancel_member_membership(
  p_membership_id uuid, p_reason text, p_reason_note text default null
) returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_gym_id uuid := public.effective_gym_id(); v_old public.member_memberships%rowtype;
  v_cancelled integer; v_new_credits integer; v_event uuid;
begin
  if auth.uid() is null or v_gym_id is null or not public.membership_actor_can_manage() then
    raise exception 'forbidden' using errcode='42501'; end if;
  if p_reason not in ('member_request','injury','plan_change','administrative','other')
    or (p_reason='other' and length(btrim(coalesce(p_reason_note,'')))<2)
    or length(coalesce(p_reason_note,''))>1000 then
    raise exception 'invalid_reason' using errcode='22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_membership_id::text,617));
  select * into v_old from public.member_memberships
  where id=p_membership_id and gym_id=v_gym_id for update;
  if not found then raise exception 'membership_not_found' using errcode='P0002'; end if;
  if v_old.status='cancelled' then return jsonb_build_object('membership_id',v_old.id,'status','cancelled','already_applied',true); end if;
  if v_old.status in ('voided','replaced','expired') then raise exception 'membership_terminal' using errcode='P0001'; end if;
  update public.member_memberships set status='cancelled',is_active=false where id=v_old.id;
  v_cancelled := public.cancel_membership_future_bookings(v_old.id,v_gym_id,null);
  select credits_remaining into v_new_credits from public.member_memberships where id=v_old.id;
  v_event := public.record_membership_admin_event(v_old,'cancel',p_reason,p_reason_note,
    'cancelled',false,coalesce(v_old.expires_at,v_old.ends_at),v_new_credits,v_cancelled);
  return jsonb_build_object('membership_id',v_old.id,'status','cancelled',
    'cancelled_booking_count',v_cancelled,'event_id',v_event,'already_applied',false);
end;
$$;

create function public.change_member_membership_expiration(
  p_membership_id uuid, p_new_expires_at timestamptz, p_reason text,
  p_reason_note text default null, p_cancel_conflicting_bookings boolean default false
) returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_gym_id uuid := public.effective_gym_id(); v_old public.member_memberships%rowtype;
  v_plan public.membership_plans%rowtype; v_conflicts integer; v_cancelled integer:=0;
  v_new_status text; v_new_active boolean; v_event uuid;
begin
  if auth.uid() is null or v_gym_id is null or not public.membership_actor_can_manage() then
    raise exception 'forbidden' using errcode='42501'; end if;
  if p_reason not in ('injury','gym_closure','commercial_extension','administrative_correction','other')
    or (p_reason='other' and length(btrim(coalesce(p_reason_note,'')))<2)
    or length(coalesce(p_reason_note,''))>1000 then
    raise exception 'invalid_reason' using errcode='22023'; end if;
  if p_new_expires_at is null or p_new_expires_at<=clock_timestamp() then
    raise exception 'expiration_must_be_future' using errcode='22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_membership_id::text,617));
  select * into v_old from public.member_memberships
  where id=p_membership_id and gym_id=v_gym_id for update;
  if not found then raise exception 'membership_not_found' using errcode='P0002'; end if;
  if v_old.status in ('cancelled','voided','replaced') then raise exception 'membership_terminal' using errcode='P0001'; end if;
  if p_new_expires_at<=coalesce(v_old.starts_at,v_old.created_at) then
    raise exception 'expiration_before_start' using errcode='22023'; end if;
  if p_new_expires_at=coalesce(v_old.expires_at,v_old.ends_at) then
    raise exception 'expiration_unchanged' using errcode='22023'; end if;
  select * into v_plan from public.membership_plans where id=v_old.plan_id and gym_id=v_gym_id;
  if not found then raise exception 'plan_not_found' using errcode='P0002'; end if;
  if v_plan.plan_type='unlimited' and exists(
    select 1 from public.member_memberships n join public.membership_plans np on np.id=n.plan_id
    where n.user_id=v_old.user_id and n.gym_id=v_gym_id and n.id<>v_old.id
      and n.status='scheduled' and n.is_active and np.plan_type='unlimited'
      and coalesce(n.starts_at,n.created_at)>coalesce(v_old.starts_at,v_old.created_at)
  ) then raise exception 'scheduled_unlimited_chain_conflict' using errcode='P0001'; end if;
  select count(*) into v_conflicts from public.class_bookings cb join public.classes c on c.id=cb.class_id
  where cb.membership_id=v_old.id and cb.status='booked' and c.gym_id=v_gym_id
    and c.starts_at>=p_new_expires_at;
  if v_conflicts>0 and not p_cancel_conflicting_bookings then
    raise exception 'future_bookings_conflict' using errcode='P0001'; end if;
  if v_conflicts>0 then
    v_cancelled:=public.cancel_membership_future_bookings(v_old.id,v_gym_id,p_new_expires_at);
  end if;
  if v_old.status='expired' then
    if v_plan.plan_type='unlimited' then v_new_status:='active';v_new_active:=true;
    elsif coalesce(v_old.credits_remaining,0)>0 then v_new_status:='active';v_new_active:=true;
    else v_new_status:='exhausted';v_new_active:=false; end if;
  else v_new_status:=v_old.status;v_new_active:=v_old.is_active; end if;
  update public.member_memberships set expires_at=p_new_expires_at,ends_at=p_new_expires_at,
    status=v_new_status,is_active=v_new_active where id=v_old.id;
  v_event:=public.record_membership_admin_event(v_old,'expiration_change',p_reason,p_reason_note,
    v_new_status,v_new_active,p_new_expires_at,
    (select credits_remaining from public.member_memberships where id=v_old.id),v_cancelled);
  return jsonb_build_object('membership_id',v_old.id,'status',v_new_status,
    'expires_at',p_new_expires_at,'cancelled_booking_count',v_cancelled,
    'reactivated',v_old.status='expired' and v_new_status='active','event_id',v_event);
end;
$$;

revoke all on function public.snapshot_member_membership_credits_total(),
  public.cancel_membership_future_bookings(uuid,uuid,timestamptz),
  public.record_membership_admin_event(public.member_memberships,text,text,text,text,boolean,timestamptz,integer,integer)
from public,anon,authenticated;
revoke all on function public.get_member_membership_operation_preview(uuid,timestamptz),
  public.void_member_membership(uuid,text,text),public.cancel_member_membership(uuid,text,text),
  public.change_member_membership_expiration(uuid,timestamptz,text,text,boolean)
from public,anon,authenticated;
grant execute on function public.get_member_membership_operation_preview(uuid,timestamptz),
  public.void_member_membership(uuid,text,text),public.cancel_member_membership(uuid,text,text),
  public.change_member_membership_expiration(uuid,timestamptz,text,text,boolean)
to authenticated;

commit;
