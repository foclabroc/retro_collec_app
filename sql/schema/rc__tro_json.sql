create or replace function public.rc__tro_json(p_dev text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object(
    'list', coalesce((select jsonb_agg(jsonb_build_object('k', x.kind, 'n', x.n, 'got', x.got, 't', x.t) order by x.ord)
                        from public.rc__tn(p_dev) x), '[]'::jsonb),
    'show', array_to_string(public.rc__tshow_k(p_dev), ','),  -- vitrine affichée (choix + meilleurs en complément)
    'pick', coalesce((select trophies from public.rc_players where device = p_dev), ''),
    'ready', (select count(*)::int from public.rc__tn(p_dev) x where x.got < 3 and x.n >= x.t[x.got + 1])) $function$;
