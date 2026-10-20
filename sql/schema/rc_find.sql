create or replace function public.rc_find(p_query text)
 returns table(pid text, name text, avatar integer, score integer, cards integer, house text, coins bigint, online boolean, seen_at timestamp with time zone)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select p.pid, p.name, p.avatar, p.score, p.cards, p.house, p.coins,
         coalesce(p.seen_at > now() - interval '75 seconds', false),
         coalesce(p.seen_at, (p.last_login::timestamp + interval '12 hours') at time zone 'Europe/Paris')
    from public.rc_players p
   where p.name_key like public.rc__name_key(p_query) || '%'
   order by p.score desc limit 20 $function$;
