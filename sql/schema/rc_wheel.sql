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
  r int; f int; c text; is_new boolean; card jsonb := null; ev jsonb := '[]'::jsonb;
  minr int;
begin
  perform public.rc__check(p_sig, p_device || '|wheel');
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  if v.wheel_day = public.rc__today() then raise exception 'déjà tourné aujourd''hui'; end if;
  gold := v.streak > 0 and v.streak % 7 = 0 and v.last_login = public.rc__today();
  if gold then
    w := array[20, 16, 14, 18, 10, 13, 6, 3];
    prize := array[40, 100, 0, 60, 200, 80, 0, 1000];
  else
    w := array[22, 16, 12, 20, 8, 15, 4, 3];
    prize := array[20, 50, 0, 30, 100, 40, 0, 300];
  end if;
  for k in 1..8 loop
    acc := acc + w[k];
    if x < acc then seg := k - 1; exit; end if;
  end loop;
  update public.rc_players set wheel_day = public.rc__today(), coins = coins + prize[seg + 1] where device = p_device;
  -- cases carte (2 = carte, 6 = rare) et, en or, le JACKPOT (7) avec une légendaire
  if seg in (2, 6) or (gold and seg = 7) then
    minr := case when gold and seg = 7 then 4
                 when gold and seg = 6 then 3
                 when gold or seg = 6 then 2
                 else 0 end;
    r := case when minr = 4 then 4 else public.rc__roll(minr) end;
    select id, rarity into c, r from public.rc_cards where rarity <= r and saga is null order by rarity desc, random() limit 1;
    f := public.rc__roll_finish(r);
    is_new := not exists (select 1 from public.rc_owned o where o.device = p_device and o.card = c);
    perform public.rc__give(p_device, c, f, 1);
    card := jsonb_build_object('c', c, 'f', f, 'r', r, 'n', is_new);
    ev := ev || public.rc__milestones(p_device);
    perform public.rc__rescore(p_device);
  end if;
  return jsonb_build_object('seg', seg, 'gain', prize[seg + 1], 'card', card, 'events', ev, 'gold', gold,
                            'coins', (select p.coins from public.rc_players p where p.device = p_device));
end $function$
