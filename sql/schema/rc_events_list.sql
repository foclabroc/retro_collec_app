create or replace function public.rc_events_list(p_device text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(x.j order by x.o, x.s desc), '[]'::jsonb) from (
    select case when e.starts_at > now() then 1
                when public.rc__ev_live(e) then 0 else 2 end as o,
           e.starts_at as s,
           -- à venir : visible en entier (titre, texte, récompenses), mais rien n'est utilisable avant le début
             jsonb_build_object(
               'id', e.id, 'kind', e.kind, 'title', e.title, 'title_en', e.title_en, 'body', e.body, 'body_en', e.body_en,
               'icon', e.icon, 'color', e.color, 'image', e.image, 'decor', e.decor, 'decor_fx', e.decor_fx,
               'starts_at', e.starts_at, 'ends_at', e.ends_at,
               'coins', e.coins, 'pixels', e.pixels, 'reward', e.reward, 'action', e.action, 'arg', e.arg,
               'effect', e.effect, 'effect_value', coalesce(e.effect_value, case e.effect when 'pixels_x2' then 2 when 'free_fast' then 3
                                                                                          when 'promo' then 20 when 'lot_free' then 1 else 2 end),
               'goal', e.goal, 'steps', e.steps,
               'progress', case when e.kind = 'goal' then public.rc__ev_progress(p_device, e) end,
               'claimed', coalesce((select claimed from public.rc_events_prog where device = p_device and event_id = e.id), 0),
               'live', public.rc__ev_live(e),
               'ended', e.ends_at is not null and e.ends_at <= now(),
               'got', exists (select 1 from public.rc_events_got g where g.device = p_device and g.event_id = e.id),
               'upcoming', e.starts_at > now(),
               'now', now()) as j
      from public.rc_events e
     where e.active
       and (e.ends_at is null or e.ends_at > now() - interval '3 days')
       -- à venir : toujours les 5 prochains, quelle que soit leur date
       and (e.starts_at <= now()
            or e.id in (select f.id from public.rc_events f where f.active and f.starts_at > now() order by f.starts_at limit 5))) x $function$;
