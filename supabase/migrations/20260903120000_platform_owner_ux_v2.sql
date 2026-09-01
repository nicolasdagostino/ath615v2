-- Platform Owner UX V2: read-only SaaS CRM aggregates.
-- Database usage is an exact record count across the explicitly enumerated
-- tenant-scoped operational tables below. It is not a physical byte estimate.

create function public.platform_gym_data_record_counts()
returns table(gym_id uuid,record_count bigint,total_tenant_record_count bigint)
language plpgsql stable security definer set search_path=public,pg_temp as $function$
#variable_conflict use_column
begin
  if not public.platform_owner_active() then
    raise exception using errcode='42501',message='platform_owner_required';
  end if;
  return query with records as (
    select gym_id,count(*)::bigint n from public.classes group by gym_id union all
    select gym_id,count(*)::bigint from public.gym_activity_events group by gym_id union all
    select gym_id,count(*)::bigint from public.gym_document_acceptances group by gym_id union all
    select gym_id,count(*)::bigint from public.gym_documents group by gym_id union all
    select gym_id,count(*)::bigint from public.gym_invitations group by gym_id union all
    select gym_id,count(*)::bigint from public.gym_join_requests group by gym_id union all
    select gym_id,count(*)::bigint from public.gym_members group by gym_id union all
    select gym_id,count(*)::bigint from public.member_memberships group by gym_id union all
    select gym_id,count(*)::bigint from public.member_staff_notes group by gym_id union all
    select gym_id,count(*)::bigint from public.membership_credit_logs group by gym_id union all
    select gym_id,count(*)::bigint from public.membership_legal_acceptances group by gym_id union all
    select gym_id,count(*)::bigint from public.membership_legal_documents group by gym_id union all
    select gym_id,count(*)::bigint from public.membership_plans group by gym_id union all
    select gym_id,count(*)::bigint from public.membership_requests group by gym_id union all
    select gym_id,count(*)::bigint from public.notifications group by gym_id union all
    select gym_id,count(*)::bigint from public.personal_records group by gym_id union all
    select gym_id,count(*)::bigint from public.programs group by gym_id union all
    select gym_id,count(*)::bigint from public.workouts group by gym_id union all
    select c.gym_id,count(*)::bigint from public.class_bookings b join public.classes c on c.id=b.class_id group by c.gym_id union all
    select c.gym_id,count(*)::bigint from public.class_waitlist w join public.classes c on c.id=w.class_id group by c.gym_id union all
    select w.gym_id,count(*)::bigint from public.workout_comments c join public.workouts w on w.id=c.workout_id group by w.gym_id union all
    select w.gym_id,count(*)::bigint from public.workout_likes l join public.workouts w on w.id=l.workout_id group by w.gym_id union all
    select d.gym_id,count(*)::bigint from public.gym_document_versions v join public.gym_documents d on d.id=v.document_id group by d.gym_id union all
    select r.gym_id,count(*)::bigint from public.membership_request_legal_acceptances a join public.membership_requests r on r.id=a.request_id group by r.gym_id
  ),per_gym as (
    select g.id gym_id,coalesce(sum(r.n),0)::bigint record_count
    from public.gyms g left join records r on r.gym_id=g.id group by g.id
  )
  select p.gym_id,p.record_count,sum(p.record_count) over()::bigint from per_gym p;
end $function$;

