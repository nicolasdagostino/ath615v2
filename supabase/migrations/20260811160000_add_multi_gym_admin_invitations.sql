-- Vertical 3G2: persistent, idempotent Owner invitations for gym admins.

create table if not exists public.gym_invitations (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  email_normalized text not null,
  full_name text,
  role text not null default 'admin' check (role='admin'),
  is_coach boolean not null default false,
  status text not null check (status in ('dispatching','accepted','failed')),
  invited_by uuid not null references public.profiles(id) on delete restrict,
  invited_user_id uuid references public.profiles(id) on delete set null,
  accepted_by uuid references public.profiles(id) on delete set null,
  dispatch_started_at timestamptz,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint gym_invitations_email_normalized_check check (
    email_normalized=btrim(lower(email_normalized))
    and length(email_normalized) between 3 and 254
  ),
  constraint gym_invitations_gym_email_role_key unique(gym_id,email_normalized,role)
);
create index if not exists gym_invitations_invited_user_idx
on public.gym_invitations(invited_user_id,gym_id);
alter table public.gym_invitations enable row level security;
revoke all on table public.gym_invitations from public,anon,authenticated;
grant all on table public.gym_invitations to service_role;
create or replace function public.apply_gym_admin_invitation_relation(
  p_invitation_id uuid,
  p_user_id uuid
)
returns text
language plpgsql security definer
set search_path=public,pg_temp
as $function$
declare
  v_invitation public.gym_invitations%rowtype;
  v_member public.gym_members%rowtype;
  v_action text;
begin
  select * into v_invitation from public.gym_invitations i
  where i.id=p_invitation_id for update;
  if not found then raise exception using errcode='P0001',message='invitation_not_found'; end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user_id::text||':'||v_invitation.gym_id::text,617)
  );

  select * into v_member from public.gym_members gm
  where gm.gym_id=v_invitation.gym_id and gm.user_id=p_user_id for update;
  if not found then
    v_action:='existing_added';
    insert into public.gym_members(gym_id,user_id,role,is_active,is_coach,joined_at,invited_by)
    values(v_invitation.gym_id,p_user_id,'admin',true,false,now(),v_invitation.invited_by)
    on conflict(gym_id,user_id) do update set
      role='admin',is_active=true,
      is_coach=(public.gym_members.is_coach or public.gym_members.role='coach'),
      invited_by=v_invitation.invited_by,updated_at=now();
  else
    v_action:=case
      when v_member.role='admin' and v_member.is_active then 'already_admin'
      when not v_member.is_active then 'reactivated'
      else 'promoted'
    end;
    update public.gym_members set
      role='admin',
      is_active=true,
      is_coach=(v_member.is_coach or v_member.role='coach'),
      invited_by=v_invitation.invited_by,
      updated_at=now()
    where gym_id=v_invitation.gym_id and user_id=p_user_id;
  end if;

  update public.gym_join_requests set
    status='approved',approved_at=coalesce(approved_at,now()),approved_by=v_invitation.invited_by
  where gym_id=v_invitation.gym_id and user_id=p_user_id and status='pending';

  update public.profiles p set
    gym_id=case when p.gym_id is null then v_invitation.gym_id else p.gym_id end,
    role=case when p.gym_id is null and coalesce(p.role,'athlete')<>'owner' then 'admin' else p.role end,
    is_active=case when p.gym_id is null then true else p.is_active end
  where p.id=p_user_id;

  update public.gym_invitations set
    status='accepted',invited_user_id=p_user_id,accepted_by=p_user_id,
    accepted_at=coalesce(accepted_at,now()),updated_at=now()
  where id=v_invitation.id;
  return v_action;
end;
$function$;
create or replace function public.prepare_owner_admin_invitation(
  p_actor_id uuid,
  p_gym_id uuid,
  p_email text,
  p_full_name text default null
)
returns table(invitation_id uuid,result text,user_id uuid)
language plpgsql security definer
set search_path=public,pg_temp
as $function$
declare
  v_email text:=lower(btrim(coalesce(p_email,'')));
  v_name text:=nullif(btrim(coalesce(p_full_name,'')),'');
  v_invitation public.gym_invitations%rowtype;
  v_user_id uuid;
  v_result text;
  v_changed boolean;
  v_invitation_exists boolean:=false;
