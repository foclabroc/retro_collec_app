-- Roue de la fortune : un tour toutes les 12 h (au lieu d'un par jour), gains doublés,
-- 9e case « Pokémon » (carte au hasard dans « Cartes à ranger », brillante dès la 152).
-- Roue en or : seulement le 1er tour du jour de série multiple de 7. Relançable.

alter table public.rc_players add column if not exists wheel_at timestamptz;
-- ceux qui ont déjà tourné aujourd'hui attendent 12 h à partir de maintenant
update public.rc_players set wheel_at = now() where wheel_at is null and wheel_day = public.rc__today();

create or replace function public.rc__wheel_in(p_device text)
 returns integer
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  -- secondes avant le prochain tour (0 = disponible) : 12 h après le dernier ; avant la bascule : un tour par jour
  select coalesce((
    select case when p.wheel_at is not null then greatest(0, ceil(extract(epoch from p.wheel_at + interval '12 hours' - now()))::int)
                when p.wheel_day is not distinct from public.rc__today() then 43200
                else 0 end
      from public.rc_players p where p.device = p_device), 0) $function$;

create or replace function public.rc__wheel_gold(p_device text)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce((select p.streak > 0 and p.streak % 7 = 0 and p.last_login = public.rc__today()
                          and p.wheel_day is distinct from public.rc__today()
                     from public.rc_players p where p.device = p_device), false) $function$;

CREATE OR REPLACE FUNCTION public.rc_wheel(p_device text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v public.rc_players;
  gold boolean;
  w int[];
  prize int[];
  x float := random() * 100; acc float := 0; seg int := 0; k int;
  r int; f int; c text; is_new boolean; card jsonb := null; pk jsonb := null; ev jsonb := '[]'::jsonb;
  minr int;
begin
  perform public.rc__check(p_sig, p_device || '|wheel');
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  if public.rc__wheel_in(p_device) > 0 then raise exception 'déjà tourné aujourd''hui'; end if;
  -- roue en or : 1er tour du jour de série multiple de 7 (le 2e tour du jour est normal)
  gold := public.rc__wheel_gold(p_device);
  -- 9 cases : 0 petit, 1, 2 carte, 3, 4, 5, 6 rare (épique en or), 7 gros lot (JACKPOT en or), 8 carte Pokémon
  if gold then
    w := array[19, 15, 14, 17, 10, 12, 6, 3, 4];
    prize := array[80, 200, 0, 120, 400, 160, 0, 2000, 0];
  else
    w := array[22, 15, 12, 19, 8, 14, 4, 3, 3];
    prize := array[40, 100, 0, 60, 200, 80, 0, 600, 0];
  end if;
  for k in 1..9 loop
    acc := acc + w[k];
    if x < acc then seg := k - 1; exit; end if;
  end loop;
  update public.rc_players set wheel_day = public.rc__today(), wheel_at = now(), coins = coins + prize[seg + 1] where device = p_device;
  -- cases carte (2 = carte, 6 = rare) et, en or, le JACKPOT (7) avec une légendaire
  if seg in (2, 6) or (gold and seg = 7) then
    minr := case when gold and seg = 7 then 4
                 when gold and seg = 6 then 3
                 when gold or seg = 6 then 2
                 else 0 end;
    r := case when minr = 4 then 4 else public.rc__roll(minr) end;
    select id, rarity into c, r from public.rc_cards where rarity <= r and saga is null order by rarity desc, random() limit 1;
    f := public.rc__roll_finish(r);
    is_new := public.rc__is_new(p_device, c, f);
    perform public.rc__give(p_device, c, f, 1);
    card := jsonb_build_object('c', c, 'f', f, 'r', r, 'n', is_new);
    ev := ev || public.rc__milestones(p_device);
    perform public.rc__rescore(p_device);
  elsif seg = 8 then
    -- carte Pokémon au hasard : elle attend dans « Cartes à ranger » (brillante dès la 152)
    select id into c from public.rc_cards where saga = 'pk' order by random() limit 1;
    if c is not null then
      f := case when substr(c, 4)::int >= 152 then 1 else 0 end;
      insert into public.rc_card_stock (device, card, finish, giver_name) values (p_device, c, f, 'Roue de la fortune');
      pk := jsonb_build_object('c', c, 'f', f, 'r', 3, 'stock', true);
    end if;
  end if;
  return jsonb_build_object('seg', seg, 'gain', prize[seg + 1], 'card', card, 'pk', pk, 'events', ev, 'gold', gold,
                            'next_in', 43200,
                            'coins', (select p.coins from public.rc_players p where p.device = p_device));
end $function$;

create or replace function public.rc_notifs(p_device text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object(
    'trades', (select count(*)::int from public.rc_trades t where t.receiver = p_device and t.status = 'pending'),
    'sales', coalesce((
      select jsonb_agg(jsonb_build_object('id', m.id, 'card', m.card, 'f', m.finish, 'price', m.price,
                                          'buyer', (select b.name from public.rc_players b where b.device = m.buyer))
                       order by m.sold_at)
        from public.rc_market m, public.rc_players me
       where me.device = p_device and m.seller = p_device and m.buyer is not null and m.sold_at > me.market_seen), '[]'::jsonb),
    'wheel', public.rc__wheel_in(p_device) = 0,
    'wheel_in', public.rc__wheel_in(p_device),
    'wheel_gold', public.rc__wheel_gold(p_device),
    'gifts', (select count(*)::int from public.rc_gifts g where g.receiver = p_device and g.opened_at is null),
    'gift_from', (select g.giver_name from public.rc_gifts g where g.receiver = p_device and g.opened_at is null order by g.id desc limit 1),
    'cards', (select count(*)::int from public.rc_card_stock s where s.device = p_device and s.taken_at is null),
    'gift_last', (select coalesce(max(g.id), 0) from public.rc_gifts g where g.receiver = p_device),
    'gifts_left', (select 3 - case when gift_day = public.rc__today() then gift_n else 0 end from public.rc_players where device = p_device),
    'can_gift', (select gift_day is distinct from public.rc__today() or gift_n < 3 from public.rc_players where device = p_device),
    'week', coalesce(public.rc__wk_ready(p_device), 0),
    'trophies', coalesce(public.rc__tro_ready(p_device), 0),
    'reacts', coalesce(public.rc__reacts_new(p_device), 0),
    'lots', (select lots from public.rc_players where device = p_device),
    'free', public.rc__free_in(p_device) = 0,
    'free_in', public.rc__free_in(p_device),
    'free_at', (select coalesce(extract(epoch from last_free_at)::bigint, 0) from public.rc_players where device = p_device),
    'lot_free', (select public.rc__lot_day() and lot_free is distinct from public.rc__today() from public.rc_players where device = p_device),
    'lot_price', public.rc__lot_price(),
    'chat', (select count(*)::int from public.rc_chat c, public.rc_players me
              where me.device = p_device and c.id > me.chat_seen and c.device <> p_device and not c.hidden),
    'chat_last', (select coalesce(max(c.id), 0) from public.rc_chat c where not c.hidden),
    'mention', (select coalesce(max(c.id), 0) from public.rc_chat c, public.rc_players me
                 where me.device = p_device and c.id > me.chat_seen and c.device <> p_device and not c.hidden
                   and (lower(regexp_replace(c.msg, '[^[:alnum:]@]', '', 'g')) like '%@' || me.name_key || '%'
                        or (lower(c.msg) ~ '@tous\M' and public.rc__is_admin(c.device))))) $function$;

create or replace function public.rc__act_players()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare dc int := 0; dp int := 0; k text; t text; p int := 1;
begin
  begin
    if tg_op = 'INSERT' then
      perform public.rc__act(new.device, 'join', 2, 'crée son compte');
      return new;
    end if;
    dc := coalesce(new.coins, 0) - coalesce(old.coins, 0);
    dp := coalesce(new.pixels, 0) - coalesce(old.pixels, 0);
    if new.last_login is distinct from old.last_login then
      k := 'login'; t := 'connexion du jour (série ' || coalesce((to_jsonb(new) ->> 'streak'), '?') || ')';
    elsif new.wheel_at is distinct from old.wheel_at then
      k := 'wheel'; t := 'tourne la roue';
    elsif new.w_claim is distinct from old.w_claim then
      k := 'week';
      t := case when (coalesce(new.w_claim, 0) & 64) <> 0 and (coalesce(old.w_claim, 0) & 64) = 0
                then 'ouvre le coffre des défis' else 'récupère un défi de la semaine' end;
    elsif new.quiz_day is distinct from old.quiz_day or (to_jsonb(new) ->> 'quiz_gain') is distinct from (to_jsonb(old) ->> 'quiz_gain') then
      k := 'quiz'; t := 'quiz';
    elsif coalesce(new.lots, 0) > coalesce(old.lots, 0) then
      k := 'lot'; t := 'achète un lot de ' || (new.lots - coalesce(old.lots, 0)) || ' paquets';
    elsif coalesce(new.packs, 0) > coalesce(old.packs, 0) then
      k := 'open'; t := 'ouvre son paquet';
    elsif dc <> 0 or dp <> 0 then
      k := 'coins'; t := 'mouvement'; p := 0;
    else
      return new;
    end if;
    perform public.rc__act(new.device, k, p, t, null, null, null, dc, dp);
  exception when others then null;
  end;
  return new;
end $function$;

alter function public.rc__wheel_in(text) owner to rc_owner;
alter function public.rc__wheel_gold(text) owner to rc_owner;
alter function public.rc_wheel(text, text) owner to rc_owner;
alter function public.rc_notifs(text) owner to rc_owner;
alter function public.rc__act_players() owner to rc_owner;

notify pgrst, 'reload schema';
