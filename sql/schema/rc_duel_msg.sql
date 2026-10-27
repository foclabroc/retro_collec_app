CREATE OR REPLACE FUNCTION public.rc_duel_msg(p_device text, p_game text, p_id bigint, p_msg text, p_sig text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare n int;
begin
  perform public.rc__check(p_sig, p_device || '|dmsg|' || coalesce(p_game, '') || '|' || p_id || '|' || coalesce(p_msg, ''));
  if p_game = 'c4' then
    update public.rc_c4 set msg = public.rc__duel_text(p_msg) where id = p_id and p1 = p_device and status = 'invite';
  elsif p_game = 'bs' then
    update public.rc_bs set msg = public.rc__duel_text(p_msg) where id = p_id and p1 = p_device and status = 'invite';
  elsif p_game = 'rj' then
    update public.rc_rj set msg = public.rc__duel_text(p_msg) where id = p_id and p1 = p_device and status = 'invite';
  else
    raise exception 'jeu inconnu';
  end if;
  get diagnostics n = row_count;
  return n > 0;
end $function$;
