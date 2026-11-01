-- Joueur en solo (Rétro Jump / course) : « En solo » au lieu de « Regarder » dans le Voisinage. Relançable.
create or replace function public.rc__duel_solo(p_device text)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select public.rc__duel_busy(p_device)
     and not exists (select 1 from public.rc_c4 g where g.mode = 'live' and g.status = 'playing'
                      and p_device in (g.p1, g.p2) and now() <= g.move_at + interval '60 seconds')
     and not exists (select 1 from public.rc_bs g where g.mode = 'live' and g.status in ('setup', 'playing')
                      and p_device in (g.p1, g.p2) and now() <= g.move_at + interval '2 minutes')
     and not exists (select 1 from public.rc_rj g where g.status = 'playing'
                      and p_device in (g.p1, g.p2) and now() <= g.end_at + interval '10 seconds') $function$;

drop function if exists public.rc_board();
create or replace function public.rc_board()
 returns table(pid text, name text, avatar integer, score integer, cards integer, showcase text, house text, coins bigint, pixels bigint, online boolean, seen_at timestamp with time zone, trophies text, busy boolean, solo boolean)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select p.pid, p.name, p.avatar, p.score, p.cards, p.showcase, p.house, p.coins, coalesce(p.pixels, 0)::bigint,
         coalesce(p.seen_at > now() - interval '75 seconds', false),
         coalesce(p.seen_at, (p.last_login::timestamp + interval '12 hours') at time zone 'Europe/Paris'),
         public.rc__tshow(p.device),
         -- en duel en direct ou en solo (4 en ligne, Console Wars, Rétro Jump, course)
         public.rc__duel_busy(p.device),
         public.rc__duel_solo(p.device)
    from public.rc_players p
   where p.packs > 0 and greatest(p.seen_at, p.last_login::timestamptz) > now() - interval '7 days'
   order by p.score desc, p.created_at asc limit 100 $function$;

-- temps réel : début / fin d'une partie solo → événement « duels » (listes En ligne et Voisinage relues tout de suite)
create or replace trigger rc_rj_runs_rt after insert or update of ended_at on public.rc_rj_runs
  for each statement execute function public.rc__rt_all('duels');
create or replace trigger rc_rn_runs_rt after insert or update of ended_at on public.rc_rn_runs
  for each statement execute function public.rc__rt_all('duels');

alter function public.rc__duel_solo(text) owner to rc_owner;
alter function public.rc_board() owner to rc_owner;
grant execute on function public.rc_board() to anon, authenticated;

notify pgrst, 'reload schema';
