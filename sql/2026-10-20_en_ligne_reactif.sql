-- Joueurs en ligne plus réactifs (relançable)
-- « En ligne » = vu il y a moins de 75 s (au lieu de 10 min ; l'appli ping toutes les 20 s au premier plan)
-- rc_duel_ping renvoie aussi le nombre de joueurs en ligne (compteur du menu à jour sans recharger le Voisinage)

-- rc_board
create or replace function public.rc_board()
 returns table(pid text, name text, avatar integer, score integer, cards integer, showcase text, house text, coins bigint, pixels bigint, online boolean, seen_at timestamp with time zone, trophies text)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select p.pid, p.name, p.avatar, p.score, p.cards, p.showcase, p.house, p.coins, coalesce(p.pixels, 0)::bigint,
         coalesce(p.seen_at > now() - interval '75 seconds', false),
         coalesce(p.seen_at, (p.last_login::timestamp + interval '12 hours') at time zone 'Europe/Paris'),
         public.rc__tshow(p.device)
    from public.rc_players p
   where p.packs > 0 and greatest(p.seen_at, p.last_login::timestamptz) > now() - interval '7 days'
   order by p.score desc, p.created_at asc limit 100 $function$;
;

-- rc_find
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
;

-- rc_profile
create or replace function public.rc_profile(p_pid text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'score', p.score,
                            'cards', p.cards, 'packs', p.packs, 'showcase', p.showcase, 'house', p.house,
                            'coins', p.coins, 'pixels', coalesce(p.pixels, 0), 'online', coalesce(p.seen_at > now() - interval '75 seconds', false),
                            'seen_at', p.seen_at,
                            'seen_day', coalesce((p.seen_at at time zone 'Europe/Paris')::date, p.last_login),
                            'since', p.created_at, 'trophies', public.rc__tshow(p.device),
                            'tro_total', (select coalesce(sum(tier), 0)::int from public.rc_trophy_got g where g.device = p.device), 'owned', public.rc__owned_json(p.device))
    from public.rc_players p where p.pid = p_pid $function$;
;

-- rc_c4_online
CREATE OR REPLACE FUNCTION public.rc_c4_online(p_device text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.rc_players set seen_at = now() where device = p_device;
  return coalesce((
    select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'score', p.score,
             'coins_ok', true, 'friendly', public.rc__duel_why(p_device, p.device),
             'w', (select count(*) from public.rc_c4 g where g.status = 'done'
                     and ((g.p1 = p.device and g.winner = 1) or (g.p2 = p.device and g.winner = 2))),
             'l', (select count(*) from public.rc_c4 g where g.status = 'done'
                     and ((g.p1 = p.device and g.winner = 2) or (g.p2 = p.device and g.winner = 1))),
             'busy', exists (select 1 from public.rc_c4 g where g.mode = 'live' and g.status = 'playing'
                              and p.device in (g.p1, g.p2) and now() <= g.move_at + interval '60 seconds'))
           order by p.seen_at desc)
      from (select * from public.rc_players q
             where q.device <> p_device and q.packs > 0 and q.seen_at > now() - interval '75 seconds'
             order by q.seen_at desc limit 50) p), '[]'::jsonb);
end $function$
;

-- rc_bs_online
CREATE OR REPLACE FUNCTION public.rc_bs_online(p_device text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.rc_players set seen_at = now() where device = p_device;
  return coalesce((
    select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'score', p.score,
             'coins_ok', true, 'friendly', public.rc__duel_why(p_device, p.device),
             'busy', exists (select 1 from public.rc_bs g where g.mode = 'live' and g.status in ('setup', 'playing')
                              and p.device in (g.p1, g.p2) and now() <= g.move_at + interval '2 minutes'),
             'w', (select count(*) from public.rc_bs g where g.status = 'done'
                     and ((g.p1 = p.device and g.winner = 1) or (g.p2 = p.device and g.winner = 2))),
             'l', (select count(*) from public.rc_bs g where g.status = 'done'
                     and ((g.p1 = p.device and g.winner = 2) or (g.p2 = p.device and g.winner = 1))))
           order by p.seen_at desc)
      from (select * from public.rc_players q
             where q.device <> p_device and q.packs > 0 and q.seen_at > now() - interval '75 seconds'
             order by q.seen_at desc limit 50) p), '[]'::jsonb);
end $function$
;

