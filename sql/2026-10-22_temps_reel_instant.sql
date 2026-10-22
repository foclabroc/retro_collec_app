-- 2026-10-22 : temps réel instantané (présence tenue par le relais, spectateurs sans attente).
--  · rc__rt_here(canal)    : le relais voit un joueur se connecter → seen_at = now() tout de suite
--                            (le déclencheur rc_players_online_rt envoie 'online' s'il était hors ligne).
--  · rc__rt_alive(canaux)  : toutes les 30 s, le relais tient à jour seen_at des joueurs connectés
--                            → plus besoin du ping de l'appli pour rester « en ligne ».
--  · rc__rt_gone(canal)    : départ (inchangé) mais 'online' porte maintenant le pid.
--  · rc__rt_unwatch(joueur, partie) : le spectateur ferme / quitte → retiré de la liste tout de suite.
--  · 'online' {pid} : arrivée / départ d'un joueur, avec son pid (pages de profil ouvertes).
--  · Seuil « en ligne » harmonisé à 75 s dans les parties et classements de duels (était 2 min).
-- Rôle rc_rt (relais) : execute sur les 4 fonctions. Relançable.

-- ─── Arrivée / départ : 'online' avec le pid ─────────────────────────────
create or replace function public.rc__rt_online()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  perform public.rc__rt_safe('rc_all', 'online', jsonb_build_object('pid', new.pid));
  return null;
end $function$;
alter function public.rc__rt_online() owner to rc_owner;

create or replace trigger rc_players_online_rt after update of seen_at on public.rc_players
  for each row
  when (new.seen_at is not null and (old.seen_at is null or old.seen_at < now() - interval '75 seconds'))
  execute function public.rc__rt_online();

-- ─── Un joueur se connecte au relais ─────────────────────────────────────
create or replace function public.rc__rt_here(p_topic text)
 returns void
 language sql
 security definer
 set search_path to 'public'
as $function$
  update public.rc_players set seen_at = now()
   where public.rc__rt_topic(device) = p_topic and (seen_at is null or seen_at < now() - interval '5 seconds') $function$;
alter function public.rc__rt_here(text) owner to rc_owner;

-- ─── Joueurs connectés au relais (toutes les 30 s) ───────────────────────
create or replace function public.rc__rt_alive(p_topics text[])
 returns void
 language sql
 security definer
 set search_path to 'public'
as $function$
  update public.rc_players set seen_at = now()
   where public.rc__rt_topic(device) = any(p_topics) and (seen_at is null or seen_at < now() - interval '20 seconds') $function$;
alter function public.rc__rt_alive(text[]) owner to rc_owner;

-- ─── Un joueur part (appelé par le relais) ───────────────────────────────
create or replace function public.rc__rt_gone(p_topic text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v text;
begin
  update public.rc_players set seen_at = now() - interval '80 seconds'
   where seen_at > now() - interval '80 seconds' and public.rc__rt_topic(device) = p_topic
  returning pid into v;
  if found then perform public.rc__rt_safe('rc_all', 'online', jsonb_build_object('pid', v)); end if;
end $function$;
alter function public.rc__rt_gone(text) owner to rc_owner;

-- ─── Un spectateur ferme la partie (appelé par le relais) ────────────────
create or replace function public.rc__rt_unwatch(p_player text, p_watch text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare r record;
begin
  for r in delete from public.rc_watch w
            where w.seen_at > now() - interval '1 hour'
              and public.rc__rt_watch_topic(w.game, w.gid) = p_watch
              and public.rc__rt_topic(w.device) = p_player
           returning w.game, w.gid loop
    perform public.rc__watch_send(r.game, r.gid, 'watchers',
      jsonb_build_object('game', r.game, 'gid', r.gid, 'list', public.rc__watch_list(r.game, r.gid)));
  end loop;
end $function$;
alter function public.rc__rt_unwatch(text, text) owner to rc_owner;

grant usage on schema public to rc_rt;
grant execute on function public.rc__rt_here(text) to rc_rt;
grant execute on function public.rc__rt_alive(text[]) to rc_rt;
grant execute on function public.rc__rt_gone(text) to rc_rt;
grant execute on function public.rc__rt_unwatch(text, text) to rc_rt;

-- ─── Seuil « en ligne » : 75 s partout ───────────────────────────────────

create or replace function public.rc__pinfo(p_device text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar,
                            'online', coalesce(p.seen_at > now() - interval '75 seconds', false))
    from public.rc_players p where p.device = p_device $function$;
;

CREATE OR REPLACE FUNCTION public.rc__c4_json(g rc_c4, p_device text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'id', g.id, 'mode', g.mode, 'status', g.status, 'board', g.board, 'turn', g.turn,
    'side', case when g.p1 = p_device then 1 else 2 end,
    'winner', g.winner, 'reason', g.reason, 'stake', g.stake, 'paid', g.paid,
    'friendly', case when g.stake = 0 and g.status <> 'done' then public.rc__duel_why(g.p1, g.p2) end, 'moves', g.moves, 'last_col', g.last_col,
    'deadline', case when g.status = 'invite' then g.created_at + public.rc__c4_invite_limit(g.mode)
                     when g.status = 'playing' then g.move_at + public.rc__c4_limit(g.mode) end,
    'now', now(), 'created_at', g.created_at, 'msg', g.msg, 'reply', g.reply, 'ended_at', case when g.status = 'done' then g.move_at end,
    'emo_opp', case when g.p1 = p_device then g.emo2 else g.emo1 end,
    'emo_opp_at', case when g.p1 = p_device then g.emo2_at else g.emo1_at end,
    'opp', (select jsonb_build_object('pid', o.pid, 'name', o.name, 'avatar', o.avatar,
                                      'online', coalesce(o.seen_at > now() - interval '75 seconds', false))
              from public.rc_players o where o.device = case when g.p1 = p_device then g.p2 else g.p1 end)) $function$
;

CREATE OR REPLACE FUNCTION public.rc__bs_json(g rc_bs, p_device text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with s as (select case when g.p1 = p_device then 1 else 2 end as side)
  select jsonb_build_object(
    'id', g.id, 'mode', g.mode, 'phase', g.status,
    'status', case when g.status = 'setup' then 'playing' else g.status end,
    'turn', case when g.status = 'setup' then
                   case when (case when s.side = 1 then g.fleet1 else g.fleet2 end) is null then s.side else 3 - s.side end
                 else g.turn end,
    'side', s.side,
    'my_fleet', case when s.side = 1 then g.fleet1 else g.fleet2 end,
    'opp_ready', (case when s.side = 1 then g.fleet2 else g.fleet1 end) is not null,
    'my_shots', case when s.side = 1 then g.shots1 else g.shots2 end,
    'opp_shots', case when s.side = 1 then g.shots2 else g.shots1 end,
    'opp_sunk', case when g.status = 'done' then coalesce(case when s.side = 1 then g.fleet2 else g.fleet1 end, '[]'::jsonb)
                     else public.rc__bs_sunk(case when s.side = 1 then g.fleet2 else g.fleet1 end, case when s.side = 1 then g.shots1 else g.shots2 end) end,
    'winner', g.winner, 'reason', g.reason, 'stake', g.stake, 'paid', g.paid,
    'friendly', case when g.stake = 0 and g.status <> 'done' then public.rc__duel_why(g.p1, g.p2) end, 'moves', g.moves,
    'last_cell', g.last_cell, 'last_by', case when g.last_by is null then null when g.last_by = s.side then 'me' else 'opp' end,
    'deadline', case when g.status = 'invite' then g.created_at + public.rc__bs_limit(g.mode, 'invite')
                     when g.status in ('setup', 'playing') then g.move_at + public.rc__bs_limit(g.mode, g.status) end,
    'now', now(), 'created_at', g.created_at, 'msg', g.msg, 'reply', g.reply, 'ended_at', case when g.status = 'done' then g.move_at end,
    'emo_opp', case when s.side = 1 then g.emo2 else g.emo1 end,
    'emo_opp_at', case when s.side = 1 then g.emo2_at else g.emo1_at end,
    'opp', (select jsonb_build_object('pid', o.pid, 'name', o.name, 'avatar', o.avatar,
                                      'online', coalesce(o.seen_at > now() - interval '75 seconds', false))
              from public.rc_players o where o.device = case when s.side = 1 then g.p2 else g.p1 end))
  from s $function$
;

CREATE OR REPLACE FUNCTION public.rc_c4_top()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(x order by (x->>'wins')::int desc), '[]'::jsonb) from (
    select jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'wins', count(*),
                              'online', coalesce(p.seen_at > now() - interval '75 seconds', false)) as x
      from public.rc_c4 g
      join public.rc_players p on p.device = case when g.winner = 1 then g.p1 else g.p2 end
     where g.status = 'done' and g.winner in (1, 2) and g.move_at > now() - interval '7 days'
     group by p.pid, p.name, p.avatar, p.seen_at
     order by count(*) desc limit 10) t $function$
;

CREATE OR REPLACE FUNCTION public.rc_bs_top()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(x order by (x->>'wins')::int desc), '[]'::jsonb) from (
    select jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'wins', count(*),
                              'online', coalesce(p.seen_at > now() - interval '75 seconds', false)) as x
      from public.rc_bs g
      join public.rc_players p on p.device = case when g.winner = 1 then g.p1 else g.p2 end
     where g.status = 'done' and g.winner in (1, 2) and g.move_at > now() - interval '7 days'
     group by p.pid, p.name, p.avatar, p.seen_at
     order by count(*) desc limit 10) t $function$
;
