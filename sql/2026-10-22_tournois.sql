-- ═══════════════════════════════════════════════════════════════════════════
-- Tournois (22/10/2026) — relançable
--  · créés par l'admin : jeu (c4 / bs), 4 / 8 / 16 places, heure de début,
--    inscription gratuite ou payante (cagnotte : 100 % au 1er ou 70 / 30),
--    lots fixes (1er, 2e, demi-finalistes) en JSON de récompense
--  · matchs en direct : 1 manche, finale en 2 manches gagnantes, nul = on rejoue,
--    absent 3 min = forfait (les deux absents : tirage au sort)
--  · tour suivant quand tous les matchs du tour sont finis
--  · horloge : rc__tour_tick(), appelée par le relais (rc__rt_alive, toutes les 30 s),
--    rc_duel_ping et les lectures du tournoi
--  · temps réel : événement 'tour' sur rc_all ; trophée « tourney » (1 / 3 / 10)
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── Tables ────────────────────────────────────────────────────────────────
create table if not exists public.rc_tour (
  id bigserial primary key,
  name text not null,
  game text not null check (game in ('c4', 'bs')),
  size int not null check (size in (4, 8, 16)),
  start_at timestamptz not null,
  fee int not null default 0,
  split int not null default 100,            -- part du 1er dans la cagnotte (100 ou 70)
  lots jsonb not null default '{}'::jsonb,   -- {"1": récompense, "2": …, "3": …}
  status text not null default 'open',       -- open, running, done, cancelled
  round int not null default 0,
  rounds int not null default 0,
  pot int not null default 0,
  winner text,
  second text,
  created_at timestamptz not null default now(),
  ended_at timestamptz
);

create table if not exists public.rc_tour_players (
  tid bigint not null references public.rc_tour(id) on delete cascade,
  device text not null,
  paid int not null default 0,
  place int,                                  -- 1, 2, 3 (demi-finale)
  at timestamptz not null default now(),
  primary key (tid, device)
);

create table if not exists public.rc_tour_matches (
  id bigserial primary key,
  tid bigint not null references public.rc_tour(id) on delete cascade,
  round int not null,
  slot int not null,
  p1 text,
  p2 text,
  ready1 timestamptz,
  ready2 timestamptz,
  start_at timestamptz not null default now(),
  best int not null default 1,
  w1 int not null default 0,
  w2 int not null default 0,
  status text not null default 'wait',        -- wait (on attend les joueurs), play (partie en cours), done
  winner text,
  reason text,                                -- win, forfeit, lot (tirage), bye (exempté), cancel
  game_id bigint,
  unique (tid, round, slot)
);

create index if not exists rc_tour_status on public.rc_tour (status);
create index if not exists rc_tour_matches_open on public.rc_tour_matches (status) where status <> 'done';
create index if not exists rc_tour_players_dev on public.rc_tour_players (device);

alter table public.rc_c4 add column if not exists tmatch bigint;
alter table public.rc_bs add column if not exists tmatch bigint;
create index if not exists rc_c4_tmatch on public.rc_c4 (status) where tmatch is not null;
create index if not exists rc_bs_tmatch on public.rc_bs (status) where tmatch is not null;

alter table public.rc_tour owner to rc_owner;
alter table public.rc_tour_players owner to rc_owner;
alter table public.rc_tour_matches owner to rc_owner;
revoke all on public.rc_tour, public.rc_tour_players, public.rc_tour_matches from public;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on public.rc_tour, public.rc_tour_players, public.rc_tour_matches from anon';
    execute 'revoke all on sequence public.rc_tour_id_seq, public.rc_tour_matches_id_seq from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on public.rc_tour, public.rc_tour_players, public.rc_tour_matches from authenticated';
    execute 'revoke all on sequence public.rc_tour_id_seq, public.rc_tour_matches_id_seq from authenticated';
  end if;
end $$;

-- ─── Trophée « Tournois gagnés » ───────────────────────────────────────────
create or replace function public.rc__tpool()
 returns table(kind text, t1 integer, t2 integer, t3 integer, ord integer)
 language sql
 immutable
as $function$
  -- trophées à 3 paliers (bronze, argent, or) ; textes et icônes dans lib/trophies.dart
  values ('packs', 25, 100, 500, 1), ('cards', 100, 400, 1000, 2), ('consoles', 1, 5, 19, 3),
         ('legend', 1, 10, 50, 4), ('fullart', 1, 10, 30, 5), ('fuse', 5, 25, 100, 6),
         ('wins', 10, 50, 200, 7), ('gifts', 10, 50, 200, 8), ('sales', 5, 25, 100, 9),
         ('trades', 5, 25, 100, 10), ('gamedle', 10, 50, 200, 11), ('chest', 1, 5, 20, 12),
         ('sagas', 1, 3, 6, 13), ('days', 7, 30, 100, 14), ('epics', 10, 50, 200, 15), ('holo', 10, 50, 200, 16),
         ('gold', 5, 25, 100, 17), ('recycle', 50, 250, 1000, 18), ('quiz', 50, 250, 1000, 19), ('played', 20, 100, 400, 20),
         ('defis', 10, 50, 200, 21), ('premium', 5, 25, 100, 22), ('buys', 5, 25, 100, 23), ('firsttry', 1, 5, 20, 24),
         ('tourney', 1, 3, 10, 25) $function$;
