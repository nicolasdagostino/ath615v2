drop policy if exists "athletes view own waitlist" on public.class_waitlist;

create policy "gym members view class waitlist"
on public.class_waitlist
for select
using (
  exists (
    select 1
    from public.classes c
    join public.profiles viewer on viewer.gym_id = c.gym_id
    where c.id = class_waitlist.class_id
      and viewer.id = auth.uid()
      and viewer.role = any (array['athlete'::text, 'admin'::text, 'owner'::text])
  )
);
