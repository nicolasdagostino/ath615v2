drop policy if exists "workout comments admins can delete gym comments" on public.workout_comments;

create policy "workout comments admins can delete gym comments"
on public.workout_comments
for delete
using (
  exists (
    select 1
    from public.workouts w
    join public.profiles p on p.gym_id = w.gym_id
    where w.id = workout_comments.workout_id
      and p.id = auth.uid()
      and p.role = 'admin'
  )
);
