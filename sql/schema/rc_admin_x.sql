create or replace function public.rc_admin_x(p_device text, p_sig text, p_op text, p_args text)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions'
as $$
declare j jsonb; d text; v rc_players; n int; f int; c text; pw text; mode text; u timestamptz; x jsonb; k text; i int; s jsonb;
begin
  perform public.rc__admin(p_device, p_sig, 'x|' || coalesce(p_op, '') || '|' || coalesce(p_args, ''));
  j := coalesce(nullif(p_args, ''), '{}')::jsonb;
  if p_op in ('player', 'balance', 'card', 'card_gift', 'password', 'clearfail', 'note', 'mute', 'sanction_add', 'reset') then
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
  when 'catalog' then return coalesce((select jsonb_agg(jsonb_build_array(id, sys, rarity, title, base)) from rc_cards), '[]'::jsonb);
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
  when 'card_gift' then
    -- carte offerte : elle attend dans « Cartes à ranger » du joueur (rc_card_stock), avec le nom du donneur
    c := j->>'card'; f := coalesce((j->>'f')::int, 0); n := coalesce((j->>'n')::int, 1);
    if not exists (select 1 from rc_cards where id = c) then raise exception 'carte inconnue'; end if;
    if f not between 0 and 3 or n not between 1 and 20 then raise exception 'valeurs invalides'; end if;
    insert into rc_card_stock (device, card, finish, giver_name)
    select d, c, f, coalesce(nullif(left(trim(j->>'from'), 40), ''), 'Admin') from generate_series(1, n);
    perform rc__rt_safe(rc__rt_topic(d), 'me', jsonb_build_object('k', 'gift'));
    return jsonb_build_object('ok', true, 'n', n);
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