-- rc_duel_ping
CREATE OR REPLACE FUNCTION public.rc_duel_ping(p_device text, p_bg boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare live jsonb; inv int; trn int; last_from text; replies jsonb; onl int;
begin
  if not p_bg then update public.rc_players set seen_at = now() where device = p_device; end if;
  select coalesce(jsonb_agg(x order by x->>'created_at'), '[]'::jsonb) into live from (
    select jsonb_build_object('game', 'c4', 'id', g.id, 'stake', g.stake, 'friendly', public.rc__duel_why(g.p1, g.p2), 'created_at', g.created_at, 'msg', g.msg,
             'deadline', g.created_at + interval '2 minutes', 'now', now(),
             'opp', jsonb_build_object('pid', o.pid, 'name', o.name, 'avatar', o.avatar,
                      'w', (select count(*) from public.rc_c4 h where h.status = 'done' and ((h.p1 = o.device and h.winner = 1) or (h.p2 = o.device and h.winner = 2))),
                      'l', (select count(*) from public.rc_c4 h where h.status = 'done' and ((h.p1 = o.device and h.winner = 2) or (h.p2 = o.device and h.winner = 1))))) as x
      from public.rc_c4 g join public.rc_players o on o.device = g.p1
     where g.p2 = p_device and g.status = 'invite' and g.mode = 'live' and g.created_at > now() - interval '2 minutes'
    union all
    select jsonb_build_object('game', 'bs', 'id', g.id, 'stake', g.stake, 'friendly', public.rc__duel_why(g.p1, g.p2), 'created_at', g.created_at, 'msg', g.msg,
             'deadline', g.created_at + interval '2 minutes', 'now', now(),
             'opp', jsonb_build_object('pid', o.pid, 'name', o.name, 'avatar', o.avatar,
                      'w', (select count(*) from public.rc_bs h where h.status = 'done' and ((h.p1 = o.device and h.winner = 1) or (h.p2 = o.device and h.winner = 2))),
                      'l', (select count(*) from public.rc_bs h where h.status = 'done' and ((h.p1 = o.device and h.winner = 2) or (h.p2 = o.device and h.winner = 1)))))
      from public.rc_bs g join public.rc_players o on o.device = g.p1
     where g.p2 = p_device and g.status = 'invite' and g.mode = 'live' and g.created_at > now() - interval '2 minutes') t;

  select (select count(*) from public.rc_c4 g where g.p2 = p_device and g.status = 'invite' and g.mode = 'turn' and g.created_at > now() - interval '24 hours')
       + (select count(*) from public.rc_bs g where g.p2 = p_device and g.status = 'invite' and g.mode = 'turn' and g.created_at > now() - interval '24 hours')
    into inv;
  select (select count(*) from public.rc_c4 g where g.status = 'playing' and g.mode = 'turn'
            and ((g.p1 = p_device and g.turn = 1) or (g.p2 = p_device and g.turn = 2)))
       + (select count(*) from public.rc_bs g where g.mode = 'turn'
            and ((g.status = 'playing' and ((g.p1 = p_device and g.turn = 1) or (g.p2 = p_device and g.turn = 2)))
              or (g.status = 'setup' and ((g.p1 = p_device and g.fleet1 is null) or (g.p2 = p_device and g.fleet2 is null)))))
    into trn;
  select o.name into last_from from (
      select p1, created_at from public.rc_c4 where p2 = p_device and status = 'invite' and mode = 'turn'
      union all select p1, created_at from public.rc_bs where p2 = p_device and status = 'invite' and mode = 'turn'
      order by created_at desc limit 1) g join public.rc_players o on o.device = g.p1;
  -- réponses reçues à mes défis encore en attente (« J'arrive ! », « Pas maintenant »…)
  select coalesce(jsonb_agg(jsonb_build_object('game', r.jeu, 'id', r.id, 'reply', r.reply, 'mode', r.mode,
                                               'name', o.name, 'avatar', o.avatar)), '[]'::jsonb) into replies
    from (select 'c4' jeu, id, p2, reply, mode from public.rc_c4
           where p1 = p_device and status = 'invite' and reply is not null and created_at > now() - interval '24 hours'
          union all
          select 'bs', id, p2, reply, mode from public.rc_bs
           where p1 = p_device and status = 'invite' and reply is not null and created_at > now() - interval '24 hours') r
    join public.rc_players o on o.device = r.p2;
  -- joueurs en ligne (même règle que rc_board : vus il y a moins de 75 s), pour le compteur du menu
  select count(*) into onl from public.rc_players
   where device <> p_device and packs > 0 and seen_at > now() - interval '75 seconds';
  return jsonb_build_object('online', onl, 'live', live, 'invites', inv, 'turns', trn, 'last_from', last_from, 'replies', replies);
end $function$
;

