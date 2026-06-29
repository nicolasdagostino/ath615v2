alter table public.class_bookings
add column if not exists guest_name text,
add column if not exists is_guest boolean not null default false;

drop policy if exists "admin insert guest bookings" on public.class_bookings;

create policy "admin insert guest bookings"
on public.class_bookings
for insert
with check (
  is_guest = true
  and user_id is null
  and guest_name is not null
  and length(trim(guest_name)) > 0
  and exists (
    select 1
    from public.classes c
    join public.profiles p on p.gym_id = c.gym_id
    where c.id = class_bookings.class_id
      and p.id = auth.uid()
      and p.role = any (array['admin'::text, 'owner'::text])
  )
);
