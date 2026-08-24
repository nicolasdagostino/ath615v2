-- Cancel classes atomically so cascades cannot discard charged bookings before
-- their memberships have been refunded. Both RPCs resolve the effective gym
-- and administrative authority server-side.

-- Authenticated clients must use the transactional RPC. Leaving the old
-- permissive DELETE policy in place would retain the cascade/refund bypass.
drop policy if exists "classes admins can delete" on public.classes;

create or replace function public.get_class_cancellation_impact(
  p_class_id uuid,
  p_scope text default 'single'
)
returns table(
  classes_count bigint,
  bookings_count bigint,
  waitlist_count bigint,
  credits_to_refund bigint
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
  v_class public.classes%rowtype;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'unauthenticated';
  end if;
  if p_class_id is null or p_scope not in ('single', 'future') then
    raise exception using errcode = '22023', message = 'invalid_request';
  end if;
  if v_gym_id is null or not (
    exists (
      select 1 from public.gym_members gm
      where gm.gym_id = v_gym_id
        and gm.user_id = auth.uid()
        and gm.role = 'admin'
        and gm.is_active = true
    )
    or exists (
      select 1 from public.gyms g
      where g.id = v_gym_id and g.owner_id = auth.uid()
    )
  ) then
    raise exception using errcode = '42501', message = 'forbidden';
  end if;

  select c.* into v_class
  from public.classes c
  where c.id = p_class_id and c.gym_id = v_gym_id;
  if not found then
    if exists (select 1 from public.classes c where c.id = p_class_id) then
      raise exception using errcode = '42501', message = 'forbidden';
    end if;
    return query select 0::bigint, 0::bigint, 0::bigint, 0::bigint;
    return;
  end if;
  if v_class.starts_at <= now() then
    raise exception using errcode = 'P0001', message = 'class_already_started';
  end if;

  return query
  with target_classes as (
    select c.id
    from public.classes c
    where c.gym_id = v_gym_id
      and c.starts_at > now()
      and (
        (p_scope = 'single' and c.id = v_class.id)
        or (
          p_scope = 'future'
          and (
            (v_class.recurring_id is null and c.id = v_class.id)
            or (
              v_class.recurring_id is not null
              and c.recurring_id = v_class.recurring_id
              and c.starts_at >= v_class.starts_at
            )
          )
        )
      )
  )
  select
    (select count(*) from target_classes),
    (select count(*) from public.class_bookings cb
      join target_classes tc on tc.id = cb.class_id
      where cb.status <> 'cancelled'),
    (select count(*) from public.class_waitlist cw
      join target_classes tc on tc.id = cw.class_id),
    (select count(*) from public.class_bookings cb
      join target_classes tc on tc.id = cb.class_id
      join public.member_memberships mm
        on mm.id = cb.membership_id
       and mm.user_id = cb.user_id
       and mm.gym_id = v_gym_id
      where cb.status = 'booked'
        and not coalesce(cb.is_guest, false)
        and cb.user_id is not null
        and mm.credits_remaining is not null);
end;
$function$;

create or replace function public.admin_cancel_class(
  p_class_id uuid,
  p_scope text default 'single'
)
returns table(
  classes_count bigint,
  bookings_count bigint,
  waitlist_count bigint,
  credits_refunded bigint
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_gym_id uuid := public.effective_gym_id();
  v_base public.classes%rowtype;
  v_class public.classes%rowtype;
  v_booking public.class_bookings%rowtype;
  v_waitlist public.class_waitlist%rowtype;
  v_membership public.member_memberships%rowtype;
  v_expiration timestamptz;
  v_program_name text;
  v_label text;
  v_locale text;
  v_refunded boolean;
  v_classes bigint := 0;
  v_bookings bigint := 0;
  v_waitlisted bigint := 0;
  v_credits bigint := 0;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'unauthenticated';
  end if;
  if p_class_id is null or p_scope not in ('single', 'future') then
    raise exception using errcode = '22023', message = 'invalid_request';
  end if;
  if v_gym_id is null or not (
    exists (
      select 1 from public.gym_members gm
      where gm.gym_id = v_gym_id
        and gm.user_id = auth.uid()
        and gm.role = 'admin'
        and gm.is_active = true
    )
    or exists (
      select 1 from public.gyms g
      where g.id = v_gym_id and g.owner_id = auth.uid()
    )
  ) then
    raise exception using errcode = '42501', message = 'forbidden';
  end if;

  -- The same class lock used by booking RPCs serializes cancellation against
  -- new bookings. A repeated cancellation safely returns zero after deletion.
  select c.* into v_base
  from public.classes c
  where c.id = p_class_id and c.gym_id = v_gym_id
  for update;
  if not found then
    if exists (select 1 from public.classes c where c.id = p_class_id) then
      raise exception using errcode = '42501', message = 'forbidden';
    end if;
    return query select 0::bigint, 0::bigint, 0::bigint, 0::bigint;
    return;
  end if;
  if v_base.starts_at <= now() then
    raise exception using errcode = 'P0001', message = 'class_already_started';
  end if;

  -- Lock every affected occurrence in a deterministic order before effects.
  perform c.id
  from public.classes c
  where c.gym_id = v_gym_id
    and c.starts_at > now()
    and (
      (p_scope = 'single' and c.id = v_base.id)
      or (
        p_scope = 'future'
        and (
          (v_base.recurring_id is null and c.id = v_base.id)
          or (
            v_base.recurring_id is not null
            and c.recurring_id = v_base.recurring_id
            and c.starts_at >= v_base.starts_at
          )
        )
      )
    )
  order by c.id
  for update;

  for v_class in
    select c.*
    from public.classes c
    where c.gym_id = v_gym_id
      and c.starts_at > now()
      and (
        (p_scope = 'single' and c.id = v_base.id)
        or (
          p_scope = 'future'
          and (
            (v_base.recurring_id is null and c.id = v_base.id)
            or (
              v_base.recurring_id is not null
              and c.recurring_id = v_base.recurring_id
              and c.starts_at >= v_base.starts_at
            )
          )
        )
      )
    order by c.starts_at, c.id
  loop
    v_classes := v_classes + 1;
    select p.name into v_program_name
    from public.programs p
    where p.id = v_class.program_id and p.gym_id = v_gym_id;
    v_label := coalesce(
      nullif(btrim(v_program_name), ''),
      nullif(btrim(v_class.title), ''),
      'Class'
    );

    for v_booking in
      select cb.* from public.class_bookings cb
      where cb.class_id = v_class.id and cb.status <> 'cancelled'
      order by cb.id for update
    loop
      v_bookings := v_bookings + 1;
      v_refunded := false;

      if v_booking.status = 'booked'
        and not coalesce(v_booking.is_guest, false)
        and v_booking.user_id is not null
        and v_booking.membership_id is not null then
        select mm.* into v_membership
        from public.member_memberships mm
        where mm.id = v_booking.membership_id
          and mm.user_id = v_booking.user_id
          and mm.gym_id = v_gym_id
        for update;
        if found and v_membership.credits_remaining is not null then
          v_expiration := coalesce(v_membership.expires_at, v_membership.ends_at);
          update public.member_memberships mm
          set credits_remaining = mm.credits_remaining + 1,
              status = case
                when v_expiration is not null and v_expiration <= now() then 'expired'
                when mm.status = 'exhausted' then 'active'
                else mm.status
              end,
              is_active = case
                when v_expiration is not null and v_expiration <= now() then false
                when mm.status = 'exhausted' then true
                else mm.is_active
              end
          where mm.id = v_membership.id;
          insert into public.membership_credit_logs(
            user_id, gym_id, membership_id, amount, reason, class_id
          ) values (
            v_booking.user_id, v_gym_id, v_membership.id, 1,
            'class_cancelled', v_class.id
          );
          v_credits := v_credits + 1;
          v_refunded := true;
        end if;
      end if;

      if not coalesce(v_booking.is_guest, false) and v_booking.user_id is not null then
        select coalesce(nullif(lower(p.preferred_locale), ''), 'en')
        into v_locale from public.profiles p where p.id = v_booking.user_id;
        insert into public.notifications(
          user_id, gym_id, title, body, type, data, scheduled_for
        ) values (
          v_booking.user_id,
          v_gym_id,
          case when v_locale = 'es' then 'CLASE CANCELADA' else 'CLASS CANCELLED' end,
          case when v_locale = 'es' then
            format(
              'La clase %s del %s a las %s fue cancelada.%s',
              v_label,
              to_char(v_class.starts_at at time zone 'UTC', 'DD/MM/YYYY'),
              to_char(v_class.starts_at at time zone 'UTC', 'HH24:MI'),
              case when v_refunded then ' Tu crédito fue devuelto.' else '' end
            )
          else
            format(
              'The %s class on %s at %s was cancelled.%s',
              v_label,
              to_char(v_class.starts_at at time zone 'UTC', 'DD/MM/YYYY'),
              to_char(v_class.starts_at at time zone 'UTC', 'HH24:MI'),
              case when v_refunded then ' Your credit was refunded.' else '' end
            )
          end,
          'class_cancelled',
          jsonb_build_object(
            'classId', v_class.id,
            'startsAt', v_class.starts_at,
            'scope', p_scope,
            'creditRefunded', v_refunded
          ),
          now()
        );
      end if;
    end loop;

    for v_waitlist in
      select cw.* from public.class_waitlist cw
      where cw.class_id = v_class.id
      order by cw.id for update
    loop
      v_waitlisted := v_waitlisted + 1;
      select coalesce(nullif(lower(p.preferred_locale), ''), 'en')
      into v_locale from public.profiles p where p.id = v_waitlist.user_id;
      insert into public.notifications(
        user_id, gym_id, title, body, type, data, scheduled_for
      ) values (
        v_waitlist.user_id,
        v_gym_id,
        case when v_locale = 'es' then 'CLASE CANCELADA' else 'CLASS CANCELLED' end,
        case when v_locale = 'es'
          then format(
            'La clase %s del %s a las %s para la que estabas en lista de espera fue cancelada.',
            v_label,
            to_char(v_class.starts_at at time zone 'UTC', 'DD/MM/YYYY'),
            to_char(v_class.starts_at at time zone 'UTC', 'HH24:MI')
          )
          else format(
            'The %s class on %s at %s that you were waitlisted for was cancelled.',
            v_label,
            to_char(v_class.starts_at at time zone 'UTC', 'DD/MM/YYYY'),
            to_char(v_class.starts_at at time zone 'UTC', 'HH24:MI')
          )
        end,
        'class_cancelled',
        jsonb_build_object(
          'classId', v_class.id,
          'startsAt', v_class.starts_at,
          'scope', p_scope,
          'waitlist', true,
          'creditRefunded', false
        ),
        now()
      );
    end loop;
  end loop;

  delete from public.classes c
  where c.gym_id = v_gym_id
    and c.starts_at > now()
    and (
      (p_scope = 'single' and c.id = v_base.id)
      or (
        p_scope = 'future'
        and (
          (v_base.recurring_id is null and c.id = v_base.id)
          or (
            v_base.recurring_id is not null
            and c.recurring_id = v_base.recurring_id
            and c.starts_at >= v_base.starts_at
          )
        )
      )
    );

  return query select v_classes, v_bookings, v_waitlisted, v_credits;
end;
$function$;

revoke all on function public.get_class_cancellation_impact(uuid, text)
  from public, anon, authenticated;
revoke all on function public.admin_cancel_class(uuid, text)
  from public, anon, authenticated;
grant execute on function public.get_class_cancellation_impact(uuid, text)
  to authenticated, service_role;
grant execute on function public.admin_cancel_class(uuid, text)
  to authenticated, service_role;
