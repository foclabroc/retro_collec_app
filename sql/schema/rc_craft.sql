CREATE OR REPLACE FUNCTION public.rc_craft(p_device text, p_card text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  r int; cost int; v public.rc_players; is_new boolean; ev jsonb := '[]'::jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|craft|' || p_card);
  select rarity into r from public.rc_cards where id = p_card;
  if r is null then raise exception 'carte inconnue'; end if;
  if exists (select 1 from public.rc_cards where id = p_card and saga is not null) then raise exception 'carte de saga : seulement dans les paquets'; end if;
  cost := public.rc__craft_cost(r);
  select * into v from public.rc_players where device = p_device for update;
  if v.coins < cost then raise exception 'pas assez de pièces'; end if;
  is_new := public.rc__is_new(p_device, p_card, 0);
  update public.rc_players set coins = coins - cost where device = p_device;
  perform public.rc__give(p_device, p_card, 0, 1);
  ev := public.rc__milestones(p_device);
  perform public.rc__rescore(p_device);
  return jsonb_build_object('n', is_new, 'coins', (select coins from public.rc_players where device = p_device), 'events', ev);
end $function$
