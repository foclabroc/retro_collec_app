CREATE OR REPLACE FUNCTION public.rc_fuse(p_device text, p_card text, p_finish integer, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare need int; ev jsonb := '[]'::jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|fuse|' || p_card || '|' || p_finish);
  if p_finish not in (0, 1) then raise exception 'fusion impossible'; end if;
  if not exists (select 1 from public.rc_cards where id = p_card) then raise exception 'carte inconnue'; end if;
  if exists (select 1 from public.rc_cards where id = p_card and saga is not null) then raise exception 'fusion impossible'; end if;
  perform 1 from public.rc_players where device = p_device for update;
  need := case p_finish when 0 then 5 else 3 end;
  if not public.rc__take(p_device, p_card, p_finish, need) then raise exception 'pas assez d''exemplaires'; end if;
  perform public.rc__give(p_device, p_card, p_finish + 1, 1);
  perform public.rc__tbump(p_device, 'fuse', 1);  -- trophée : fusions
  ev := public.rc__milestones(p_device);
  perform public.rc__rescore(p_device);
  return jsonb_build_object('card', p_card, 'f', p_finish + 1, 'events', ev,
                            'score', (select score from public.rc_players where device = p_device));
end $function$
