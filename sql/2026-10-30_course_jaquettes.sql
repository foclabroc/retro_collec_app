-- 30/10/2026 : « Course de jaquettes » (runner) en solo du jour et en duel en direct.
-- Le duel réutilise la table et tout le moteur de Rétro Jump (rc_rj) avec une colonne `kind` ('jump' / 'run') :
--  parties, arbitre (rc__rj_settle), gains, spectateurs, réactions, fantôme du relais ('rjpos' sur le canal 'rj')
--  restent identiques. Score = distance en mètres, plafonnée à 100 + 24 m par seconde (vitesse max du jeu : 22 m/s).
--  Pas de tournoi pour ce jeu.
-- Solo : tables rc_rn_* (copie de rc_rj_* : une graine par jour, meilleur score du jour, 3 premiers récompensés
--  le lendemain : 500 + 2 pixels / 300 + 1 / 100), RPC rc_rn_solo_start / _board / _end / _winners.
-- Appli trop ancienne : le jeu n'est proposé qu'aux joueurs dont l'appli est en 1.0.32 ou plus (rc_players.app_ver).
-- rc_rj_invite / rc_rj_online / rc_rj_stats / rc_rj_top reçoivent un paramètre p_kind (défaut 'jump' : les anciennes
-- appli continuent de marcher). Signature d'un défi en course : '<device>|rjinv|<pid>|run'.
-- Relançable. À lancer avant de pousser l'appli.

alter table public.rc_rj add column if not exists kind text not null default 'jump';

-- appli assez récente pour connaître la course (1.0.32+)
create or replace function public.rc__rn_ok(p_device text)
 returns boolean
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare v text;
begin
  select split_part(coalesce(app_ver, ''), '|', 1) into v from public.rc_players where device = p_device;
  if v is null or v = '' then return false; end if;
  return string_to_array(v, '.')::int[] >= array[1, 0, 32];
exception when others then
  return false;
end $function$;
alter function public.rc__rn_ok(text) owner to rc_owner;

