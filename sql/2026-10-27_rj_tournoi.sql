-- 27/10/2026 : tournois Rétro Jump + partie solo comptée « en partie ».
-- À lancer après sql/2026-10-27_duel_retro_jump.sql et sql/2026-10-27_rj_solo.sql.
--  · Tournois : l'admin peut choisir Rétro Jump (rc_admin_tour_save) ; chaque manche est un duel Rétro Jump
--    (rc__tour_game : départ 8 s après, 2 min, ou 15 s de plus à partir de la 2e manche), sans gains par manche
--    (rc__rj_finish), égalité rejouée, personne de présent → tirage au sort (rc__rj_settle), manches réglées
--    par l'horloge des tournois (rc__tour_tick) et comptées par rc__tour_game_done (déclencheur rc_rj_tour).
--  · Une partie solo en cours (moins de 3 min, pas finie) compte comme « en partie » (rc__duel_busy) :
--    on ne peut ni défier ce joueur, ni être défié, et il apparaît « En partie ».
-- Relançable.

-- le jeu d'un tournoi peut maintenant être 'rj'
do $$
declare c text;
begin
  for c in select conname from pg_constraint
            where conrelid = 'public.rc_tour'::regclass and contype = 'c' and pg_get_constraintdef(oid) ilike '%game%' loop
    execute format('alter table public.rc_tour drop constraint %I', c);
  end loop;
  alter table public.rc_tour add constraint rc_tour_game_check check (game in ('c4', 'bs', 'rj'));
end $$;

-- ═══ Fonctions complétées (même texte que sql/schema/) ═══

-- rc__duel_busy (partie solo comptée)
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
      -- partie solo de Rétro Jump en cours (au plus 3 min, si l'appli a été quittée sans finir)
      or exists (select 1 from public.rc_rj_runs r where r.device = p_device and r.ended_at is null
                  and r.started_at > now() - interval '3 minutes') $function$;

-- rc_admin_tour_save (tournoi Rétro Jump)
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
  if coalesce(j->>'game', '') not in ('c4', 'bs', 'rj') then raise exception 'jeu inconnu'; end if;
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

-- rc__tour_game (manches Rétro Jump)
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
    -- Rétro Jump : départ 8 s plus tard (le temps d'ouvrir la partie), 2 min
    insert into public.rc_rj (p1, p2, status, seed, start_at, end_at, move_at, tmatch)
    values (a, b, 'playing', floor(random() * 2147483646)::int + 1, now() + d + interval '8 seconds',
            now() + d + interval '128 seconds', now(), m.id) returning id into gid;
  else
    insert into public.rc_bs (p1, p2, mode, stake, status, move_at, tmatch)
    values (a, b, 'live', 0, 'setup', now() + d, m.id) returning id into gid;
  end if;
  update public.rc_tour_matches set status = 'play', game_id = gid where id = p_mid;
end $function$;

-- rc__tour_tick (manches Rétro Jump)
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
  for x in select id from public.rc_rj where tmatch is not null and status = 'playing' loop
    perform public.rc__rj_settle(x);
  end loop;
end $function$;

-- rc__rj_finish (manches de tournoi)
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
  if g.tmatch is not null then  -- manche de tournoi : défis et compteurs seulement, lots à la fin du tournoi
    update public.rc_rj set status = 'done', winner = p_winner, reason = p_reason, paid = false, move_at = now() where id = p_id;
    if p_winner in (1, 2) then perform public.rc__wbump(case when p_winner = 1 then g.p1 else g.p2 end, 'win', 1); end if;
    perform public.rc__wbump(g.p1, 'play', 1);
    perform public.rc__wbump(g.p2, 'play', 1);
    return;
  end if;
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

-- rc__rj_settle (tirage au sort en tournoi)
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
  -- tournoi : personne n'est venu → tirage au sort (sinon la manche serait rejouée sans fin)
  if w = 0 and g.tmatch is not null and g.gone1 and g.gone2 then
    w := 1 + floor(random() * 2)::int;
    perform public.rc__rj_finish(p_id, w, 'timeout');
    return;
  end if;
  why := case when w = 0 then 'draw'
              when (w = 1 and g.gone2) or (w = 2 and g.gone1) then 'timeout'
              else 'win' end;
  perform public.rc__rj_finish(p_id, w, why);
end $function$;

-- rc__rj_json (étiquette du tournoi)
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

-- manche de tournoi finie → compter la manche, manche suivante ou tour suivant
drop trigger if exists rc_rj_tour on public.rc_rj;
create trigger rc_rj_tour after update of status on public.rc_rj
  for each row when (new.tmatch is not null and new.status = 'done' and old.status is distinct from 'done')
  execute function public.rc__tour_game_done();

-- PostgREST : prendre en compte les nouvelles fonctions
notify pgrst, 'reload schema';
