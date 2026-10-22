create or replace function public.rc__tour_tag(p_mid bigint)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object('tid', t.id, 'name', t.name, 'mid', m.id, 'round', m.round, 'rounds', t.rounds,
                            'best', m.best, 'w1', m.w1, 'w2', m.w2,
                            'p1', (select pid from public.rc_players where device = m.p1))
    from public.rc_tour_matches m join public.rc_tour t on t.id = m.tid where m.id = p_mid $function$;