alter function public.rc__tpool() owner to rc_owner;

-- ─── Fin d'une partie : rien à gagner en partie de tournoi (les lots viennent à la fin) ──
create or replace function public.rc__c4_finish(p_id bigint, p_winner integer, p_reason text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare g public.rc_c4; ok boolean; m int := least(coalesce(public.rc__effect('duel_x'), 1), 5);
begin
  select * into g from public.rc_c4 where id = p_id;
  if g.status <> 'playing' then return; end if;
  if g.tmatch is not null then  -- partie de tournoi : défis et compteurs seulement
    update public.rc_c4 set status = 'done', winner = p_winner, reason = p_reason, paid = false where id = p_id;
    if p_winner in (1, 2) then perform public.rc__wbump(case when p_winner = 1 then g.p1 else g.p2 end, 'win', 1); end if;
    perform public.rc__wbump(g.p1, 'play', 1);
    perform public.rc__wbump(g.p2, 'play', 1);
    return;
  end if;
  ok := g.stake > 0 or public.rc__duel_paid(g.p1, g.p2);
  update public.rc_c4 set status = 'done', winner = p_winner, reason = p_reason, paid = ok where id = p_id;
  if not ok then return; end if;  -- partie amicale : pas de gains
  if p_winner in (1, 2) then perform public.rc__wbump(case when p_winner = 1 then g.p1 else g.p2 end, 'win', 1); end if;
  perform public.rc__wbump(g.p1, 'play', 1);  -- défi : duels joués
  perform public.rc__wbump(g.p2, 'play', 1);
  if g.stake > 0 then  -- ancienne partie avec mise
    if p_winner = 0 then
      update public.rc_players set coins = coins + g.stake where device in (g.p1, g.p2);
    else
      update public.rc_players set coins = coins + g.stake * 2, pixels = pixels + 1
       where device = case when p_winner = 1 then g.p1 else g.p2 end;
    end if;
  elsif p_winner = 0 then
    update public.rc_players set coins = coins + 10 * m where device in (g.p1, g.p2);
  else
    update public.rc_players set coins = coins + 150 * m, pixels = pixels + 1
     where device = case when p_winner = 1 then g.p1 else g.p2 end;
    update public.rc_players set coins = coins + 10 * m
     where device = case when p_winner = 1 then g.p2 else g.p1 end;
  end if;
end $function$;
alter function public.rc__c4_finish(bigint, integer, text) owner to rc_owner;

create or replace function public.rc__bs_finish(p_id bigint, p_winner integer, p_reason text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare g public.rc_bs; ok boolean; m int := least(coalesce(public.rc__effect('duel_x'), 1), 5);
begin
  select * into g from public.rc_bs where id = p_id;
  if g.status not in ('setup', 'playing') then return; end if;
  if g.tmatch is not null then  -- partie de tournoi : défis et compteurs seulement
    update public.rc_bs set status = 'done', winner = p_winner, reason = p_reason, paid = false where id = p_id;
    if p_winner in (1, 2) then perform public.rc__wbump(case when p_winner = 1 then g.p1 else g.p2 end, 'win', 1); end if;
    perform public.rc__wbump(g.p1, 'play', 1);
    perform public.rc__wbump(g.p2, 'play', 1);
    return;
  end if;
  ok := g.stake > 0 or public.rc__duel_paid(g.p1, g.p2);
  update public.rc_bs set status = 'done', winner = p_winner, reason = p_reason, paid = ok where id = p_id;
  if not ok then return; end if;  -- partie amicale : pas de gains
  if p_winner in (1, 2) then perform public.rc__wbump(case when p_winner = 1 then g.p1 else g.p2 end, 'win', 1); end if;
  perform public.rc__wbump(g.p1, 'play', 1);  -- défi : duels joués
  perform public.rc__wbump(g.p2, 'play', 1);
  if g.stake > 0 then  -- ancienne partie avec mise
    update public.rc_players set coins = coins + g.stake * 2, pixels = pixels + 1
     where device = case when p_winner = 1 then g.p1 else g.p2 end;
  else
    update public.rc_players set coins = coins + 150 * m, pixels = pixels + 1
     where device = case when p_winner = 1 then g.p1 else g.p2 end;
    update public.rc_players set coins = coins + 10 * m
     where device = case when p_winner = 1 then g.p2 else g.p1 end;
  end if;
end $function$;
alter function public.rc__bs_finish(bigint, integer, text) owner to rc_owner;

-- ─── JSON des parties : nom du tournoi, pas de « amicale » ─────────────────
-- Étiquette d'une partie de tournoi : {tid, name, round, rounds, best, w1, w2 (dans l'ordre p1 / p2 du match)}
create or replace function public.rc__tour_tag(p_mid bigint)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object('tid', t.id, 'name', t.name, 'mid', m.id, 'round', m.round, 'rounds', t.rounds,
                            'best', m.best, 'w1', m.w1, 'w2', m.w2,
                            'p1', (select pid from public.rc_players where device = m.p1))
    from public.rc_tour_matches m join public.rc_tour t on t.id = m.tid where m.id = p_mid $function$;

