-- Outil admin web : étape 2 (tout le reste de la liste « À venir »)
-- Programmation, sanctions, anti-triche, duels en cours, défis (réservoir + express), Gamedle,
-- roue / paquet gratuit / solo du jour, bornes, cadeaux de version, Actu (masquer), rôles d'admin,
-- remises à zéro. À lancer APRÈS 2026-11-03_outil_admin.sql. Relançable.
-- Les fonctions du jeu modifiées gardent leur comportement tant qu'aucun réglage n'est posé.

-- ═════════════════════════════ TABLES ═════════════════════════════
create table if not exists public.rc_admin_sched (
  id      bigserial primary key,
  at      timestamptz not null,
  every   text check (every in ('day', 'week')),
  op      text not null check (op in ('mail', 'banner', 'live', 'maint', 'chat', 'event')),
  args    jsonb not null default '{}'::jsonb,
  label   text not null default '',
  by_dev  text,
  done_at timestamptz,
  runs    int not null default 0,
  last_err text,
  created_at timestamptz not null default now()
);
alter table public.rc_admin_sched owner to rc_owner;
revoke all on public.rc_admin_sched from anon, authenticated;

create table if not exists public.rc_sanctions (
  id        bigserial primary key,
  device    text not null references public.rc_players(device) on delete cascade,
  kind      text not null check (kind in ('block', 'mute', 'trade', 'duel', 'warn')),
  until     timestamptz,                -- null = définitif
  reason    text not null default '',
  by_dev    text,
  at        timestamptz not null default now(),
  lifted_at timestamptz
);
create index if not exists rc_sanctions_dev on public.rc_sanctions (device) where lifted_at is null;
alter table public.rc_sanctions owner to rc_owner;
revoke all on public.rc_sanctions from anon, authenticated;

create table if not exists public.rc_admin_alert_ok (key text primary key, at timestamptz not null default now());
alter table public.rc_admin_alert_ok owner to rc_owner;
revoke all on public.rc_admin_alert_ok from anon, authenticated;

create table if not exists public.rc_gamedle_force (day date primary key, card text not null references public.rc_cards(id));
alter table public.rc_gamedle_force owner to rc_owner;
revoke all on public.rc_gamedle_force from anon, authenticated;

create table if not exists public.rc_upgrade_gifts (ver text primary key, reward jsonb not null, out_at timestamptz not null);
alter table public.rc_upgrade_gifts owner to rc_owner;
revoke all on public.rc_upgrade_gifts from anon, authenticated;
insert into public.rc_upgrade_gifts (ver, reward, out_at) values
  ('1.0.16', '{"coins":500}', '2026-10-21 09:30+00'),
  ('1.0.18', '{"coins":600,"pixels":8,"packs":{"premium":1}}', '2026-10-22 06:45+00'),
  ('1.0.23', '{"coins":600,"packs":{"premium":1}}', '2026-10-27 08:00+00')
on conflict (ver) do nothing;

alter table public.rc_admins add column if not exists role text not null default 'full';
alter table public.rc_feed add column if not exists hidden boolean not null default false;

-- ═════════════════════════ RÔLES D'ADMIN ═════════════════════════
-- full = tout ; anim = animation (événements, tournois, courrier, sondages, bandeau, programmation)
-- modo = modération (chat, Bourse, Actu, muet / avertissement / Bourse interdite, notes, alertes)
create or replace function public.rc__adm_allowed(p_role text)
 returns text[] language sql immutable as $$
  select array['check', 'accounts', 'player', 'links', 'stats', 'chat', 'market', 'mails', 'polls', 'events', 'log', 'feed',
               'act', 'card', 'statlist',
               'x:dash', 'x:players', 'x:player', 'x:econ', 'x:catalog', 'x:duels', 'x:sched', 'x:cheat', 'x:sanctions',
               'x:feed', 'x:cfg', 'x:gamedle', 'x:cab', 'x:admins']
       || case p_role
            when 'modo' then array['chatact', 'mremove', 'x:mute', 'x:sanction_add', 'x:sanction_lift', 'x:feed_hide',
                                   'x:note', 'x:alert_ok']
            when 'anim' then array['mail', 'mail2', 'maildel', 'pollnew', 'pollclose', 'evsave', 'evactive', 'toursave',
                                   'tourcancel', 'config:banner', 'x:sched_add', 'x:sched_del']
            else array[]::text[] end
$$;
alter function public.rc__adm_allowed(text) owner to rc_owner;

create or replace function public.rc__admin(p_dev text, p_sig text, p_payload text)
 returns void language plpgsql security definer set search_path to 'public', 'extensions'
as $$
declare v_role text; a text := split_part(coalesce(p_payload, ''), '|', 1); k text;
begin
  perform public.rc__check(p_sig, p_dev || '|admin|' || coalesce(p_payload, ''));
  if not public.rc__is_admin(p_dev) then raise exception 'réservé'; end if;
  select coalesce(r.role, 'full') into v_role
    from public.rc_admins r join public.rc_players p on p.pid = r.pid where p.device = p_dev limit 1;
  if coalesce(v_role, 'full') <> 'full' then
    k := case a when 'x' then 'x:' || split_part(p_payload, '|', 2)
                when 'config' then 'config:' || split_part(p_payload, '|', 2) else a end;
    if not (k = any(public.rc__adm_allowed(v_role))) then raise exception 'action réservée à un autre rôle d''admin'; end if;
  end if;
  -- journal : seulement les actions (pas les lectures ; celles de rc_admin_x sont notées par rc_admin_x)
  if a in ('mail', 'mail2', 'block', 'rename', 'config', 'live', 'mremove', 'maildel', 'pollnew', 'pollclose', 'evsave', 'evactive',
           'toursave', 'tourcancel', 'chatact') then
    insert into public.rc_admin_log (device, action) values (p_dev, left(p_payload, 400));
  end if;
end $$;
alter function public.rc__admin(text, text, text) owner to rc_owner;

-- ═════════════════════════ SANCTIONS (dans le jeu) ═════════════════════════
create or replace function public.rc__sanction_until(p_dev text, p_kind text)
 returns timestamptz language sql stable security definer set search_path to 'public' as $$
  select case when bool_or(until is null) then 'infinity'::timestamptz else max(until) end
    from public.rc_sanctions where device = p_dev and kind = p_kind and lifted_at is null and (until is null or until > now())
$$;
alter function public.rc__sanction_until(text, text) owner to rc_owner;

-- Bourse, cadeaux, échanges : rc__not_new est déjà appelé par toutes ces fonctions
create or replace function public.rc__not_new(p_device text)
 returns void language plpgsql security definer set search_path to 'public' as $$
declare u timestamptz;
begin
  if exists (select 1 from public.rc_players where device = p_device and created_at > now() - interval '24 hours') then
    raise exception 'compte trop récent : possible 24 h après la création du compte';
  end if;
  u := public.rc__sanction_until(p_device, 'trade');
  if u is not null then
    raise exception 'Bourse, cadeaux et échanges suspendus %',
      case when u = 'infinity' then 'pour ce compte' else 'jusqu''au ' || to_char(u at time zone 'Europe/Paris', 'DD/MM à HH24"h"MI') end;
  end if;
end $$;
alter function public.rc__not_new(text) owner to rc_owner;

-- duels et tournois : rc__not_blocked est appelé par les défis, acceptations et inscriptions
create or replace function public.rc__not_blocked(p_dev text)
 returns void language plpgsql security definer set search_path to 'public' as $$
