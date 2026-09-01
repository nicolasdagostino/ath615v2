begin;
select plan(1);

do $$
declare
  actor_id uuid:='fc100000-0000-0000-0000-000000000001';
  author_id uuid:='fc100000-0000-0000-0000-000000000002';
  inactive_id uuid:='fc100000-0000-0000-0000-000000000003';
  other_id uuid:='fc100000-0000-0000-0000-000000000004';
  gym_a uuid:='fc200000-0000-0000-0000-000000000001';
  gym_b uuid:='fc200000-0000-0000-0000-000000000002';
  program_a uuid:='fc300000-0000-0000-0000-000000000001';
  program_b uuid:='fc300000-0000-0000-0000-000000000002';
  workout_a uuid:='fc400000-0000-0000-0000-000000000001';
  workout_b uuid:='fc400000-0000-0000-0000-000000000002';
  comment_a uuid:='fc500000-0000-0000-0000-000000000001';
  self_comment uuid:='fc500000-0000-0000-0000-000000000002';
  comment_b uuid:='fc500000-0000-0000-0000-000000000003';
  liked_value boolean; count_value bigint; original_body text;
begin
  insert into auth.users(id,email) values
    (actor_id,'comment-like-actor@test.invalid'),
    (author_id,'comment-like-author@test.invalid'),
    (inactive_id,'comment-like-inactive@test.invalid'),
    (other_id,'comment-like-other@test.invalid');
  insert into gyms(id,name) values(gym_a,'Comment Likes A'),(gym_b,'Comment Likes B');
  update profiles set full_name=case when id=actor_id then 'Like Actor' else 'Comment Author' end,
    role='athlete',is_active=true,
    gym_id=case when id=other_id then gym_b else gym_a end
  where id in(actor_id,author_id,inactive_id,other_id);
  insert into gym_members(gym_id,user_id,role,is_active,joined_at) values
    (gym_a,actor_id,'athlete',true,now()),(gym_a,author_id,'athlete',true,now()),
    (gym_a,inactive_id,'athlete',false,now()),(gym_b,other_id,'athlete',true,now());
  insert into programs(id,gym_id,name) values(program_a,gym_a,'Program A'),(program_b,gym_b,'Program B');
  insert into workouts(id,gym_id,program_id,workout_date,description,created_by) values
    (workout_a,gym_a,program_a,current_date,'A',author_id),
    (workout_b,gym_b,program_b,current_date,'B',other_id);
  insert into workout_comments(id,workout_id,user_id,body) values
    (comment_a,workout_a,author_id,'Original comment'),
    (self_comment,workout_a,actor_id,'Self comment'),
    (comment_b,workout_b,other_id,'Other gym comment');
  select body into original_body from workout_comments where id=comment_a;

  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',actor_id::text,true);

  select liked,like_count into liked_value,count_value
  from toggle_workout_comment_like(comment_a);
  if not liked_value or count_value<>1 then raise exception 'authorized like failed'; end if;
  if not exists(select 1 from list_effective_workout_comments(workout_a) c
    where c.id=comment_a and c.like_count=1 and c.liked_by_me) then
    raise exception 'batch count/liked_by_me failed';
  end if;
  if (select count(*) from notifications where type='workout_comment_liked'
      and user_id=author_id and data->>'commentId'=comment_a::text)<>1 then
    raise exception 'author notification missing';
  end if;

  select liked,like_count into liked_value,count_value
  from toggle_workout_comment_like(comment_a);
  if liked_value or count_value<>0 then raise exception 'unlike failed'; end if;
  select liked,like_count into liked_value,count_value
  from toggle_workout_comment_like(comment_a);
  if not liked_value or count_value<>1 then raise exception 're-like failed'; end if;
  if (select count(*) from notifications where type='workout_comment_liked'
      and user_id=author_id and data->>'commentId'=comment_a::text)<>1 then
    raise exception 'toggle duplicated notification';
  end if;

  select liked,like_count into liked_value,count_value
  from toggle_workout_comment_like(self_comment);
  if not liked_value or count_value<>1 then raise exception 'self-like failed'; end if;
  if exists(select 1 from notifications where type='workout_comment_liked'
      and user_id=actor_id and data->>'commentId'=self_comment::text) then
    raise exception 'self-like notified actor';
  end if;

  begin perform toggle_workout_comment_like(comment_b); raise exception 'cross-gym like allowed';
  exception when sqlstate 'P0001' then null; end;
  begin perform toggle_workout_comment_like(gen_random_uuid()); raise exception 'missing comment allowed';
  exception when sqlstate 'P0001' then null; end;

  perform set_config('request.jwt.claim.sub',inactive_id::text,true);
  begin perform toggle_workout_comment_like(comment_a); raise exception 'inactive actor allowed';
  exception when sqlstate 'P0001' then null; end;
  perform set_config('request.jwt.claim.sub',actor_id::text,true);
  update gyms set lifecycle_status='suspended' where id=gym_a;
  begin perform toggle_workout_comment_like(comment_a); raise exception 'suspended gym allowed';
  exception when sqlstate 'P0001' then null; end;
  update gyms set lifecycle_status='archived' where id=gym_a;
  begin perform list_effective_workout_comments(workout_a); raise exception 'archived gym read allowed';
  exception when sqlstate 'P0001' then null; end;
  update gyms set lifecycle_status='active' where id=gym_a;

  if (select body from workout_comments where id=comment_a)<>original_body then
    raise exception 'comment content mutated';
  end if;
  delete from workout_comments where id=self_comment;
  if exists(select 1 from workout_comment_likes where comment_id=self_comment) then
    raise exception 'comment like did not cascade';
  end if;
end $$;

select pass('Workout comment likes are atomic, isolated, aggregated and lifecycle-safe');
select * from finish();
rollback;
