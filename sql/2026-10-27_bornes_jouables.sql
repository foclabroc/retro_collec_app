-- 27/10/2026 : bornes jouables du Voisinage. Chaque joueur choisit le mini-jeu de sa borne (snake / bricks / dodge),
-- les visiteurs y jouent gratuitement, record de la borne affiché sur l'écran, remis à zéro chaque lundi
-- (et quand le propriétaire change de jeu).
-- Gains : record de la borne battu = +20 pièces (1 fois par jour et par borne, pas sur sa propre borne) ;
-- propriétaire = +1 pièce par partie d'un autre joueur (5 par visiteur et par jour, 30 par jour au total).
-- Temps réel : canal du propriétaire 'me' {k: cabrec, name, game, score} ; canal commun 'cab' {pid}.
-- Relançable.

alter table public.rc_players add column if not exists cab_game text;

create table if not exists public.rc_cab_runs (
  id         bigserial   primary key,
  device     text        not null,          -- joueur
  owner      text        not null,          -- propriétaire de la borne (device)
  game       text        not null,
  started_at timestamptz not null default now(),
  comm       boolean     not null default false, -- commission versée au propriétaire
  score      int,
  done_at    timestamptz
);
create index if not exists rc_cab_runs_owner on public.rc_cab_runs (owner, started_at);
create index if not exists rc_cab_runs_dev on public.rc_cab_runs (device, started_at);
alter table public.rc_cab_runs owner to rc_owner;
revoke all on public.rc_cab_runs from public;

-- meilleur score de chaque joueur sur chaque borne, par semaine (lundi)
create table if not exists public.rc_cab_best (
  owner  text        not null,
  game   text        not null,
  week   date        not null,
  device text        not null,
  score  int         not null,
  at     timestamptz not null default now(),
  primary key (owner, game, week, device)
);
create index if not exists rc_cab_best_rec on public.rc_cab_best (week, owner, game, score desc);
alter table public.rc_cab_best owner to rc_owner;
revoke all on public.rc_cab_best from public;

-- prime de record déjà versée (1 par jour et par borne)
create table if not exists public.rc_cab_paid (
  owner  text not null,
  device text not null,
  day    date not null,
  primary key (owner, device, day)
);
alter table public.rc_cab_paid owner to rc_owner;
revoke all on public.rc_cab_paid from public;

-- jeu d'une borne : choisi, sinon un des 3 selon le joueur
create or replace function public.rc__cab_game(p_game text, p_pid text)
 returns text
 language sql
 immutable
as $function$
  select coalesce(p_game, (array['snake', 'bricks', 'dodge'])[1 + abs(hashtext(coalesce(p_pid, ''))) % 3]) $function$;
alter function public.rc__cab_game(text, text) owner to rc_owner;

create or replace function public.rc__cab_week()
 returns date
 language sql
 stable
as $function$
  select date_trunc('week', public.rc__today())::date $function$;
alter function public.rc__cab_week() owner to rc_owner;

-- record actuel d'une borne : (device, score) ou rien
create or replace function public.rc__cab_rec(p_owner text, p_game text)
 returns table(device text, score int)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select b.device, b.score from public.rc_cab_best b
   where b.owner = p_owner and b.game = p_game and b.week = public.rc__cab_week()
   order by b.score desc, b.at asc limit 1 $function$;
alter function public.rc__cab_rec(text, text) owner to rc_owner;

-- écrans des bornes du Voisinage : jeu + record de la semaine
create or replace function public.rc_cab_board()
 returns table(pid text, game text, rec int, rec_name text)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select p.pid, g.game, r.score, rp.name
    from public.rc_players p
   cross join lateral (select public.rc__cab_game(p.cab_game, p.pid) as game) g
    left join lateral public.rc__cab_rec(p.device, g.game) r on true
    left join public.rc_players rp on rp.device = r.device
   where p.packs > 0 and greatest(p.seen_at, p.last_login::timestamptz) > now() - interval '7 days' $function$;
alter function public.rc_cab_board() owner to rc_owner;

