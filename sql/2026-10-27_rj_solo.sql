-- 27/10/2026 : Rétro Jump solo du jour + défis bloqués quand on est déjà en partie.
-- À lancer APRÈS sql/2026-10-27_duel_retro_jump.sql (il utilise rc__duel_busy).
--  · Solo : un parcours par jour (graine tirée au 1er départ du jour, la même pour tous), parties illimitées,
--    le meilleur score du jour compte. Score plafonné à 60 + 70 pts par seconde de partie (rc_rj_solo_end).
--  · Le lendemain, les 3 premiers du jour sont récompensés une seule fois (rc__rj_solo_pay, appelé par
--    rc_duel_ping, rc_rj_solo_start et rc_rj_solo_board) : 1er 300 pièces + 2 pixels, 2e 200 + 1 pixel, 3e 100.
--    Historique dans rc_rj_wins (rc_rj_solo_winners), nouvelle « rjsolo » dans l'Actu pour le 1er.
--  · Défi en direct (4 en ligne, Console Wars, Rétro Jump) refusé si je suis déjà en partie en direct
--    (« tu es déjà en partie ») ou si l'adversaire l'est (« joueur déjà en partie »), à l'envoi comme à l'acceptation.
-- Relançable.

create table if not exists public.rc_rj_day (
  day  date primary key,
  seed integer not null,
  paid boolean not null default false
);
create table if not exists public.rc_rj_runs (
  id         bigserial primary key,
  device     text not null,
  day        date not null,
  started_at timestamptz not null default now(),
  score      integer,
  ended_at   timestamptz
);
create index if not exists rc_rj_runs_dev on public.rc_rj_runs (device, started_at desc);
create table if not exists public.rc_rj_best (
  day    date not null,
  device text not null,
  score  integer not null,
  at     timestamptz not null default now(),
  primary key (day, device)
);
create index if not exists rc_rj_best_rank on public.rc_rj_best (day, score desc, at);
create table if not exists public.rc_rj_wins (
  day    date not null,
  place  integer not null,
  device text not null,
  score  integer not null,
  reward jsonb not null,
  primary key (day, place)
);
alter table public.rc_rj_day owner to rc_owner;
alter table public.rc_rj_runs owner to rc_owner;
alter table public.rc_rj_best owner to rc_owner;
alter table public.rc_rj_wins owner to rc_owner;
revoke all on public.rc_rj_day, public.rc_rj_runs, public.rc_rj_best, public.rc_rj_wins from public;
do $$ begin
  revoke all on public.rc_rj_day, public.rc_rj_runs, public.rc_rj_best, public.rc_rj_wins from anon, authenticated;
  revoke all on sequence public.rc_rj_runs_id_seq from anon, authenticated;
exception when undefined_object then null;
end $$;

-- récompense d'une place (1, 2, 3)
create or replace function public.rc__rj_solo_prize(p_place integer)
 returns jsonb
 language sql
 immutable
as $function$
  select case p_place when 1 then '{"coins":300,"pixels":2}'::jsonb
                      when 2 then '{"coins":200,"pixels":1}'::jsonb
                      when 3 then '{"coins":100}'::jsonb end $function$;
alter function public.rc__rj_solo_prize(integer) owner to rc_owner;

-- graine du parcours du jour (tirée au premier départ)
create or replace function public.rc__rj_seed(p_day date)
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare s int;
begin
  insert into public.rc_rj_day (day, seed) values (p_day, floor(random() * 2147483646)::int + 1)
  on conflict (day) do nothing;
  select seed into s from public.rc_rj_day where day = p_day;
  return s;
end $function$;
alter function public.rc__rj_seed(date) owner to rc_owner;