begin
  if p_actor_id is null or p_gym_id is null or v_email='' or length(v_email)>254
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    or (v_name is not null and length(v_name)>100)
  then raise exception using errcode='P0001',message='invalid_request'; end if;

  if not exists(
    select 1 from public.profiles p join public.gyms g on g.id=p_gym_id
    where p.id=p_actor_id and p.role='owner' and p.is_active and g.owner_id=p_actor_id
  ) then raise exception using errcode='42501',message='forbidden'; end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_gym_id::text||':'||v_email,619)
  );

  select u.id into v_user_id from auth.users u
  where lower(btrim(u.email))=v_email order by u.created_at limit 1;
  if v_user_id is not null then
    insert into public.profiles(id,email,full_name,role,is_active,is_coach)
    values(v_user_id,v_email,coalesce(v_name,v_email),'athlete',true,false)
    on conflict(id) do update set
      email=coalesce(public.profiles.email,excluded.email),
      full_name=coalesce(public.profiles.full_name,excluded.full_name);
  end if;

  select * into v_invitation from public.gym_invitations i
  where i.gym_id=p_gym_id and i.email_normalized=v_email and i.role='admin'
  for update;
  v_invitation_exists:=found;
  if v_invitation_exists then
    update public.gym_invitations set
      full_name=coalesce(v_name,full_name),invited_by=p_actor_id,updated_at=clock_timestamp()
    where id=v_invitation.id returning * into v_invitation;
  else
    insert into public.gym_invitations(
      gym_id,email_normalized,full_name,role,status,invited_by,dispatch_started_at,
      invited_user_id,accepted_by,accepted_at
    ) values(
      p_gym_id,v_email,v_name,'admin',
      case when v_user_id is null then 'dispatching' else 'accepted' end,
      p_actor_id,case when v_user_id is null then clock_timestamp() else null end,
      v_user_id,case when v_user_id is null then null else v_user_id end,
      case when v_user_id is null then null else clock_timestamp() end
    ) returning * into v_invitation;
  end if;

  if v_user_id is not null then
    v_result:=public.apply_gym_admin_invitation_relation(v_invitation.id,v_user_id);
    v_changed:=v_result<>'already_admin';
    if v_changed then
      insert into public.notifications(user_id,gym_id,title,body,type,data,scheduled_for)
      values(v_user_id,p_gym_id,'Administrator access',
        'You were added as an administrator of a gym.','gym_admin_added',
        jsonb_build_object('gymId',p_gym_id,'invitationId',v_invitation.id),now());
    end if;
    return query select v_invitation.id,v_result,v_user_id;
    return;
  end if;

  if v_invitation.status='accepted' then
    return query select v_invitation.id,'already_admin'::text,v_invitation.invited_user_id;
    return;
  elsif v_invitation.status='dispatching'
    and v_invitation_exists
    and v_invitation.dispatch_started_at is not null
    and v_invitation.dispatch_started_at>clock_timestamp()-interval '5 minutes'
  then
    return query select v_invitation.id,'invite_in_progress'::text,null::uuid;
    return;
  end if;

  update public.gym_invitations set status='dispatching',dispatch_started_at=clock_timestamp(),updated_at=clock_timestamp()
  where id=v_invitation.id;
  return query select v_invitation.id,'send_new_user'::text,null::uuid;
end;
$function$;
create or replace function public.materialize_owner_admin_invitation(
  p_invitation_id uuid,
  p_user_id uuid
)
returns text
language plpgsql security definer
set search_path=public,pg_temp
as $function$
declare
  v_invitation public.gym_invitations%rowtype;
  v_auth_email text;
begin
  select * into v_invitation from public.gym_invitations i where i.id=p_invitation_id for update;
  if not found then raise exception using errcode='P0001',message='invitation_not_found'; end if;
  select lower(btrim(u.email)) into v_auth_email from auth.users u where u.id=p_user_id;
  if v_auth_email is null or v_auth_email<>v_invitation.email_normalized then
    raise exception using errcode='42501',message='invitation_identity_mismatch';
  end if;
  insert into public.profiles(id,email,full_name,role,is_active,is_coach)
  values(p_user_id,v_auth_email,coalesce(v_invitation.full_name,v_auth_email),'athlete',true,false)
  on conflict(id) do update set
    email=coalesce(public.profiles.email,excluded.email),
    full_name=coalesce(public.profiles.full_name,excluded.full_name);
  return public.apply_gym_admin_invitation_relation(p_invitation_id,p_user_id);
end;
$function$;
create or replace function public.fail_owner_admin_invitation(
  p_actor_id uuid,
  p_invitation_id uuid
)
returns void
language plpgsql security definer
set search_path=public,pg_temp
as $function$
begin
  update public.gym_invitations i set status='failed',updated_at=now()
  from public.gyms g,public.profiles p
  where i.id=p_invitation_id and g.id=i.gym_id and g.owner_id=p_actor_id
    and p.id=p_actor_id and p.role='owner' and p.is_active
    and i.status='dispatching';
  if not found then raise exception using errcode='42501',message='forbidden'; end if;
end;
$function$;
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
set search_path=public,pg_temp
as $function$
declare v_invitation_id uuid;
begin
  insert into public.profiles(id,email,full_name,role,gym_id,phone,birth_date)
  values(
    new.id,new.email,
    nullif(trim(coalesce(new.raw_user_meta_data->>'full_name',new.email)),''),
    coalesce(new.raw_user_meta_data->>'role','athlete'),
    nullif(new.raw_user_meta_data->>'gym_id','')::uuid,
    nullif(trim(new.raw_user_meta_data->>'phone'),''),
    nullif(new.raw_user_meta_data->>'birth_date','')::date
  )
  on conflict(id) do update set
    email=excluded.email,full_name=excluded.full_name,role=excluded.role,
    gym_id=excluded.gym_id,phone=excluded.phone,birth_date=excluded.birth_date;

  for v_invitation_id in
    select i.id from public.gym_invitations i
    where i.email_normalized=lower(btrim(new.email)) and i.status in ('dispatching','failed')
    order by i.created_at,i.id
  loop
    perform public.materialize_owner_admin_invitation(v_invitation_id,new.id);
  end loop;
  return new;
