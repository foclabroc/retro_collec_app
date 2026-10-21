-- 2026-10-21 : temps réel, suite (1.0.18) + regarder les duels en direct.
--  · Spectateurs : rc_live_games() (duels en direct en cours), rc_c4_watch(id), rc_bs_watch(id)
--    (rien de secret : flottes cachées tant qu'elles ne sont pas coulées, ni message d'invitation).
--    Chaque coup part aussi sur le canal de la partie : 'rc_' + sha256('watch|<jeu>|<id>')[0..24].
--  · Canal commun rc_all : 'duels' (un duel en direct commence / finit), 'mail' (courrier, sondage),
--    'events' (événements modifiés), 'player' {pid} (profil ou collection d'un joueur changé),
--    'online' aussi quand un joueur part (rc__rt_gone, appelé par le relais 10 s après sa déconnexion).
--  · Canal du joueur, 'me' : 'prog' (défis de la semaine, trophées), 'react' (réaction à ma nouvelle).
-- Envois par rc__rt_safe : jamais bloquant. Relançable.

-- ─── Canal d'une partie (spectateurs) ─────────────────────────────────────
create or replace function public.rc__rt_watch_topic(p_game text, p_id bigint)
 returns text
 language sql
 immutable
 set search_path to 'public', 'extensions'
as $function$
  select 'rc_' || left(encode(extensions.digest('watch|' || p_game || '|' || p_id, 'sha256'), 'hex'), 24) $function$;

create or replace function public.rc__rt_duel()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare msg jsonb;
begin
  msg := jsonb_build_object('game', tg_argv[0], 'gid', new.id, 'status', new.status);
  begin
    if new.p1 is not null then perform public.rc__rt_send(public.rc__rt_topic(new.p1), 'duel', msg); end if;
    if new.p2 is not null then perform public.rc__rt_send(public.rc__rt_topic(new.p2), 'duel', msg); end if;
    if new.mode = 'live' then
      -- spectateurs de cette partie
      perform public.rc__rt_send(public.rc__rt_watch_topic(tg_argv[0], new.id), 'duel', msg);
      -- liste des parties en cours (début, fin)
      if tg_op = 'INSERT' or new.status is distinct from old.status then
        perform public.rc__rt_send('rc_all', 'duels', '{}'::jsonb);
      end if;
    end if;
  exception when others then
    null; -- relais indisponible : le polling de secours prend le relais
  end;
  return null;
end $function$;

-- ─── Spectateurs ──────────────────────────────────────────────────────────
create or replace function public.rc__pinfo(p_device text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar,
                            'online', coalesce(p.seen_at > now() - interval '2 minutes', false))
    from public.rc_players p where p.device = p_device $function$;

create or replace function public.rc_live_games()
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(x.j order by x.at desc), '[]'::jsonb) from (
    select g.created_at as at, jsonb_build_object('game', 'c4', 'id', g.id, 'phase', g.status, 'moves', g.moves,
             'p1', public.rc__pinfo(g.p1), 'p2', public.rc__pinfo(g.p2)) as j
      from public.rc_c4 g
     where g.mode = 'live' and g.status = 'playing' and now() <= g.move_at + interval '60 seconds'
    union all
    select g.created_at, jsonb_build_object('game', 'bs', 'id', g.id, 'phase', g.status, 'moves', g.moves,
             'p1', public.rc__pinfo(g.p1), 'p2', public.rc__pinfo(g.p2))
      from public.rc_bs g
     where g.mode = 'live' and g.status in ('setup', 'playing') and now() <= g.move_at + interval '2 minutes'
  ) x $function$;