create function public.get_platform_owner_dashboard_v2()
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $function$
declare v_gyms jsonb;
begin
  if not public.platform_owner_active() then
    raise exception using errcode='42501',message='platform_owner_required';
  end if;
  with inactive as (
    select gm.gym_id,count(*) filter(where gm.role='athlete' and not gm.is_active) inactive_athletes
    from public.gym_members gm group by gm.gym_id
  ),class_counts as (
    select c.gym_id,count(*) classes from public.classes c group by c.gym_id
  ),booking_counts as (
    select c.gym_id,count(*) filter(where b.status<>'cancelled') bookings
    from public.class_bookings b join public.classes c on c.id=b.class_id group by c.gym_id
  ),pending as (
    select r.*,rp.name requested_plan_name,rp.monthly_price_eur requested_price_eur,
      rp.active_member_limit requested_member_limit
    from public.gym_saas_plan_change_requests r
    join public.saas_plans rp on rp.code=r.requested_plan_code where r.status='pending'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'gym_id',o.gym_id,'gym_name',o.gym_name,'lifecycle_status',o.lifecycle_status,
    'created_at',o.created_at,'last_activity_at',o.last_activity_at,
    'active_member_count',o.active_member_count,'active_athlete_count',o.saas_active_athlete_count,
    'inactive_athlete_count',coalesce(i.inactive_athletes,0),'admin_count',o.admin_count,
    'coach_count',o.coach_count,'active_membership_count',o.active_membership_count,
    'class_count',coalesce(cc.classes,0),'booking_count',coalesce(bc.bookings,0),
    'stripe_account_id',o.stripe_account_id,'stripe_onboarding_complete',o.stripe_onboarding_complete,
    'stripe_charges_enabled',o.stripe_charges_enabled,'stripe_payouts_enabled',o.stripe_payouts_enabled,
    'saas_plan_code',o.saas_plan_code,'saas_plan_name',o.saas_plan_name,
    'saas_monthly_price_eur',sp.monthly_price_eur,'saas_active_member_limit',o.saas_active_member_limit,
    'saas_active_athlete_count',o.saas_active_athlete_count,'saas_remaining_slots',o.saas_remaining_slots,
    'saas_limit_reached',o.saas_limit_reached,'saas_over_limit',o.saas_over_limit,
    'saas_plan_status',o.saas_plan_status,
    'capacity_percent',case when o.saas_active_member_limit is null then null when o.saas_active_member_limit=0 then 100
      else round(o.saas_active_athlete_count*100.0/o.saas_active_member_limit,1) end,
    'pending_plan_request',case when p.id is null then null else jsonb_build_object(
      'id',p.id,'gym_id',p.gym_id,'gym_name',o.gym_name,'current_plan_code',p.current_plan_code,
      'current_plan_name',o.saas_plan_name,'current_price_eur',sp.monthly_price_eur,
      'requested_plan_code',p.requested_plan_code,'requested_plan_name',p.requested_plan_name,
      'requested_price_eur',p.requested_price_eur,'requested_member_limit',p.requested_member_limit,
      'active_athlete_count',o.saas_active_athlete_count,'status',p.status,'requested_at',p.requested_at) end
  ) order by lower(o.gym_name),o.gym_id),'[]'::jsonb) into v_gyms
  from public.list_owner_gym_overview() o
  join public.saas_plans sp on sp.code=o.saas_plan_code
  left join inactive i on i.gym_id=o.gym_id left join class_counts cc on cc.gym_id=o.gym_id
  left join booking_counts bc on bc.gym_id=o.gym_id left join pending p on p.gym_id=o.gym_id;

  return jsonb_build_object(
    'summary',jsonb_build_object(
      'gym_count',jsonb_array_length(v_gyms),
      'active_gym_count',(select count(*) from jsonb_array_elements(v_gyms) g where g->>'lifecycle_status'='active'),
      'active_athlete_count',(select coalesce(sum((g->>'active_athlete_count')::bigint),0) from jsonb_array_elements(v_gyms) g),
      'pending_plan_request_count',(select count(*) from jsonb_array_elements(v_gyms) g where g->'pending_plan_request'<>'null'::jsonb),
      'suspended_gym_count',(select count(*) from jsonb_array_elements(v_gyms) g where g->>'lifecycle_status'='suspended'),
      'archived_gym_count',(select count(*) from jsonb_array_elements(v_gyms) g where g->>'lifecycle_status'='archived')
    ),'gyms',v_gyms
  );
end $function$;

create function public.get_platform_gym_crm_v2(p_gym_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $function$
declare v_dashboard jsonb; v_gym jsonb; v_contact jsonb; v_admins jsonb; v_records record;
begin
  if not public.platform_owner_active() then
    raise exception using errcode='42501',message='platform_owner_required';
  end if;
  v_dashboard:=public.get_platform_owner_dashboard_v2();
  select g into v_gym from jsonb_array_elements(v_dashboard->'gyms') g where g->>'gym_id'=p_gym_id::text;
  if v_gym is null then raise exception using errcode='P0002',message='gym_not_found'; end if;
  select jsonb_build_object('phone',g.phone,'email',g.email,'website',g.website,'address',g.address)
    into v_contact from public.gyms g where g.id=p_gym_id;
  select coalesce(jsonb_agg(jsonb_build_object('full_name',p.full_name,'email',p.email,'phone',p.phone)
    order by lower(coalesce(p.full_name,'')),p.id),'[]'::jsonb) into v_admins
  from public.gym_members gm join public.profiles p on p.id=gm.user_id
  where gm.gym_id=p_gym_id and gm.role='admin' and gm.is_active;
  select * into v_records from public.platform_gym_data_record_counts() r where r.gym_id=p_gym_id;
  return v_gym||jsonb_build_object('contact',v_contact,'admins',v_admins,
    'database_record_count',coalesce(v_records.record_count,0),
    'database_record_share_percent',case when coalesce(v_records.total_tenant_record_count,0)=0 then 0
      else round(coalesce(v_records.record_count,0)*100.0/v_records.total_tenant_record_count,1) end,
    'storage_attribution_available',false);
end $function$;

revoke all on function public.platform_gym_data_record_counts() from public,anon,authenticated,service_role;
revoke all on function public.get_platform_owner_dashboard_v2() from public,anon,authenticated,service_role;
revoke all on function public.get_platform_gym_crm_v2(uuid) from public,anon,authenticated,service_role;
grant execute on function public.get_platform_owner_dashboard_v2(),public.get_platform_gym_crm_v2(uuid) to authenticated;

comment on function public.platform_gym_data_record_counts() is
  'Platform-only exact record counts across the enumerated tenant dataset; not physical database bytes.';
comment on function public.get_platform_owner_dashboard_v2() is
  'Single Platform Owner dashboard aggregate; no per-gym client queries.';
comment on function public.get_platform_gym_crm_v2(uuid) is
  'Single Platform Owner CRM detail aggregate with minimized gym/admin contact data.';