declare u timestamptz;
begin
  if exists (select 1 from public.rc_players where device = p_dev and blocked) then
    raise exception 'compte bloqué : échanges, ventes, achats, cadeaux, duels et tournois désactivés';
  end if;
  u := public.rc__sanction_until(p_dev, 'duel');
  if u is not null then
    raise exception 'duels et tournois suspendus %',
      case when u = 'infinity' then 'pour ce compte' else 'jusqu''au ' || to_char(u at time zone 'Europe/Paris', 'DD/MM à HH24"h"MI') end;
  end if;
end $$;
alter function public.rc__not_blocked(text) owner to rc_owner;

-- ═════════════════════════ RÉGLAGES LUS PAR LE JEU ═════════════════════════
-- défis de la semaine : réservoir modifiable (objectif, pièces, désactivé) dans rc_config « wpool »
create or replace function public.rc__wpool()
 returns table(id integer, kind text, goal integer, reward integer)
 language sql stable security definer set search_path to 'public' as $$
  -- réservoir des défis de la semaine : 6 sont tirés chaque lundi (ne pas renuméroter) ; surcharges : rc_config « wpool »
  select d.id, d.kind, coalesce((o.e->>'goal')::int, d.goal), coalesce((o.e->>'reward')::int, d.reward)
    from (values (1, 'open', 25, 250), (2, 'gift', 18, 200), (3, 'trade', 6, 300), (4, 'win', 5, 300), (5, 'gamedle', 6, 200),
                 (6, 'epic', 3, 300), (7, 'play', 10, 250), (8, 'new', 40, 300), (9, 'quiz', 50, 200), (10, 'sale', 5, 250),
                 (11, 'free', 7, 250), (12, 'premium', 5, 250)) d(id, kind, goal, reward)
    left join lateral (select e from jsonb_array_elements(coalesce((select value from public.rc_config where key = 'wpool'), '[]'::jsonb)) e
                        where (e->>'id')::int = d.id limit 1) o on true
$$;
alter function public.rc__wpool() owner to rc_owner;

create or replace function public.rc__wsel()
 returns integer[] language sql stable security definer set search_path to 'public' as $$
  -- les 6 défis de la semaine (mêmes pour tous) : figés par l'admin (rc_config « wsel_fix »), sinon tirés parmi les défis actifs
  select coalesce(
    (select array_agg(v::int order by v::int)
       from jsonb_array_elements_text((select value -> (public.rc__week()::text) from public.rc_config where key = 'wsel_fix')) v),
    case when public.rc__week() = date '2026-10-19' then array[1, 2, 3, 4, 5, 6]
         else (select array_agg(s.id order by s.id) from (
                 select p.id from public.rc__wpool() p
                  where p.id not in (select (e->>'id')::int from jsonb_array_elements(coalesce((select value from public.rc_config where key = 'wpool'), '[]'::jsonb)) e
                                      where coalesce((e->>'off')::boolean, false))
                  order by md5(public.rc__week()::text || '#' || p.id) limit 6) s) end)
$$;
alter function public.rc__wsel() owner to rc_owner;

-- défi express : liste modifiable (rc_config « express »), mission du jour figée lors d'une modification (« express_fix »)
create or replace function public.rc__express_def(p_day date)
 returns table(kind text, goal integer, reward jsonb)
 language plpgsql stable security definer set search_path to 'public' as $$
declare j jsonb; n int; v_h int := abs(hashtext('express#' || p_day::text));
begin
  select value into j from public.rc_config where key = 'express_fix';
  if j is not null and j->>'day' = p_day::text then
    return query select j->>'kind', (j->>'goal')::int, j->'reward'; return;
  end if;
  select value into j from public.rc_config where key = 'express';
  if j is not null and jsonb_typeof(j) = 'array' and jsonb_array_length(j) > 0 then
    n := jsonb_array_length(j);
    return query select j->(v_h % n)->>'kind', (j->(v_h % n)->>'goal')::int, j->(v_h % n)->'reward'; return;
  end if;
  return query select m.kind, m.goal, m.reward from (values
    (0, 'open', 2, '{"coins":80}'::jsonb), (1, 'gift', 1, '{"coins":60}'::jsonb), (2, 'trade', 1, '{"coins":100}'::jsonb),
    (3, 'win', 1, '{"coins":100}'::jsonb), (4, 'gamedle', 1, '{"coins":60}'::jsonb), (5, 'play', 2, '{"coins":80}'::jsonb),
    (6, 'new', 2, '{"coins":80}'::jsonb), (7, 'quiz', 5, '{"coins":60}'::jsonb), (8, 'sale', 1, '{"coins":80}'::jsonb),
    (9, 'free', 1, '{"coins":50}'::jsonb), (10, 'premium', 1, '{"coins":100}'::jsonb), (11, 'epic', 1, '{"coins":150,"pixels":1}'::jsonb)
  ) m(i, kind, goal, reward) where m.i = v_h % 12;
end $$;
alter function public.rc__express_def(date) owner to rc_owner;

-- Gamedle : carte forcée par l'admin pour un jour (rc_gamedle_force), sinon tirage habituel
create or replace function public.rc__gamedle_card(p_day date)
 returns text language sql stable security definer set search_path to 'public' as $$
  select coalesce((select card from public.rc_gamedle_force where day = p_day),
                  (select id from public.rc_cards where saga is null and rarity >= case when p_day >= date '2026-10-17' then 3 else 2 end
                    order by md5(id || p_day::text) limit 1))
$$;
alter function public.rc__gamedle_card(date) owner to rc_owner;

-- paquet gratuit : délai réglable (live « free_hours », 6 h par défaut ; l'effet d'événement garde la main)
create or replace function public.rc__free_in(p_dev text)
 returns integer language sql stable security definer set search_path to 'public' as $$
  select coalesce((select greatest(0, ceil(extract(epoch from (last_free_at
           + make_interval(hours => coalesce(public.rc__effect('free_fast'), public.rc__cfg('free_hours', 6))::int) - now()))))::int
         from public.rc_players where device = p_dev), 0)
$$;
alter function public.rc__free_in(text) owner to rc_owner;

-- roue : délai réglable (live « wheel_hours », 12 h par défaut)
create or replace function public.rc__wheel_in(p_device text)
 returns integer language sql stable security definer set search_path to 'public' as $$
  -- secondes avant le prochain tour (0 = disponible) ; avant la bascule : un tour par jour
  select coalesce((
    select case when p.wheel_at is not null
                then greatest(0, ceil(extract(epoch from p.wheel_at + make_interval(hours => public.rc__cfg('wheel_hours', 12)::int) - now()))::int)
                when p.wheel_day is not distinct from public.rc__today() then (public.rc__cfg('wheel_hours', 12) * 3600)::int
                else 0 end
      from public.rc_players p where p.device = p_device), 0)
$$;
alter function public.rc__wheel_in(text) owner to rc_owner;

-- lots du solo du jour (Rétro Jump / course) : rc_config « solo_prize » {"1":…, "2":…, "3":…}
create or replace function public.rc__rj_solo_prize(p_place integer)
 returns jsonb language sql stable security definer set search_path to 'public' as $$
  select coalesce((select value -> (p_place::text) from public.rc_config where key = 'solo_prize'),
                  case p_place when 1 then '{"coins":500,"pixels":2}'::jsonb when 2 then '{"coins":300,"pixels":1}'::jsonb
                               when 3 then '{"coins":100}'::jsonb end)
$$;
alter function public.rc__rj_solo_prize(integer) owner to rc_owner;

