create index if not exists notifications_communication_group_idx
on public.notifications (gym_id, ((data ->> 'communicationId')))
where type = 'communication'
  and data ? 'communicationId';
