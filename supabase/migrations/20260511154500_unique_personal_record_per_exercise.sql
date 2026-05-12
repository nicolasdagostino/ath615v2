delete from public.personal_records a
using public.personal_records b
where a.user_id = b.user_id
  and lower(trim(a.exercise_name)) = lower(trim(b.exercise_name))
  and (
    a.weight_kg < b.weight_kg
    or (a.weight_kg = b.weight_kg and a.created_at < b.created_at)
  );

create unique index if not exists personal_records_user_exercise_unique
on public.personal_records (user_id, lower(trim(exercise_name)));
