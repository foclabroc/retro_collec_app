-- Trophées à 3 paliers (bronze, argent, or) + vitrine de 3 trophées au profil et sur la borne (relançable)

create table if not exists public.rc_trophy_n (   -- compteurs tenus par le serveur
  device text not null,
  kind text not null,
  n integer not null default 0,
  primary key (device, kind)
);
alter table public.rc_trophy_n enable row level security;

create table if not exists public.rc_trophy_got (  -- dernier palier récupéré (1 bronze, 2 argent, 3 or)
  device text not null,
  kind text not null,
  tier integer not null default 0,
  primary key (device, kind)
);
alter table public.rc_trophy_got enable row level security;

alter table public.rc_players add column if not exists trophies text not null default '';  -- vitrine : « wins,,cards »

-- rc__tpool
create or replace function public.rc__tpool()
 returns table(kind text, t1 integer, t2 integer, t3 integer, ord integer)
 language sql
 immutable
as $function$
  -- trophées à 3 paliers (bronze, argent, or) ; textes et icônes dans lib/trophies.dart
  values ('packs', 25, 100, 500, 1), ('cards', 100, 400, 1000, 2), ('consoles', 1, 5, 14, 3),
         ('legend', 1, 10, 50, 4), ('fullart', 1, 10, 30, 5), ('fuse', 5, 25, 100, 6),
         ('wins', 10, 50, 200, 7), ('gifts', 10, 50, 200, 8), ('sales', 5, 25, 100, 9),
         ('trades', 5, 25, 100, 10), ('gamedle', 10, 50, 200, 11), ('chest', 1, 5, 20, 12) $function$;

-- rc__tbump
create or replace function public.rc__tbump(p_dev text, p_kind text, p_n integer)
 returns void
 language sql
 security definer
 set search_path to 'public'
as $function$
  insert into public.rc_trophy_n (device, kind, n)
  select p_dev, p_kind, p_n where p_dev is not null and p_kind is not null and coalesce(p_n, 0) > 0
  on conflict (device, kind) do update set n = public.rc_trophy_n.n + excluded.n $function$;

-- rc__tn
create or replace function public.rc__tn(p_dev text)
 returns table(kind text, n integer, got integer, t integer[], ord integer)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  -- progression de chaque trophée : paquets, cartes et consoles lus en direct, le reste compté
  select k.kind,
         case k.kind when 'packs' then p.packs
                     when 'cards' then p.cards
                     when 'consoles' then (select count(*)::int from public.rc_milestones m
                                            where m.device = p_dev and m.step = 100 and m.sys not like 'sg\_%')
                     else coalesce(c.n, 0) end,
         coalesce(g.tier, 0), array[k.t1, k.t2, k.t3], k.ord
    from public.rc__tpool() k
    join public.rc_players p on p.device = p_dev
    left join public.rc_trophy_n c on c.device = p_dev and c.kind = k.kind
    left join public.rc_trophy_got g on g.device = p_dev and g.kind = k.kind $function$;

-- rc__tshow
create or replace function public.rc__tshow(p_dev text)
 returns text
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  -- vitrine de trophées « type:palier » (3 cases, vides possibles), ex. « wins:3,,cards:2 »
  select coalesce(string_agg(case when g.tier > 0 then x.k || ':' || g.tier else '' end, ',' order by x.o), '')
    from public.rc_players p,
         unnest(string_to_array(nullif(p.trophies, ''), ',')) with ordinality x(k, o)
    left join public.rc_trophy_got g on g.device = p_dev and g.kind = x.k
   where p.device = p_dev $function$;