-- une borne : jeu, top 5 de la semaine, mon meilleur score ; + stats de la semaine si c'est la mienne
create or replace function public.rc_cab_get(p_device text, p_pid text, p_sig text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare o public.rc_players; v_game text; v_week date := public.rc__cab_week(); r jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|cab|' || coalesce(p_pid, ''));
  select * into o from public.rc_players where pid = p_pid;
  if o.device is null then raise exception 'joueur inconnu'; end if;
  v_game := public.rc__cab_game(o.cab_game, o.pid);
  r := jsonb_build_object(
    'pid', o.pid, 'name', o.name, 'game', v_game, 'me', o.device = p_device,
    'top', (select coalesce(jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'score', t.score)
                                      order by t.score desc, t.at), '[]'::jsonb)
              from (select b.device, b.score, b.at from public.rc_cab_best b
                     where b.owner = o.device and b.game = v_game and b.week = v_week
                     order by b.score desc, b.at limit 5) t
              join public.rc_players p on p.device = t.device),
    'best', (select b.score from public.rc_cab_best b
              where b.owner = o.device and b.game = v_game and b.week = v_week and b.device = p_device),
    'paid', exists (select 1 from public.rc_cab_paid x where x.owner = o.device and x.device = p_device and x.day = public.rc__today()));
  if o.device = p_device then
    r := r || jsonb_build_object(
      'plays', (select count(*) from public.rc_cab_runs x
                 where x.owner = p_device and x.device <> p_device and x.started_at >= v_week::timestamp at time zone 'Europe/Paris'),
      'comm', (select count(*) from public.rc_cab_runs x
                 where x.owner = p_device and x.comm and x.started_at >= v_week::timestamp at time zone 'Europe/Paris'),
      'held', (select count(*) from public.rc_players p
                where p.device <> p_device
                  and (select c.device from public.rc__cab_rec(p.device, public.rc__cab_game(p.cab_game, p.pid)) c) = p_device));
  end if;
  return r;
end $function$;
alter function public.rc_cab_get(text, text, text) owner to rc_owner;

-- choisir le jeu de ma borne (changer de jeu remet son record à zéro)
create or replace function public.rc_cab_set_game(p_device text, p_game text, p_sig text)
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v public.rc_players;
begin
  perform public.rc__check(p_sig, p_device || '|cabgame|' || coalesce(p_game, ''));
  if p_game is null or p_game not in ('snake', 'bricks', 'dodge') then raise exception 'jeu inconnu'; end if;
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  if public.rc__cab_game(v.cab_game, v.pid) = p_game then
    update public.rc_players set cab_game = p_game where device = p_device and cab_game is null;
    return false;
  end if;
  update public.rc_players set cab_game = p_game where device = p_device;
  delete from public.rc_cab_best where owner = p_device;
  perform public.rc__rt_safe('rc_all', 'cab', jsonb_build_object('pid', v.pid));
  return true;
end $function$;
alter function public.rc_cab_set_game(text, text, text) owner to rc_owner;

