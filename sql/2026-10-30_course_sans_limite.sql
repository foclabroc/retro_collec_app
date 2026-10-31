-- Course de jaquettes et Rétro Jump : plus de limite de 2 min (garde-fou d'1 h, fin à la chute).
-- Course : plafond serveur 100 + 40 m/s (vitesse max 36). Relançable.

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
           start_at = now() + interval '6 seconds', end_at = now() + interval '3606 seconds', move_at = now()
     where id = p_id;
  end if;
  select * into g from public.rc_rj where id = p_id;
  return public.rc__rj_json(g, p_device) || jsonb_build_object('coins', (select coins from public.rc_players where device = p_device));
end $function$;
alter function public.rc_rj_answer(text, bigint, boolean, text) owner to rc_owner;

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
  elsif jeu = 'rj' then
    -- Rétro Jump : départ 8 s plus tard (le temps d'ouvrir la partie), fin à la chute (garde-fou 1 h)
    insert into public.rc_rj (p1, p2, status, seed, start_at, end_at, move_at, tmatch)
    values (a, b, 'playing', floor(random() * 2147483646)::int + 1, now() + d + interval '8 seconds',
            now() + d + interval '3608 seconds', now(), m.id) returning id into gid;
  else
    insert into public.rc_bs (p1, p2, mode, stake, status, move_at, tmatch)
    values (a, b, 'live', 0, 'setup', now() + d, m.id) returning id into gid;
  end if;
  update public.rc_tour_matches set status = 'play', game_id = gid where id = p_mid;
end $function$;
alter function public.rc__tour_game(bigint) owner to rc_owner;

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
    -- Rétro Jump : 70 points par seconde ; course : 40 mètres par seconde (vitesse max 36)
    cap := case when g.kind = 'run' then 100 + floor(40 * sec)::int else 60 + floor(70 * sec)::int end;
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
  cap := 100 + floor(40 * extract(epoch from (now() - r.started_at)))::int;
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

notify pgrst, 'reload schema';
