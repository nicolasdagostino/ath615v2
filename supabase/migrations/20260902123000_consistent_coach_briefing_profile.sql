begin;

create or replace function public.get_daily_coach_briefing_with_coach()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_briefing jsonb;
  v_classes jsonb;
begin
  -- The existing RPC remains authoritative for authorization, gym scoping,
  -- roster intelligence and timezone boundaries.
  v_briefing := public.get_daily_coach_briefing();

  select coalesce(
    jsonb_agg(
      class_item || jsonb_build_object(
        'coach_id', c.coach_id,
        'coach_avatar_url', coach.avatar_url
      )
      order by class_position
    ),
    '[]'::jsonb
  )
  into v_classes
  from jsonb_array_elements(v_briefing->'classes')
    with ordinality as items(class_item, class_position)
  left join public.classes c on c.id::text = class_item->>'id'
  left join public.profiles coach on coach.id = c.coach_id;

  return jsonb_set(v_briefing, '{classes}', v_classes, true);
end;
$function$;

revoke all on function public.get_daily_coach_briefing_with_coach() from public, anon;
grant execute on function public.get_daily_coach_briefing_with_coach() to authenticated, service_role;

commit;
