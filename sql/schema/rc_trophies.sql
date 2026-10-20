create or replace function public.rc_trophies(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
begin
  perform public.rc__check(p_sig, p_device || '|trophies');
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'joueur inconnu'; end if;
  return public.rc__tro_json(p_device);
end $function$;
