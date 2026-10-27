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
