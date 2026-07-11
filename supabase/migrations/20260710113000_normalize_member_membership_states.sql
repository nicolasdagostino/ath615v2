alter table public.member_memberships
drop constraint if exists member_memberships_status_check;

update public.member_memberships
set status = case
  when is_active = true
    and coalesce(expires_at, ends_at) is not null
    and coalesce(expires_at, ends_at) <= now()
    then 'expired'

  when is_active = true
    and credits_remaining is not null
    and credits_remaining <= 0
    then 'exhausted'

  when is_active = true
    and coalesce(starts_at, created_at) > now()
    then 'scheduled'

  when is_active = true
    then 'active'

  when is_active = false
    and status = 'cancelled'
    then 'cancelled'

  when is_active = false
    then 'replaced'

  else status
end;

update public.member_memberships
set is_active = false
where status in ('exhausted', 'expired', 'cancelled', 'replaced');

update public.member_memberships
set is_active = true
where status in ('active', 'scheduled');

alter table public.member_memberships
alter column status set default 'active';

alter table public.member_memberships
alter column status set not null;

alter table public.member_memberships
alter column is_active set default true;

alter table public.member_memberships
alter column is_active set not null;

alter table public.member_memberships
add constraint member_memberships_status_check
check (
  status in (
    'active',
    'scheduled',
    'exhausted',
    'expired',
    'cancelled',
    'replaced'
  )
);

alter table public.member_memberships
drop constraint if exists member_memberships_status_active_consistency_check;

alter table public.member_memberships
add constraint member_memberships_status_active_consistency_check
check (
  (
    status in ('active', 'scheduled')
    and is_active = true
  )
  or
  (
    status in ('exhausted', 'expired', 'cancelled', 'replaced')
    and is_active = false
  )
);

alter table public.member_memberships
drop constraint if exists member_memberships_credits_nonnegative_check;

alter table public.member_memberships
add constraint member_memberships_credits_nonnegative_check
check (
  credits_remaining is null
  or credits_remaining >= 0
);

create index if not exists member_memberships_user_gym_status_idx
on public.member_memberships (
  user_id,
  gym_id,
  status,
  starts_at,
  expires_at
);

create index if not exists member_memberships_usable_credit_packs_idx
on public.member_memberships (
  user_id,
  gym_id,
  expires_at,
  created_at
)
where
  status = 'active'
  and is_active = true
  and credits_remaining > 0;

create index if not exists member_memberships_active_unlimited_idx
on public.member_memberships (
  user_id,
  gym_id,
  starts_at,
  expires_at
)
where
  status = 'active'
  and is_active = true
  and credits_remaining is null;

create index if not exists member_memberships_scheduled_idx
on public.member_memberships (
  user_id,
  gym_id,
  starts_at
)
where
  status = 'scheduled'
  and is_active = true;
