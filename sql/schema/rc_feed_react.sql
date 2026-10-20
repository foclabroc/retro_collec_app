CREATE OR REPLACE FUNCTION public.rc_feed_react(p_device text, p_id bigint, p_emo integer, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare cur int;
begin
  perform public.rc__check(p_sig, p_device || '|react|' || p_id || '|' || p_emo);
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'joueur inconnu'; end if;
  if not exists (select 1 from public.rc_feed where id = p_id) then raise exception 'nouvelle introuvable'; end if;
  select emo into cur from public.rc_feed_react where feed_id = p_id and device = p_device;
  if p_emo is null or p_emo not between 0 and 2 or cur = p_emo then
    delete from public.rc_feed_react where feed_id = p_id and device = p_device;
  else
    insert into public.rc_feed_react (feed_id, device, emo) values (p_id, p_device, p_emo)
    on conflict (feed_id, device) do update set emo = excluded.emo, at = now();
  end if;
  return jsonb_build_object(
    'rx', (select jsonb_build_array(count(*) filter (where emo = 0), count(*) filter (where emo = 1), count(*) filter (where emo = 2))
             from public.rc_feed_react where feed_id = p_id),
    'me', coalesce((select emo from public.rc_feed_react where feed_id = p_id and device = p_device), -1));
end $function$
