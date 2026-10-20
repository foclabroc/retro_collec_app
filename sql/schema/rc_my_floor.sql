create or replace function public.rc_my_floor(p_device text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'score', p.score, 'cards', p.cards,
                            'house', p.house, 'coins', p.coins, 'online', true,
                            'rank', (select count(*) + 1 from public.rc_players q where q.packs > 0 and q.score > p.score
                                       and greatest(q.seen_at, q.last_login::timestamptz) > now() - interval '7 days'))
    from public.rc_players p where p.device = p_device $function$
;

$function$;
