alter table public.class_bookings
add column if not exists membership_id uuid;

alter table public.class_bookings
drop constraint if exists class_bookings_membership_id_fkey;

alter table public.class_bookings
add constraint class_bookings_membership_id_fkey
foreign key (membership_id)
references public.member_memberships(id)
on delete set null;

with latest_consumption as (
  select distinct on (user_id, class_id)
    user_id,
    class_id,
    membership_id
  from public.membership_credit_logs
  where reason in ('booked', 'waitlist_promoted')
    and class_id is not null
    and membership_id is not null
  order by
    user_id,
    class_id,
    created_at desc,
    id desc
)
update public.class_bookings cb
set membership_id = lc.membership_id
from latest_consumption lc
where cb.is_guest = false
  and cb.user_id = lc.user_id
  and cb.class_id = lc.class_id
  and cb.membership_id is null;

create index if not exists class_bookings_membership_id_idx
on public.class_bookings (membership_id)
where membership_id is not null;

create index if not exists class_bookings_user_class_membership_idx
on public.class_bookings (
  user_id,
  class_id,
  membership_id,
  created_at desc
)
where is_guest = false
  and membership_id is not null;
