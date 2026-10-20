CREATE OR REPLACE FUNCTION public.rc_week_claim(p_device text, p_i integer, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v public.rc_players; bit int; gain int := 0;
begin
  perform public.rc__check(p_sig, p_device || '|wclaim|' || p_i);
  perform public.rc__wk(p_device);
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  if p_i between 1 and 6 then
    bit := 1 << (p_i - 1);
    if (v.w_claim & bit) <> 0 then raise exception 'déjà récupéré'; end if;
    if v.w_prog[p_i] < (public.rc__wgoals())[p_i] then raise exception 'défi pas terminé'; end if;
    gain := (public.rc__wrewards())[p_i];
    update public.rc_players set w_claim = w_claim | bit, coins = coins + gain where device = p_device;
  elsif p_i = 7 then
    if (v.w_claim & 64) <> 0 then raise exception 'coffre déjà ouvert'; end if;
    if (v.w_claim & 63) <> 63 then raise exception 'coffre fermé'; end if;
    gain := public.rc__cfg('chest_coins', 500)::int;
    update public.rc_players set w_claim = w_claim | 64, coins = coins + gain, pixels = pixels + public.rc__cfg('chest_pixels', 2)::int where device = p_device;
    insert into public.rc_gifts (receiver, giver, giver_name, kind) values (p_device, null, 'Défis de la semaine', 'premium');
  else
    raise exception 'défi inconnu';
  end if;
  return public.rc__week_json(p_device) || jsonb_build_object('gain', gain);
end $function$
