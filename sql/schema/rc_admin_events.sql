create or replace function public.rc_admin_events(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
begin
  perform public.rc__admin(p_device, p_sig, 'events');
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', e.id, 'kind', e.kind, 'title', e.title, 'title_en', e.title_en, 'body', e.body, 'body_en', e.body_en,
             'icon', e.icon, 'color', e.color, 'decor', e.decor, 'starts_at', e.starts_at, 'ends_at', e.ends_at,
             'coins', e.coins, 'pixels', e.pixels, 'reward', e.reward, 'arg', e.arg, 'action', e.action, 'active', e.active,
             'effect', e.effect, 'effect_value', e.effect_value, 'goal', e.goal, 'steps', e.steps,
             'live', public.rc__ev_live(e), 'upcoming', e.starts_at > now(), 'ended', e.ends_at is not null and e.ends_at <= now(),
             'got', (select count(*) from public.rc_events_got g where g.event_id = e.id)) order by e.starts_at)
      from public.rc_events e
     where e.ends_at is null or e.ends_at > now() - interval '7 days'), '[]'::jsonb);
end $function$;