-- roue (chances), bornes (plafonds, prime), cadeaux de version (table), Actu (masquées) : retouches ciblées des fonctions
-- en place (vérifiées avant d'être appliquées ; sans effet si déjà faites)
do $$
declare d text; n text;
begin
  -- rc_wheel : chances lues dans rc_config « wheel » {w:[9], wg:[9]}, délai réglable
  d := pg_get_functiondef('public.rc_wheel(text, text)'::regprocedure);
  if position('rc__wheel_w(' in d) = 0 then
    n := replace(d, 'w := array[19, 15, 14, 17, 10, 12, 6, 3, 4];', 'w := public.rc__wheel_w(''wg'', array[19, 15, 14, 17, 10, 12, 6, 3, 4]);');
    n := replace(n, 'w := array[22, 15, 12, 19, 8, 14, 4, 3, 3];', 'w := public.rc__wheel_w(''w'', array[22, 15, 12, 19, 8, 14, 4, 3, 3]);');
    n := replace(n, '''next_in'', 43200', '''next_in'', public.rc__wheel_in(p_device)');
    if n = d or position('rc__wheel_w(''w''' in n) = 0 or position('rc__wheel_w(''wg''' in n) = 0 then raise exception 'rc_wheel : retouche impossible'; end if;
    -- rc__wheel_w doit exister avant
    execute $f$
      create or replace function public.rc__wheel_w(p_k text, p_def int[])
       returns int[] language sql stable security definer set search_path to 'public' as $b$
        select coalesce(nullif(array(select x::int from jsonb_array_elements_text((select value -> p_k from public.rc_config where key = 'wheel')) x), '{}'::int[]), p_def)
      $b$ $f$;
    execute 'alter function public.rc__wheel_w(text, int[]) owner to rc_owner';
    execute n;
  end if;

  -- rc_cab_end : plafonds de points par seconde et prime du record réglables (live « cab_snake / cab_bricks / cab_dodge / cab_prime »)
  d := pg_get_functiondef('public.rc_cab_end(text, bigint, integer, text)'::regprocedure);
  if position('cab_snake' in d) = 0 then
    n := replace(d, 'v_rate := case x.game when ''snake'' then 250 when ''bricks'' then 450 else 120 end',
                    'v_rate := case x.game when ''snake'' then public.rc__cfg(''cab_snake'', 250) when ''bricks'' then public.rc__cfg(''cab_bricks'', 450) else public.rc__cfg(''cab_dodge'', 120) end');
    n := replace(n, 'v_gain := 20;', 'v_gain := public.rc__cfg(''cab_prime'', 20)::int;');
    if position('cab_snake' in n) = 0 or position('cab_prime' in n) = 0 then raise exception 'rc_cab_end : retouche impossible'; end if;
    execute n;
  end if;

  -- rc_upgrade_gift : cadeaux lus dans la table rc_upgrade_gifts (au lieu de la liste écrite dans la fonction)
  d := pg_get_functiondef('public.rc_upgrade_gift(text, text, text)'::regprocedure);
  if position('rc_upgrade_gifts' in d) = 0 then
    n := regexp_replace(d, 'from \(values.*?\) x\(ver, rw, out_at\)', 'from (select g.ver, g.reward, g.out_at from public.rc_upgrade_gifts g) x(ver, rw, out_at)');
    if position('rc_upgrade_gifts' in n) = 0 then raise exception 'rc_upgrade_gift : retouche impossible'; end if;
    execute n;
  end if;

  -- Actu : les publications masquées par l'admin n'apparaissent plus (3 versions de la liste)
  foreach n in array array['public.rc_feed_list(bigint)', 'public.rc_feed_list2(bigint)', 'public.rc_feed_list3(text, bigint)'] loop
    d := pg_get_functiondef(n::regprocedure);
    if position('not f.hidden' in d) = 0 and position('where f.id' in d) > 0 then
      execute replace(d, 'where f.id', 'where not f.hidden and f.id');
    end if;
  end loop;
end $$;

-- ═════════════════════════ HORLOGE : PROGRAMMATION + FIN DES SANCTIONS ═════════════════════════
create or replace function public.rc__adm_run(s public.rc_admin_sched)
 returns void language plpgsql security definer set search_path to 'public' as $$
declare a jsonb := s.args; t text; d text; v_id bigint; rw jsonb;
begin
  case s.op
  when 'mail' then
    t := coalesce(a->>'target', 'all'); rw := public.rc__rw_clean(coalesce(a->'reward', '{}'::jsonb));
    if t like 'pid:%' then select device into d from public.rc_players where pid = substr(t, 5); if d is null then raise exception 'joueur inconnu'; end if; end if;
    insert into public.rc_mail (device, title, body, coins, pixels, packs, reward, grp)
    values (d, left(coalesce(a->>'title', ''), 80), left(coalesce(a->>'body', ''), 600), 0, 0, 0, rw,
            case when t in ('active7', 'new7', 'inactive7') then t end) returning id into v_id;
    if t in ('active7', 'new7', 'inactive7') then
      insert into public.rc_mail_to (mail_id, device)
      select v_id, p.device from public.rc_players p
       where (t = 'active7' and p.seen_at > now() - interval '7 days') or (t = 'new7' and p.created_at > now() - interval '7 days')
          or (t = 'inactive7' and (p.seen_at is null or p.seen_at <= now() - interval '7 days'));
    end if;
  when 'banner' then
    insert into public.rc_config (key, value) values ('banner', jsonb_build_object('text', left(coalesce(a->>'text', ''), 200), 'until', a->>'until'))
    on conflict (key) do update set value = excluded.value;
  when 'live' then
    update public.rc_config set value = value || (a->'values') where key = 'live';
  when 'maint' then
    insert into public.rc_config (key, value) values ('maintenance', jsonb_build_object('on', coalesce((a->>'on')::boolean, false), 'msg', left(coalesce(a->>'msg', ''), 300)))
    on conflict (key) do update set value = excluded.value;
  when 'chat' then
    insert into public.rc_chat (device, msg) values (s.by_dev, left(coalesce(a->>'msg', ''), 300));
  when 'event' then
    update public.rc_events set active = coalesce((a->>'on')::boolean, true) where id = (a->>'id')::bigint;
  end case;
end $$;
alter function public.rc__adm_run(public.rc_admin_sched) owner to rc_owner;

create or replace function public.rc__adm_tick()
 returns void language plpgsql security definer set search_path to 'public' as $$
declare s public.rc_admin_sched; e text; nx timestamptz; step interval;
begin
  if not pg_try_advisory_xact_lock(hashtext('rc__adm_tick')) then return; end if;
  for s in select * from public.rc_admin_sched where done_at is null and at <= now() order by at limit 20 loop
    e := null;
    begin perform public.rc__adm_run(s);
    exception when others then e := sqlerrm; end;
    if s.every is null then
      update public.rc_admin_sched set done_at = now(), runs = runs + 1, last_err = e where id = s.id;
    else
      step := case s.every when 'day' then interval '1 day' else interval '7 days' end;
      nx := s.at; while nx <= now() loop nx := nx + step; end loop;
      update public.rc_admin_sched set runs = runs + 1, last_err = e, at = nx where id = s.id;
    end if;
  end loop;
  -- blocages arrivés à échéance
  with ex as (update public.rc_sanctions set lifted_at = until
               where kind = 'block' and lifted_at is null and until is not null and until <= now() returning device)
  update public.rc_players p set blocked = false
   where p.device in (select ex.device from ex)
     and not exists (select 1 from public.rc_sanctions z where z.device = p.device and z.kind = 'block' and z.lifted_at is null
                        and (z.until is null or z.until > now()));
end $$;
alter function public.rc__adm_tick() owner to rc_owner;

-- appelée toutes les 30 s par le relais (en plus de la présence et des tournois)
create or replace function public.rc__rt_alive(p_topics text[])
 returns void language plpgsql security definer set search_path to 'public' as $$
begin
  update public.rc_players set seen_at = now()
   where public.rc__rt_topic(device) = any(p_topics) and (seen_at is null or seen_at < now() - interval '20 seconds');
  begin perform public.rc__tour_tick(); exception when others then null; end;   -- jamais bloquant pour la présence
  begin perform public.rc__adm_tick(); exception when others then null; end;
end $$;
alter function public.rc__rt_alive(text[]) owner to rc_owner;

-- ═════════════════════════ ALERTES (seuils réglables, « marquer normal ») ═════════════════════════
create or replace function public.rc__adm_alerts()
 returns jsonb language sql stable security definer set search_path to 'public', 'extensions'
as $$
  with c as (select coalesce((select value from rc_config where key = 'alerts'), '{}'::jsonb) j),
  t as (select coalesce((j->>'gain')::int, 15000) gain, coalesce((j->>'ip')::int, 2) ip, coalesce((j->>'gifts')::int, 8) gifts,
               coalesce((j->>'cheap')::int, 10) cheap, coalesce((j->>'login')::int, 5) login from c)
  select coalesce(jsonb_agg(a), '[]'::jsonb) from (
    select jsonb_build_object('key', 'gain:' || p.pid || ':' || rc__today(), 'kind', 'gain', 'level', 'hi', 'pid', p.pid, 'name', p.name, 'n', g.n) a
      from (select device, sum(coins) n from rc_activity
             where coins > 0 and at > now() - interval '24 hours' and kind not in ('sold') group by device having sum(coins) >= (select gain from t)) g
      join rc_players p on p.device = g.device
    union all
    select jsonb_build_object('key', 'ip:' || s.ip, 'kind', 'ip', 'level', 'hi', 'names', s.names, 'n', s.n)
      from (select ip, count(distinct name) n, jsonb_agg(distinct name) names from rc_ip_log
             where kind = 'signup' and at > now() - interval '7 days' group by ip having count(distinct name) >= (select ip from t)) s
    union all
    select jsonb_build_object('key', 'gifts:' || a.pid || ':' || b.pid, 'kind', 'gifts', 'level', 'md', 'from', a.name, 'to', b.name, 'from_pid', a.pid, 'n', g.n)
      from (select giver, receiver, count(*) n from rc_gifts
             where giver is not null and created_at > now() - interval '48 hours' group by 1, 2 having count(*) >= (select gifts from t)) g
      join rc_players a on a.device = g.giver join rc_players b on b.device = g.receiver
    union all
    select jsonb_build_object('key', 'cheap:' || m.id, 'kind', 'cheap', 'level', 'md', 'id', m.id, 'card', m.card, 'f', m.finish, 'price', m.price, 'avg', m.avg,
                              'seller', s.name, 'buyer', b.name, 'seller_pid', s.pid)
      from (select x.*, rc__avg_price(x.card, x.finish, x.id) avg from rc_market x
             where x.buyer is not null and x.sold_at > now() - interval '24 hours') m
      join rc_players s on s.device = m.seller join rc_players b on b.device = m.buyer
     where m.avg >= 100 and m.price * 100 < m.avg * (select cheap from t)
    union all
    select jsonb_build_object('key', 'login:' || l.name || ':' || rc__today(), 'kind', 'login', 'level', 'lo', 'name', l.name, 'n', l.n,
                              'pid', (select pid from rc_players where name_key = l.name))
      from (select name, count(*) n from rc_ip_log where kind = 'login_fail' and at > now() - interval '24 hours'
             group by name having count(*) >= (select login from t)) l
  ) x where not exists (select 1 from rc_admin_alert_ok k where k.key = x.a->>'key');
$$;
alter function public.rc__adm_alerts() owner to rc_owner;

-- ═════════════════════════ LECTURES DE L'OUTIL ═════════════════════════
create or replace function public.rc__adm_duels()
 returns jsonb language sql stable security definer set search_path to 'public' as $$
  select coalesce(jsonb_agg(x order by x->>'created_at' desc), '[]'::jsonb) from (
    select jsonb_build_object('game', g.game, 'id', g.id, 'status', g.status, 'mode', g.mode, 'stake', g.stake, 'tour', g.tmatch is not null,
                              'created_at', g.created_at, 'move_at', g.move_at,
                              'p1', jsonb_build_object('pid', a.pid, 'name', a.name, 'avatar', a.avatar, 'online', a.seen_at > now() - interval '75 seconds'),
                              'p2', jsonb_build_object('pid', b.pid, 'name', b.name, 'avatar', b.avatar, 'online', b.seen_at > now() - interval '75 seconds')) x
      from (select 'c4' game, id, status, mode, stake, tmatch, created_at, move_at, p1, p2 from rc_c4 where status in ('invite', 'playing')
            union all select 'bs', id, status, mode, stake, tmatch, created_at, move_at, p1, p2 from rc_bs where status in ('invite', 'setup', 'playing')
            union all select case when kind = 'run' then 'rn' else 'rj' end, id, status, mode, stake, tmatch, created_at, move_at, p1, p2
                        from rc_rj where status in ('invite', 'playing')) g
      join rc_players a on a.device = g.p1 join rc_players b on b.device = g.p2) s
$$;
alter function public.rc__adm_duels() owner to rc_owner;

create or replace function public.rc__adm_cheat()
 returns jsonb language sql stable security definer set search_path to 'public' as $$
  -- groupes de comptes créés depuis la même IP (toutes dates), avec ce qu'ils se sont passé
  select coalesce(jsonb_agg(g order by (g->>'flow')::int desc, (g->>'n')::int desc), '[]'::jsonb) from (
    select jsonb_build_object('key', 'ip:' || s.ip, 'ip', left(s.ip, 8), 'n', count(*), 'ok', exists (select 1 from rc_admin_alert_ok k where k.key = 'ip:' || s.ip),
             'players', jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'created_at', p.created_at, 'coins', p.coins,
                                                     'packs', p.packs, 'cards', p.cards, 'blocked', p.blocked, 'seen_at', p.seen_at) order by p.created_at),
             'gifts', (select count(*) from rc_gifts x where x.giver = any(array_agg(p.device)) and x.receiver = any(array_agg(p.device))),
             'sales', (select count(*) from rc_market x where x.buyer is not null and x.seller = any(array_agg(p.device)) and x.buyer = any(array_agg(p.device))),
             'sales_v', (select coalesce(sum(price), 0) from rc_market x where x.buyer is not null and x.seller = any(array_agg(p.device)) and x.buyer = any(array_agg(p.device))),
             'trades', (select count(*) from rc_trades x where x.status = 'accepted' and x.sender = any(array_agg(p.device)) and x.receiver = any(array_agg(p.device))),
             'flow', (select count(*) from rc_gifts x where x.giver = any(array_agg(p.device)) and x.receiver = any(array_agg(p.device)))
                   + (select count(*) from rc_market x where x.buyer is not null and x.seller = any(array_agg(p.device)) and x.buyer = any(array_agg(p.device)))
                   + (select count(*) from rc_trades x where x.status = 'accepted' and x.sender = any(array_agg(p.device)) and x.receiver = any(array_agg(p.device)))) g
      from (select distinct ip, name from rc_ip_log where kind = 'signup') s
      join rc_players p on p.name_key = s.name
     group by s.ip having count(*) >= 2) z
