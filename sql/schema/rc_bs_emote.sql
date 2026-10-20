CREATE OR REPLACE FUNCTION public.rc_bs_emote(p_device text, p_id bigint, p_emo text, p_sig text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare g public.rc_bs;
begin
  perform public.rc__check(p_sig, p_device || '|bsemo|' || p_id || '|' || coalesce(p_emo, ''));
  if p_emo not in ('👍', '😮', '😂', '🔥', '👏', 'Bien joué !', 'Oups 😅', 'GG 🤝', 'Pas mal !') then raise exception 'réaction inconnue'; end if;
  select * into g from public.rc_bs where id = p_id;
  if g.id is null or p_device not in (g.p1, g.p2) then raise exception 'partie inconnue'; end if;
  if g.p1 = p_device then update public.rc_bs set emo1 = p_emo, emo1_at = now() where id = p_id;
  else update public.rc_bs set emo2 = p_emo, emo2_at = now() where id = p_id; end if;
  return true;
end $function$
