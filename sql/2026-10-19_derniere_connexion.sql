-- Pixel Trade · 19/10/2026 · Dernière connexion connue même sans seen_at
-- seen_at (heure exacte) n'existe que depuis l'ajout de « en ligne » ; avant, seul last_login (le jour) était gardé.
--   • Profil : nouveau champ seen_day (dernier jour connu) → « le 12/10 (il y a 7 jours) »
--   • Immeuble et recherche : seen_at retombe sur last_login → « vu le 12/10 »
-- Voisinage : joueurs vus dans les 7 derniers jours (remet les 7 jours si le fichier « 3 jours » a été lancé). Relançable.

create or replace function public.rc_profile(p_pid text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'score', p.score,
                            'cards', p.cards, 'packs', p.packs, 'showcase', p.showcase, 'house', p.house,
                            'coins', p.coins, 'online', coalesce(p.seen_at > now() - interval '10 minutes', false),
                            'seen_at', p.seen_at,
                            'seen_day', coalesce((p.seen_at at time zone 'Europe/Paris')::date, p.last_login),
                            'since', p.created_at, 'owned', public.rc__owned_json(p.device))
    from public.rc_players p where p.pid = p_pid $function$;

create or replace function public.rc_board()
 returns table(pid text, name text, avatar integer, score integer, cards integer, showcase text, house text, coins bigint, online boolean, seen_at timestamp with time zone)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select p.pid, p.name, p.avatar, p.score, p.cards, p.showcase, p.house, p.coins,
         coalesce(p.seen_at > now() - interval '10 minutes', false),
         coalesce(p.seen_at, (p.last_login::timestamp + interval '12 hours') at time zone 'Europe/Paris')
    from public.rc_players p
   where p.packs > 0 and greatest(p.seen_at, p.last_login::timestamptz) > now() - interval '7 days'
   order by p.score desc, p.created_at asc limit 100 $function$;

create or replace function public.rc_find(p_query text)
 returns table(pid text, name text, avatar integer, score integer, cards integer, house text, coins bigint, online boolean, seen_at timestamp with time zone)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select p.pid, p.name, p.avatar, p.score, p.cards, p.house, p.coins,
         coalesce(p.seen_at > now() - interval '10 minutes', false),
         coalesce(p.seen_at, (p.last_login::timestamp + interval '12 hours') at time zone 'Europe/Paris')
    from public.rc_players p
   where p.name_key like public.rc__name_key(p_query) || '%'
   order by p.score desc limit 20 $function$;

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

create or replace function public.rc_rank(p_device text)
 RETURNS TABLE(rank integer, total integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select (select count(*)::int + 1 from public.rc_players o
           where o.packs > 0 and greatest(o.seen_at, o.last_login::timestamptz) > now() - interval '7 days' and o.score > (select p.score from public.rc_players p where p.device = p_device)),
         (select count(*)::int from public.rc_players q where q.packs > 0 and greatest(q.seen_at, q.last_login::timestamptz) > now() - interval '7 days') $function$
;