-- rc__tro_json
create or replace function public.rc__tro_json(p_dev text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object(
    'list', coalesce((select jsonb_agg(jsonb_build_object('k', x.kind, 'n', x.n, 'got', x.got, 't', x.t) order by x.ord)
                        from public.rc__tn(p_dev) x), '[]'::jsonb),
    'show', coalesce((select trophies from public.rc_players where device = p_dev), ''),
    'ready', (select count(*)::int from public.rc__tn(p_dev) x where x.got < 3 and x.n >= x.t[x.got + 1])) $function$;

-- rc_trophies
create or replace function public.rc_trophies(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
begin
  perform public.rc__check(p_sig, p_device || '|trophies');
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'joueur inconnu'; end if;
  return public.rc__tro_json(p_device);
end $function$;

-- rc_trophy_claim
create or replace function public.rc_trophy_claim(p_device text, p_kind text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare x record; gain int; px int; v public.rc_players;
begin
  perform public.rc__check(p_sig, p_device || '|tclaim|' || p_kind);
  perform 1 from public.rc_players where device = p_device for update;
  if not found then raise exception 'joueur inconnu'; end if;
  select * into x from public.rc__tn(p_device) t where t.kind = p_kind;
  if x.kind is null then raise exception 'trophée inconnu'; end if;
  if x.got >= 3 then raise exception 'trophée complet'; end if;
  if x.n < x.t[x.got + 1] then raise exception 'palier pas atteint'; end if;
  gain := (array[100, 300, 800])[x.got + 1];
  px := (array[0, 0, 3])[x.got + 1];
  insert into public.rc_trophy_got (device, kind, tier) values (p_device, p_kind, x.got + 1)
  on conflict (device, kind) do update set tier = excluded.tier;
  update public.rc_players set coins = coins + gain, pixels = pixels + px where device = p_device
  returning * into v;
  return public.rc__tro_json(p_device) || jsonb_build_object('coins', v.coins, 'pixels', v.pixels, 'gain', gain, 'px', px, 'tier', x.got + 1);
end $function$;

-- rc_trophy_show
create or replace function public.rc_trophy_show(p_device text, p_list text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare a text[]; i int; s text := '';
begin
  perform public.rc__check(p_sig, p_device || '|tshow|' || coalesce(p_list, ''));
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'joueur inconnu'; end if;
  a := string_to_array(coalesce(p_list, ''), ',');
  for i in 1..3 loop
    -- seulement des trophées débloqués (au moins bronze), sans doublon
    if i > 1 then s := s || ','; end if;
    if i <= coalesce(array_length(a, 1), 0) and a[i] <> ''
       and exists (select 1 from public.rc_trophy_got g where g.device = p_device and g.kind = a[i] and g.tier > 0)
       and not (a[i] = any(a[1:i - 1])) then
      s := s || a[i];
    end if;
  end loop;
  update public.rc_players set trophies = case when replace(s, ',', '') = '' then '' else s end where device = p_device;
  return public.rc__tro_json(p_device);
end $function$;

-- rc__give
create or replace function public.rc__give(p_dev text, p_card text, p_f integer, p_n integer)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  insert into public.rc_owned (device, card, finish, qty) values (p_dev, p_card, p_f, p_n)
  on conflict (device, card, finish) do update set qty = public.rc_owned.qty + excluded.qty;
  -- trophées : légendaires et Full art obtenues
  if exists (select 1 from public.rc_cards where id = p_card and rarity = 4) then perform public.rc__tbump(p_dev, 'legend', p_n); end if;
  if p_f = 3 then perform public.rc__tbump(p_dev, 'fullart', p_n); end if;
end $function$;

-- rc_fuse
CREATE OR REPLACE FUNCTION public.rc_fuse(p_device text, p_card text, p_finish integer, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare need int; ev jsonb := '[]'::jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|fuse|' || p_card || '|' || p_finish);
  if p_finish not in (0, 1) then raise exception 'fusion impossible'; end if;
  if not exists (select 1 from public.rc_cards where id = p_card) then raise exception 'carte inconnue'; end if;
  if exists (select 1 from public.rc_cards where id = p_card and saga is not null) then raise exception 'fusion impossible'; end if;
  perform 1 from public.rc_players where device = p_device for update;
  need := case p_finish when 0 then 5 else 3 end;
  if not public.rc__take(p_device, p_card, p_finish, need) then raise exception 'pas assez d''exemplaires'; end if;
  perform public.rc__give(p_device, p_card, p_finish + 1, 1);
  perform public.rc__tbump(p_device, 'fuse', 1);  -- trophée : fusions
  ev := public.rc__milestones(p_device);
  perform public.rc__rescore(p_device);
  return jsonb_build_object('card', p_card, 'f', p_finish + 1, 'events', ev,
                            'score', (select score from public.rc_players where device = p_device));
end $function$;

-- rc_trade_answer
create or replace function public.rc_trade_answer(p_device text, p_id bigint, p_accept boolean, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  t public.rc_trades; it record; ev jsonb := '[]'::jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|answer|' || p_id || '|' || p_accept);
  select * into t from public.rc_trades x where x.id = p_id and x.receiver = p_device and x.status = 'pending' for update;
  if t.id is null then raise exception 'échange introuvable'; end if;
  if p_accept then
    perform public.rc__not_blocked(t.sender);
    perform public.rc__not_blocked(t.receiver);
  end if;
  if not p_accept then
    update public.rc_trades set status = 'refused', done_at = now() where id = t.id;
    return jsonb_build_object('status', 'refused');
  end if;
  -- verrouille les deux joueurs dans un ordre fixe (pas d'interblocage)
  perform 1 from public.rc_players where device in (t.sender, t.receiver) order by device for update;
  if not public.rc__has(t.sender, t.give) or not public.rc__has(t.receiver, t.want) then
    update public.rc_trades set status = 'failed', done_at = now() where id = t.id;
    return jsonb_build_object('status', 'failed');
  end if;
  for it in select * from public.rc__items(t.give) loop
    perform public.rc__take(t.sender, it.card, it.finish, it.n);
    perform public.rc__give(t.receiver, it.card, it.finish, it.n);
  end loop;
  for it in select * from public.rc__items(t.want) loop
    perform public.rc__take(t.receiver, it.card, it.finish, it.n);
    perform public.rc__give(t.sender, it.card, it.finish, it.n);
  end loop;
  update public.rc_trades set status = 'accepted', done_at = now() where id = t.id;
  ev := ev || public.rc__bump(p_device, 'trade', 1) || public.rc__milestones(p_device);
  perform public.rc__bump(t.sender, 'trade', 1);
  perform public.rc__ev_bump(t.sender, 'trades', 1);    -- défi : échanges
  perform public.rc__ev_bump(t.receiver, 'trades', 1);
  perform public.rc__tbump(t.sender, 'trades', 1);    -- trophée : échanges
  perform public.rc__tbump(t.receiver, 'trades', 1);
  perform public.rc__milestones(t.sender);
  perform public.rc__rescore(t.sender);
  perform public.rc__rescore(t.receiver);
  return jsonb_build_object('status', 'accepted', 'events', ev);
end $function$;

-- rc_week_claim
CREATE OR REPLACE FUNCTION public.rc_week_claim(p_device text, p_i integer, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v public.rc_players; bit int; gain int := 0;
begin
  perform public.rc__check(p_sig, p_device || '|wclaim|' || p_i);
  perform public.rc__wk(p_device);
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  if p_i between 1 and 6 then
    bit := 1 << (p_i - 1);
    if (v.w_claim & bit) <> 0 then raise exception 'déjà récupéré'; end if;
    if v.w_prog[p_i] < (public.rc__wgoals())[p_i] then raise exception 'défi pas terminé'; end if;
    gain := (public.rc__wrewards())[p_i];
    update public.rc_players set w_claim = w_claim | bit, coins = coins + gain where device = p_device;
  elsif p_i = 7 then
    if (v.w_claim & 64) <> 0 then raise exception 'coffre déjà ouvert'; end if;
    if (v.w_claim & 63) <> 63 then raise exception 'coffre fermé'; end if;
    gain := public.rc__cfg('chest_coins', 500)::int;
    update public.rc_players set w_claim = w_claim | 64, coins = coins + gain, pixels = pixels + public.rc__cfg('chest_pixels', 2)::int where device = p_device;
    insert into public.rc_gifts (receiver, giver, giver_name, kind) values (p_device, null, 'Défis de la semaine', 'premium');
    perform public.rc__tbump(p_device, 'chest', 1);  -- trophée : coffres des défis
  else
    raise exception 'défi inconnu';
  end if;
  return public.rc__week_json(p_device) || jsonb_build_object('gain', gain);
end $function$;

-- rc__wbump
create or replace function public.rc__wbump(p_dev text, p_kind text, p_n integer)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare k text[];
begin
  if p_dev is null or coalesce(p_n, 0) <= 0 then return; end if;
  -- trophées : cadeaux, ventes, duels gagnés, Gamedle (comptés même hors des défis de la semaine)
  perform public.rc__tbump(p_dev, case p_kind when 'gift' then 'gifts' when 'sale' then 'sales' when 'win' then 'wins' when 'gamedle' then 'gamedle' end, p_n);
  k := public.rc__wkinds();
  if not (p_kind = any(k)) then return; end if;  -- pas au programme cette semaine
  perform public.rc__wk(p_dev);
  update public.rc_players set w_prog[array_position(k, p_kind)] =
         least(coalesce(w_prog[array_position(k, p_kind)], 0) + p_n, 9999)
   where device = p_dev;
end $function$;

-- rc_board (une colonne en plus : il faut la recréer)
drop function if exists public.rc_board();
create or replace function public.rc_board()
 returns table(pid text, name text, avatar integer, score integer, cards integer, showcase text, house text, coins bigint, online boolean, seen_at timestamp with time zone, trophies text)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select p.pid, p.name, p.avatar, p.score, p.cards, p.showcase, p.house, p.coins,
         coalesce(p.seen_at > now() - interval '10 minutes', false),
         coalesce(p.seen_at, (p.last_login::timestamp + interval '12 hours') at time zone 'Europe/Paris'),
         public.rc__tshow(p.device)
    from public.rc_players p
   where p.packs > 0 and greatest(p.seen_at, p.last_login::timestamptz) > now() - interval '7 days'
   order by p.score desc, p.created_at asc limit 100 $function$;

-- rc_profile
create or replace function public.rc_profile(p_pid text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'score', p.score,
                            'cards', p.cards, 'packs', p.packs, 'showcase', p.showcase, 'house', p.house,
                            'coins', p.coins, 'online', coalesce(p.seen_at > now() - interval '10 minutes', false),
                            'seen_at', p.seen_at,
                            'seen_day', coalesce((p.seen_at at time zone 'Europe/Paris')::date, p.last_login),
                            'since', p.created_at, 'trophies', public.rc__tshow(p.device),
                            'tro_total', (select coalesce(sum(tier), 0)::int from public.rc_trophy_got g where g.device = p.device), 'owned', public.rc__owned_json(p.device))
    from public.rc_players p where p.pid = p_pid $function$;

-- Reprise de l'historique (relançable : ne fait que remonter un compteur, jamais le doubler)
insert into public.rc_trophy_n (device, kind, n)
select device, kind, n from (
  select case winner when 1 then p1 else p2 end as device, 'wins' as kind, count(*)::int as n
    from (select p1, p2, winner, paid from public.rc_c4 union all select p1, p2, winner, paid from public.rc_bs) d
   where winner in (1, 2) and coalesce(paid, true) group by 1
  union all
  select giver, 'gifts', count(*)::int from public.rc_gifts where giver is not null group by 1
  union all
  select seller, 'sales', count(*)::int from public.rc_market where sold_at is not null group by 1
  union all
  select dev, 'trades', count(*)::int from (select sender as dev from public.rc_trades where status = 'accepted'
                                             union all select receiver from public.rc_trades where status = 'accepted') t group by 1
  union all
  select device, 'gamedle', count(*)::int from public.rc_gamedle where won group by 1
  union all
  select o.device, 'legend', sum(o.qty)::int from public.rc_owned o join public.rc_cards c on c.id = o.card
   where c.rarity = 4 and o.qty > 0 group by 1
  union all
  select device, 'fullart', sum(qty)::int from public.rc_owned where finish = 3 and qty > 0 group by 1
) s
where device in (select device from public.rc_players) and n > 0
on conflict (device, kind) do update set n = greatest(public.rc_trophy_n.n, excluded.n);
