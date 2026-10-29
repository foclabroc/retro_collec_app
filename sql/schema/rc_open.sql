CREATE OR REPLACE FUNCTION public.rc_open(p_device text, p_kind text, p_sys text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v public.rc_players;
  price int := public.rc__pack_price(p_kind);
  scope text := case when p_kind = 'console' then p_sys else null end;
  n int := 5; x float;
  i int; r int; f int; c text; sg text; is_new boolean; got_epic boolean := false; nnew int := 0;
  res jsonb := '[]'::jsonb; ev jsonb := '[]'::jsonb; gid bigint;
begin
  perform public.rc__check(p_sig, p_device || '|open|' || coalesce(p_kind, '') || '|' || coalesce(p_sys, ''));
  if price is null then raise exception 'paquet inconnu'; end if;
  if p_kind = 'console' and not exists (select 1 from public.rc_cards where sys = p_sys) then
    raise exception 'console inconnue';
  end if;
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  if p_kind = 'free' then
    if public.rc__free_in(p_device) > 0 then raise exception 'paquet gratuit pas encore prêt'; end if;
    update public.rc_players set last_free = public.rc__today(), last_free_at = now() where device = p_device;
  elsif p_kind = 'gift' then
    -- un cadeau précis (p_sys = son numéro) ou le plus ancien
    select g.id into gid from public.rc_gifts g
     where g.receiver = p_device and g.opened_at is null
       and (coalesce(p_sys, '') = '' or g.id::text = p_sys)
     order by g.id limit 1 for update;
    if gid is null then raise exception 'aucun cadeau'; end if;
    update public.rc_gifts set opened_at = now() where id = gid;
  elsif p_kind = 'lot' then
    if v.lots < 1 then raise exception 'aucun paquet du lot'; end if;
    update public.rc_players set lots = lots - 1 where device = p_device;
  elsif v.coins < price then
    raise exception 'pas assez de pièces';
  else
    update public.rc_players set coins = coins - price where device = p_device;
  end if;

  if p_kind = 'mystery' then
    x := random();
    n := case when x < 0.5 then 3 when x < 0.9 then 5 else 8 end;
  end if;

  for i in 1..n loop
    if i = n and p_kind = 'premium' then r := public.rc__roll(2); else r := public.rc__roll(0); end if;
    if i = n and not got_epic and v.pity >= 29 then r := public.rc__roll(3); end if;
    select id into c from public.rc_cards
     where rarity = r and saga is null and (scope is null or sys = scope) order by random() limit 1;
    if c is null then
      select id, rarity into c, r from public.rc_cards
       where rarity <= r and saga is null and (scope is null or sys = scope) order by rarity desc, random() limit 1;
    end if;
    if c is null then raise exception 'catalogue vide'; end if;
    if r >= 3 then got_epic := true; end if;
    f := public.rc__roll_finish(r);
    sg := public.rc__saga_roll();  -- carte de saga
    if sg is not null then c := sg; r := 3; f := 0; got_epic := true; end if;
    is_new := public.rc__is_new(p_device, c, f);
    if is_new then nnew := nnew + 1; end if;
    perform public.rc__give(p_device, c, f, 1);
    res := res || jsonb_build_object('c', c, 'f', f, 'r', r, 'n', is_new);
    c := null;
  end loop;

  update public.rc_players set packs = packs + 1, pity = case when got_epic then 0 else pity + 1 end,
         pixels = pixels + 1
   where device = p_device;
  ev := ev || public.rc__bump(p_device, 'open', 1);
  if got_epic then  -- défi : carte épique ou mieux
    perform public.rc__wbump(p_device, 'epic', 1);
    perform public.rc__ev_bump(p_device, 'epics', 1);
  end if;
  perform public.rc__wbump(p_device, 'new', nnew);  -- défi : nouvelles cartes
  if p_kind in ('free', 'premium') then perform public.rc__wbump(p_device, p_kind, 1); end if;  -- défis : paquet gratuit, premium
  ev := ev || public.rc__milestones(p_device);
  perform public.rc__rescore(p_device);
  select * into v from public.rc_players where device = p_device;
  return jsonb_build_object('cards', res, 'coins', v.coins, 'pity', v.pity, 'score', v.score, 'events', ev,
                            'lots', v.lots, 'pixels', v.pixels,
                            'gifts', (select count(*)::int from public.rc_gifts g where g.receiver = p_device and g.opened_at is null));
end $function$
