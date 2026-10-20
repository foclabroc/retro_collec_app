create or replace function public.rc_board()
 returns table(pid text, name text, avatar integer, score integer, cards integer, showcase text, house text, coins bigint, online boolean, seen_at timestamp with time zone, trophies text)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select p.pid, p.name, p.avatar, p.score, p.cards, p.showcase, p.house, p.coins,
         coalesce(p.seen_at > now() - interval '10 minutes', false),
         coalesce(p.seen_at, (p.last_login::timestamp + interval '12 hours') at time zone 'Europe/Paris'),
         public.rc__tshow(p.device)
    from public.rc_players p
   where p.packs > 0 and greatest(p.seen_at, p.last_login::timestamptz) > now() - interval '7 days'
   order by p.score desc, p.created_at asc limit 100 $function$;
