CREATE OR REPLACE FUNCTION public.rc_gamedle_guess(p_device text, p_card text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  ans text := public.rc__gamedle_card(public.rc__today());
  g public.rc_gamedle;
  ok boolean;
  tries int;
  reward int := 0;
begin
  perform public.rc__check(p_sig, p_device || '|gamedle|' || p_card);
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'invalide'; end if;
  if not exists (select 1 from public.rc_cards where id = p_card) then raise exception 'carte inconnue'; end if;
  insert into public.rc_gamedle (device, day) values (p_device, public.rc__today()) on conflict do nothing;
  select * into g from public.rc_gamedle where device = p_device and day = public.rc__today() for update;
  if g.won or coalesce(array_length(g.guesses, 1), 0) >= 6 then raise exception 'gamedle terminé'; end if;
  if p_card = any(g.guesses) then raise exception 'déjà proposé'; end if;
  ok := (select regexp_replace(lower(a.title), '[^a-z0-9]', '', 'g') = regexp_replace(lower(b.title), '[^a-z0-9]', '', 'g')
           from public.rc_cards a, public.rc_cards b where a.id = ans and b.id = p_card);
  update public.rc_gamedle set guesses = guesses || p_card, won = ok
   where device = p_device and day = public.rc__today();
  tries := coalesce(array_length(g.guesses, 1), 0) + 1;
  if ok then
    reward := (array[100, 80, 60, 45, 30, 20])[tries];
    update public.rc_players set coins = coins + reward where device = p_device;
    perform public.rc__feed_add(p_device, 'gamedle', ans, null, null, tries);
    perform public.rc__wbump(p_device, 'gamedle', 1);
  end if;
  return public.rc__gamedle_json(p_device) || jsonb_build_object('ok', ok, 'reward', reward, 'answer', case when ok or tries >= 6 then ans end);
end $function$
