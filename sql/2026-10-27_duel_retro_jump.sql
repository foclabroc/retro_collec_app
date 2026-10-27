-- 27/10/2026 : duel Rétro Jump en direct (3e jeu de la Salle de jeux).
-- Même parcours pour les deux (graine tirée ici), sans bonus, 2 minutes max, le plus haut gagne.
-- Mêmes gains que le 4 en ligne (150 pièces + 1 pixel au gagnant, 10 au perdant, parties amicales : rc__duel_why).
-- Chaque joueur envoie sa hauteur toutes les 2 s (rc_rj_score, plafonnée à 70 pts/s), le serveur décide :
--  · les deux sont tombés (ou les 2 min sont finies) → le plus haut gagne, égalité = nul ;
--  · un joueur est tombé et l'autre le dépasse → victoire tout de suite ;
--  · plus de nouvelles d'un joueur depuis 20 s → il est compté tombé à sa dernière hauteur (déconnexion).
-- Seuls les joueurs dont l'appli connaît le jeu peuvent être défiés : rc_players.rj_ok, mis à vrai par
-- rc_duel_ping(…, p_rj => true) (les anciennes appli ne l'envoient pas et ne reçoivent pas ces défis).
-- Les positions du fantôme ne passent pas par la base : relais rc-realtime (événement client 'rjpos'
-- sur le canal de la partie, rc__rt_watch_topic('rj', id)), voir selfhost/rc-realtime/server.js.
-- Relançable. À lancer avant de pousser l'appli.

create table if not exists public.rc_rj (
  id         bigserial primary key,
  p1         text not null,
  p2         text not null,
  mode       text not null default 'live',
  status     text not null default 'invite',   -- invite / playing / done
  seed       integer,
  start_at   timestamptz,                       -- départ (3, 2, 1, GO compris avant)
  end_at     timestamptz,                       -- start_at + 2 min
  h1         integer not null default 0,        -- hauteur max (points) du joueur 1
  h2         integer not null default 0,
  dead1      timestamptz,                       -- tombé (ou fin des 2 min)
  dead2      timestamptz,
  seen1      timestamptz,                       -- dernière hauteur reçue
  seen2      timestamptz,
  gone1      boolean not null default false,    -- compté tombé faute de nouvelles
  gone2      boolean not null default false,
  winner     integer,
  reason     text,
  stake      integer not null default 0,
  paid       boolean,
  moves      integer not null default 0,        -- hauteurs reçues (0 = personne n'a joué)
  msg        text,
  reply      text,
  tmatch     bigint,                            -- pas de tournoi pour l'instant (colonne lue par les déclencheurs communs)
  created_at timestamptz not null default now(),
  move_at    timestamptz not null default now()
);
create index if not exists rc_rj_p1 on public.rc_rj (p1, status);
create index if not exists rc_rj_p2 on public.rc_rj (p2, status);
alter table public.rc_rj owner to rc_owner;
revoke all on public.rc_rj from public;
alter table public.rc_players add column if not exists rj_ok boolean not null default false;
do $$ begin
  revoke all on public.rc_rj from anon, authenticated;
  revoke all on sequence public.rc_rj_id_seq from anon, authenticated;
exception when undefined_object then null;
end $$;

-- ─── JSON d'une partie, vue du joueur p_device ───────────────────────────
create or replace function public.rc__rj_json(g public.rc_rj, p_device text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object(
    'id', g.id, 'mode', g.mode, 'status', g.status,
    'side', case when g.p1 = p_device then 1 else 2 end,
    'winner', g.winner, 'reason', g.reason, 'stake', g.stake, 'paid', g.paid,
    'friendly', case when g.stake = 0 and g.status <> 'done' then public.rc__duel_why(g.p1, g.p2) end,
    'moves', g.moves, 'seed', g.seed, 'start_at', g.start_at, 'end_at', g.end_at,
    'h_me', case when g.p1 = p_device then g.h1 else g.h2 end,
    'h_opp', case when g.p1 = p_device then g.h2 else g.h1 end,
    'dead_me', case when g.p1 = p_device then g.dead1 is not null else g.dead2 is not null end,
    'dead_opp', case when g.p1 = p_device then g.dead2 is not null else g.dead1 is not null end,
    'deadline', case when g.status = 'invite' then g.created_at + interval '2 minutes'
                     when g.status = 'playing' then g.end_at end,
    'now', now(), 'created_at', g.created_at, 'msg', g.msg, 'reply', g.reply,
    'ended_at', case when g.status = 'done' then g.move_at end,
    'opp', (select jsonb_build_object('pid', o.pid, 'name', o.name, 'avatar', o.avatar,
                                      'online', coalesce(o.seen_at > now() - interval '75 seconds', false))
              from public.rc_players o where o.device = case when g.p1 = p_device then g.p2 else g.p1 end)) $function$;
alter function public.rc__rj_json(public.rc_rj, text) owner to rc_owner;

-- ─── Fin de partie : mêmes gains que le 4 en ligne ─────────────────────────
create or replace function public.rc__rj_finish(p_id bigint, p_winner integer, p_reason text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare g public.rc_rj; ok boolean; m int := least(coalesce(public.rc__effect('duel_x'), 1), 5);
begin
  select * into g from public.rc_rj where id = p_id;
  if g.status <> 'playing' then return; end if;
  ok := g.moves > 0 and public.rc__duel_paid(g.p1, g.p2);
  update public.rc_rj set status = 'done', winner = p_winner, reason = p_reason, paid = ok, move_at = now() where id = p_id;
  if not ok then return; end if;  -- partie amicale (ou personne n'a joué) : pas de gains
  if p_winner in (1, 2) then perform public.rc__wbump(case when p_winner = 1 then g.p1 else g.p2 end, 'win', 1); end if;
  perform public.rc__wbump(g.p1, 'play', 1);
  perform public.rc__wbump(g.p2, 'play', 1);
  if p_winner = 0 then
    update public.rc_players set coins = coins + 10 * m where device in (g.p1, g.p2);
  else
    update public.rc_players set coins = coins + 150 * m, pixels = pixels + 1
     where device = case when p_winner = 1 then g.p1 else g.p2 end;
    update public.rc_players set coins = coins + 10 * m
     where device = case when p_winner = 1 then g.p2 else g.p1 end;
  end if;
end $function$;
alter function public.rc__rj_finish(bigint, integer, text) owner to rc_owner;

-- ─── Arbitre : invitation expirée, déconnexion, fin de partie ──────────────
create or replace function public.rc__rj_settle(p_id bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare g public.rc_rj; over boolean; d1 boolean; d2 boolean; w int; why text;
begin
  select * into g from public.rc_rj where id = p_id for update;
  if g.id is null then return; end if;
  if g.status = 'invite' then
    if now() > g.created_at + interval '2 minutes' then
      update public.rc_rj set status = 'done', reason = 'expired', move_at = now() where id = p_id;
    end if;
    return;
  end if;
  if g.status <> 'playing' then return; end if;
  -- plus de nouvelles depuis 20 s (et la partie a commencé depuis 20 s) : compté tombé
  if g.dead1 is null and now() > g.start_at + interval '20 seconds'
     and coalesce(g.seen1, g.start_at) < now() - interval '20 seconds' then
    g.dead1 := coalesce(g.seen1, g.start_at); g.gone1 := true;
    update public.rc_rj set dead1 = g.dead1, gone1 = true where id = p_id;
  end if;
  if g.dead2 is null and now() > g.start_at + interval '20 seconds'
     and coalesce(g.seen2, g.start_at) < now() - interval '20 seconds' then
    g.dead2 := coalesce(g.seen2, g.start_at); g.gone2 := true;
    update public.rc_rj set dead2 = g.dead2, gone2 = true where id = p_id;
  end if;
  over := now() > g.end_at + interval '5 seconds';  -- 2 min passées (+ 5 s pour la dernière hauteur)
  d1 := g.dead1 is not null or over;
  d2 := g.dead2 is not null or over;
  if d1 and d2 then
    w := case when g.h1 > g.h2 then 1 when g.h2 > g.h1 then 2 else 0 end;
  elsif g.dead1 is not null and g.h2 > g.h1 then
    w := 2;
  elsif g.dead2 is not null and g.h1 > g.h2 then
    w := 1;
  else
    return;  -- on continue
  end if;
  why := case when w = 0 then 'draw'
              when (w = 1 and g.gone2) or (w = 2 and g.gone1) then 'timeout'
              else 'win' end;
  perform public.rc__rj_finish(p_id, w, why);
end $function$;
alter function public.rc__rj_settle(bigint) owner to rc_owner;

-- ─── Défier un joueur en ligne (en direct seulement) ───────────────────────
create or replace function public.rc_rj_invite(p_device text, p_pid text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v public.rc_players; o public.rc_players; gid bigint;
begin
  perform public.rc__check(p_sig, p_device || '|rjinv|' || coalesce(p_pid, ''));
  select * into v from public.rc_players where device = p_device;
  select * into o from public.rc_players where pid = p_pid;
  if v.device is null or o.device is null then raise exception 'joueur inconnu'; end if;
  if o.device = v.device then raise exception 'pas contre toi-même'; end if;
  perform public.rc__not_blocked(p_device);
  if o.blocked then raise exception 'joueur indisponible'; end if;
  if not o.rj_ok then raise exception 'joueur à mettre à jour'; end if;
  if coalesce(o.seen_at < now() - interval '2 minutes', true) then raise exception 'joueur hors ligne'; end if;
  if exists (select 1 from public.rc_rj g where g.status in ('invite', 'playing')
              and ((g.p1 = v.device and g.p2 = o.device) or (g.p1 = o.device and g.p2 = v.device))
              and now() <= case when g.status = 'invite' then g.created_at + interval '2 minutes'
                                else g.end_at + interval '30 seconds' end) then
    raise exception 'partie déjà en cours';
  end if;
  if (select count(*) from public.rc_rj g where g.status in ('invite', 'playing') and v.device in (g.p1, g.p2)
        and g.created_at > now() - interval '10 minutes') >= 5 then
    raise exception 'trop de défis';
  end if;
  update public.rc_players set seen_at = now() where device = p_device;
  insert into public.rc_rj (p1, p2) values (v.device, o.device) returning id into gid;
  return public.rc__rj_json((select g from public.rc_rj g where g.id = gid), p_device);
end $function$;
alter function public.rc_rj_invite(text, text, text) owner to rc_owner;

-- ─── Accepter / refuser (ou annuler son invitation) ────────────────────────
create or replace function public.rc_rj_answer(p_device text, p_id bigint, p_accept boolean, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare g public.rc_rj;
begin
  perform public.rc__check(p_sig, p_device || '|rjans|' || p_id || '|' || case when p_accept then 1 else 0 end);
  perform public.rc__rj_settle(p_id);
  select * into g from public.rc_rj where id = p_id for update;
  if g.id is null or p_device not in (g.p1, g.p2) then raise exception 'partie inconnue'; end if;
  if g.status <> 'invite' then raise exception 'invitation expirée'; end if;
  if not p_accept then
    update public.rc_rj set status = 'done', reason = case when p_device = g.p1 then 'cancelled' else 'declined' end, move_at = now()
     where id = p_id;
  else
    if p_device <> g.p2 then raise exception 'partie inconnue'; end if;
    perform public.rc__not_blocked(p_device);
    if exists (select 1 from public.rc_players where device = g.p1 and blocked) then raise exception 'joueur indisponible'; end if;
    update public.rc_players set seen_at = now() where device = p_device;
    -- départ dans 6 s : le temps d'ouvrir la partie des deux côtés + 3, 2, 1
    update public.rc_rj set status = 'playing', seed = floor(random() * 2147483646)::int + 1,
           start_at = now() + interval '6 seconds', end_at = now() + interval '126 seconds', move_at = now()
     where id = p_id;
  end if;
  select * into g from public.rc_rj where id = p_id;
  return public.rc__rj_json(g, p_device) || jsonb_build_object('coins', (select coins from public.rc_players where device = p_device));
end $function$;
alter function public.rc_rj_answer(text, bigint, boolean, text) owner to rc_owner;

-- ─── Ma hauteur (toutes les 2 s, à la chute et à la fin des 2 min) ─────────
create or replace function public.rc_rj_score(p_device text, p_id bigint, p_h integer, p_dead boolean, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare g public.rc_rj; side int; cap int;
begin
  perform public.rc__check(p_sig, p_device || '|rjsc|' || p_id || '|' || p_h || '|' || case when p_dead then 1 else 0 end);
  select * into g from public.rc_rj where id = p_id for update;
  if g.id is null or p_device not in (g.p1, g.p2) then raise exception 'partie inconnue'; end if;
  side := case when g.p1 = p_device then 1 else 2 end;
  if g.status = 'playing' and now() <= g.end_at + interval '5 seconds'
     and (case when side = 1 then g.dead1 else g.dead2 end) is null then
    -- plafond : 70 points par seconde de jeu (sans bonus, on monte bien moins vite)
    cap := 60 + floor(70 * greatest(0, extract(epoch from (least(now(), g.end_at) - g.start_at))))::int;
    p_h := least(greatest(coalesce(p_h, 0), 0), cap);
    if side = 1 then
      update public.rc_rj set h1 = greatest(h1, p_h), seen1 = now(), moves = moves + 1,
             dead1 = case when p_dead then now() end, move_at = now() where id = p_id;
    else
      update public.rc_rj set h2 = greatest(h2, p_h), seen2 = now(), moves = moves + 1,
             dead2 = case when p_dead then now() end, move_at = now() where id = p_id;
    end if;
  end if;
  update public.rc_players set seen_at = now()
   where device = p_device and (seen_at is null or seen_at < now() - interval '30 seconds');
  perform public.rc__rj_settle(p_id);
  select * into g from public.rc_rj where id = p_id;
  return public.rc__rj_json(g, p_device);
end $function$;
alter function public.rc_rj_score(text, bigint, integer, boolean, text) owner to rc_owner;

-- ─── État d'une partie ─────────────────────────────────────────────────────
create or replace function public.rc_rj_state(p_device text, p_id bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare g public.rc_rj;
begin
  update public.rc_players set seen_at = now() where device = p_device;
  perform public.rc__rj_settle(p_id);
  select * into g from public.rc_rj where id = p_id and (p1 = p_device or p2 = p_device);
  if g.id is null then raise exception 'partie inconnue'; end if;
  return public.rc__rj_json(g, p_device) || jsonb_build_object('coins', (select coins from public.rc_players where device = p_device));
end $function$;
alter function public.rc_rj_state(text, bigint) owner to rc_owner;

-- ─── Mes parties (salon) ───────────────────────────────────────────────────
create or replace function public.rc_rj_list(p_device text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare r record;
begin
  update public.rc_players set seen_at = now() where device = p_device;
  for r in select id from public.rc_rj where (p1 = p_device or p2 = p_device) and status in ('invite', 'playing') loop
    perform public.rc__rj_settle(r.id);
  end loop;
  return coalesce((
    select jsonb_agg(public.rc__rj_json(g, p_device) order by
             case g.status when 'playing' then 0 when 'invite' then 1 else 2 end, g.move_at desc)
      from (select * from public.rc_rj x
             where (x.p1 = p_device or x.p2 = p_device)
               and (x.status <> 'done' or x.move_at > now() - interval '3 days')
             order by x.id desc limit 40) g), '[]'::jsonb);
end $function$;
alter function public.rc_rj_list(text) owner to rc_owner;

-- ─── Joueurs en ligne (salon) ──────────────────────────────────────────────
create or replace function public.rc_rj_online(p_device text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  update public.rc_players set seen_at = now() where device = p_device;
  return coalesce((
    select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'score', p.score,
             'coins_ok', true, 'friendly', public.rc__duel_why(p_device, p.device),
             'w', (select count(*) from public.rc_rj g where g.status = 'done'
                     and ((g.p1 = p.device and g.winner = 1) or (g.p2 = p.device and g.winner = 2))),
             'l', (select count(*) from public.rc_rj g where g.status = 'done'
                     and ((g.p1 = p.device and g.winner = 2) or (g.p2 = p.device and g.winner = 1))),
             'busy', public.rc__duel_busy(p.device))
           order by p.seen_at desc)
      from (select * from public.rc_players q
             where q.device <> p_device and q.packs > 0 and q.rj_ok and q.seen_at > now() - interval '75 seconds'
             order by q.seen_at desc limit 50) p), '[]'::jsonb);
end $function$;
alter function public.rc_rj_online(text) owner to rc_owner;

-- ─── Statistiques et meilleurs joueurs ─────────────────────────────────────
create or replace function public.rc_rj_stats(p_device text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare w int := 0; l int := 0; d int := 0; net int := 0; streak int := 0; best int := 0; r record; counting boolean := true;
begin
  for r in select (case when p1 = p_device then 1 else 2 end) as side, winner, paid,
                  case when p1 = p_device then h1 else h2 end as h
             from public.rc_rj
            where (p1 = p_device or p2 = p_device) and status = 'done' and winner is not null
            order by move_at desc loop
    best := greatest(best, r.h);
    if r.winner = 0 then d := d + 1; counting := false; if r.paid then net := net + 10; end if;
    elsif r.winner = r.side then w := w + 1; if r.paid then net := net + 150; end if; if counting then streak := streak + 1; end if;
    else l := l + 1; if r.paid then net := net + 10; end if; counting := false;
    end if;
  end loop;
  return jsonb_build_object('wins', w, 'losses', l, 'draws', d, 'streak', streak, 'net', net, 'best', best);
end $function$;
alter function public.rc_rj_stats(text) owner to rc_owner;

create or replace function public.rc_rj_top()
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(x order by (x->>'wins')::int desc), '[]'::jsonb) from (
    select jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'wins', count(*),
                              'online', coalesce(p.seen_at > now() - interval '75 seconds', false)) as x
      from public.rc_rj g
      join public.rc_players p on p.device = case when g.winner = 1 then g.p1 else g.p2 end
     where g.status = 'done' and g.winner in (1, 2) and g.move_at > now() - interval '7 days'
     group by p.pid, p.name, p.avatar, p.seen_at
     order by count(*) desc limit 10) t $function$;
alter function public.rc_rj_top() owner to rc_owner;

-- ─── Spectateur : vue du joueur 1 (+ 'me' = joueur 1) ──────────────────────
create or replace function public.rc_rj_watch(p_id bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare g public.rc_rj;
begin
  perform public.rc__rj_settle(p_id);
  select * into g from public.rc_rj where id = p_id and status in ('playing', 'done');
  if g.id is null then raise exception 'partie introuvable'; end if;
  return (public.rc__rj_json(g, g.p1) - 'msg' - 'reply') || jsonb_build_object('watch', true, 'me', public.rc__pinfo(g.p1));
end $function$;
alter function public.rc_rj_watch(bigint) owner to rc_owner;

-- ─── « En partie » : duel en direct en cours (4 en ligne, Console Wars, Rétro Jump) ───
create or replace function public.rc__duel_busy(p_device text)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select exists (select 1 from public.rc_c4 g where g.mode = 'live' and g.status = 'playing'
                  and p_device in (g.p1, g.p2) and now() <= g.move_at + interval '60 seconds')
      or exists (select 1 from public.rc_bs g where g.mode = 'live' and g.status in ('setup', 'playing')
                  and p_device in (g.p1, g.p2) and now() <= g.move_at + interval '2 minutes')
      or exists (select 1 from public.rc_rj g where g.status = 'playing'
                  and p_device in (g.p1, g.p2) and now() <= g.end_at + interval '10 seconds') $function$;
alter function public.rc__duel_busy(text) owner to rc_owner;

-- ═══ Fonctions existantes complétées pour Rétro Jump (même texte que sql/schema/) ═══

-- rc__duel_why (Rétro Jump ajouté)
CREATE OR REPLACE FUNCTION public.rc__duel_why(p_a text, p_b text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case
    when exists (select 1 from public.rc_players where device in (p_a, p_b) and created_at > now() - interval '1 day') then 'new'
    when (select count(*) from (
            select 1 from public.rc_c4 g where g.paid and ((g.p1 = p_a and g.p2 = p_b) or (g.p1 = p_b and g.p2 = p_a))
               and (g.move_at at time zone 'Europe/Paris')::date = (now() at time zone 'Europe/Paris')::date
            union all
            select 1 from public.rc_bs g where g.paid and ((g.p1 = p_a and g.p2 = p_b) or (g.p1 = p_b and g.p2 = p_a))
               and (g.move_at at time zone 'Europe/Paris')::date = (now() at time zone 'Europe/Paris')::date
            union all
            select 1 from public.rc_rj g where g.paid and ((g.p1 = p_a and g.p2 = p_b) or (g.p1 = p_b and g.p2 = p_a))
               and (g.move_at at time zone 'Europe/Paris')::date = (now() at time zone 'Europe/Paris')::date) x) >= 4 then 'limit'
  end $function$;

-- rc_duel_msg (Rétro Jump ajouté)
CREATE OR REPLACE FUNCTION public.rc_duel_msg(p_device text, p_game text, p_id bigint, p_msg text, p_sig text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare n int;
begin
  perform public.rc__check(p_sig, p_device || '|dmsg|' || coalesce(p_game, '') || '|' || p_id || '|' || coalesce(p_msg, ''));
  if p_game = 'c4' then
    update public.rc_c4 set msg = public.rc__duel_text(p_msg) where id = p_id and p1 = p_device and status = 'invite';
  elsif p_game = 'bs' then
    update public.rc_bs set msg = public.rc__duel_text(p_msg) where id = p_id and p1 = p_device and status = 'invite';
  elsif p_game = 'rj' then
    update public.rc_rj set msg = public.rc__duel_text(p_msg) where id = p_id and p1 = p_device and status = 'invite';
  else
    raise exception 'jeu inconnu';
  end if;
  get diagnostics n = row_count;
  return n > 0;
end $function$;

-- rc_duel_reply (Rétro Jump ajouté)
CREATE OR REPLACE FUNCTION public.rc_duel_reply(p_device text, p_game text, p_id bigint, p_msg text, p_sig text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare n int;
begin
  perform public.rc__check(p_sig, p_device || '|dreply|' || coalesce(p_game, '') || '|' || p_id || '|' || coalesce(p_msg, ''));
  if p_game = 'c4' then
    update public.rc_c4 set reply = public.rc__duel_text(p_msg) where id = p_id and p2 = p_device and status = 'invite';
  elsif p_game = 'bs' then
    update public.rc_bs set reply = public.rc__duel_text(p_msg) where id = p_id and p2 = p_device and status = 'invite';
  elsif p_game = 'rj' then
    update public.rc_rj set reply = public.rc__duel_text(p_msg) where id = p_id and p2 = p_device and status = 'invite';
  else
    raise exception 'jeu inconnu';
  end if;
  get diagnostics n = row_count;
  return n > 0;
end $function$;

-- rc__watch_game (Rétro Jump ajouté)
create or replace function public.rc__watch_game(p_game text, p_id bigint)
 returns table(p1 text, p2 text)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select g.p1, g.p2 from public.rc_c4 g
   where p_game = 'c4' and g.id = p_id and g.mode = 'live' and g.status = 'playing'
  union all
  select g.p1, g.p2 from public.rc_bs g
   where p_game = 'bs' and g.id = p_id and g.mode = 'live' and g.status in ('setup', 'playing')
  union all
  select g.p1, g.p2 from public.rc_rj g
   where p_game = 'rj' and g.id = p_id and g.status = 'playing' $function$;

-- rc_live_games (Rétro Jump ajouté)
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
    union all
    select g.created_at, jsonb_build_object('game', 'rj', 'id', g.id, 'phase', g.status, 'moves', g.moves,
             'h1', g.h1, 'h2', g.h2, 'end_at', g.end_at, 'now', now(),
             'p1', public.rc__pinfo(g.p1), 'p2', public.rc__pinfo(g.p2))
      from public.rc_rj g
     where g.status = 'playing' and now() <= g.end_at + interval '10 seconds'
  ) x $function$;

-- rc_duel_ping (Rétro Jump ajouté) : nouveau paramètre p_rj (appli qui connaît le duel Rétro Jump)
drop function if exists public.rc_duel_ping(text, boolean);
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
alter function public.rc_duel_ping(text, boolean, boolean) owner to rc_owner;

-- rc_board (Rétro Jump ajouté)
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
         -- en duel en direct (4 en ligne, Console Wars, Rétro Jump)
         public.rc__duel_busy(p.device)
    from public.rc_players p
   where p.packs > 0 and greatest(p.seen_at, p.last_login::timestamptz) > now() - interval '7 days'
   order by p.score desc, p.created_at asc limit 100 $function$;

-- rc_c4_online (Rétro Jump ajouté)
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
             'busy', public.rc__duel_busy(p.device))
           order by p.seen_at desc)
      from (select * from public.rc_players q
             where q.device <> p_device and q.packs > 0 and q.seen_at > now() - interval '75 seconds'
             order by q.seen_at desc limit 50) p), '[]'::jsonb);
end $function$;

-- rc_bs_online (Rétro Jump ajouté)
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
             'busy', public.rc__duel_busy(p.device),
             'w', (select count(*) from public.rc_bs g where g.status = 'done'
                     and ((g.p1 = p.device and g.winner = 1) or (g.p2 = p.device and g.winner = 2))),
             'l', (select count(*) from public.rc_bs g where g.status = 'done'
                     and ((g.p1 = p.device and g.winner = 2) or (g.p2 = p.device and g.winner = 1))))
           order by p.seen_at desc)
      from (select * from public.rc_players q
             where q.device <> p_device and q.packs > 0 and q.seen_at > now() - interval '75 seconds'
             order by q.seen_at desc limit 50) p), '[]'::jsonb);
end $function$;

-- rc__feed_duel (Rétro Jump ajouté)
create or replace function public.rc__feed_duel()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare k text := case tg_table_name when 'rc_bs' then 'bs' when 'rc_rj' then 'rj' else 'c4' end;
begin
  if new.status <> 'done' or old.status = 'done' then return new; end if;
  if new.tmatch is not null then return new; end if;  -- tournoi : une seule nouvelle à la fin
  if new.reason not in ('win', 'draw', 'timeout', 'resign') or new.moves = 0 then return new; end if;
  if new.winner = 0 then
    perform public.rc__feed_put(new.p1, k || 'draw', new.p2, null, null, null, null, new.reason);
  elsif new.winner in (1, 2) then
    perform public.rc__feed_put(case new.winner when 1 then new.p1 else new.p2 end, k,
                                case new.winner when 1 then new.p2 else new.p1 end,
                                null, null, null, case when new.stake > 0 then new.stake * 2 when new.paid then 150 end, new.reason);
  end if;
  return new;
end $function$;

-- rc__act_duel (Rétro Jump ajouté)
create or replace function public.rc__act_duel()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare jeu text := case tg_table_name when 'rc_bs' then 'Console Wars' when 'rc_rj' then 'Rétro Jump' else '4 en ligne' end;
        how text; ami text;
begin
  begin
    if tg_op = 'INSERT' then
      if new.tmatch is not null then
        perform public.rc__act(new.p1, 'tour', 2, 'match de tournoi à ' || jeu || ' contre', null, null, new.p2);
        perform public.rc__act(new.p2, 'tour', 2, 'match de tournoi à ' || jeu || ' contre', null, null, new.p1);
      else
        perform public.rc__act(new.p1, 'duel', 2, 'invite à ' || jeu, null, null, new.p2);
      end if;
    elsif new.status = 'done' and old.status is distinct from 'done' then
      if new.reason in ('win', 'draw', 'timeout', 'resign') then
        how := case new.reason when 'timeout' then ' (temps écoulé)' when 'resign' then ' (abandon)' else '' end;
        ami := case when new.tmatch is not null then ' — tournoi' when coalesce(new.paid, false) then '' else ' — amical' end;
        if new.winner in (1, 2) then
          perform public.rc__act(case new.winner when 1 then new.p1 else new.p2 end, 'duel', 2,
                                 'gagne à ' || jeu || how || ami || ' contre', null, null,
                                 case new.winner when 1 then new.p2 else new.p1 end);
          perform public.rc__act(case new.winner when 1 then new.p2 else new.p1 end, 'duel', 2,
                                 'perd à ' || jeu || how || ami || ' contre', null, null,
                                 case new.winner when 1 then new.p1 else new.p2 end);
        else
          perform public.rc__act(new.p1, 'duel', 2, 'match nul à ' || jeu || ami || ' contre', null, null, new.p2);
          perform public.rc__act(new.p2, 'duel', 2, 'match nul à ' || jeu || ami || ' contre', null, null, new.p1);
        end if;
      elsif new.reason = 'declined' then
        perform public.rc__act(new.p2, 'duel', 2, 'refuse le ' || jeu || ' de', null, null, new.p1);
      elsif new.reason = 'cancelled' then
        perform public.rc__act(new.p1, 'duel', 2, 'annule son invitation à ' || jeu || ' pour', null, null, new.p2);
      end if;
    end if;
  exception when others then null;
  end;
  return new;
end $function$;

-- rc_admin_feed (Rétro Jump ajouté)
-- Admin : journal de TOUS les joueurs (même contenu que l'activité d'une fiche joueur),
-- du plus récent au plus ancien, 150 lignes par page (p_before = date de la dernière ligne reçue, '' = début).
-- Avec les courriers / cadeaux de l'admin (envoi + récupération) depuis le 22/10. Relançable.
create or replace function public.rc_admin_feed(p_device text, p_sig text, p_before text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare b timestamptz;
begin
  perform public.rc__admin(p_device, p_sig, 'feed|' || coalesce(p_before, ''));
  b := case when coalesce(p_before, '') = '' then now() + interval '1 minute' else p_before::timestamptz end;
  return coalesce((
    select jsonb_agg(
             r.e || jsonb_build_object('at', r.at, 'pid', p.pid, 'name', p.name, 'avatar', p.avatar,
                                       'other', coalesce(o.name, r.e->>'other'))
                 || case when r.e->>'kind' = 'sold'
                         then jsonb_build_object('avg', public.rc__avg_price(r.e->>'card', (r.e->>'f')::int, (r.e->>'mid')::bigint))
                         else '{}'::jsonb end
             order by r.at desc)
      from (
        select * from (
          -- Bourse : mise en vente (pas vendue) ou vente conclue, vue du vendeur
          select coalesce(m.sold_at, m.created_at) at, m.seller dev, m.buyer odev,
                 jsonb_build_object('kind', case when m.buyer is null then 'listing' else 'sold' end,
                                    'card', m.card, 'f', m.finish, 'price', m.price, 'mid', m.id) e
            from public.rc_market m
           where coalesce(m.sold_at, m.created_at) < b
          union all
          -- échanges, vus de celui qui propose
          select coalesce(t.done_at, t.created_at), t.sender, t.receiver,
                 jsonb_build_object('kind', 'trade', 'status', t.status, 'gave', t.give, 'got', t.want,
                                    'gave_v', public.rc__items_value(t.give), 'got_v', public.rc__items_value(t.want))
            from public.rc_trades t
           where coalesce(t.done_at, t.created_at) < b
          union all
          -- cadeaux, vus de celui qui offre ; cadeau du jeu (sans donneur : défis, courrier, parrainage…) vu de celui qui le reçoit
          select g.created_at, coalesce(g.giver, g.receiver), case when g.giver is null then null else g.receiver end,
                 jsonb_build_object('kind', case when g.giver is null then 'gift_in' else 'gift_out' end,
                                    'other', case when g.giver is null then g.giver_name end)
            from public.rc_gifts g
           where g.created_at < b
          union all
          -- duels, vus du joueur 1
          select x.created_at, x.p1, x.p2,
                 jsonb_build_object('kind', 'duel', 'game', x.jeu, 'status', x.status, 'reason', x.reason,
                                    'result', case when x.winner = 0 then 'draw' when x.winner is null then null
                                                   when x.winner = 1 then 'win' else 'loss' end)
            from (select 'c4' jeu, p1, p2, status, reason, winner, created_at from public.rc_c4
                  union all select 'bs', p1, p2, status, reason, winner, created_at from public.rc_bs
                  union all select 'rj', p1, p2, status, reason, winner, created_at from public.rc_rj) x
           where x.created_at < b
          union all
          select c.created_at, c.device, null::text,
                 jsonb_build_object('kind', 'chat', 'msg', c.msg, 'hidden', c.hidden, 'reports', c.reports)
            from public.rc_chat c
           where c.created_at < b
          union all
          select l.at, l.device, null::text, jsonb_build_object('kind', 'pack', 'pack', l.kind, 'sys', l.sys)
            from public.rc_pack_log l
           where l.at < b
          union all
          -- courrier / cadeau de l'admin : envoi, vu du destinataire (sans joueur = envoi à un groupe)
          select m.created_at, m.device, null::text,
                 jsonb_build_object('kind', 'mail_sent', 'title', m.title,
                                    'grp', coalesce(m.grp, case when m.device is null then 'all' end),
                                    'reward', case when coalesce(m.reward, '{}'::jsonb) = '{}'::jsonb
                                                   then jsonb_strip_nulls(jsonb_build_object(
                                                          'coins', nullif(m.coins, 0), 'pixels', nullif(m.pixels, 0),
                                                          'packs', case when m.packs > 0 then jsonb_build_object('premium', m.packs) end))
                                                   else m.reward end)
            from public.rc_mail m
           where m.created_at < b
          union all
          -- courrier récupéré par le joueur (journal d'activité : pièces / pixels versés)
          select a.at, a.device, null::text,
                 jsonb_build_object('kind', 'mail_got', 'txt', a.txt, 'coins', a.coins, 'pixels', a.pixels)
            from public.rc_activity a
           where a.at < b and a.at > now() - interval '30 days' and a.txt like 'récupère le courrier%'
        ) u
        order by u.at desc
        limit 150
      ) r
      left join public.rc_players p on p.device = r.dev
      left join public.rc_players o on o.device = r.odev), '[]'::jsonb);
end $function$;

-- rc_admin_player (Rétro Jump ajouté)
create or replace function public.rc_admin_player(p_device text, p_sig text, p_pid text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v public.rc_players;
begin
  perform public.rc__admin(p_device, p_sig, 'player|' || coalesce(p_pid, ''));
  select * into v from public.rc_players where pid = p_pid;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  return jsonb_build_object(
    'pid', v.pid, 'name', v.name, 'avatar', v.avatar, 'created_at', v.created_at, 'seen_at', v.seen_at,
    'coins', v.coins, 'pixels', v.pixels, 'packs', v.packs, 'cards', v.cards, 'score', v.score, 'days', v.days, 'blocked', v.blocked,
    'ver', v.app_ver, 'os', v.app_os, 'ver_at', v.app_at,
    'referrer', (select s.name from public.rc_players s where s.device = v.referrer),
    'events', coalesce((select jsonb_agg(e order by e->>'at' desc) from (
      select e from (
        select jsonb_build_object('at', coalesce(m.sold_at, m.created_at), 'kind', case when m.seller = v.device then (case when m.buyer is null then 'listing' else 'sold' end) else 'bought' end,
                 'other', (select o.name from public.rc_players o where o.device = case when m.seller = v.device then m.buyer else m.seller end),
                 'card', m.card, 'f', m.finish, 'price', m.price,
                 'avg', public.rc__avg_price(m.card, m.finish, m.id)) e
          from public.rc_market m where v.device in (m.seller, m.buyer)
        union all
        select jsonb_build_object('at', coalesce(t.done_at, t.created_at), 'kind', 'trade', 'status', t.status,
                 'other', (select o.name from public.rc_players o where o.device = case when t.sender = v.device then t.receiver else t.sender end),
                 'gave', case when t.sender = v.device then t.give else t.want end,
                 'got', case when t.sender = v.device then t.want else t.give end,
                 'gave_v', public.rc__items_value(case when t.sender = v.device then t.give else t.want end),
                 'got_v', public.rc__items_value(case when t.sender = v.device then t.want else t.give end))
          from public.rc_trades t where v.device in (t.sender, t.receiver)
        union all
        select jsonb_build_object('at', g.created_at, 'kind', case when g.giver = v.device then 'gift_out' else 'gift_in' end,
                 'other', coalesce((select o.name from public.rc_players o where o.device = case when g.giver = v.device then g.receiver else g.giver end), g.giver_name))
          from public.rc_gifts g where v.device in (g.giver, g.receiver)
        union all
        select jsonb_build_object('at', x.created_at, 'kind', 'duel', 'game', x.jeu, 'status', x.status, 'reason', x.reason,
                 'other', (select o.name from public.rc_players o where o.device = case when x.p1 = v.device then x.p2 else x.p1 end),
                 'result', case when x.winner = 0 then 'draw' when x.winner is null then null
                                when (x.winner = 1) = (x.p1 = v.device) then 'win' else 'loss' end)
          from (select 'c4' jeu, p1, p2, status, reason, winner, created_at from public.rc_c4
                union all select 'bs', p1, p2, status, reason, winner, created_at from public.rc_bs
                  union all select 'rj', p1, p2, status, reason, winner, created_at from public.rc_rj) x
         where v.device in (x.p1, x.p2)
        union all
        select jsonb_build_object('at', c.created_at, 'kind', 'chat', 'msg', c.msg, 'hidden', c.hidden, 'reports', c.reports)
          from public.rc_chat c where c.device = v.device
        union all
        select jsonb_build_object('at', l.at, 'kind', 'pack', 'pack', l.kind, 'sys', l.sys)
          from public.rc_pack_log l where l.device = v.device
      ) all_e order by e->>'at' desc limit 100) s), '[]'::jsonb));
end $function$;

-- rc_admin_stat_list (Rétro Jump ajouté)
create or replace function public.rc_admin_stat_list(p_device text, p_sig text, p_kind text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare today date := public.rc__today();
begin
  perform public.rc__admin(p_device, p_sig, 'statlist|' || coalesce(p_kind, ''));
  if p_kind in ('active7', 'today') then
    return coalesce((select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'at', p.seen_at,
                                                         'n', p.packs, 'coins', p.coins, 'ver', p.app_ver, 'os', p.app_os) order by p.seen_at desc)
                       from public.rc_players p
                      where (p_kind = 'active7' and p.seen_at > now() - interval '7 days')
                         or (p_kind = 'today' and (p.seen_at at time zone 'Europe/Paris')::date = today)), '[]'::jsonb);
  elsif p_kind = 'new7' then
    return coalesce((select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'at', p.created_at,
                                                         'n', p.packs, 'ref', (select s.name from public.rc_players s where s.device = p.referrer))
                                      order by p.created_at desc)
                       from public.rc_players p where p.created_at > now() - interval '7 days'), '[]'::jsonb);
  elsif p_kind = 'packs' then
    return coalesce((select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'at', x.last,
                                                         'n', x.n, 'kinds', x.kinds) order by x.n desc, x.last desc)
                       from (select l.device, count(*)::int n, max(l.at) last, jsonb_object_agg(l.kind, l.c) kinds
                               from (select device, coalesce(kind, '?') kind, count(*)::int c, max(at) at from public.rc_pack_log
                                      where (at at time zone 'Europe/Paris')::date = today group by device, coalesce(kind, '?')) l
                              group by l.device) x
                       join public.rc_players p on p.device = x.device), '[]'::jsonb);
  elsif p_kind = 'sales' then
    return coalesce((select jsonb_agg(jsonb_build_object('pid', s.pid, 'name', s.name, 'avatar', s.avatar, 'at', m.sold_at,
                                                         'other', b.name, 'other_pid', b.pid, 'card', m.card, 'f', m.finish, 'price', m.price)
                                      order by m.sold_at desc)
                       from public.rc_market m
                       join public.rc_players s on s.device = m.seller
                       left join public.rc_players b on b.device = m.buyer
                      where m.buyer is not null and (m.sold_at at time zone 'Europe/Paris')::date = today), '[]'::jsonb);
  elsif p_kind = 'duels' then
    return coalesce((select jsonb_agg(jsonb_build_object('pid', a.pid, 'name', a.name, 'avatar', a.avatar, 'at', d.move_at,
                                                         'other', b.name, 'other_pid', b.pid, 'game', d.jeu, 'winner', d.winner, 'reason', d.reason)
                                      order by d.move_at desc)
                       from (select 'c4' jeu, p1, p2, status, reason, winner, move_at from public.rc_c4
                             union all select 'bs', p1, p2, status, reason, winner, move_at from public.rc_bs
                  union all select 'rj', p1, p2, status, reason, winner, move_at from public.rc_rj) d
                       join public.rc_players a on a.device = d.p1
                       left join public.rc_players b on b.device = d.p2
                      where d.status = 'done' and coalesce(d.reason, '') not in ('declined', 'cancelled', 'expired')
                        and (d.move_at at time zone 'Europe/Paris')::date = today), '[]'::jsonb);
  end if;
  raise exception 'liste inconnue';
end $function$;

-- rc_admin_stats (Rétro Jump ajouté)
CREATE OR REPLACE FUNCTION public.rc_admin_stats(p_device text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare today date := public.rc__today();
begin
  perform public.rc__admin(p_device, p_sig, 'stats');
  return jsonb_build_object(
    'players', (select count(*) from public.rc_players where packs > 0),
    'active7', (select count(*) from public.rc_players where seen_at > now() - interval '7 days'),
    'today', (select count(*) from public.rc_players where (seen_at at time zone 'Europe/Paris')::date = today),
    'new7', (select count(*) from public.rc_players where created_at > now() - interval '7 days'),
    'packs_today', coalesce((select packs from public.rc_daily where day = today), 0),
    'sales_today', (select count(*) from public.rc_market where buyer is not null and (sold_at at time zone 'Europe/Paris')::date = today),
    'market_open', (select count(*) from public.rc_market where buyer is null),
    'duels_today', (select count(*) from (select status, reason, move_at from public.rc_c4 union all select status, reason, move_at from public.rc_bs
                                         union all select status, reason, move_at from public.rc_rj) d
                     where d.status = 'done' and coalesce(d.reason, '') not in ('declined', 'cancelled', 'expired')
                       and (d.move_at at time zone 'Europe/Paris')::date = today),
    'coins', (select coalesce(sum(coins), 0) from public.rc_players),
    'pixels', (select coalesce(sum(pixels), 0) from public.rc_players),
    'saga', (select coalesce(sum(qty), 0) from public.rc_owned where card like 'sg\_%'),
    'rich', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'pid', pid, 'coins', coins) order by coins desc)
                        from (select name, pid, coins from public.rc_players order by coins desc limit 3) r), '[]'::jsonb),
    'days', coalesce((select jsonb_agg(jsonb_build_object('day', d.day::date, 'players', coalesce(x.players, 0), 'packs', coalesce(x.packs, 0)) order by d.day)
                        from generate_series(today - 6, today, interval '1 day') d(day)
                        left join public.rc_daily x on x.day = d.day::date), '[]'::jsonb));
end $function$;

-- ─── Déclencheurs : temps réel, journal d'activité, Actu ───────────────────
-- temps réel : seulement quand ça compte (début, chute, fin), pas à chaque hauteur reçue
drop trigger if exists rc_rj_rt on public.rc_rj;
drop trigger if exists rc_rj_rt_ins on public.rc_rj;
create trigger rc_rj_rt_ins after insert on public.rc_rj
  for each row execute function public.rc__rt_duel('rj');
create trigger rc_rj_rt after update on public.rc_rj
  for each row when (old.status is distinct from new.status or old.dead1 is distinct from new.dead1
                     or old.dead2 is distinct from new.dead2 or old.msg is distinct from new.msg
                     or old.reply is distinct from new.reply)
  execute function public.rc__rt_duel('rj');

drop trigger if exists rc_act_rj on public.rc_rj;
create trigger rc_act_rj after insert or update of status on public.rc_rj
  for each row execute function public.rc__act_duel();

drop trigger if exists rc_rj_feed on public.rc_rj;
create trigger rc_rj_feed after update of status on public.rc_rj
  for each row execute function public.rc__feed_duel();

-- PostgREST : prendre en compte les nouvelles fonctions
notify pgrst, 'reload schema';
