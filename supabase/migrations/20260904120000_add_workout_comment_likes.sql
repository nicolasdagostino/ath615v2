begin;

create table public.workout_comment_likes (
  comment_id uuid not null references public.workout_comments(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);

create index workout_comment_likes_comment_created_idx
  on public.workout_comment_likes(comment_id, created_at desc);

alter table public.workout_comment_likes enable row level security;

create policy "effective members read workout comment likes"
on public.workout_comment_likes for select to authenticated
using (exists(
  select 1
  from public.workout_comments wc
  join public.workouts w on w.id=wc.workout_id
  where wc.id=comment_id
    and w.gym_id=public.effective_gym_id()
    and exists(select 1 from public.gym_members gm
      where gm.gym_id=w.gym_id and gm.user_id=auth.uid() and gm.is_active)
));

create policy "effective members insert own workout comment likes"
on public.workout_comment_likes for insert to authenticated
with check (user_id=auth.uid() and exists(
  select 1
  from public.workout_comments wc
  join public.workouts w on w.id=wc.workout_id
  where wc.id=comment_id
    and w.gym_id=public.effective_gym_id()
    and exists(select 1 from public.gym_members gm
      where gm.gym_id=w.gym_id and gm.user_id=auth.uid() and gm.is_active)
));

create policy "effective members delete own workout comment likes"
on public.workout_comment_likes for delete to authenticated
using (user_id=auth.uid() and exists(
  select 1
  from public.workout_comments wc
  join public.workouts w on w.id=wc.workout_id
  where wc.id=comment_id
    and w.gym_id=public.effective_gym_id()
    and exists(select 1 from public.gym_members gm
      where gm.gym_id=w.gym_id and gm.user_id=auth.uid() and gm.is_active)
));

create or replace function public.list_effective_workout_comments(
  p_workout_id uuid
)
returns table(
  id uuid,
  body text,
  user_id uuid,
  created_at timestamptz,
  like_count bigint,
  liked_by_me boolean
)
language plpgsql
stable
security definer
set search_path=public,pg_temp
as $function$
declare v_user_id uuid:=auth.uid(); v_gym_id uuid:=public.effective_gym_id();
begin
  if v_user_id is null or v_gym_id is null or not exists(
    select 1 from public.workouts w
    where w.id=p_workout_id and w.gym_id=v_gym_id
      and exists(select 1 from public.gym_members gm
        where gm.gym_id=w.gym_id and gm.user_id=v_user_id and gm.is_active)
  ) then
    raise exception using errcode='P0001',message='workout_comment_access_denied';
  end if;

  return query
  select wc.id,wc.body,wc.user_id,wc.created_at,
    count(wcl.user_id)::bigint,
    coalesce(bool_or(wcl.user_id=v_user_id),false)
  from public.workout_comments wc
  left join public.workout_comment_likes wcl on wcl.comment_id=wc.id
  where wc.workout_id=p_workout_id
  group by wc.id,wc.body,wc.user_id,wc.created_at
  order by wc.created_at desc,wc.id desc;
end;
$function$;

create or replace function public.toggle_workout_comment_like(
  p_comment_id uuid
)
returns table(liked boolean, like_count bigint)
language plpgsql
security definer
set search_path=public,pg_temp
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_gym_id uuid:=public.effective_gym_id();
  v_author_id uuid;
  v_workout_id uuid;
  v_workout_date date;
  v_actor_name text;
  v_liked boolean;
begin
  if v_user_id is null or v_gym_id is null or p_comment_id is null then
    raise exception using errcode='P0001',message='workout_comment_access_denied';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_comment_id::text||':'||v_user_id::text,624)
  );

  select wc.user_id,w.id,w.workout_date
  into v_author_id,v_workout_id,v_workout_date
  from public.workout_comments wc
  join public.workouts w on w.id=wc.workout_id
  where wc.id=p_comment_id and w.gym_id=v_gym_id
    and exists(select 1 from public.gym_members gm
      where gm.gym_id=w.gym_id and gm.user_id=v_user_id and gm.is_active);

  if not found then
    raise exception using errcode='P0001',message='workout_comment_access_denied';
  end if;

  if exists(select 1 from public.workout_comment_likes wcl
    where wcl.comment_id=p_comment_id and wcl.user_id=v_user_id) then
    delete from public.workout_comment_likes
    where comment_id=p_comment_id and user_id=v_user_id;
    v_liked:=false;
  else
    insert into public.workout_comment_likes(comment_id,user_id)
    values(p_comment_id,v_user_id);
    v_liked:=true;

    if v_author_id<>v_user_id and not exists(
      select 1 from public.notifications n
      where n.type='workout_comment_liked'
        and n.user_id=v_author_id
        and n.data->>'commentId'=p_comment_id::text
        and n.data->>'actorId'=v_user_id::text
    ) then
      select nullif(btrim(p.full_name),'') into v_actor_name
      from public.profiles p where p.id=v_user_id;
      insert into public.notifications(
        user_id,gym_id,title,body,type,data,scheduled_for
      ) values(
        v_author_id,v_gym_id,'Nuevo me gusta',
        coalesce(v_actor_name,'Alguien')||' indicó que le gusta tu comentario.',
        'workout_comment_liked',
        jsonb_build_object(
          'source','workout','workoutId',v_workout_id,
          'workoutDate',v_workout_date,'commentId',p_comment_id,
          'actorId',v_user_id
        ),clock_timestamp()
      );
    end if;
  end if;

  return query select v_liked,count(*)::bigint
  from public.workout_comment_likes wcl where wcl.comment_id=p_comment_id;
end;
$function$;

revoke all on table public.workout_comment_likes from public,anon,authenticated;
grant all on table public.workout_comment_likes to service_role;
revoke all on function public.list_effective_workout_comments(uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.toggle_workout_comment_like(uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.list_effective_workout_comments(uuid)
  to authenticated,service_role;
grant execute on function public.toggle_workout_comment_like(uuid)
  to authenticated,service_role;

commit;
