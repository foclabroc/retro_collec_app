create or replace function public.rc__promo(p_kind text)
 returns integer
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select least(coalesce(max(coalesce(e.effect_value, 20)), 0), 90)::int
    from public.rc_events e
   where e.kind = 'effect' and e.effect = 'promo' and public.rc__ev_live(e)
     and (coalesce(e.arg, '') in ('', 'all') or e.arg = p_kind) $function$;