-- récompenses des jours terminés (une seule fois par jour)
create or replace function public.rc__rj_solo_pay()
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare d record; r record; pl int; rw jsonb;
begin
  if not exists (select 1 from public.rc_rj_day where not paid and day < public.rc__today()) then return; end if;
  if not pg_try_advisory_xact_lock(hashtext('rc_rj_solo_pay')) then return; end if;
  for d in select day from public.rc_rj_day where not paid and day < public.rc__today() order by day for update loop
    pl := 0;
    for r in select b.device, b.score from public.rc_rj_best b join public.rc_players p on p.device = b.device
              where b.day = d.day and b.score > 0 and not coalesce(p.blocked, false)
              order by b.score desc, b.at asc limit 3 loop
      pl := pl + 1;
      rw := public.rc__rj_solo_prize(pl);
      insert into public.rc_rj_wins (day, place, device, score, reward) values (d.day, pl, r.device, r.score, rw)
      on conflict (day, place) do nothing;
      if found then
        perform public.rc__grant(r.device, rw);
        if pl = 1 then perform public.rc__feed_put(r.device, 'rjsolo', null, null, null, null, r.score, null); end if;
      end if;
    end loop;
    update public.rc_rj_day set paid = true where day = d.day;
  end loop;
end $function$;
alter function public.rc__rj_solo_pay() owner to rc_owner;

-- départ d'une partie solo : graine du jour + numéro de partie
create or replace function public.rc_rj_solo_start(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v_day date := public.rc__today(); v_run bigint;
begin
  perform public.rc__check(p_sig, p_device || '|rjsstart');
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'joueur inconnu'; end if;
  perform public.rc__not_blocked(p_device);
  begin
    perform public.rc__rj_solo_pay();
  exception when others then null;
  end;
  if exists (select 1 from public.rc_rj_runs where device = p_device and started_at > now() - interval '3 seconds') then
    raise exception 'trop vite';
  end if;
  if (select count(*) from public.rc_rj_runs where device = p_device and day = v_day) >= 300 then
    raise exception 'trop de parties';
  end if;
  insert into public.rc_rj_runs (device, day) values (p_device, v_day) returning id into v_run;
  if random() < 0.01 then delete from public.rc_rj_runs where started_at < now() - interval '3 days'; end if;
  return jsonb_build_object('run', v_run, 'seed', public.rc__rj_seed(v_day), 'day', v_day,
    'best', coalesce((select score from public.rc_rj_best where day = v_day and device = p_device), 0));
end $function$;
alter function public.rc_rj_solo_start(text, text) owner to rc_owner;

-- classement du jour : top 10, ma place, gagnants d'hier
create or replace function public.rc_rj_solo_board(p_device text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_day date := public.rc__today(); my int; rk int;
begin
  begin
    perform public.rc__rj_solo_pay();
  exception when others then null;
  end;
  select score into my from public.rc_rj_best where day = v_day and device = p_device;
  if my is not null then
    select count(*) + 1 into rk from public.rc_rj_best b
     where b.day = v_day and (b.score > my or (b.score = my and b.at < (select at from public.rc_rj_best where day = v_day and device = p_device)));
  end if;
  return jsonb_build_object(
    'day', v_day, 'now', now(), 'best', coalesce(my, 0), 'rank', rk,
    'players', (select count(*) from public.rc_rj_best where day = v_day),
    'prizes', jsonb_build_array(public.rc__rj_solo_prize(1), public.rc__rj_solo_prize(2), public.rc__rj_solo_prize(3)),
    'top', coalesce((select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'score', b.score,
                                                         'me', b.device = p_device) order by b.score desc, b.at asc)
                       from (select * from public.rc_rj_best where day = v_day order by score desc, at asc limit 10) b
                       join public.rc_players p on p.device = b.device), '[]'::jsonb),
    'yesterday', coalesce((select jsonb_agg(jsonb_build_object('place', w.place, 'pid', p.pid, 'name', p.name, 'avatar', p.avatar,
                                                               'score', w.score, 'reward', w.reward, 'me', w.device = p_device) order by w.place)
                             from public.rc_rj_wins w join public.rc_players p on p.device = w.device
                            where w.day = v_day - 1), '[]'::jsonb));
