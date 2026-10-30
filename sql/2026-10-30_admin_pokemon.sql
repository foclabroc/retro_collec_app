-- Admin : Pokémon dans les cadeaux possibles (récompense cards.pk = 1 carte Pokémon au hasard)
-- et dans les réglages en direct (pk = chance par carte de paquet, en %, défaut 0,15).
-- Relançable.

create or replace function public.rc__rw_clean(r jsonb)
 returns jsonb
 language plpgsql
 immutable
as $function$
declare out jsonb := '{}'::jsonb; m jsonb := '{}'::jsonb; k text; v text; n int;
begin
  if r is null or jsonb_typeof(r) <> 'object' then return '{}'::jsonb; end if;
  n := least(greatest(coalesce((r->>'coins')::int, 0), 0), 100000); if n > 0 then out := out || jsonb_build_object('coins', n); end if;
  n := least(greatest(coalesce((r->>'pixels')::int, 0), 0), 1000);  if n > 0 then out := out || jsonb_build_object('pixels', n); end if;
  n := least(greatest(coalesce((r->>'lots')::int, 0), 0), 5);       if n > 0 then out := out || jsonb_build_object('lots', n); end if;
  for k, v in select key, value from jsonb_each_text(coalesce(r->'packs', '{}'::jsonb)) loop
    n := least(greatest(coalesce(v::int, 0), 0), 10);
    if k in ('mixte', 'premium', 'mystery', 'star', 'gold') and n > 0 then m := m || jsonb_build_object(k, n); end if;
  end loop;
  if m <> '{}'::jsonb then out := out || jsonb_build_object('packs', m); end if;
  m := '{}'::jsonb;
  for k, v in select key, value from jsonb_each_text(coalesce(r->'cards', '{}'::jsonb)) loop
    n := least(greatest(coalesce(v::int, 0), 0), 10);
    if k in ('0', '1', '2', '3', '4', 'pk') and n > 0 then m := m || jsonb_build_object(k, n); end if;
  end loop;
  if m <> '{}'::jsonb then out := out || jsonb_build_object('cards', m); end if;
  return out;
end $function$;

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
      -- 'pk' = une carte Pokémon au hasard
      if k = 'pk' then
        select id into c from public.rc_cards where saga = 'pk' order by random() limit 1;
      else
        select id into c from public.rc_cards where rarity = k::int and saga is null order by random() limit 1;
      end if;
      if c is not null then
        -- la carte attend dans le stock « Cartes à ranger » : le joueur la voit avant qu'elle entre dans sa collection
        insert into public.rc_card_stock (device, card, finish, giver_name)
        values (p_dev, c, 0, coalesce(nullif(current_setting('rc.gift_from', true), ''), 'Pixel Trade'));
        cards := cards || jsonb_build_object('c', c, 'r', (select rarity from public.rc_cards where id = c), 'f', 0, 'stock', true);
      end if;
    end loop;
  end loop;
  return r || jsonb_build_object('cards', cards);
end $function$;

CREATE OR REPLACE FUNCTION public.rc_admin_set_live(p_device text, p_sig text, p_values text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare j jsonb; k text; n numeric;
begin
  perform public.rc__admin(p_device, p_sig, 'live|' || coalesce(p_values, ''));
  j := p_values::jsonb;
  for k in select jsonb_object_keys(j) loop
    n := (j->>k)::numeric;
    if k in ('saga', 'holo', 'gold', 'fullart', 'pk') then
      if n < 0 or n > 50 then raise exception 'chance entre 0 et 50 %%'; end if;
    elsif k in ('mixte', 'console', 'premium', 'mystery', 'chest_coins', 'chest_pixels') then
      if n < 0 or n > 10000 or n <> round(n) then raise exception 'nombre entier entre 0 et 10000'; end if;
    else
      raise exception 'réglage inconnu : %', k;
    end if;
  end loop;
  update public.rc_config set value = value || j where key = 'live';
  return public.rc__live();
end $function$;

create or replace function public.rc__live()
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object(
    'saga', public.rc__cfg('saga', 3.2), 'holo', public.rc__cfg('holo', 5), 'gold', public.rc__cfg('gold', 0.5),
    'fullart', public.rc__cfg('fullart', 0.2), 'pk', public.rc__cfg('pk', 0.15),
    'mixte', public.rc__cfg('mixte', 100), 'console', public.rc__cfg('console', 150),
    'premium', public.rc__cfg('premium', 400), 'mystery', public.rc__cfg('mystery', 120),
    'chest_coins', public.rc__cfg('chest_coins', 500), 'chest_pixels', public.rc__cfg('chest_pixels', 2),
    -- effets en cours (affichage) : réductions par paquet, multiplicateurs
    'promo', jsonb_build_object('mixte', public.rc__promo('mixte'), 'console', public.rc__promo('console'),
                                'premium', public.rc__promo('premium'), 'mystery', public.rc__promo('mystery'), 'lot', public.rc__promo('lot')),
    'holo_x', coalesce(public.rc__effect('holo_x'), 1), 'rare_x', coalesce(public.rc__effect('rare_x'), 1),
    'recycle_x', coalesce(public.rc__effect('recycle_x'), 1), 'duel_x', coalesce(public.rc__effect('duel_x'), 1)) $function$;

alter function public.rc__rw_clean(jsonb) owner to rc_owner;
alter function public.rc__grant(text, jsonb) owner to rc_owner;
alter function public.rc_admin_set_live(text, text, text) owner to rc_owner;
alter function public.rc__live() owner to rc_owner;

notify pgrst, 'reload schema';