-- début d'une partie sur une borne (+1 pièce au propriétaire, dans les limites)
create or replace function public.rc_cab_start(p_device text, p_pid text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare o public.rc_players; v_game text; v_comm boolean := false; v_id bigint; v_day timestamptz;
begin
  perform public.rc__check(p_sig, p_device || '|cabstart|' || coalesce(p_pid, ''));
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'joueur inconnu'; end if;
  select * into o from public.rc_players where pid = p_pid;
  if o.device is null then raise exception 'joueur inconnu'; end if;
  v_game := public.rc__cab_game(o.cab_game, o.pid);
  v_day := public.rc__today()::timestamp at time zone 'Europe/Paris';
  if (select count(*) from public.rc_cab_runs where device = p_device and started_at > now() - interval '1 minute') >= 12 then
    raise exception 'trop de parties, attends un peu';
  end if;
  if o.device <> p_device
     and not exists (select 1 from public.rc_players where device = p_device and blocked)
     and not exists (select 1 from public.rc_players where device = p_device and created_at > now() - interval '24 hours')
     and (select count(*) from public.rc_cab_runs where owner = o.device and device = p_device and comm and started_at >= v_day) < 5
     and (select count(*) from public.rc_cab_runs where owner = o.device and comm and started_at >= v_day) < 30 then
    v_comm := true;
  end if;
  if random() < 0.01 then perform public.rc__cab_clean(); end if;
  insert into public.rc_cab_runs (device, owner, game, comm) values (p_device, o.device, v_game, v_comm) returning id into v_id;
  if v_comm then
    update public.rc_players set coins = coins + 1, updated_at = now() where device = o.device;
  end if;
  return jsonb_build_object('run', v_id, 'game', v_game,
    'rec', (select r.score from public.rc__cab_rec(o.device, v_game) r));
end $function$;
alter function public.rc_cab_start(text, text, text) owner to rc_owner;

-- fin d'une partie : score enregistré, record de la borne, prime
create or replace function public.rc_cab_end(p_device text, p_run bigint, p_score integer, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  x public.rc_cab_runs; o public.rc_players; me public.rc_players;
  v_week date := public.rc__cab_week(); v_secs numeric; v_rate int; v_prev int; v_new boolean := false; v_gain int := 0; v_best int;
begin
  perform public.rc__check(p_sig, p_device || '|cabend|' || coalesce(p_run, 0) || '|' || coalesce(p_score, 0));
  select * into x from public.rc_cab_runs where id = p_run for update;
  if x.id is null or x.device <> p_device then raise exception 'partie inconnue'; end if;
  if x.done_at is not null then raise exception 'partie déjà terminée'; end if;
  v_secs := extract(epoch from now() - x.started_at);
  v_rate := case x.game when 'snake' then 250 when 'bricks' then 450 else 120 end; -- points par seconde au maximum
  if p_score is null or p_score < 0 or p_score > v_rate * v_secs + 200 or v_secs > 3 * 3600 then
    update public.rc_cab_runs set done_at = now(), score = 0 where id = x.id;
    raise exception 'score refusé';
  end if;
  update public.rc_cab_runs set done_at = now(), score = p_score where id = x.id;
  select * into o from public.rc_players where device = x.owner;
  select * into me from public.rc_players where device = p_device for update;
  -- la partie compte si la borne a toujours le même jeu
  if public.rc__cab_game(o.cab_game, o.pid) = x.game and p_score > 0 then
    select r.score into v_prev from public.rc__cab_rec(o.device, x.game) r;
    insert into public.rc_cab_best (owner, game, week, device, score, at)
    values (o.device, x.game, v_week, p_device, p_score, now())
    on conflict (owner, game, week, device) do update set score = excluded.score, at = excluded.at
      where public.rc_cab_best.score < excluded.score;
    v_new := p_score > coalesce(v_prev, 0);
    if v_new and o.device <> p_device and not me.blocked then
      insert into public.rc_cab_paid (owner, device, day) values (o.device, p_device, public.rc__today())
      on conflict do nothing;
      if found then
        v_gain := 20;
        update public.rc_players set coins = coins + v_gain, updated_at = now() where device = p_device returning coins into me.coins;
      end if;
    end if;
    if v_new then
      perform public.rc__rt_safe('rc_all', 'cab', jsonb_build_object('pid', o.pid));
      if o.device <> p_device then
        perform public.rc__rt_safe(public.rc__rt_topic(o.device), 'me',
          jsonb_build_object('k', 'cabrec', 'name', me.name, 'game', x.game, 'score', p_score));
      end if;
    end if;
  end if;
  select b.score into v_best from public.rc_cab_best b
   where b.owner = o.device and b.game = x.game and b.week = v_week and b.device = p_device;
  return jsonb_build_object('score', p_score, 'best', v_best, 'newrec', v_new, 'gain', v_gain, 'coins', me.coins,
    'rec', (select r.score from public.rc__cab_rec(o.device, x.game) r));
end $function$;
alter function public.rc_cab_end(text, bigint, integer, text) owner to rc_owner;

-- journal d'activité (admin)
create or replace function public.rc__act_cab()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  begin
    if tg_table_name = 'rc_cab_paid' then
      perform public.rc__act(new.device, 'reward', 2, 'record de borne battu');
    elsif tg_table_name = 'rc_cab_runs' and new.comm then
      perform public.rc__act(new.owner, 'reward', 2, 'commission de borne');
    end if;
  exception when others then null;
  end;
  return new;
end $function$;
alter function public.rc__act_cab() owner to rc_owner;

drop trigger if exists rc_cab_paid_act on public.rc_cab_paid;
create trigger rc_cab_paid_act after insert on public.rc_cab_paid for each row execute function public.rc__act_cab();
drop trigger if exists rc_cab_runs_act on public.rc_cab_runs;
create trigger rc_cab_runs_act after insert on public.rc_cab_runs for each row execute function public.rc__act_cab();

-- nettoyage : parties de plus de 30 jours, scores de plus de 5 semaines (appelé à chaque début de partie, rarement)
create or replace function public.rc__cab_clean()
 returns void
 language sql
 security definer
 set search_path to 'public'
as $function$
  delete from public.rc_cab_runs where started_at < now() - interval '30 days';
  delete from public.rc_cab_best where week < public.rc__cab_week() - 35;
  delete from public.rc_cab_paid where day < public.rc__today() - 7; $function$;
alter function public.rc__cab_clean() owner to rc_owner;
