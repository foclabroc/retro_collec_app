CREATE OR REPLACE FUNCTION public.rc_poll_vote(p_device text, p_id bigint, p_choice integer, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare p public.rc_polls;
begin
  perform public.rc__check(p_sig, p_device || '|vote|' || p_id || '|' || p_choice);
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'joueur inconnu'; end if;
  select * into p from public.rc_polls where id = p_id;
  if p.id is null or p.closed or p.ends_at <= now() then raise exception 'sondage terminé'; end if;
  if p_choice < 0 or p_choice >= jsonb_array_length(p.options) then raise exception 'réponse inconnue'; end if;
  insert into public.rc_poll_votes (poll_id, device, choice) values (p_id, p_device, p_choice) on conflict do nothing;
  return public.rc__poll_json(p);
end $function$
