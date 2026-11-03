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
    w := public.rc__wheel_w('wg', array[19, 15, 14, 17, 10, 12, 6, 3, 4]);
    prize := array[80, 200, 0, 120, 400, 160, 0, 2000, 0];
  else
    w := public.rc__wheel_w('w', array[22, 15, 12, 19, 8, 14, 4, 3, 3]);
    prize := array[40, 100, 0, 60, 200, 80, 0, 600, 0];
  end if;
  for k in 1..9 loop
    acc := acc + w[k];
    if x < acc then seg := k - 1; exit; end if;
  end loop;
  perform public.rc__tbump(p_device, 'wheel', 1);  -- trophée : tours de roue
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
