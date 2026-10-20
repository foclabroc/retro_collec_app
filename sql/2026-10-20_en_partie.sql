-- Statut « en partie » : rc_board renvoie aussi busy (duel en direct en cours) — relançable
-- La liste des colonnes change : on supprime puis on recrée la fonction.

drop function if exists public.rc_board();

create or replace function public.rc_board()
 returns table(pid text, name text, avatar integer, score integer, cards integer, showcase text, house text, coins bigint, pixels bigint, online boolean, seen_at timestamp with time zone, trophies text, busy boolean)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select p.pid, p.name, p.avatar, p.score, p.cards, p.showcase, p.house, p.coins, coalesce(p.pixels, 0)::bigint,
         coalesce(p.seen_at > now() - interval '75 seconds', false),
         coalesce(p.seen_at, (p.last_login::timestamp + interval '12 hours') at time zone 'Europe/Paris'),
         public.rc__tshow(p.device),
         -- en duel en direct (même règle que rc_c4_online / rc_bs_online)
         exists (select 1 from public.rc_c4 g where g.mode = 'live' and g.status = 'playing'
                  and p.device in (g.p1, g.p2) and now() <= g.move_at + interval '60 seconds')
         or exists (select 1 from public.rc_bs g where g.mode = 'live' and g.status in ('setup', 'playing')
                  and p.device in (g.p1, g.p2) and now() <= g.move_at + interval '2 minutes')
    from public.rc_players p
   where p.packs > 0 and greatest(p.seen_at, p.last_login::timestamptz) > now() - interval '7 days'
   order by p.score desc, p.created_at asc limit 100 $function$;

grant execute on function public.rc_board() to anon, authenticated;
