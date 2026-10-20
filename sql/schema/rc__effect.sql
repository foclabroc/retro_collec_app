create or replace function public.rc__effect(p_effect text)
 returns integer
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select max(coalesce(e.effect_value, case p_effect when 'pixels_x2' then 2 when 'free_fast' then 3 when 'promo' then 20
                                                     when 'lot_free' then 1 else 2 end))
    from public.rc_events e
   where e.kind = 'effect' and e.effect = p_effect and public.rc__ev_live(e) $function$;
