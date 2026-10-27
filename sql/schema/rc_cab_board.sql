create or replace function public.rc_cab_board()
 returns table(pid text, game text, rec int, rec_name text)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select p.pid, g.game, r.score, rp.name
    from public.rc_players p
   cross join lateral (select public.rc__cab_game(p.cab_game, p.pid) as game) g
    left join lateral public.rc__cab_rec(p.device, g.game) r on true
    left join public.rc_players rp on rp.device = r.device
   where p.packs > 0 and greatest(p.seen_at, p.last_login::timestamptz) > now() - interval '7 days' $function$;