$$;
alter function public.rc__adm_cheat() owner to rc_owner;

create or replace function public.rc__adm_cfg()
 returns jsonb language sql stable security definer set search_path to 'public' as $$
  select jsonb_build_object(
    'live', coalesce((select value from rc_config where key = 'live'), '{}'::jsonb),
    'wpool', (select jsonb_agg(jsonb_build_object('id', p.id, 'kind', p.kind, 'goal', p.goal, 'reward', p.reward,
                                                  'off', coalesce((select (e->>'off')::boolean from jsonb_array_elements(coalesce((select value from rc_config where key = 'wpool'), '[]'::jsonb)) e
                                                                     where (e->>'id')::int = p.id limit 1), false)) order by p.id) from rc__wpool() p),
    'week', rc__week(), 'wsel', to_jsonb(rc__wsel()),
    'week_done', (select jsonb_agg(jsonb_build_object('i', i, 'n', (select count(*) from rc_players where w_week = rc__week() and coalesce(w_prog[i], 0) >= (rc__wgoals())[i])))
                    from generate_series(1, 6) i),
    'express', coalesce((select value from rc_config where key = 'express'),
                        '[{"kind":"open","goal":2,"reward":{"coins":80}},{"kind":"gift","goal":1,"reward":{"coins":60}},{"kind":"trade","goal":1,"reward":{"coins":100}},{"kind":"win","goal":1,"reward":{"coins":100}},{"kind":"gamedle","goal":1,"reward":{"coins":60}},{"kind":"play","goal":2,"reward":{"coins":80}},{"kind":"new","goal":2,"reward":{"coins":80}},{"kind":"quiz","goal":5,"reward":{"coins":60}},{"kind":"sale","goal":1,"reward":{"coins":80}},{"kind":"free","goal":1,"reward":{"coins":50}},{"kind":"premium","goal":1,"reward":{"coins":100}},{"kind":"epic","goal":1,"reward":{"coins":150,"pixels":1}}]'::jsonb),
    'express_today', (select jsonb_build_object('kind', d.kind, 'goal', d.goal, 'reward', d.reward,
                                                'n', (select count(*) from rc_express x where x.day = rc__today()),
                                                'done', (select count(*) from rc_express x where x.day = rc__today() and x.prog >= x.goal),
                                                'claimed', (select count(*) from rc_express x where x.day = rc__today() and x.claimed))
                        from rc__express_def(rc__today()) d),
    'wheel', jsonb_build_object('w', to_jsonb(rc__wheel_w('w', array[22, 15, 12, 19, 8, 14, 4, 3, 3])),
                                'wg', to_jsonb(rc__wheel_w('wg', array[19, 15, 14, 17, 10, 12, 6, 3, 4])),
                                'spins7', (select count(*) from rc_activity where kind = 'wheel' and at > now() - interval '7 days')),
    'solo_prize', jsonb_build_object('1', rc__rj_solo_prize(1), '2', rc__rj_solo_prize(2), '3', rc__rj_solo_prize(3)),
    'alerts', coalesce((select value from rc_config where key = 'alerts'), '{}'::jsonb),
    'trophies', (select jsonb_agg(jsonb_build_object('kind', t.kind, 't', jsonb_build_array(t.t1, t.t2, t.t3),
                                                     'n', (select jsonb_object_agg(g.tier, g.n) from (select tier, count(*) n from rc_trophy_got x where x.kind = t.kind group by tier) g))
                                  order by t.ord) from rc__tpool() t),
    'gifts', (select jsonb_agg(jsonb_build_object('ver', g.ver, 'reward', g.reward, 'out_at', g.out_at,
                                                  'got', (select count(*) from rc_upgrade_got u where u.ver = g.ver),
                                                  'can', (select count(*) from rc_players p where p.created_at < g.out_at)) order by g.ver desc) from rc_upgrade_gifts g),
    'houses', (select jsonb_object_agg(h, n) from (select coalesce(house, '0') h, count(*) n from rc_players group by 1) x),
    'pioche_today', (select count(*) from rc_players where pick_day = rc__today()),
    'quiz7', (select jsonb_build_object('n', count(*), 'players', count(distinct device), 'coins', coalesce(sum(coins), 0)) from rc_activity where kind = 'quiz' and at > now() - interval '7 days')
  )
