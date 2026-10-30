create or replace function public.rc_craft_full(p_device text, p_card text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  r int; cost int; v public.rc_players; is_new boolean; ev jsonb := '[]'::jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|craftfull|' || p_card);
  select rarity into r from public.rc_cards where id = p_card and saga is null;
  cost := public.rc__fragment_cost(r);
  if cost is null then raise exception 'full art impossible pour cette carte'; end if;
  select * into v from public.rc_players where device = p_device for update;
  if exists (select 1 from public.rc_owned where device = p_device and card = p_card and finish = 3 and qty > 0) then
    raise exception 'full art déjà possédée';
  end if;
  if v.fragments < cost then raise exception 'pas assez de fragments'; end if;
  is_new := public.rc__is_new(p_device, p_card, 3);
  update public.rc_players set fragments = fragments - cost where device = p_device;
  perform public.rc__give(p_device, p_card, 3, 1);
  perform public.rc__rescore(p_device);
  return jsonb_build_object('n', is_new, 'fragments', (select fragments from public.rc_players where device = p_device), 'events', ev);
end $function$;