create or replace function public.rc__c4_json(g rc_c4, p_device text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object(
    'id', g.id, 'mode', g.mode, 'status', g.status, 'board', g.board, 'turn', g.turn,
    'side', case when g.p1 = p_device then 1 else 2 end,
    'winner', g.winner, 'reason', g.reason, 'stake', g.stake, 'paid', g.paid,
    'friendly', case when g.tmatch is null and g.stake = 0 and g.status <> 'done' then public.rc__duel_why(g.p1, g.p2) end, 'moves', g.moves, 'last_col', g.last_col,
    'deadline', case when g.status = 'invite' then g.created_at + public.rc__c4_invite_limit(g.mode)
                     when g.status = 'playing' then g.move_at + public.rc__c4_limit(g.mode) end,
    'now', now(), 'created_at', g.created_at, 'msg', g.msg, 'reply', g.reply, 'ended_at', case when g.status = 'done' then g.move_at end,
    'emo_opp', case when g.p1 = p_device then g.emo2 else g.emo1 end,
    'emo_opp_at', case when g.p1 = p_device then g.emo2_at else g.emo1_at end,
    'tour', case when g.tmatch is not null then public.rc__tour_tag(g.tmatch) end,
    'opp', (select jsonb_build_object('pid', o.pid, 'name', o.name, 'avatar', o.avatar,
                                      'online', coalesce(o.seen_at > now() - interval '75 seconds', false))
              from public.rc_players o where o.device = case when g.p1 = p_device then g.p2 else g.p1 end)) $function$;

create or replace function public.rc__bs_json(g rc_bs, p_device text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
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
    'friendly', case when g.tmatch is null and g.stake = 0 and g.status <> 'done' then public.rc__duel_why(g.p1, g.p2) end, 'moves', g.moves,
    'last_cell', g.last_cell, 'last_by', case when g.last_by is null then null when g.last_by = s.side then 'me' else 'opp' end,
    'deadline', case when g.status = 'invite' then g.created_at + public.rc__bs_limit(g.mode, 'invite')
                     when g.status in ('setup', 'playing') then g.move_at + public.rc__bs_limit(g.mode, g.status) end,
    'now', now(), 'created_at', g.created_at, 'msg', g.msg, 'reply', g.reply, 'ended_at', case when g.status = 'done' then g.move_at end,
    'emo_opp', case when s.side = 1 then g.emo2 else g.emo1 end,
    'emo_opp_at', case when s.side = 1 then g.emo2_at else g.emo1_at end,
    'tour', case when g.tmatch is not null then public.rc__tour_tag(g.tmatch) end,
    'opp', (select jsonb_build_object('pid', o.pid, 'name', o.name, 'avatar', o.avatar,
                                      'online', coalesce(o.seen_at > now() - interval '75 seconds', false))
              from public.rc_players o where o.device = case when s.side = 1 then g.p2 else g.p1 end))
  from s $function$;

alter function public.rc__tour_tag(bigint) owner to rc_owner;
alter function public.rc__c4_json(rc_c4, text) owner to rc_owner;
alter function public.rc__bs_json(rc_bs, text) owner to rc_owner;

-- ─── Actu et journal : pas de nouvelle par partie de tournoi ───────────────
create or replace function public.rc__feed_duel()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare k text := case when tg_table_name = 'rc_bs' then 'bs' else 'c4' end;
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
alter function public.rc__feed_duel() owner to rc_owner;

create or replace function public.rc__act_duel()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare jeu text := case when tg_table_name = 'rc_bs' then 'Console Wars' else '4 en ligne' end;
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
alter function public.rc__act_duel() owner to rc_owner;

-- ─── Moteur du tournoi ─────────────────────────────────────────────────────

-- Annulation : mises rendues, matchs fermés
create or replace function public.rc__tour_cancel(p_tid bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare t public.rc_tour;
begin
  select * into t from public.rc_tour where id = p_tid for update;
  if t.id is null or t.status in ('done', 'cancelled') then return; end if;
  update public.rc_players p set coins = p.coins + tp.paid
    from public.rc_tour_players tp
   where tp.tid = p_tid and tp.paid > 0 and p.device = tp.device;
  update public.rc_tour_players set paid = 0 where tid = p_tid;
  update public.rc_tour_matches set status = 'done', reason = coalesce(reason, 'cancel') where tid = p_tid and status <> 'done';
  update public.rc_tour set status = 'cancelled', ended_at = now() where id = p_tid;
end $function$;

-- Crée la partie (en direct) d'un match ; ordre des joueurs tiré au sort
create or replace function public.rc__tour_game(p_mid bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare m public.rc_tour_matches; jeu text; a text; b text; gid bigint; d interval;
begin
  select * into m from public.rc_tour_matches where id = p_mid;
  select game into jeu from public.rc_tour where id = m.tid;
  if random() < 0.5 then a := m.p1; b := m.p2; else a := m.p2; b := m.p1; end if;
  -- manche suivante : 15 s pour revenir sur la partie
  d := case when m.game_id is null then interval '0' else interval '15 seconds' end;
  if jeu = 'c4' then
    insert into public.rc_c4 (p1, p2, mode, stake, status, turn, move_at, tmatch)
    values (a, b, 'live', 0, 'playing', 1, now() + d, m.id) returning id into gid;
  else
    insert into public.rc_bs (p1, p2, mode, stake, status, move_at, tmatch)
    values (a, b, 'live', 0, 'setup', now() + d, m.id) returning id into gid;
  end if;
  update public.rc_tour_matches set status = 'play', game_id = gid where id = p_mid;
end $function$;

-- Fin du tournoi : places, lots, cagnotte, trophée, nouvelle
create or replace function public.rc__tour_finish(p_tid bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare t public.rc_tour; f public.rc_tour_matches; w text; s text; d text; a int;
begin
  select * into t from public.rc_tour where id = p_tid;
  select * into f from public.rc_tour_matches where tid = p_tid and round = t.rounds and slot = 0;
  w := f.winner;
  s := case when f.winner = f.p1 then f.p2 else f.p1 end;
  update public.rc_tour_players set place = 1 where tid = p_tid and device = w;
  if s is not null then update public.rc_tour_players set place = 2 where tid = p_tid and device = s; end if;
  -- lots fixes
  perform public.rc__grant(w, coalesce(t.lots->'1', '{}'::jsonb));
  if s is not null then perform public.rc__grant(s, coalesce(t.lots->'2', '{}'::jsonb)); end if;
  if t.rounds >= 2 then
    for d in select case when m.winner = m.p1 then m.p2 else m.p1 end
               from public.rc_tour_matches m where m.tid = p_tid and m.round = t.rounds - 1 loop
      if d is not null then
        update public.rc_tour_players set place = 3 where tid = p_tid and device = d;
        perform public.rc__grant(d, coalesce(t.lots->'3', '{}'::jsonb));
      end if;
    end loop;
  end if;
  -- cagnotte
  if t.pot > 0 then
    if t.split >= 100 or s is null then
      update public.rc_players set coins = coins + t.pot where device = w;
    else
      a := floor(t.pot * t.split / 100.0);
      update public.rc_players set coins = coins + a where device = w;
      update public.rc_players set coins = coins + (t.pot - a) where device = s;
    end if;
  end if;
  perform public.rc__tbump(w, 'tourney', 1);
  begin
    perform public.rc__feed_put(w, 'tour', s, null, null, t.game, t.pot, t.name);
  exception when others then null;
  end;
  update public.rc_tour set status = 'done', winner = w, second = s, ended_at = now() where id = p_tid;
end $function$;

-- Après un match fini : tour suivant ou fin du tournoi
create or replace function public.rc__tour_after(p_tid bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare t public.rc_tour; w text[]; n int; i int;
begin
  select * into t from public.rc_tour where id = p_tid for update;
  if t.id is null or t.status <> 'running' then return; end if;
  if exists (select 1 from public.rc_tour_matches where tid = p_tid and round = t.round and status <> 'done') then return; end if;
  if t.round >= t.rounds then
    perform public.rc__tour_finish(p_tid);
    return;
  end if;
  select array_agg(winner order by slot) into w from public.rc_tour_matches where tid = p_tid and round = t.round;
  n := array_length(w, 1) / 2;
  for i in 0 .. n - 1 loop
    insert into public.rc_tour_matches (tid, round, slot, p1, p2, start_at, best)
    values (p_tid, t.round + 1, i, w[2 * i + 1], w[2 * i + 2], now(), case when t.round + 1 = t.rounds then 3 else 1 end)
    on conflict (tid, round, slot) do nothing;
  end loop;
  update public.rc_tour set round = round + 1 where id = p_tid;
end $function$;

-- Début : arbre tiré au hasard (taille réduite à la puissance de 2 utile), exemptés si places vides
create or replace function public.rc__tour_start(p_tid bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare t public.rc_tour; devs text[]; cnt int; n int := 2; r int := 0; m int; i int;
begin
  select * into t from public.rc_tour where id = p_tid for update;
  if t.id is null or t.status <> 'open' then return; end if;
  select array_agg(device order by random()) into devs from public.rc_tour_players where tid = p_tid;
  cnt := coalesce(array_length(devs, 1), 0);
  if cnt < 2 then
    perform public.rc__tour_cancel(p_tid);
    return;
  end if;
  while n < cnt loop n := n * 2; end loop;
  n := least(n, t.size);
  m := n;
  while m > 1 loop r := r + 1; m := m / 2; end loop;
  m := n / 2;
  for i in 0 .. m - 1 loop
    insert into public.rc_tour_matches (tid, round, slot, p1, p2, start_at, best)
    values (p_tid, 1, i, devs[i + 1], devs[m + i + 1], now(), case when r = 1 then 3 else 1 end)
    on conflict (tid, round, slot) do nothing;
  end loop;
  update public.rc_tour_matches set status = 'done', winner = p1, reason = 'bye'
   where tid = p_tid and round = 1 and p2 is null and status <> 'done';
  update public.rc_tour set status = 'running', round = 1, rounds = r,
         pot = (select coalesce(sum(paid), 0) from public.rc_tour_players where tid = p_tid)
   where id = p_tid;
  perform public.rc__tour_after(p_tid);
end $function$;

-- Forfait (3 min après le début du match) : présent contre absent, ou tirage au sort
create or replace function public.rc__tour_resolve(p_mid bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare m public.rc_tour_matches; w text; why text;
begin
  select * into m from public.rc_tour_matches where id = p_mid for update;
  if m.id is null or m.status <> 'wait' or now() <= m.start_at + interval '3 minutes' then return; end if;
  if m.ready1 is not null and m.ready2 is null then w := m.p1; why := 'forfeit';
  elsif m.ready2 is not null and m.ready1 is null then w := m.p2; why := 'forfeit';
  elsif m.ready1 is null and m.ready2 is null then
    w := case when random() < 0.5 then m.p1 else m.p2 end; why := 'lot';
  else
    perform public.rc__tour_game(p_mid);  -- les deux là (ne devrait pas arriver)
    return;
  end if;
  update public.rc_tour_matches set status = 'done', winner = w, reason = why where id = p_mid;
  perform public.rc__tour_after(m.tid);
end $function$;

-- Horloge : débuts, forfaits, délais des parties de tournoi
create or replace function public.rc__tour_tick()
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare x bigint;
begin
  if not pg_try_advisory_xact_lock(7311001) then return; end if;
  for x in select id from public.rc_tour where status = 'open' and start_at <= now() loop
    perform public.rc__tour_start(x);
  end loop;
  for x in select id from public.rc_tour_matches where status = 'wait' and start_at + interval '3 minutes' < now() loop
    perform public.rc__tour_resolve(x);
  end loop;
  for x in select id from public.rc_c4 where tmatch is not null and status = 'playing' loop
    perform public.rc__c4_settle(x);
  end loop;
  for x in select id from public.rc_bs where tmatch is not null and status in ('setup', 'playing') loop
    perform public.rc__bs_settle(x);
  end loop;
end $function$;

-- Déclencheur : une partie de tournoi se termine → manche comptée, partie suivante ou match fini
create or replace function public.rc__tour_game_done()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare m public.rc_tour_matches; st text; dev text; need int;
begin
  select * into m from public.rc_tour_matches where id = new.tmatch for update;
  if m.id is null or m.status <> 'play' or m.game_id is distinct from new.id then return null; end if;
  select status into st from public.rc_tour where id = m.tid;
  if st is distinct from 'running' then return null; end if;
  if new.winner in (1, 2) then
    dev := case when new.winner = 1 then new.p1 else new.p2 end;
    if dev = m.p1 then m.w1 := m.w1 + 1; else m.w2 := m.w2 + 1; end if;
    update public.rc_tour_matches set w1 = m.w1, w2 = m.w2 where id = m.id;
  end if;
  need := (m.best + 1) / 2;
  if m.w1 >= need or m.w2 >= need then
    update public.rc_tour_matches set status = 'done', reason = 'win',
           winner = case when m.w1 >= need then m.p1 else m.p2 end
     where id = m.id;
    perform public.rc__tour_after(m.tid);
  else
    perform public.rc__tour_game(m.id);  -- match nul ou manche suivante
  end if;
  return null;
end $function$;

drop trigger if exists rc_c4_tour on public.rc_c4;
create trigger rc_c4_tour after update of status on public.rc_c4
  for each row when (new.tmatch is not null and new.status = 'done' and old.status is distinct from 'done')
  execute function public.rc__tour_game_done();
drop trigger if exists rc_bs_tour on public.rc_bs;
create trigger rc_bs_tour after update of status on public.rc_bs
  for each row when (new.tmatch is not null and new.status = 'done' and old.status is distinct from 'done')
  execute function public.rc__tour_game_done();

-- Temps réel : 'tour' sur le canal commun à chaque changement
drop trigger if exists rc_tour_rt on public.rc_tour;
create trigger rc_tour_rt after insert or update or delete on public.rc_tour
  for each statement execute function public.rc__rt_all('tour');
drop trigger if exists rc_tour_players_rt on public.rc_tour_players;
create trigger rc_tour_players_rt after insert or update or delete on public.rc_tour_players
  for each statement execute function public.rc__rt_all('tour');
drop trigger if exists rc_tour_matches_rt on public.rc_tour_matches;
create trigger rc_tour_matches_rt after insert or update or delete on public.rc_tour_matches
  for each statement execute function public.rc__rt_all('tour');

-- Journal d'activité (admin) : inscription, désinscription, remboursement, place
create or replace function public.rc__act_tour()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare nm text;
begin
  begin
    select '« ' || name || ' »' into nm from public.rc_tour where id = coalesce(new.tid, old.tid);
    if tg_op = 'INSERT' then
      perform public.rc__act(new.device, 'tour', 2, 's''inscrit au tournoi ' || nm);
    elsif tg_op = 'DELETE' then
      perform public.rc__act(old.device, 'tour', 2, 'se désinscrit du tournoi ' || nm);
    elsif new.paid = 0 and old.paid > 0 then
      perform public.rc__act(new.device, 'tour', 2, 'remboursé : tournoi annulé ' || nm);
    elsif new.place is distinct from old.place and new.place is not null then
      perform public.rc__act(new.device, 'tour', 2,
        case new.place when 1 then 'gagne le tournoi ' when 2 then 'finaliste du tournoi ' else 'demi-finaliste du tournoi ' end || nm);
    end if;
  exception when others then null;
  end;
  return null;
end $function$;
drop trigger if exists rc_act_tour on public.rc_tour_players;
create trigger rc_act_tour after insert or update or delete on public.rc_tour_players
  for each row execute function public.rc__act_tour();

-- ─── Lectures (JSON) ───────────────────────────────────────────────────────

-- Un tournoi, résumé (liste) ou complet (joueurs + matchs)
create or replace function public.rc__tour_json(p_tid bigint, p_device text, p_full boolean)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object(
    'id', t.id, 'name', t.name, 'game', t.game, 'size', t.size, 'start_at', t.start_at,
    'fee', t.fee, 'split', t.split, 'lots', t.lots, 'status', t.status, 'round', t.round, 'rounds', t.rounds,
    'pot', case when t.status = 'open' then (select coalesce(sum(paid), 0) from public.rc_tour_players where tid = t.id) else t.pot end,
    'n', (select count(*) from public.rc_tour_players where tid = t.id),
    'mine', exists (select 1 from public.rc_tour_players where tid = t.id and device = p_device),
    'winner', public.rc__pinfo(t.winner), 'second', public.rc__pinfo(t.second),
    'ended_at', t.ended_at, 'now', now())
  || case when not p_full then '{}'::jsonb else jsonb_build_object(
    'players', (select coalesce(jsonb_agg(public.rc__pinfo(tp.device) || jsonb_build_object('place', tp.place) order by tp.at), '[]'::jsonb)
                  from public.rc_tour_players tp where tp.tid = t.id),
    'matches', (select coalesce(jsonb_agg(jsonb_build_object(
                   'id', m.id, 'round', m.round, 'slot', m.slot, 'best', m.best, 'w1', m.w1, 'w2', m.w2,
                   'status', m.status, 'reason', m.reason, 'game_id', m.game_id,
                   'start_at', m.start_at, 'deadline', m.start_at + interval '3 minutes',
                   'ready1', m.ready1 is not null, 'ready2', m.ready2 is not null,
                   'p1', public.rc__pinfo(m.p1), 'p2', public.rc__pinfo(m.p2),
                   'winner', (select pid from public.rc_players where device = m.winner),
                   'mine', p_device in (m.p1, m.p2)) order by m.round, m.slot), '[]'::jsonb)
                  from public.rc_tour_matches m where m.tid = t.id),
    'me', (select pid from public.rc_players where device = p_device)) end
  from public.rc_tour t where t.id = p_tid $function$;

-- Mon match en cours (ou mon tournoi qui commence dans moins de 10 min), pour rc_duel_ping
create or replace function public.rc__tour_me(p_device text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare r record; me int;
begin
  select m.*, t.name, t.game, t.rounds into r
    from public.rc_tour_matches m join public.rc_tour t on t.id = m.tid
   where t.status = 'running' and m.status in ('wait', 'play') and p_device in (m.p1, m.p2)
   order by m.id desc limit 1;
  if r.id is not null then
    me := case when r.p1 = p_device then 1 else 2 end;
    return jsonb_build_object(
      'tid', r.tid, 'name', r.name, 'game', r.game, 'mid', r.id, 'round', r.round, 'rounds', r.rounds, 'best', r.best,
      'status', r.status, 'gid', case when r.status = 'play' then r.game_id end,
      'ready', case when me = 1 then r.ready1 is not null else r.ready2 is not null end,
      'opp_ready', case when me = 1 then r.ready2 is not null else r.ready1 is not null end,
      'my_w', case when me = 1 then r.w1 else r.w2 end, 'opp_w', case when me = 1 then r.w2 else r.w1 end,
      'deadline', r.start_at + interval '3 minutes', 'now', now(),
      'opp', public.rc__pinfo(case when me = 1 then r.p2 else r.p1 end));
  end if;
  select t.id, t.name, t.game, t.start_at into r
    from public.rc_tour t join public.rc_tour_players tp on tp.tid = t.id and tp.device = p_device
   where t.status = 'open' and t.start_at <= now() + interval '10 minutes'
   order by t.start_at limit 1;
  if r.id is not null then
    return jsonb_build_object('tid', r.id, 'name', r.name, 'game', r.game, 'soon', r.start_at, 'now', now());
  end if;
  return null;
end $function$;

-- ─── RPC ───────────────────────────────────────────────────────────────────

-- Tournois à venir / en cours, et ceux finis depuis moins de 7 jours
create or replace function public.rc_tour_list(p_device text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  perform public.rc__tour_tick();
  return (select coalesce(jsonb_agg(public.rc__tour_json(t.id, p_device, false)
                   order by case t.status when 'running' then 0 when 'open' then 1 else 2 end,
                            case when t.status in ('open', 'running') then t.start_at end,
                            t.ended_at desc nulls last), '[]'::jsonb)
            from (select * from public.rc_tour
                   where status in ('open', 'running') or ended_at > now() - interval '7 days'
                   order by id desc limit 20) t);
end $function$;

create or replace function public.rc_tour_get(p_id bigint, p_device text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  perform public.rc__tour_tick();
  if not exists (select 1 from public.rc_tour where id = p_id) then raise exception 'tournoi inconnu'; end if;
  return public.rc__tour_json(p_id, p_device, true);
end $function$;

create or replace function public.rc_tour_join(p_device text, p_id bigint, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare t public.rc_tour; c bigint;
begin
  perform public.rc__check(p_sig, p_device || '|tjoin|' || p_id);
  select * into t from public.rc_tour where id = p_id for update;
  if t.id is null then raise exception 'tournoi inconnu'; end if;
  if t.status <> 'open' or now() >= t.start_at then raise exception 'inscriptions fermées'; end if;
  if exists (select 1 from public.rc_tour_players where tid = p_id and device = p_device) then raise exception 'déjà inscrit'; end if;
  if (select count(*) from public.rc_tour_players where tid = p_id) >= t.size then raise exception 'tournoi complet'; end if;
  select coins into c from public.rc_players where device = p_device for update;
  if c is null then raise exception 'joueur inconnu'; end if;
  if c < t.fee then raise exception 'pas assez de pièces'; end if;
  if t.fee > 0 then update public.rc_players set coins = coins - t.fee where device = p_device; end if;
  insert into public.rc_tour_players (tid, device, paid) values (p_id, p_device, t.fee);
  return public.rc__tour_json(p_id, p_device, true) || jsonb_build_object('coins', (select coins from public.rc_players where device = p_device));
end $function$;

create or replace function public.rc_tour_leave(p_device text, p_id bigint, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare t public.rc_tour; v int;
begin
  perform public.rc__check(p_sig, p_device || '|tleave|' || p_id);
  select * into t from public.rc_tour where id = p_id for update;
  if t.id is null then raise exception 'tournoi inconnu'; end if;
  if t.status <> 'open' or now() >= t.start_at then raise exception 'le tournoi a commencé'; end if;
  delete from public.rc_tour_players where tid = p_id and device = p_device returning paid into v;
  if v is null then raise exception 'pas inscrit'; end if;
  if v > 0 then update public.rc_players set coins = coins + v where device = p_device; end if;
  return public.rc__tour_json(p_id, p_device, true) || jsonb_build_object('coins', (select coins from public.rc_players where device = p_device));
end $function$;

-- « Je suis là » pour mon match : les deux présents → la partie démarre
create or replace function public.rc_tour_ready(p_device text, p_mid bigint, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare m public.rc_tour_matches;
begin
  perform public.rc__check(p_sig, p_device || '|tready|' || p_mid);
  select * into m from public.rc_tour_matches where id = p_mid for update;
  if m.id is null or p_device not in (m.p1, m.p2) then raise exception 'match inconnu'; end if;
  update public.rc_players set seen_at = now() where device = p_device;
  if m.status = 'wait' then
    if now() > m.start_at + interval '3 minutes' then
      perform public.rc__tour_resolve(p_mid);
    else
      if p_device = m.p1 then update public.rc_tour_matches set ready1 = coalesce(ready1, now()) where id = p_mid;
      else update public.rc_tour_matches set ready2 = coalesce(ready2, now()) where id = p_mid; end if;
      select * into m from public.rc_tour_matches where id = p_mid;
      if m.ready1 is not null and m.ready2 is not null then perform public.rc__tour_game(p_mid); end if;
    end if;
  end if;
  return coalesce(public.rc__tour_me(p_device), '{}'::jsonb)
      || jsonb_build_object('match', (select jsonb_build_object('id', x.id, 'status', x.status, 'game_id', x.game_id, 'reason', x.reason,
                                                               'won', x.winner = p_device)
                                        from public.rc_tour_matches x where x.id = p_mid));
end $function$;

-- Admin : créer ou modifier (tant que les inscriptions sont ouvertes)
create or replace function public.rc_admin_tour_save(p_device text, p_sig text, p_data text)
 returns bigint
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare j jsonb; v_id bigint; v_st timestamptz; v_sz int; v_fee int; v_sp int; v_lots jsonb := '{}'::jsonb; k text; nm text;
begin
  perform public.rc__admin(p_device, p_sig, 'toursave|' || coalesce(p_data, ''));
  j := p_data::jsonb;
  v_id := nullif(j->>'id', '')::bigint;
  nm := left(trim(coalesce(j->>'name', '')), 40);
  if nm = '' then raise exception 'nom vide'; end if;
  if coalesce(j->>'game', '') not in ('c4', 'bs') then raise exception 'jeu inconnu'; end if;
  v_sz := coalesce((j->>'size')::int, 8);
  if v_sz not in (4, 8, 16) then raise exception 'places : 4, 8 ou 16'; end if;
  v_st := (j->>'start_at')::timestamptz;
  if v_st is null or v_st < now() + interval '1 minute' then raise exception 'le début doit être dans le futur'; end if;
  v_fee := least(greatest(coalesce((j->>'fee')::int, 0), 0), 10000);
  v_sp := case when coalesce((j->>'split')::int, 100) = 70 then 70 else 100 end;
  foreach k in array array['1', '2', '3'] loop
    if j->'lots' ? k then v_lots := v_lots || jsonb_build_object(k, public.rc__rw_clean(j->'lots'->k)); end if;
  end loop;
  if v_id is null then
    insert into public.rc_tour (name, game, size, start_at, fee, split, lots)
    values (nm, j->>'game', v_sz, v_st, v_fee, v_sp, v_lots) returning id into v_id;
    if coalesce((j->>'news')::boolean, true) then
      begin
        perform public.rc__feed_put(p_device, 'tournew', null, null, null, j->>'game', v_sz, nm);
      exception when others then null;
      end;
    end if;
  else
    if not exists (select 1 from public.rc_tour where id = v_id and status = 'open') then raise exception 'tournoi déjà commencé'; end if;
    if v_sz < (select count(*) from public.rc_tour_players where tid = v_id) then raise exception 'plus d''inscrits que de places'; end if;
    if v_fee <> (select t.fee from public.rc_tour t where t.id = v_id)
       and exists (select 1 from public.rc_tour_players where tid = v_id) then
      raise exception 'mise non modifiable : des joueurs sont inscrits';
    end if;
    update public.rc_tour set name = nm, game = j->>'game', size = v_sz, start_at = v_st, fee = v_fee, split = v_sp, lots = v_lots
     where id = v_id;
  end if;
  return v_id;
end $function$;

create or replace function public.rc_admin_tour_cancel(p_device text, p_sig text, p_id bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
begin
  perform public.rc__admin(p_device, p_sig, 'tourcancel|' || p_id);
  perform public.rc__tour_cancel(p_id);
end $function$;

-- Journal admin : nouvelles actions notées
create or replace function public.rc__admin(p_dev text, p_sig text, p_payload text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
begin
  perform public.rc__check(p_sig, p_dev || '|admin|' || coalesce(p_payload, ''));
  if not public.rc__is_admin(p_dev) then raise exception 'réservé'; end if;
  -- journal : seulement les actions (pas les lectures)
  if split_part(coalesce(p_payload, ''), '|', 1) in
     ('mail', 'mail2', 'block', 'rename', 'config', 'live', 'mremove', 'maildel', 'pollnew', 'pollclose', 'evsave', 'evactive',
      'toursave', 'tourcancel') then
    insert into public.rc_admin_log (device, action) values (p_dev, left(p_payload, 400));
  end if;
end $function$;

-- ─── Horloge branchée sur le relais (toutes les 30 s) et sur rc_duel_ping ──
create or replace function public.rc__rt_alive(p_topics text[])
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  update public.rc_players set seen_at = now()
   where public.rc__rt_topic(device) = any(p_topics) and (seen_at is null or seen_at < now() - interval '20 seconds');
  begin
    perform public.rc__tour_tick();
  exception when others then null;  -- jamais bloquant pour la présence
  end;
end $function$;

create or replace function public.rc_duel_ping(p_device text, p_bg boolean DEFAULT false)
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
  tour := public.rc__tour_me(p_device);
  return jsonb_build_object('online', onl, 'live', live, 'invites', inv, 'turns', trn, 'last_from', last_from, 'replies', replies, 'tour', tour);
end $function$;

-- ─── Propriétaire ──────────────────────────────────────────────────────────
alter function public.rc__tour_cancel(bigint) owner to rc_owner;
alter function public.rc__tour_game(bigint) owner to rc_owner;
alter function public.rc__tour_finish(bigint) owner to rc_owner;
alter function public.rc__tour_after(bigint) owner to rc_owner;
alter function public.rc__tour_start(bigint) owner to rc_owner;
alter function public.rc__tour_resolve(bigint) owner to rc_owner;
alter function public.rc__tour_tick() owner to rc_owner;
alter function public.rc__tour_game_done() owner to rc_owner;
alter function public.rc__act_tour() owner to rc_owner;
alter function public.rc__tour_json(bigint, text, boolean) owner to rc_owner;
alter function public.rc__tour_me(text) owner to rc_owner;
alter function public.rc_tour_list(text) owner to rc_owner;
alter function public.rc_tour_get(bigint, text) owner to rc_owner;
alter function public.rc_tour_join(text, bigint, text) owner to rc_owner;
alter function public.rc_tour_leave(text, bigint, text) owner to rc_owner;
alter function public.rc_tour_ready(text, bigint, text) owner to rc_owner;
alter function public.rc_admin_tour_save(text, text, text) owner to rc_owner;
alter function public.rc_admin_tour_cancel(text, text, bigint) owner to rc_owner;
alter function public.rc__admin(text, text, text) owner to rc_owner;
alter function public.rc__rt_alive(text[]) owner to rc_owner;
alter function public.rc_duel_ping(text, boolean) owner to rc_owner;