$$;
alter function public.rc__adm_cfg() owner to rc_owner;

-- ═════════════════════════ POINT D'ENTRÉE (remplace celui de l'étape 1) ═════════════════════════
create or replace function public.rc_admin_x(p_device text, p_sig text, p_op text, p_args text)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions'
as $$
declare j jsonb; d text; v rc_players; n int; f int; c text; pw text; mode text; u timestamptz; x jsonb; k text; i int; s jsonb;
begin
  perform public.rc__admin(p_device, p_sig, 'x|' || coalesce(p_op, '') || '|' || coalesce(p_args, ''));
  j := coalesce(nullif(p_args, ''), '{}')::jsonb;
  if p_op in ('player', 'balance', 'card', 'password', 'clearfail', 'note', 'mute', 'sanction_add', 'reset') then
    select * into v from rc_players where pid = j->>'pid';
    if v.device is null then raise exception 'joueur inconnu'; end if;
    d := v.device;
  end if;
  -- journal : seulement les actions
  if p_op not in ('dash', 'players', 'player', 'econ', 'catalog', 'duels', 'sched', 'cheat', 'sanctions', 'feed', 'cfg', 'gamedle', 'cab', 'admins') then
    insert into rc_admin_log (device, action)
    values (p_device, left('x|' || p_op || '|' || coalesce(v.name, '') || '|' || coalesce(p_args, ''), 400));
  end if;

  case p_op
  -- ── lectures ──
  when 'dash' then return rc__adm_dash();
  when 'players' then return rc__adm_players();
  when 'player' then
    return rc__adm_player(j->>'pid') || jsonb_build_object('sanctions', coalesce((select jsonb_agg(jsonb_build_object('id', s2.id, 'kind', s2.kind, 'until', s2.until,
             'reason', s2.reason, 'at', s2.at, 'lifted_at', s2.lifted_at, 'by', (select name from rc_players where device = s2.by_dev)) order by s2.id desc)
             from rc_sanctions s2 where s2.device = d), '[]'::jsonb));
  when 'econ' then return rc__adm_econ((j->>'days')::int);
  when 'catalog' then return coalesce((select jsonb_agg(jsonb_build_array(id, sys, rarity, title)) from rc_cards), '[]'::jsonb);
  when 'duels' then return rc__adm_duels();
  when 'cheat' then return rc__adm_cheat();
  when 'cfg' then return rc__adm_cfg();
  when 'sched' then
    return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'at', at, 'every', every, 'op', op, 'args', args, 'label', label, 'done_at', done_at,
                                                         'runs', runs, 'last_err', last_err, 'by', (select name from rc_players where device = by_dev)) order by done_at nulls first, at)
                       from (select * from rc_admin_sched where done_at is null or done_at > now() - interval '14 days') q), '[]'::jsonb);
  when 'sanctions' then
    return coalesce((select jsonb_agg(jsonb_build_object('id', s2.id, 'kind', s2.kind, 'until', s2.until, 'reason', s2.reason, 'at', s2.at, 'lifted_at', s2.lifted_at,
                                                         'active', s2.lifted_at is null and (s2.until is null or s2.until > now()),
                                                         'pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'by', (select name from rc_players where device = s2.by_dev)) order by s2.id desc)
                       from (select * from rc_sanctions order by id desc limit 200) s2 join rc_players p on p.device = s2.device), '[]'::jsonb);
  when 'feed' then
    return coalesce((select jsonb_agg(jsonb_build_object('id', f2.id, 'at', f2.at, 'kind', f2.kind, 'card', f2.card, 'f', f2.finish, 'sys', f2.sys, 'n', f2.n,
                                                         'x', f2.extra, 'hidden', f2.hidden, 'name', p.name, 'pid', p.pid, 'avatar', p.avatar, 'name2', o.name,
                                                         'rx', (select count(*) from rc_feed_react r where r.feed_id = f2.id)) order by f2.id desc)
                       from (select * from rc_feed order by id desc limit 150) f2 join rc_players p on p.device = f2.device
                       left join rc_players o on o.device = f2.other), '[]'::jsonb);
  when 'gamedle' then
    return jsonb_build_object(
      'today', rc__today(),
      'days', (select jsonb_agg(jsonb_build_object('day', dd::date, 'card', rc__gamedle_card(dd::date), 'title', (select title from rc_cards where id = rc__gamedle_card(dd::date)),
                                                   'sys', (select sys from rc_cards where id = rc__gamedle_card(dd::date)),
                                                   'forced', exists (select 1 from rc_gamedle_force g where g.day = dd::date),
                                                   'players', (select count(*) from rc_gamedle g where g.day = dd::date),
                                                   'won', (select count(*) from rc_gamedle g where g.day = dd::date and g.won),
                                                   'tries', (select round(avg(cardinality(g.guesses)), 1) from rc_gamedle g where g.day = dd::date and g.won)) order by dd)
                 from generate_series(rc__today() - 6, rc__today() + 7, interval '1 day') dd),
      'quiz7', (select jsonb_build_object('n', count(*), 'players', count(distinct device), 'coins', coalesce(sum(coins), 0)) from rc_activity where kind = 'quiz' and at > now() - interval '7 days'));
  when 'cab' then
    return jsonb_build_object('week', rc__cab_week(),
      'live', jsonb_build_object('snake', rc__cfg('cab_snake', 250), 'bricks', rc__cfg('cab_bricks', 450), 'dodge', rc__cfg('cab_dodge', 120), 'prime', rc__cfg('cab_prime', 20)),
      'games', (select jsonb_object_agg(z.g, z.cnt) from (select rc__cab_game(cab_game, pid) g, count(*) cnt from rc_players where seen_at > now() - interval '7 days' group by 1) z),
      'runs7', (select jsonb_object_agg(z.game, z.cnt) from (select game, count(*) cnt from rc_cab_runs where started_at > now() - interval '7 days' group by game) z),
      'records', coalesce((select jsonb_agg(jsonb_build_object('owner', o.name, 'owner_pid', o.pid, 'game', b.game, 'name', p.name, 'pid', p.pid, 'score', b.score) order by b.score desc)
                             from (select distinct on (owner, game) * from rc_cab_best where week = rc__cab_week() order by owner, game, score desc) b
                             join rc_players o on o.device = b.owner join rc_players p on p.device = b.device), '[]'::jsonb));
  when 'admins' then
    return coalesce((select jsonb_agg(jsonb_build_object('pid', a.pid, 'role', a.role, 'name', p.name, 'avatar', p.avatar, 'me', p.device = p_device,
                                                         'seen_at', p.seen_at)) from rc_admins a left join rc_players p on p.pid = a.pid), '[]'::jsonb);

  -- ── actions sur un joueur (étape 1) ──
  when 'balance' then
    mode := coalesce(j->>'mode', 'add');
    if mode = 'set' then
      update rc_players set coins = greatest(coalesce((j->>'coins')::bigint, coins), 0),
                            pixels = greatest(coalesce((j->>'pixels')::int, pixels), 0),
                            fragments = greatest(coalesce((j->>'frag')::int, fragments, 0), 0)
       where device = d;
    else
      update rc_players set coins = greatest(coins + coalesce((j->>'coins')::bigint, 0), 0),
                            pixels = greatest(pixels + coalesce((j->>'pixels')::int, 0), 0),
                            fragments = greatest(coalesce(fragments, 0) + coalesce((j->>'frag')::int, 0), 0)
       where device = d;
    end if;
    select * into v from rc_players where device = d;
    return jsonb_build_object('coins', v.coins, 'pixels', v.pixels, 'frag', v.fragments);
  when 'card' then
    c := j->>'card'; f := coalesce((j->>'f')::int, 0); n := coalesce((j->>'n')::int, 1);
    if not exists (select 1 from rc_cards where id = c) then raise exception 'carte inconnue'; end if;
    if f not between 0 and 3 or n = 0 or abs(n) > 50 then raise exception 'valeurs invalides'; end if;
    if n > 0 then
      insert into rc_owned (device, card, finish, qty, first_at) values (d, c, f, n, now())
      on conflict (device, card, finish) do update set qty = rc_owned.qty + excluded.qty;
    else
      update rc_owned set qty = qty + n where device = d and card = c and finish = f and qty + n > 0;
      if not found then delete from rc_owned where device = d and card = c and finish = f; end if;
    end if;
    perform rc__rescore(d);
    return jsonb_build_object('qty', coalesce((select qty from rc_owned where device = d and card = c and finish = f), 0));
  when 'password' then
    pw := substr(translate(encode(gen_random_bytes(9), 'base64'), '+/=lIO0', 'xyzkmPQ'), 1, 8);
    update rc_players set pass_hash = crypt(encode(digest('pt-pass#41c9|' || pw, 'sha256'), 'hex'), gen_salt('bf', 8)),
                          pass_fail = 0, pass_lock = null where device = d;
    delete from rc_ip_log where kind = 'login_fail' and name = v.name_key;
    return jsonb_build_object('password', pw);
  when 'clearfail' then
    delete from rc_ip_log where kind = 'login_fail' and name = v.name_key;
    update rc_players set pass_fail = 0, pass_lock = null where device = d;
    return jsonb_build_object('ok', true);
  when 'note' then
    insert into rc_admin_notes (device, note, tags, at) values (d, left(coalesce(j->>'note', ''), 4000), left(coalesce(j->>'tags', ''), 400), now())
    on conflict (device) do update set note = excluded.note, tags = excluded.tags, at = now();
    return jsonb_build_object('ok', true);
  when 'mute' then
    n := coalesce((j->>'hours')::int, 24);
    delete from rc_chat_bans where device = d;
    if n <> 0 then insert into rc_chat_bans (device, until) values (d, case when n < 0 then null else now() + make_interval(hours => n) end); end if;
    return jsonb_build_object('ok', true);

  -- ── remises à zéro ──
  when 'reset' then
    k := j->>'what';
    if k = 'wheel' then update rc_players set wheel_at = null, wheel_day = null where device = d;
    elsif k = 'pioche' then update rc_players set pick_day = null where device = d;
    elsif k = 'free' then update rc_players set last_free_at = now() - interval '7 days', last_free = null where device = d;
    elsif k = 'gamedle' then delete from rc_gamedle where device = d and day = rc__today();
    elsif k = 'express' then delete from rc_express where device = d and day = rc__today();
    elsif k = 'quiz' then update rc_players set quiz_day = null, quiz_gain = 0 where device = d;
    else raise exception 'remise à zéro inconnue'; end if;
    return jsonb_build_object('ok', true);

  -- ── sanctions ──
  when 'sanction_add' then
    k := j->>'kind'; n := coalesce((j->>'hours')::int, 24);
    if k not in ('block', 'mute', 'trade', 'duel', 'warn') then raise exception 'sanction inconnue'; end if;
    if (select coalesce(r.role, 'full') from rc_admins r join rc_players p on p.pid = r.pid where p.device = p_device) = 'modo'
       and (k in ('block', 'duel') or n < 0 or n > 168) then raise exception 'un modérateur peut seulement : muet, avertissement, Bourse interdite (7 jours max)'; end if;
    u := case when k = 'warn' then now() when n < 0 then null else now() + make_interval(hours => n) end;
    insert into rc_sanctions (device, kind, until, reason, by_dev) values (d, k, u, left(coalesce(j->>'reason', ''), 300), p_device);
    if k = 'block' then update rc_players set blocked = true where device = d; end if;
    if k = 'mute' then delete from rc_chat_bans where device = d; insert into rc_chat_bans (device, until) values (d, u); end if;
    if coalesce((j->>'mail')::boolean, false) then
      insert into rc_mail (device, title, body, coins, pixels, packs, reward)
      values (d, case k when 'warn' then '⚠️ Avertissement' else '⛔ Sanction' end,
              left(case k when 'block' then 'Ton compte est bloqué' when 'mute' then 'Tu ne peux plus écrire dans le chat'
                          when 'trade' then 'Bourse, cadeaux et échanges suspendus' when 'duel' then 'Duels et tournois suspendus'
                          else 'Avertissement de l''équipe' end
                   || case when k = 'warn' then '' when u is null then ' (définitif)' else ' jusqu''au ' || to_char(u at time zone 'Europe/Paris', 'DD/MM à HH24"h"MI') end
                   || case when coalesce(j->>'reason', '') <> '' then E'.\nMotif : ' || (j->>'reason') else '.' end, 600), 0, 0, 0, '{}'::jsonb);
    end if;
    return jsonb_build_object('ok', true);
  when 'sanction_lift' then
    update rc_sanctions set lifted_at = now() where id = (j->>'id')::bigint and lifted_at is null returning device, kind into d, k;
    if d is null then raise exception 'sanction introuvable ou déjà levée'; end if;
    if k = 'block' and not exists (select 1 from rc_sanctions where device = d and kind = 'block' and lifted_at is null and (until is null or until > now())) then
      update rc_players set blocked = false where device = d;
    end if;
    if k = 'mute' and not exists (select 1 from rc_sanctions where device = d and kind = 'mute' and lifted_at is null and (until is null or until > now())) then
      delete from rc_chat_bans where device = d;
    end if;
    return jsonb_build_object('ok', true);

  -- ── alertes ──
  when 'alert_ok' then
    insert into rc_admin_alert_ok (key) values (left(j->>'key', 200)) on conflict do nothing;
    return jsonb_build_object('ok', true);
  when 'alerts_set' then
    insert into rc_config (key, value) values ('alerts', jsonb_build_object(
      'gain', least(greatest(coalesce((j->>'gain')::int, 15000), 1000), 1000000), 'ip', least(greatest(coalesce((j->>'ip')::int, 2), 2), 20),
      'gifts', least(greatest(coalesce((j->>'gifts')::int, 8), 2), 100), 'cheap', least(greatest(coalesce((j->>'cheap')::int, 10), 1), 90),
      'login', least(greatest(coalesce((j->>'login')::int, 5), 2), 100)))
    on conflict (key) do update set value = excluded.value;
    return jsonb_build_object('ok', true);

  -- ── programmation ──
  when 'sched_add' then
    if coalesce(j->>'op', '') not in ('mail', 'banner', 'live', 'maint', 'chat', 'event') then raise exception 'action inconnue'; end if;
    if (j->>'at')::timestamptz < now() - interval '1 minute' then raise exception 'la date doit être dans le futur'; end if;
    if j->>'op' = 'live' then
      for k in select jsonb_object_keys(j->'args'->'values') loop
        if k not in ('saga', 'holo', 'gold', 'fullart', 'pk', 'mixte', 'console', 'premium', 'mystery', 'chest_coins', 'chest_pixels', 'free_hours', 'wheel_hours') then
          raise exception 'réglage inconnu : %', k; end if;
      end loop;
    end if;
    if j->>'op' = 'mail' and trim(coalesce(j->'args'->>'title', '')) = '' then raise exception 'titre vide'; end if;
    insert into rc_admin_sched (at, every, op, args, label, by_dev)
    values ((j->>'at')::timestamptz, nullif(j->>'every', ''), j->>'op', coalesce(j->'args', '{}'::jsonb), left(coalesce(j->>'label', ''), 120), p_device)
    returning id into n;
    return jsonb_build_object('id', n);
  when 'sched_del' then
    delete from rc_admin_sched where id = (j->>'id')::bigint;
    return jsonb_build_object('ok', true);

  -- ── duels ──
  when 'duel_end' then
    k := j->>'game'; i := (j->>'id')::bigint; mode := j->>'how';
    if k not in ('c4', 'bs', 'rj', 'rn') or mode not in ('cancel', 'draw', 'win1', 'win2') then raise exception 'valeurs invalides'; end if;
    if k = 'rn' then k := 'rj'; end if;
    execute format('select jsonb_build_object(''p1'', p1, ''p2'', p2, ''stake'', coalesce(stake, 0), ''status'', status) from public.rc_%s where id = $1', k)
      into x using i;
    if x is null then raise exception 'partie introuvable'; end if;
    if x->>'status' = 'done' then raise exception 'partie déjà finie'; end if;
    if mode = 'cancel' or x->>'status' = 'invite' then
      execute format('update public.rc_%s set status = ''done'', reason = ''cancelled'', paid = false where id = $1', k) using i;
      -- anciennes parties avec mise déjà engagée : chacun récupère la sienne
      if (x->>'stake')::int > 0 and x->>'status' <> 'invite' then
        update rc_players set coins = coins + (x->>'stake')::int where device in (x->>'p1', x->>'p2');
      end if;
    else
      if k = 'c4' then perform rc__c4_finish(i, case mode when 'draw' then 0 when 'win1' then 1 else 2 end, case mode when 'draw' then 'draw' else 'timeout' end);
      elsif k = 'bs' then perform rc__bs_finish(i, case mode when 'draw' then 0 when 'win1' then 1 else 2 end, case mode when 'draw' then 'draw' else 'timeout' end);
      else perform rc__rj_finish(i, case mode when 'draw' then 0 when 'win1' then 1 else 2 end, case mode when 'draw' then 'draw' else 'timeout' end);
      end if;
    end if;
    return jsonb_build_object('ok', true);
  when 'duel_clean' then
    n := least(greatest(coalesce((j->>'hours')::int, 24), 1), 720);
    update rc_c4 set status = 'done', reason = 'expired' where status = 'invite' and created_at < now() - make_interval(hours => n);
    get diagnostics i = row_count;
    update rc_bs set status = 'done', reason = 'expired' where status = 'invite' and created_at < now() - make_interval(hours => n);
    get diagnostics f = row_count; i := i + f;
    update rc_rj set status = 'done', reason = 'expired' where status = 'invite' and created_at < now() - make_interval(hours => n);
    get diagnostics f = row_count;
    return jsonb_build_object('n', i + f);

  -- ── réglages du jeu ──
  when 'live2' then
    for k in select jsonb_object_keys(j) loop
      if k in ('free_hours', 'wheel_hours') then
        if (j->>k)::int not between 1 and 72 then raise exception 'délai entre 1 et 72 h'; end if;
      elsif k in ('cab_snake', 'cab_bricks', 'cab_dodge') then
        if (j->>k)::int not between 10 and 5000 then raise exception 'plafond entre 10 et 5000'; end if;
      elsif k = 'cab_prime' then
        if (j->>k)::int not between 0 and 1000 then raise exception 'prime entre 0 et 1000'; end if;
      else raise exception 'réglage inconnu : %', k; end if;
    end loop;
    update rc_config set value = value || j where key = 'live';
    return (select value from rc_config where key = 'live');
  when 'wpool_set' then
    -- [{id, goal, reward, off}] ; la sélection de la semaine en cours est figée avant
    if (select count(*) from jsonb_array_elements(j->'list') e where not coalesce((e->>'off')::boolean, false)) < 6 then
      raise exception 'il faut au moins 6 défis actifs'; end if;
    insert into rc_config (key, value) values ('wsel_fix', jsonb_build_object(rc__week()::text, to_jsonb(rc__wsel())))
    on conflict (key) do update set value = rc_config.value || jsonb_build_object(rc__week()::text, to_jsonb(rc__wsel()))
     where not (rc_config.value ? rc__week()::text);
    insert into rc_config (key, value) values ('wpool', (
      select jsonb_agg(jsonb_build_object('id', (e->>'id')::int, 'goal', least(greatest((e->>'goal')::int, 1), 10000),
                                          'reward', least(greatest((e->>'reward')::int, 0), 100000), 'off', coalesce((e->>'off')::boolean, false)))
        from jsonb_array_elements(j->'list') e where (e->>'id')::int between 1 and 12))
    on conflict (key) do update set value = excluded.value;
    return jsonb_build_object('ok', true);
  when 'wsel_set' then
    -- figer les 6 défis d'une semaine (en cours par défaut) ; attention : la progression suit l'ordre des défis
    if jsonb_array_length(j->'ids') <> 6 then raise exception 'il faut 6 défis'; end if;
    k := coalesce(j->>'week', rc__week()::text);
    insert into rc_config (key, value) values ('wsel_fix', jsonb_build_object(k, j->'ids'))
    on conflict (key) do update set value = rc_config.value || jsonb_build_object(k, j->'ids');
    return jsonb_build_object('ok', true);
  when 'express_set' then
    if jsonb_array_length(j->'list') < 1 then raise exception 'liste vide'; end if;
    for x in select e from jsonb_array_elements(j->'list') e loop
      if x->>'kind' not in ('open', 'gift', 'trade', 'win', 'gamedle', 'play', 'new', 'quiz', 'sale', 'free', 'premium', 'epic') then
        raise exception 'mission inconnue : %', x->>'kind'; end if;
    end loop;
    -- la mission du jour ne change pas en cours de journée
    insert into rc_config (key, value)
    select 'express_fix', jsonb_build_object('day', rc__today(), 'kind', e.kind, 'goal', e.goal, 'reward', e.reward) from rc__express_def(rc__today()) e
    on conflict (key) do update set value = excluded.value where rc_config.value->>'day' is distinct from rc__today()::text;
    insert into rc_config (key, value) values ('express', (
      select jsonb_agg(jsonb_build_object('kind', e->>'kind', 'goal', least(greatest((e->>'goal')::int, 1), 100), 'reward', rc__rw_clean(e->'reward')))
        from jsonb_array_elements(j->'list') e))
    on conflict (key) do update set value = excluded.value;
    return jsonb_build_object('ok', true);
  when 'wheel_set' then
    if jsonb_array_length(j->'w') <> 9 or jsonb_array_length(j->'wg') <> 9 then raise exception 'il faut 9 cases'; end if;
    if exists (select 1 from jsonb_array_elements_text(j->'w') a where a::int < 0 or a::int > 100)
       or exists (select 1 from jsonb_array_elements_text(j->'wg') a where a::int < 0 or a::int > 100)
       or (select sum(a::int) from jsonb_array_elements_text(j->'w') a) <> 100
       or (select sum(a::int) from jsonb_array_elements_text(j->'wg') a) <> 100 then
      raise exception 'les chances doivent faire 100 %% en tout'; end if;
    insert into rc_config (key, value) values ('wheel', jsonb_build_object('w', j->'w', 'wg', j->'wg'))
    on conflict (key) do update set value = excluded.value;
    return jsonb_build_object('ok', true);
  when 'solo_set' then
    insert into rc_config (key, value) values ('solo_prize', jsonb_build_object('1', rc__rw_clean(j->'1'), '2', rc__rw_clean(j->'2'), '3', rc__rw_clean(j->'3')))
    on conflict (key) do update set value = excluded.value;
    return jsonb_build_object('ok', true);
  when 'cab_reset' then
    if coalesce(j->>'pid', '') = '' then delete from rc_cab_best where week = rc__cab_week();
    else delete from rc_cab_best where week = rc__cab_week() and owner = (select device from rc_players where pid = j->>'pid')
           and (coalesce(j->>'game', '') = '' or game = j->>'game'); end if;
    get diagnostics n = row_count;
    return jsonb_build_object('n', n);
  when 'gamedle_force' then
    if (j->>'day')::date < rc__today() then raise exception 'jour passé'; end if;
    if coalesce(j->>'card', '') = '' then delete from rc_gamedle_force where day = (j->>'day')::date; return jsonb_build_object('ok', true); end if;
    if (j->>'day')::date = rc__today() and exists (select 1 from rc_gamedle where day = rc__today()) then
      raise exception 'des joueurs ont déjà joué aujourd''hui'; end if;
    if not exists (select 1 from rc_cards where id = j->>'card' and saga is null) then raise exception 'carte inconnue (ni saga ni Pokémon)'; end if;
    insert into rc_gamedle_force (day, card) values ((j->>'day')::date, j->>'card') on conflict (day) do update set card = excluded.card;
    return jsonb_build_object('ok', true);
  when 'gift_set' then
    if coalesce(j->>'ver', '') !~ '^\d+\.\d+\.\d+$' then raise exception 'version invalide (ex. 1.0.42)'; end if;
    if coalesce((j->>'del')::boolean, false) then
      if exists (select 1 from rc_upgrade_got where ver = j->>'ver') then raise exception 'déjà reçu par des joueurs : impossible de le supprimer'; end if;
      delete from rc_upgrade_gifts where ver = j->>'ver'; return jsonb_build_object('ok', true);
    end if;
    insert into rc_upgrade_gifts (ver, reward, out_at) values (j->>'ver', rc__rw_clean(j->'reward'), coalesce((j->>'out_at')::timestamptz, now()))
    on conflict (ver) do update set reward = excluded.reward, out_at = excluded.out_at;
    return jsonb_build_object('ok', true);
  when 'feed_hide' then
    update rc_feed set hidden = coalesce((j->>'on')::boolean, true) where id = (j->>'id')::bigint;
    return jsonb_build_object('ok', true);
  when 'admin_set' then
    -- {pid, role: full | anim | modo | null (retirer)}
    if (select coalesce(r.role, 'full') from rc_admins r join rc_players p on p.pid = r.pid where p.device = p_device) <> 'full' then
      raise exception 'réservé aux admins complets'; end if;
    if not exists (select 1 from rc_players where pid = j->>'pid') then raise exception 'joueur inconnu'; end if;
    if (select pid from rc_players where device = p_device) = j->>'pid' then raise exception 'tu ne peux pas changer ton propre rôle'; end if;
    if j->>'role' is null then delete from rc_admins where pid = j->>'pid';
    elsif j->>'role' in ('full', 'anim', 'modo') then
      insert into rc_admins (pid, role) values (j->>'pid', j->>'role') on conflict (pid) do update set role = excluded.role;
    else raise exception 'rôle inconnu'; end if;
    return jsonb_build_object('ok', true);
  else
    raise exception 'opération inconnue : %', p_op;
  end case;
end $$;
alter function public.rc_admin_x(text, text, text, text) owner to rc_owner;
grant execute on function public.rc_admin_x(text, text, text, text) to anon;

notify pgrst, 'reload schema';
