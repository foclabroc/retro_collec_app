CREATE OR REPLACE FUNCTION public.rc_open_choice(p_device text, p_kind text, p_sys text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v public.rc_players;
  pd public.rc_pending;
  price int := public.rc__pack_price(p_kind);
  sp int := public.rc__special_cost(p_kind);
  packs jsonb := '[]'::jsonb; gid bigint; i int; gk text;
begin
  perform public.rc__check(p_sig, p_device || '|open6|' || coalesce(p_kind, '') || '|' || coalesce(p_sys, ''));
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;

  select * into pd from public.rc_pending where device = p_device;
  if pd.device is not null then
    return jsonb_build_object('choose', jsonb_array_length(pd.packs), 'kind', pd.kind, 'sys', pd.sys, 'resumed', true,
                              'coins', v.coins, 'lots', v.lots, 'pixels', v.pixels,
                              'gifts', (select count(*)::int from public.rc_gifts g where g.receiver = p_device and g.opened_at is null));
  end if;

  if price is null and sp is null then raise exception 'paquet inconnu'; end if;
  if p_kind in ('console', 'sconsole') and not exists (select 1 from public.rc_cards where sys = p_sys) then
    raise exception 'console inconnue';
  end if;
  if sp is not null then
    -- booster spécial : payé en pixels
    if v.pixels < sp then raise exception 'pas assez de pixels'; end if;
    update public.rc_players set pixels = pixels - sp where device = p_device;
  elsif p_kind = 'free' then
    if public.rc__free_in(p_device) > 0 then raise exception 'paquet gratuit pas encore prêt'; end if;
    update public.rc_players set last_free = public.rc__today(), last_free_at = now() where device = p_device;
  elsif p_kind = 'gift' then
    select g.id, g.kind into gid, gk from public.rc_gifts g
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

  for i in 1..6 loop
    packs := packs || jsonb_build_array(public.rc__draw_pack(case when p_kind = 'gift' then coalesce(gk, 'gift') else p_kind end, p_sys, v.pity));
  end loop;
  insert into public.rc_pending (device, kind, sys, packs) values (p_device, p_kind, p_sys, packs);

  select * into v from public.rc_players where device = p_device;
  return jsonb_build_object('choose', 6, 'kind', p_kind, 'sys', p_sys, 'resumed', false,
                            'coins', v.coins, 'lots', v.lots, 'pixels', v.pixels,
                            'gifts', (select count(*)::int from public.rc_gifts g where g.receiver = p_device and g.opened_at is null));
end $function$