create or replace function public.rc_c4_watch(p_id bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare g public.rc_c4;
begin
  perform public.rc__c4_settle(p_id);
  select * into g from public.rc_c4 where id = p_id and mode = 'live' and status in ('playing', 'done');
  if g.id is null then raise exception 'partie introuvable'; end if;
  -- vue du joueur 1 (side = 1, opp = joueur 2), sans les messages d'invitation
  return (public.rc__c4_json(g, g.p1) - 'msg' - 'reply')
         || jsonb_build_object('watch', true, 'me', public.rc__pinfo(g.p1), 'emo_me', g.emo1, 'emo_me_at', g.emo1_at);
end $function$;

create or replace function public.rc_bs_watch(p_id bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare g public.rc_bs;
begin
  perform public.rc__bs_settle(p_id);
  select * into g from public.rc_bs where id = p_id and mode = 'live' and status in ('setup', 'playing', 'done');
  if g.id is null then raise exception 'partie introuvable'; end if;
  -- vue du joueur 1 ; sa flotte : seulement les consoles coulées (toute la flotte à la fin)
  return (public.rc__bs_json(g, g.p1) - 'msg' - 'reply')
         || jsonb_build_object(
              'watch', true, 'me', public.rc__pinfo(g.p1), 'emo_me', g.emo1, 'emo_me_at', g.emo1_at,
              'me_ready', g.fleet1 is not null,
              'my_fleet', case when g.status = 'done' then coalesce(g.fleet1, '[]'::jsonb)
                               else public.rc__bs_sunk(g.fleet1, coalesce(g.shots2, '')) end,
              'turn', case when g.status = 'setup' then 0 else g.turn end);
end $function$;

-- ─── Un joueur part (appelé par le relais, rôle rc_rt) ────────────────────
create or replace function public.rc__rt_gone(p_topic text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  update public.rc_players set seen_at = now() - interval '80 seconds'
   where seen_at > now() - interval '80 seconds' and public.rc__rt_topic(device) = p_topic;
  if found then perform public.rc__rt_safe('rc_all', 'online', '{}'::jsonb); end if;
end $function$;

-- ─── Canal commun ─────────────────────────────────────────────────────────
create or replace trigger rc_mail_rt after insert on public.rc_mail
  for each statement execute function public.rc__rt_all('mail');
create or replace trigger rc_polls_rt after insert or update on public.rc_polls
  for each statement execute function public.rc__rt_all('mail');
create or replace trigger rc_events_rt after insert or update or delete on public.rc_events
  for each statement execute function public.rc__rt_all('events');

-- profil / collection d'un joueur : {pid}
create or replace function public.rc__rt_player()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare r record;
begin
  if tg_table_name = 'rc_players' then
    perform public.rc__rt_safe('rc_all', 'player', jsonb_build_object('pid', new.pid));
  elsif tg_op = 'DELETE' then
    for r in select distinct p.pid from old_rows o join public.rc_players p on p.device = o.device loop
      perform public.rc__rt_safe('rc_all', 'player', jsonb_build_object('pid', r.pid));
    end loop;
  else
    for r in select distinct p.pid from new_rows o join public.rc_players p on p.device = o.device loop
      perform public.rc__rt_safe('rc_all', 'player', jsonb_build_object('pid', r.pid));
    end loop;
  end if;
  return null;
exception when others then
  return null;
end $function$;

create or replace trigger rc_players_profile_rt after update on public.rc_players
  for each row
  when (new.showcase is distinct from old.showcase or new.avatar is distinct from old.avatar
        or new.name is distinct from old.name or new.house is distinct from old.house
        or new.trophies is distinct from old.trophies or new.score is distinct from old.score
        or new.cards is distinct from old.cards)
  execute function public.rc__rt_player();
create or replace trigger rc_owned_rt_ins after insert on public.rc_owned
  referencing new table as new_rows for each statement execute function public.rc__rt_player();
create or replace trigger rc_owned_rt_upd after update on public.rc_owned
  referencing new table as new_rows for each statement execute function public.rc__rt_player();
create or replace trigger rc_owned_rt_del after delete on public.rc_owned
  referencing old table as old_rows for each statement execute function public.rc__rt_player();

-- ─── Canal du joueur ──────────────────────────────────────────────────────
create or replace function public.rc__rt_me2()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare d text;
begin
  if tg_table_name = 'rc_feed_react' then
    select f.device into d from public.rc_feed f where f.id = new.feed_id;
    if d is not null and d <> new.device then
      perform public.rc__rt_safe(public.rc__rt_topic(d), 'me', '{"k":"react"}');
    end if;
  else -- rc_players (défis de la semaine, paquets, cartes) ou rc_trophy_n
    perform public.rc__rt_safe(public.rc__rt_topic(new.device), 'me', '{"k":"prog"}');
  end if;
  return null;
exception when others then
  return null;
end $function$;

create or replace trigger rc_feed_react_rt after insert or update on public.rc_feed_react
  for each row execute function public.rc__rt_me2();
create or replace trigger rc_players_prog_rt after update on public.rc_players
  for each row
  when (new.w_prog is distinct from old.w_prog or new.w_week is distinct from old.w_week
        or new.packs is distinct from old.packs or new.cards is distinct from old.cards)
  execute function public.rc__rt_me2();
create or replace trigger rc_trophy_n_rt after insert or update on public.rc_trophy_n
  for each row execute function public.rc__rt_me2();

-- ─── Propriétaire et droits ───────────────────────────────────────────────
alter function public.rc__rt_watch_topic(text, bigint) owner to rc_owner;
alter function public.rc__rt_duel() owner to rc_owner;
alter function public.rc__pinfo(text) owner to rc_owner;
alter function public.rc_live_games() owner to rc_owner;
alter function public.rc_c4_watch(bigint) owner to rc_owner;
alter function public.rc_bs_watch(bigint) owner to rc_owner;
alter function public.rc__rt_gone(text) owner to rc_owner;
alter function public.rc__rt_player() owner to rc_owner;
alter function public.rc__rt_me2() owner to rc_owner;
revoke execute on function public.rc__rt_watch_topic(text, bigint) from public, anon, authenticated;
revoke execute on function public.rc__pinfo(text) from public, anon, authenticated;
revoke execute on function public.rc__rt_gone(text) from public, anon, authenticated;
revoke execute on function public.rc__rt_player() from public, anon, authenticated;
revoke execute on function public.rc__rt_me2() from public, anon, authenticated;
grant execute on function public.rc_live_games() to anon, authenticated;
grant execute on function public.rc_c4_watch(bigint) to anon, authenticated;
grant execute on function public.rc_bs_watch(bigint) to anon, authenticated;
-- le relais (rôle rc_rt) prévient quand un joueur se déconnecte
-- (droit sur le schéma : à lancer en postgres, le propriétaire du schéma)
grant usage on schema public to rc_rt;
grant execute on function public.rc__rt_gone(text) to rc_rt;