-- ─── JSON d'une partie : + kind ────────────────────────────────────────────
create or replace function public.rc__rj_json(g public.rc_rj, p_device text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object(
    'id', g.id, 'mode', g.mode, 'status', g.status, 'kind', g.kind,
    'side', case when g.p1 = p_device then 1 else 2 end,
    'winner', g.winner, 'reason', g.reason, 'stake', g.stake, 'paid', g.paid,
    'friendly', case when g.tmatch is null and g.stake = 0 and g.status <> 'done' then public.rc__duel_why(g.p1, g.p2) end,
    'tour', case when g.tmatch is not null then public.rc__tour_tag(g.tmatch) end,
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

-- ─── Ma hauteur / ma distance : plafond selon le jeu ───────────────────────
create or replace function public.rc_rj_score(p_device text, p_id bigint, p_h integer, p_dead boolean, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare g public.rc_rj; side int; cap int; sec numeric;
begin
  perform public.rc__check(p_sig, p_device || '|rjsc|' || p_id || '|' || p_h || '|' || case when p_dead then 1 else 0 end);
  select * into g from public.rc_rj where id = p_id for update;
  if g.id is null or p_device not in (g.p1, g.p2) then raise exception 'partie inconnue'; end if;
  side := case when g.p1 = p_device then 1 else 2 end;
  if g.status = 'playing' and now() <= g.end_at + interval '5 seconds'
     and (case when side = 1 then g.dead1 else g.dead2 end) is null then
    sec := greatest(0, extract(epoch from (least(now(), g.end_at) - g.start_at)));
    -- Rétro Jump : 70 points par seconde ; course : 24 mètres par seconde (vitesse max 22)
    cap := case when g.kind = 'run' then 100 + floor(24 * sec)::int else 60 + floor(70 * sec)::int end;
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

-- ─── Défier (p_kind : jump / run) ──────────────────────────────────────────
drop function if exists public.rc_rj_invite(text, text, text);
create or replace function public.rc_rj_invite(p_device text, p_pid text, p_sig text, p_kind text default 'jump')
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v public.rc_players; o public.rc_players; gid bigint;
begin
  if p_kind not in ('jump', 'run') then raise exception 'jeu inconnu'; end if;
  perform public.rc__check(p_sig, p_device || '|rjinv|' || coalesce(p_pid, '') || case when p_kind = 'run' then '|run' else '' end);
  select * into v from public.rc_players where device = p_device;
  select * into o from public.rc_players where pid = p_pid;
  if v.device is null or o.device is null then raise exception 'joueur inconnu'; end if;
  if o.device = v.device then raise exception 'pas contre toi-même'; end if;
  perform public.rc__not_blocked(p_device);
  if o.blocked then raise exception 'joueur indisponible'; end if;
  if p_kind = 'jump' and not o.rj_ok then raise exception 'joueur à mettre à jour'; end if;
  if p_kind = 'run' and not public.rc__rn_ok(o.device) then raise exception 'joueur à mettre à jour'; end if;
  if coalesce(o.seen_at < now() - interval '2 minutes', true) then raise exception 'joueur hors ligne'; end if;
  if public.rc__duel_busy(v.device) then raise exception 'tu es déjà en partie'; end if;
  if public.rc__duel_busy(o.device) then raise exception 'joueur déjà en partie'; end if;
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
  insert into public.rc_rj (p1, p2, kind) values (v.device, o.device, p_kind) returning id into gid;
  return public.rc__rj_json((select g from public.rc_rj g where g.id = gid), p_device);
end $function$;
alter function public.rc_rj_invite(text, text, text, text) owner to rc_owner;

-- ─── Joueurs en ligne qui connaissent le jeu ───────────────────────────────
drop function if exists public.rc_rj_online(text);
create or replace function public.rc_rj_online(p_device text, p_kind text default 'jump')
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
             'w', (select count(*) from public.rc_rj g where g.status = 'done' and g.kind = p_kind
                     and ((g.p1 = p.device and g.winner = 1) or (g.p2 = p.device and g.winner = 2))),
             'l', (select count(*) from public.rc_rj g where g.status = 'done' and g.kind = p_kind
                     and ((g.p1 = p.device and g.winner = 2) or (g.p2 = p.device and g.winner = 1))),
             'busy', public.rc__duel_busy(p.device))
           order by p.seen_at desc)
      from (select * from public.rc_players q
             where q.device <> p_device and q.packs > 0 and q.seen_at > now() - interval '75 seconds'
               and case when p_kind = 'run' then public.rc__rn_ok(q.device) else q.rj_ok end
             order by q.seen_at desc limit 50) p), '[]'::jsonb);
end $function$;
alter function public.rc_rj_online(text, text) owner to rc_owner;

-- ─── Statistiques et meilleurs joueurs par jeu ─────────────────────────────
drop function if exists public.rc_rj_stats(text);
create or replace function public.rc_rj_stats(p_device text, p_kind text default 'jump')
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
            where (p1 = p_device or p2 = p_device) and status = 'done' and winner is not null and kind = p_kind
            order by move_at desc loop
    best := greatest(best, r.h);
    if r.winner = 0 then d := d + 1; counting := false; if r.paid then net := net + 10; end if;
    elsif r.winner = r.side then w := w + 1; if r.paid then net := net + 150; end if; if counting then streak := streak + 1; end if;
    else l := l + 1; if r.paid then net := net + 10; end if; counting := false;
    end if;
  end loop;
  return jsonb_build_object('wins', w, 'losses', l, 'draws', d, 'streak', streak, 'net', net, 'best', best);
end $function$;
alter function public.rc_rj_stats(text, text) owner to rc_owner;

