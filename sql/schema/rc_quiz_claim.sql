create or replace function public.rc_quiz_claim(p_device text, p_correct integer, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v public.rc_players;
  already int;
  gain int;
begin
  perform public.rc__check(p_sig, p_device || '|quiz|' || p_correct);
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  already := case when v.quiz_day = public.rc__today() then v.quiz_gain else 0 end;
  gain := least(greatest(coalesce(p_correct, 0), 0), 10) * 5;
  gain := least(gain, greatest(0, 100 - already));
  update public.rc_players
     set coins = coins + gain, quiz_day = public.rc__today(), quiz_gain = already + gain, updated_at = now()
   where device = p_device
  returning coins into v.coins;
  perform public.rc__ev_bump(p_device, 'quiz', gain / 5);  -- défi : bonnes réponses (dans la limite du jour)
  perform public.rc__wbump(p_device, 'quiz', gain / 5);
  return jsonb_build_object('gain', gain, 'left', greatest(0, 100 - already - gain), 'coins', v.coins);
end $function$;
