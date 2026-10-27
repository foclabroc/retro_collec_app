create or replace function public.rc_duel_ping(p_device text, p_bg boolean DEFAULT false, p_rj boolean DEFAULT false)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare live jsonb; inv int; trn int; last_from text; replies jsonb; onl int; tour jsonb;
begin
  -- « en ligne » : seen_at réécrit seulement s'il date de plus de 30 s (ping toutes les 10-20 s, seuil 75 s)
  if not p_bg then
    update public.rc_players set seen_at = now()
     where device = p_device and (seen_at is null or seen_at < now() - interval '30 seconds');
  end if;
  if p_rj then update public.rc_players set rj_ok = true where device = p_device and not rj_ok; end if;
  begin
    perform public.rc__tour_tick();
  exception when others then null;
  end;
  begin
    perform public.rc__rj_solo_pay();  -- Rétro Jump solo : 3 premiers de la veille
  exception when others then null;
  end;
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
     where g.p2 = p_device and g.status = 'invite' and g.mode = 'live' and g.created_at > now() - interval '2 minutes'
    union all
    select jsonb_build_object('game', 'rj', 'id', g.id, 'stake', g.stake, 'friendly', public.rc__duel_why(g.p1, g.p2), 'created_at', g.created_at, 'msg', g.msg,
             'deadline', g.created_at + interval '2 minutes', 'now', now(),
             'opp', jsonb_build_object('pid', o.pid, 'name', o.name, 'avatar', o.avatar,
                      'w', (select count(*) from public.rc_rj h where h.status = 'done' and ((h.p1 = o.device and h.winner = 1) or (h.p2 = o.device and h.winner = 2))),
                      'l', (select count(*) from public.rc_rj h where h.status = 'done' and ((h.p1 = o.device and h.winner = 2) or (h.p2 = o.device and h.winner = 1)))))
      from public.rc_rj g join public.rc_players o on o.device = g.p1
     where p_rj and g.p2 = p_device and g.status = 'invite' and g.created_at > now() - interval '2 minutes') t;

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
           where p1 = p_device and status = 'invite' and reply is not null and created_at > now() - interval '24 hours'
          union all
          select 'rj', id, p2, reply, mode from public.rc_rj
           where p1 = p_device and status = 'invite' and reply is not null and created_at > now() - interval '2 minutes') r
    join public.rc_players o on o.device = r.p2;
  -- joueurs en ligne (même règle que rc_board : vus il y a moins de 75 s), pour le compteur du menu
  select count(*) into onl from public.rc_players
   where device <> p_device and packs > 0 and seen_at > now() - interval '75 seconds';
  tour := public.rc__tour_me(p_device);
  return jsonb_build_object('online', onl, 'live', live, 'invites', inv, 'turns', trn, 'last_from', last_from, 'replies', replies, 'tour', tour);
end $function$;