drop function if exists public.rc_rj_top();
create or replace function public.rc_rj_top(p_kind text default 'jump')
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
     where g.status = 'done' and g.winner in (1, 2) and g.move_at > now() - interval '7 days' and g.kind = p_kind
     group by p.pid, p.name, p.avatar, p.seen_at
     order by count(*) desc limit 10) t $function$;
alter function public.rc_rj_top(text) owner to rc_owner;

-- ═══ Solo du jour : tables et fonctions (copie de rc_rj_*) ═══
create table if not exists public.rc_rn_day (
  day  date primary key,
  seed integer not null,
  paid boolean not null default false
);
create table if not exists public.rc_rn_runs (
  id         bigserial primary key,
  device     text not null,
  day        date not null,
  started_at timestamptz not null default now(),
  score      integer,
  ended_at   timestamptz
);
create index if not exists rc_rn_runs_dev on public.rc_rn_runs (device, started_at desc);
create table if not exists public.rc_rn_best (
  day    date not null,
  device text not null,
  score  integer not null,
  at     timestamptz not null default now(),
  primary key (day, device)
);
create index if not exists rc_rn_best_rank on public.rc_rn_best (day, score desc, at);
create table if not exists public.rc_rn_wins (
  day    date not null,
  place  integer not null,
  device text not null,
  score  integer not null,
  reward jsonb not null,
  primary key (day, place)
);
alter table public.rc_rn_day owner to rc_owner;
alter table public.rc_rn_runs owner to rc_owner;
alter table public.rc_rn_best owner to rc_owner;
alter table public.rc_rn_wins owner to rc_owner;
revoke all on public.rc_rn_day, public.rc_rn_runs, public.rc_rn_best, public.rc_rn_wins from public;
do $$ begin
  revoke all on public.rc_rn_day, public.rc_rn_runs, public.rc_rn_best, public.rc_rn_wins from anon, authenticated;
  revoke all on sequence public.rc_rn_runs_id_seq from anon, authenticated;
exception when undefined_object then null;
end $$;

create or replace function public.rc__rn_seed(p_day date)
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare s int;
begin
  insert into public.rc_rn_day (day, seed) values (p_day, floor(random() * 2147483646)::int + 1)
  on conflict (day) do nothing;
  select seed into s from public.rc_rn_day where day = p_day;
  return s;
end $function$;
alter function public.rc__rn_seed(date) owner to rc_owner;

-- récompenses des jours terminés (mêmes lots que le Rétro Jump solo : rc__rj_solo_prize)
create or replace function public.rc__rn_solo_pay()
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare d record; r record; pl int; rw jsonb;
begin
  if not exists (select 1 from public.rc_rn_day where not paid and day < public.rc__today()) then return; end if;
  if not pg_try_advisory_xact_lock(hashtext('rc_rn_solo_pay')) then return; end if;
  for d in select day from public.rc_rn_day where not paid and day < public.rc__today() order by day for update loop
    pl := 0;
    for r in select b.device, b.score from public.rc_rn_best b join public.rc_players p on p.device = b.device
              where b.day = d.day and b.score > 0 and not coalesce(p.blocked, false)
              order by b.score desc, b.at asc limit 3 loop
      pl := pl + 1;
      rw := public.rc__rj_solo_prize(pl);
      insert into public.rc_rn_wins (day, place, device, score, reward) values (d.day, pl, r.device, r.score, rw)
      on conflict (day, place) do nothing;
      if found then
        perform public.rc__grant(r.device, rw);
        if pl = 1 then perform public.rc__feed_put(r.device, 'rnsolo', null, null, null, null, r.score, null); end if;
      end if;
    end loop;
    update public.rc_rn_day set paid = true where day = d.day;
  end loop;
end $function$;
alter function public.rc__rn_solo_pay() owner to rc_owner;

