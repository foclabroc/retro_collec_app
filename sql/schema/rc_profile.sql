create or replace function public.rc_profile(p_pid text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'score', p.score,
                            'cards', p.cards, 'packs', p.packs, 'showcase', p.showcase, 'house', p.house,
                            'coins', p.coins, 'pixels', coalesce(p.pixels, 0), 'online', coalesce(p.seen_at > now() - interval '10 minutes', false),
                            'seen_at', p.seen_at,
                            'seen_day', coalesce((p.seen_at at time zone 'Europe/Paris')::date, p.last_login),
                            'since', p.created_at, 'trophies', public.rc__tshow(p.device),
                            'tro_total', (select coalesce(sum(tier), 0)::int from public.rc_trophy_got g where g.device = p.device), 'owned', public.rc__owned_json(p.device))
    from public.rc_players p where p.pid = p_pid $function$;
