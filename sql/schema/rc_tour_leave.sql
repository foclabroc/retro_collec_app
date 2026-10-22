create or replace function public.rc_tour_leave(p_device text, p_id bigint, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare t public.rc_tour; v int;
begin
  perform public.rc__check(p_sig, p_device || '|tleave|' || p_id);
  select * into t from public.rc_tour where id = p_id for update;
  if t.id is null then raise exception 'tournoi inconnu'; end if;
  if t.status <> 'open' or now() >= t.start_at then raise exception 'le tournoi a commencé'; end if;
  delete from public.rc_tour_players where tid = p_id and device = p_device returning paid into v;
  if v is null then raise exception 'pas inscrit'; end if;
  if v > 0 then update public.rc_players set coins = coins + v where device = p_device; end if;
  return public.rc__tour_json(p_id, p_device, true) || jsonb_build_object('coins', (select coins from public.rc_players where device = p_device));
end $function$;