create or replace function public.rc_rn_solo_start(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v_day date := public.rc__today(); v_run bigint;
begin
  perform public.rc__check(p_sig, p_device || '|rnsstart');
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'joueur inconnu'; end if;
  perform public.rc__not_blocked(p_device);
  begin
    perform public.rc__rn_solo_pay();
  exception when others then null;
  end;
  if exists (select 1 from public.rc_rn_runs where device = p_device and started_at > now() - interval '3 seconds') then
    raise exception 'trop vite';
  end if;
  if (select count(*) from public.rc_rn_runs where device = p_device and day = v_day) >= 300 then
    raise exception 'trop de parties';
  end if;
  insert into public.rc_rn_runs (device, day) values (p_device, v_day) returning id into v_run;
  if random() < 0.01 then delete from public.rc_rn_runs where started_at < now() - interval '3 days'; end if;
  return jsonb_build_object('run', v_run, 'seed', public.rc__rn_seed(v_day), 'day', v_day,
    'best', coalesce((select score from public.rc_rn_best where day = v_day and device = p_device), 0));
end $function$;
alter function public.rc_rn_solo_start(text, text) owner to rc_owner;

create or replace function public.rc_rn_solo_board(p_device text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_day date := public.rc__today(); my int; rk int;
begin
  begin
    perform public.rc__rn_solo_pay();
  exception when others then null;
  end;
  select score into my from public.rc_rn_best where day = v_day and device = p_device;
  if my is not null then
    select count(*) + 1 into rk from public.rc_rn_best b
     where b.day = v_day and (b.score > my or (b.score = my and b.at < (select at from public.rc_rn_best where day = v_day and device = p_device)));
  end if;
  return jsonb_build_object(
    'day', v_day, 'now', now(), 'best', coalesce(my, 0), 'rank', rk,
    'players', (select count(*) from public.rc_rn_best where day = v_day),
    'prizes', jsonb_build_array(public.rc__rj_solo_prize(1), public.rc__rj_solo_prize(2), public.rc__rj_solo_prize(3)),
    'top', coalesce((select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'score', b.score,
                                                         'me', b.device = p_device) order by b.score desc, b.at asc)
                       from (select * from public.rc_rn_best where day = v_day order by score desc, at asc limit 10) b
                       join public.rc_players p on p.device = b.device), '[]'::jsonb),
    'yesterday', coalesce((select jsonb_agg(jsonb_build_object('place', w.place, 'pid', p.pid, 'name', p.name, 'avatar', p.avatar,
                                                               'score', w.score, 'reward', w.reward, 'me', w.device = p_device) order by w.place)
                             from public.rc_rn_wins w join public.rc_players p on p.device = w.device
                            where w.day = v_day - 1), '[]'::jsonb));
end $function$;
alter function public.rc_rn_solo_board(text) owner to rc_owner;

-- fin d'une partie solo : distance plafonnée à 100 + 24 m par seconde de partie
create or replace function public.rc_rn_solo_end(p_device text, p_run bigint, p_score integer, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare r public.rc_rn_runs; cap int; sc int; old int;
begin
  perform public.rc__check(p_sig, p_device || '|rnsend|' || p_run || '|' || p_score);
  select * into r from public.rc_rn_runs where id = p_run and device = p_device for update;
  if r.id is null then raise exception 'partie inconnue'; end if;
  if r.ended_at is not null then raise exception 'partie terminée'; end if;
  cap := 100 + floor(24 * extract(epoch from (now() - r.started_at)))::int;
  sc := least(greatest(coalesce(p_score, 0), 0), cap);
  update public.rc_rn_runs set score = sc, ended_at = now() where id = p_run;
  select score into old from public.rc_rn_best where day = r.day and device = p_device;
  if sc > 0 and (old is null or sc > old) then
    insert into public.rc_rn_best (day, device, score, at) values (r.day, p_device, sc, now())
    on conflict (day, device) do update set score = excluded.score, at = excluded.at;
  end if;
  return public.rc_rn_solo_board(p_device) || jsonb_build_object('score', sc, 'record', sc > coalesce(old, 0), 'run_day', r.day);
end $function$;
alter function public.rc_rn_solo_end(text, bigint, integer, text) owner to rc_owner;

create or replace function public.rc_rn_solo_winners(p_days integer default 30)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(x.j order by x.day desc), '[]'::jsonb) from (
    select w.day, jsonb_build_object('day', w.day,
             'list', jsonb_agg(jsonb_build_object('place', w.place, 'pid', p.pid, 'name', p.name, 'avatar', p.avatar,
                                                  'score', w.score, 'reward', w.reward) order by w.place)) as j
      from public.rc_rn_wins w join public.rc_players p on p.device = w.device
     where w.day >= public.rc__today() - least(greatest(coalesce(p_days, 30), 1), 90)
     group by w.day) x $function$;
