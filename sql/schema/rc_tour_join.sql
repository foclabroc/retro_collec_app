create or replace function public.rc_tour_join(p_device text, p_id bigint, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare t public.rc_tour; c bigint;
begin
  perform public.rc__check(p_sig, p_device || '|tjoin|' || p_id);
  select * into t from public.rc_tour where id = p_id for update;
  if t.id is null then raise exception 'tournoi inconnu'; end if;
  if t.status <> 'open' or now() >= t.start_at then raise exception 'inscriptions fermées'; end if;
  if exists (select 1 from public.rc_tour_players where tid = p_id and device = p_device) then raise exception 'déjà inscrit'; end if;
  if (select count(*) from public.rc_tour_players where tid = p_id) >= t.size then raise exception 'tournoi complet'; end if;
  select coins into c from public.rc_players where device = p_device for update;
  if c is null then raise exception 'joueur inconnu'; end if;
  if c < t.fee then raise exception 'pas assez de pièces'; end if;
  if t.fee > 0 then update public.rc_players set coins = coins - t.fee where device = p_device; end if;
  insert into public.rc_tour_players (tid, device, paid) values (p_id, p_device, t.fee);
  return public.rc__tour_json(p_id, p_device, true) || jsonb_build_object('coins', (select coins from public.rc_players where device = p_device));
end $function$;
