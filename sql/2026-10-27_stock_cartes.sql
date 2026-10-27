-- ═══════════════════════════════════════════════════════════════════════════
-- Pixel Trade : les cartes offertes en récompense (événements, paliers, courrier, défis, tournois,
-- cadeau de version) ne tombent plus directement dans la collection : elles vont dans un stock
-- « Cartes à ranger » où on les voit, puis on les range (une par une ou toutes).
--  • rc_card_stock : le stock (taken_at renseigné = rangée).
--  • rc__grant : les 'cards' d'une récompense vont dans le stock (plus de rc__give direct).
--  • rc_notifs : + 'cards' (nombre de cartes à ranger).
--  • rc_stock_list(device, sig '<device>|stock') : [{id, c, f, r, from, at, n}].
--  • rc_stock_take(device, id|null, sig '<device>|stocktake|<id ou 0>') : range (rc__give, défi « nouvelles »,
--    palier de collection, score) et renvoie {cards, events, coins, pixels, score, left}.
--  • déclencheur rc_card_stock_rt : événement temps réel « me/gift » (le stock s'affiche tout de suite).
-- Les cartes déjà reçues avant ce fichier sont dans la collection, rien ne bouge.
-- Lancement : psql -U postgres -d postgres -f 2026-10-27_stock_cartes.sql
-- ═══════════════════════════════════════════════════════════════════════════
begin;

create table if not exists public.rc_card_stock (
  id bigserial primary key,
  device text not null,
  card text not null,
  finish int not null default 0,
  giver_name text,
  created_at timestamptz not null default now(),
  taken_at timestamptz
);
create index if not exists rc_card_stock_dev on public.rc_card_stock (device) where taken_at is null;
alter table public.rc_card_stock enable row level security;
alter table public.rc_card_stock owner to rc_owner;
alter sequence public.rc_card_stock_id_seq owner to rc_owner;
revoke all on table public.rc_card_stock from public, anon, authenticated;
revoke all on sequence public.rc_card_stock_id_seq from public, anon, authenticated;

create or replace function public.rc__grant(p_dev text, p_reward jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  r jsonb := public.rc__rw_clean(p_reward);
  k text; v text; n int; i int; c text; cards jsonb := '[]'::jsonb;
  lbl text;
begin
  -- rc.gift_from (réglage de la transaction) : nom du donneur des paquets offerts, « Pixel Trade » par défaut (tournois : « Tournoi X »)
  if r = '{}'::jsonb then return jsonb_build_object('cards', cards); end if;
  update public.rc_players
     set coins = coins + coalesce((r->>'coins')::int, 0),
         pixels = pixels + coalesce((r->>'pixels')::int, 0),
         lots = lots + 5 * coalesce((r->>'lots')::int, 0)
   where device = p_dev;
  for k, v in select key, value from jsonb_each_text(coalesce(r->'packs', '{}'::jsonb)) loop
    lbl := case k when 'mixte' then 'mixte' when 'premium' then 'premium' when 'mystery' then 'mystère'
                  when 'star' then 'Étoile' when 'gold' then 'Rétro d''or' end;
    for i in 1 .. v::int loop
      insert into public.rc_gifts (receiver, giver, giver_name, kind)
      values (p_dev, null, coalesce(nullif(current_setting('rc.gift_from', true), ''), 'Pixel Trade') || ' · ' || lbl, k);
    end loop;
  end loop;
  for k, v in select key, value from jsonb_each_text(coalesce(r->'cards', '{}'::jsonb)) loop
    for i in 1 .. v::int loop
      select id into c from public.rc_cards where rarity = k::int and saga is null order by random() limit 1;
      if c is not null then
        -- la carte attend dans le stock « Cartes à ranger » : le joueur la voit avant qu'elle entre dans sa collection
        insert into public.rc_card_stock (device, card, finish, giver_name)
        values (p_dev, c, 0, coalesce(nullif(current_setting('rc.gift_from', true), ''), 'Pixel Trade'));
        cards := cards || jsonb_build_object('c', c, 'r', k::int, 'f', 0, 'stock', true);
      end if;
    end loop;
  end loop;
  return r || jsonb_build_object('cards', cards);
end $function$;

create or replace function public.rc__rt_stock()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  perform public.rc__rt_safe(public.rc__rt_topic(new.device), 'me', '{"k":"gift"}');
  return null;
exception when others then
  return null;
end $function$;

create or replace function public.rc_stock_list(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'extensions'
as $function$
begin
  perform public.rc__check(p_sig, p_device || '|stock');
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', s.id, 'c', s.card, 'f', s.finish, 'r', c.rarity, 'from', s.giver_name, 'at', s.created_at,
                                        'n', not exists (select 1 from public.rc_owned o where o.device = p_device and o.card = s.card))
                     order by s.id)
      from public.rc_card_stock s join public.rc_cards c on c.id = s.card
     where s.device = p_device and s.taken_at is null), '[]'::jsonb);
end $function$;

create or replace function public.rc_stock_take(p_device text, p_id bigint, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v public.rc_players; s public.rc_card_stock; r int; sy text; is_new boolean; nnew int := 0;
  res jsonb := '[]'::jsonb; ev jsonb := '[]'::jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|stocktake|' || coalesce(p_id, 0));
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  for s in select * from public.rc_card_stock
            where device = p_device and taken_at is null and (p_id is null or id = p_id)
            order by id for update loop
    select rarity, sys into r, sy from public.rc_cards where id = s.card;
    is_new := not exists (select 1 from public.rc_owned where device = p_device and card = s.card);
    if is_new then nnew := nnew + 1; end if;
    perform public.rc__give(p_device, s.card, s.finish, 1);
    update public.rc_card_stock set taken_at = now() where id = s.id;
    res := res || jsonb_build_object('c', s.card, 'f', s.finish, 'r', r, 'n', is_new);
    perform public.rc__ev_bump(p_device, 'console', 1, sy);  -- défi : cartes d'une console
  end loop;
  if jsonb_array_length(res) = 0 then raise exception 'rien à ranger'; end if;
  perform public.rc__wbump(p_device, 'new', nnew);  -- défi : nouvelles cartes
  ev := ev || public.rc__milestones(p_device);
  perform public.rc__rescore(p_device);
  select * into v from public.rc_players where device = p_device;
  return jsonb_build_object('cards', res, 'events', ev, 'coins', v.coins, 'pixels', v.pixels, 'score', v.score,
                            'left', (select count(*)::int from public.rc_card_stock x where x.device = p_device and x.taken_at is null));
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
    'wheel', (select wheel_day is distinct from public.rc__today() from public.rc_players where device = p_device),
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

drop trigger if exists rc_card_stock_rt on public.rc_card_stock;
create trigger rc_card_stock_rt after insert on public.rc_card_stock
  for each row execute function public.rc__rt_stock();

alter function public.rc__rt_stock() owner to rc_owner;
alter function public.rc_stock_list(text, text) owner to rc_owner;
alter function public.rc_stock_take(text, bigint, text) owner to rc_owner;

commit;