alter function public.rc_rn_solo_winners(integer) owner to rc_owner;

-- ═══ Fonctions existantes complétées (même texte que sql/schema/) ═══

-- « En partie » : + partie solo de course en cours
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
                  and p_device in (g.p1, g.p2) and now() <= g.end_at + interval '10 seconds')
      -- partie solo de Rétro Jump / de course en cours (au plus 3 min, si l'appli a été quittée sans finir)
      or exists (select 1 from public.rc_rj_runs r where r.device = p_device and r.ended_at is null
                  and r.started_at > now() - interval '3 minutes')
      or exists (select 1 from public.rc_rn_runs r where r.device = p_device and r.ended_at is null
                  and r.started_at > now() - interval '3 minutes') $function$;
alter function public.rc__duel_busy(text) owner to rc_owner;

-- spectateur : + kind dans la liste des duels à regarder
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
    select g.created_at, jsonb_build_object('game', 'rj', 'id', g.id, 'phase', g.status, 'moves', g.moves, 'kind', g.kind,
             'h1', g.h1, 'h2', g.h2, 'end_at', g.end_at, 'now', now(),
             'p1', public.rc__pinfo(g.p1), 'p2', public.rc__pinfo(g.p2))
      from public.rc_rj g
     where g.status = 'playing' and now() <= g.end_at + interval '10 seconds'
  ) x $function$;
alter function public.rc_live_games() owner to rc_owner;

-- Actu : « rn » / « rndraw » pour la course
create or replace function public.rc__feed_duel()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare k text := case tg_table_name when 'rc_bs' then 'bs' when 'rc_rj' then case when new.kind = 'run' then 'rn' else 'rj' end else 'c4' end;
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

-- rc_duel_ping : kind dans les défis reçus, paiement de la course solo
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
  begin
    perform public.rc__rn_solo_pay();  -- course solo : 3 premiers de la veille
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
    select jsonb_build_object('game', 'rj', 'kind', g.kind, 'id', g.id, 'stake', g.stake, 'friendly', public.rc__duel_why(g.p1, g.p2), 'created_at', g.created_at, 'msg', g.msg,
             'deadline', g.created_at + interval '2 minutes', 'now', now(),
             'opp', jsonb_build_object('pid', o.pid, 'name', o.name, 'avatar', o.avatar,
                      'w', (select count(*) from public.rc_rj h where h.status = 'done' and h.kind = g.kind and ((h.p1 = o.device and h.winner = 1) or (h.p2 = o.device and h.winner = 2))),
                      'l', (select count(*) from public.rc_rj h where h.status = 'done' and h.kind = g.kind and ((h.p1 = o.device and h.winner = 2) or (h.p2 = o.device and h.winner = 1)))))
      from public.rc_rj g join public.rc_players o on o.device = g.p1
     where p_rj and g.p2 = p_device and g.status = 'invite' and g.created_at > now() - interval '2 minutes'
       and (g.kind = 'jump' or public.rc__rn_ok(p_device))) t;

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

-- PostgREST : prendre en compte les nouvelles fonctions
notify pgrst, 'reload schema';