end;
$function$;
-- An Owner invitation has higher priority than a concurrent athlete Join approval.
create or replace function public.approve_gym_join_request(p_request_id uuid)
returns void language plpgsql security definer
set search_path=public,pg_temp
as $function$
declare
  v_gym_id uuid:=public.effective_gym_id(); v_request public.gym_join_requests%rowtype;
  v_gym_name text; v_is_web boolean:=public.is_registered_web_session();
begin
  if auth.uid() is null then raise exception using errcode='P0001',message='unauthenticated'; end if;
  if v_gym_id is null or not (public.effective_gym_role()='admin' or (
    not v_is_web and public.effective_gym_role()='owner'
  )) then raise exception using errcode='42501',message='forbidden'; end if;
  select * into v_request from public.gym_join_requests r where r.id=p_request_id;
  if not found or v_request.gym_id is distinct from v_gym_id then
    raise exception using errcode='P0001',message='request_not_found';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_request.user_id::text||':'||v_request.gym_id::text,617)
  );
  select * into v_request from public.gym_join_requests r where r.id=p_request_id for update;
  if v_request.status='approved' then return; end if;
  if v_request.status<>'pending' then raise exception using errcode='P0001',message='request_resolved'; end if;
  insert into public.gym_members(gym_id,user_id,role,is_active,is_coach,joined_at,invited_by)
  values(v_gym_id,v_request.user_id,'athlete',true,false,now(),auth.uid())
  on conflict(gym_id,user_id) do update set
    role=case when public.gym_members.role='admin' then 'admin' else 'athlete' end,
    is_active=true,
    is_coach=(public.gym_members.is_coach or public.gym_members.role='coach');
  if not v_is_web then
    update public.profiles set gym_id=v_gym_id,role='athlete',is_active=true,is_coach=false
    where id=v_request.user_id;
  end if;
  update public.gym_join_requests set status='approved',approved_at=now(),approved_by=auth.uid()
  where id=v_request.id;
  select g.name into v_gym_name from public.gyms g where g.id=v_gym_id;
  insert into public.notifications(user_id,gym_id,title,body,type,data,scheduled_for)
  values(v_request.user_id,v_gym_id,'🎉 Welcome!',format('You now have access to %s.',coalesce(v_gym_name,'your gym')),
    'gym_join_approved',jsonb_build_object('gymId',v_gym_id,'requestId',v_request.id),now());
end;
$function$;
create or replace function public.set_notification_gym_id()
returns trigger language plpgsql security definer
set search_path=public,pg_temp
as $function$
begin
  if new.type='workout_published' then
    select w.gym_id into new.gym_id from public.workouts w where w.id::text=new.data->>'workoutId';
    if new.gym_id is null then raise exception 'invalid_notification_origin'; end if; return new;
  end if;
  if new.type='waitlist_promoted' then
    select c.gym_id into new.gym_id from public.classes c where c.id::text=new.data->>'classId';
    if new.gym_id is null then raise exception 'invalid_notification_origin'; end if; return new;
  end if;
  if new.type in ('membership_scheduled','membership_approved','membership_payment_completed') and new.data?'requestId' then
    select mr.gym_id into new.gym_id from public.membership_requests mr where mr.id::text=new.data->>'requestId';
    if new.gym_id is null then raise exception 'invalid_notification_origin'; end if; return new;
  end if;
  if new.type in ('gym_join_approved','gym_join_rejected') and new.data?'requestId' then
    select r.gym_id into new.gym_id from public.gym_join_requests r where r.id::text=new.data->>'requestId';
    if new.gym_id is null then raise exception 'invalid_notification_origin'; end if; return new;
  end if;
  if new.type='gym_admin_added' and new.data?'invitationId' then
    select i.gym_id into new.gym_id from public.gym_invitations i where i.id::text=new.data->>'invitationId';
    if new.gym_id is null then raise exception 'invalid_notification_origin'; end if; return new;
  end if;
  select p.gym_id into new.gym_id from public.profiles p where p.id=new.user_id;
  return new;
end;
$function$;
revoke all on function public.apply_gym_admin_invitation_relation(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function public.handle_new_user() from public,anon,authenticated,service_role;
revoke all on function public.set_notification_gym_id() from public,anon,authenticated,service_role;
revoke all on function public.prepare_owner_admin_invitation(uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.materialize_owner_admin_invitation(uuid,uuid) from public,anon,authenticated;
revoke all on function public.fail_owner_admin_invitation(uuid,uuid) from public,anon,authenticated;
grant execute on function public.prepare_owner_admin_invitation(uuid,uuid,text,text) to service_role;
grant execute on function public.materialize_owner_admin_invitation(uuid,uuid) to service_role;
grant execute on function public.fail_owner_admin_invitation(uuid,uuid) to service_role;