end $function$;
alter function public.rc_rj_solo_board(text) owner to rc_owner;

-- fin d'une partie solo : score plafonné, meilleur score du jour, classement
create or replace function public.rc_rj_solo_end(p_device text, p_run bigint, p_score integer, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare r public.rc_rj_runs; cap int; sc int; old int;
begin
  perform public.rc__check(p_sig, p_device || '|rjsend|' || p_run || '|' || p_score);
  select * into r from public.rc_rj_runs where id = p_run and device = p_device for update;
  if r.id is null then raise exception 'partie inconnue'; end if;
  if r.ended_at is not null then raise exception 'partie terminée'; end if;
  cap := 60 + floor(70 * extract(epoch from (now() - r.started_at)))::int;
  sc := least(greatest(coalesce(p_score, 0), 0), cap);
  update public.rc_rj_runs set score = sc, ended_at = now() where id = p_run;
  select score into old from public.rc_rj_best where day = r.day and device = p_device;
  if sc > 0 and (old is null or sc > old) then
    insert into public.rc_rj_best (day, device, score, at) values (r.day, p_device, sc, now())
    on conflict (day, device) do update set score = excluded.score, at = excluded.at;
  end if;
  return public.rc_rj_solo_board(p_device) || jsonb_build_object('score', sc, 'record', sc > coalesce(old, 0), 'run_day', r.day);
end $function$;
alter function public.rc_rj_solo_end(text, bigint, integer, text) owner to rc_owner;

-- historique des gagnants (jours les plus récents d'abord)
create or replace function public.rc_rj_solo_winners(p_days integer default 30)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(x.j order by x.day desc), '[]'::jsonb) from (
    select w.day, jsonb_build_object('day', w.day,
             'list', jsonb_agg(jsonb_build_object('place', w.place, 'pid', p.pid, 'name', p.name, 'avatar', p.avatar,
                                                  'score', w.score, 'reward', w.reward) order by w.place)) as j
      from public.rc_rj_wins w join public.rc_players p on p.device = w.device
     where w.day >= public.rc__today() - least(greatest(coalesce(p_days, 30), 1), 90)
     group by w.day) x $function$;
alter function public.rc_rj_solo_winners(integer) owner to rc_owner;

-- ═══ Fonctions existantes complétées (même texte que sql/schema/) ═══

-- rc_c4_invite (défi refusé si déjà en partie)
CREATE OR REPLACE FUNCTION public.rc_c4_invite(p_device text, p_pid text, p_mode text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v public.rc_players; o public.rc_players; gid bigint;
begin
  perform public.rc__check(p_sig, p_device || '|c4inv|' || coalesce(p_pid, '') || '|' || coalesce(p_mode, ''));
  if p_mode not in ('live', 'turn') then raise exception 'mode inconnu'; end if;
  select * into v from public.rc_players where device = p_device;
  select * into o from public.rc_players where pid = p_pid;
  if v.device is null or o.device is null then raise exception 'joueur inconnu'; end if;
  if o.device = v.device then raise exception 'pas contre toi-même'; end if;
  perform public.rc__not_blocked(p_device);
  if o.blocked then raise exception 'joueur indisponible'; end if;
  if p_mode = 'live' and coalesce(o.seen_at < now() - interval '2 minutes', true) then raise exception 'joueur hors ligne'; end if;
  if p_mode = 'live' and public.rc__duel_busy(v.device) then raise exception 'tu es déjà en partie'; end if;
  if p_mode = 'live' and public.rc__duel_busy(o.device) then raise exception 'joueur déjà en partie'; end if;
  if exists (select 1 from public.rc_c4 g where g.status in ('invite', 'playing') and g.mode = p_mode
              and ((g.p1 = v.device and g.p2 = o.device) or (g.p1 = o.device and g.p2 = v.device))
              and now() <= case when g.status = 'invite' then g.created_at + public.rc__c4_invite_limit(g.mode)
                                else g.move_at + public.rc__c4_limit(g.mode) end) then
    raise exception 'partie déjà en cours';
  end if;
  if (select count(*) from public.rc_c4 g where g.status in ('invite', 'playing') and v.device in (g.p1, g.p2)) >= 15 then
    raise exception 'trop de parties';
  end if;
  update public.rc_players set seen_at = now() where device = p_device;
  insert into public.rc_c4 (p1, p2, mode) values (v.device, o.device, p_mode) returning id into gid;
  return public.rc__c4_json((select g from public.rc_c4 g where g.id = gid), p_device);
end $function$;

-- rc_bs_invite (défi refusé si déjà en partie)
CREATE OR REPLACE FUNCTION public.rc_bs_invite(p_device text, p_pid text, p_mode text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v public.rc_players; o public.rc_players; gid bigint; x bigint;
begin
  perform public.rc__check(p_sig, p_device || '|bsinv|' || coalesce(p_pid, '') || '|' || coalesce(p_mode, ''));
  if p_mode not in ('live', 'turn') then raise exception 'mode inconnu'; end if;
  select * into v from public.rc_players where device = p_device;
  select * into o from public.rc_players where pid = p_pid;
  if v.device is null or o.device is null then raise exception 'joueur inconnu'; end if;
  if o.device = v.device then raise exception 'pas contre toi-même'; end if;
  perform public.rc__not_blocked(p_device);
  if o.blocked then raise exception 'joueur indisponible'; end if;
  if p_mode = 'live' and coalesce(o.seen_at < now() - interval '2 minutes', true) then raise exception 'joueur hors ligne'; end if;
  if p_mode = 'live' and public.rc__duel_busy(v.device) then raise exception 'tu es déjà en partie'; end if;
  if p_mode = 'live' and public.rc__duel_busy(o.device) then raise exception 'joueur déjà en partie'; end if;
  -- parties dépassées (abandonnées) : réglées d'abord, sinon elles bloqueraient les contrôles ci-dessous
  for x in select g.id from public.rc_bs g
            where g.status in ('invite', 'setup', 'playing') and v.device in (g.p1, g.p2)
              and now() > case when g.status = 'invite' then g.created_at + public.rc__bs_limit(g.mode, 'invite')
                               else g.move_at + public.rc__bs_limit(g.mode, g.status) end loop
    perform public.rc__bs_settle(x);
  end loop;
  if exists (select 1 from public.rc_bs g where g.status in ('invite', 'setup', 'playing') and g.mode = p_mode
              and ((g.p1 = v.device and g.p2 = o.device) or (g.p1 = o.device and g.p2 = v.device))) then
    raise exception 'partie déjà en cours';
  end if;
  if (select count(*) from public.rc_bs g where g.status in ('invite', 'setup', 'playing') and v.device in (g.p1, g.p2)) >= 15 then
    raise exception 'trop de parties';
  end if;
  update public.rc_players set seen_at = now() where device = p_device;
  insert into public.rc_bs (p1, p2, mode) values (v.device, o.device, p_mode) returning id into gid;
  return public.rc__bs_out(gid, p_device);
end $function$;

-- rc_rj_invite (défi refusé si déjà en partie)
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
  insert into public.rc_rj (p1, p2) values (v.device, o.device) returning id into gid;
  return public.rc__rj_json((select g from public.rc_rj g where g.id = gid), p_device);
end $function$;

-- rc_c4_answer (acceptation refusée si déjà en partie)
CREATE OR REPLACE FUNCTION public.rc_c4_answer(p_device text, p_id bigint, p_accept boolean, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare g public.rc_c4; c1 bigint; c2 bigint;
begin
  perform public.rc__check(p_sig, p_device || '|c4ans|' || p_id || '|' || case when p_accept then 1 else 0 end);
  perform public.rc__c4_settle(p_id);
  select * into g from public.rc_c4 where id = p_id for update;
  if g.id is null or p_device not in (g.p1, g.p2) then raise exception 'partie inconnue'; end if;
  if g.status <> 'invite' then raise exception 'invitation expirée'; end if;
  if not p_accept then
    update public.rc_c4 set status = 'done', reason = case when p_device = g.p1 then 'cancelled' else 'declined' end where id = p_id;
  else
    if p_device <> g.p2 then raise exception 'partie inconnue'; end if;
    perform public.rc__not_blocked(p_device);
    if g.mode = 'live' and public.rc__duel_busy(p_device) then raise exception 'tu es déjà en partie'; end if;
    if g.mode = 'live' and public.rc__duel_busy(g.p1) then raise exception 'joueur déjà en partie'; end if;
    if exists (select 1 from public.rc_players where device = g.p1 and blocked) then raise exception 'joueur indisponible'; end if;
    -- mises : 50 pièces chacun, prélevées maintenant
    select coins into c1 from public.rc_players where device = g.p1 for update;
    select coins into c2 from public.rc_players where device = g.p2 for update;
    if c2 < g.stake then raise exception 'pas assez de pièces'; end if;
    if c1 < g.stake then raise exception 'adversaire sans pièces'; end if;
    update public.rc_players set coins = coins - g.stake where device in (g.p1, g.p2);
    update public.rc_players set seen_at = now() where device = p_device;
    update public.rc_c4 set status = 'playing', turn = 1, move_at = now() where id = p_id;
  end if;
  select * into g from public.rc_c4 where id = p_id;
  return public.rc__c4_json(g, p_device) || jsonb_build_object('coins', (select coins from public.rc_players where device = p_device));
end $function$;

-- rc_bs_answer (acceptation refusée si déjà en partie)
CREATE OR REPLACE FUNCTION public.rc_bs_answer(p_device text, p_id bigint, p_accept boolean, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare g public.rc_bs; c1 bigint; c2 bigint;
begin
  perform public.rc__check(p_sig, p_device || '|bsans|' || p_id || '|' || case when p_accept then 1 else 0 end);
  perform public.rc__bs_settle(p_id);
  select * into g from public.rc_bs where id = p_id for update;
  if g.id is null or p_device not in (g.p1, g.p2) then raise exception 'partie inconnue'; end if;
  if g.status <> 'invite' then raise exception 'invitation expirée'; end if;
  if not p_accept then
    update public.rc_bs set status = 'done', reason = case when p_device = g.p1 then 'cancelled' else 'declined' end where id = p_id;
  else
    if p_device <> g.p2 then raise exception 'partie inconnue'; end if;
    perform public.rc__not_blocked(p_device);
    if g.mode = 'live' and public.rc__duel_busy(p_device) then raise exception 'tu es déjà en partie'; end if;
    if g.mode = 'live' and public.rc__duel_busy(g.p1) then raise exception 'joueur déjà en partie'; end if;
    if exists (select 1 from public.rc_players where device = g.p1 and blocked) then raise exception 'joueur indisponible'; end if;
    select coins into c1 from public.rc_players where device = g.p1 for update;
    select coins into c2 from public.rc_players where device = g.p2 for update;
    if c2 < g.stake then raise exception 'pas assez de pièces'; end if;
    if c1 < g.stake then raise exception 'adversaire sans pièces'; end if;
    update public.rc_players set coins = coins - g.stake where device in (g.p1, g.p2);
    update public.rc_players set seen_at = now() where device = p_device;
    update public.rc_bs set status = 'setup', move_at = now() where id = p_id;
  end if;
  return public.rc__bs_out(p_id, p_device);
end $function$;

-- rc_rj_answer (acceptation refusée si déjà en partie)
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
    if public.rc__duel_busy(p_device) then raise exception 'tu es déjà en partie'; end if;
    if public.rc__duel_busy(g.p1) then raise exception 'joueur déjà en partie'; end if;
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

-- rc_duel_ping (paiement du Rétro Jump solo)
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

-- PostgREST : prendre en compte les nouvelles fonctions
notify pgrst, 'reload schema';
