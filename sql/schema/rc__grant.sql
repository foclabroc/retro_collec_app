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
