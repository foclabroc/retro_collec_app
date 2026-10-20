-- Pièces et pixels des autres joueurs : renvoyés par rc_board (Voisinage) et rc_profile (profil).
-- Relançable. rc_board change de colonnes : il faut le supprimer avant de le recréer.

drop function if exists public.rc_board();

create or replace function public.rc_board()
 returns table(pid text, name text, avatar integer, score integer, cards integer, showcase text, house text, coins bigint, pixels bigint, online boolean, seen_at timestamp with time zone, trophies text)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select p.pid, p.name, p.avatar, p.score, p.cards, p.showcase, p.house, p.coins, coalesce(p.pixels, 0)::bigint,
         coalesce(p.seen_at > now() - interval '10 minutes', false),
         coalesce(p.seen_at, (p.last_login::timestamp + interval '12 hours') at time zone 'Europe/Paris'),
         public.rc__tshow(p.device)
    from public.rc_players p
   where p.packs > 0 and greatest(p.seen_at, p.last_login::timestamptz) > now() - interval '7 days'
   order by p.score desc, p.created_at asc limit 100 $function$;

grant execute on function public.rc_board() to anon, authenticated;

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
