CREATE OR REPLACE FUNCTION public.rc_set_house(p_device text, p_house text, p_sig text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v public.rc_players; n int;
  need int[] := array[0, 0, 0, 50, 100, 150, 200, 250, 300, 400, 500, 600, 700, 800, 1000, 1200];  -- cartes pour chaque thème d'étage
begin
  perform public.rc__check(p_sig, p_device || '|house|' || coalesce(p_house, ''));
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  if coalesce(p_house, '') !~ '^[0-9]{1,2}$' then raise exception 'maison invalide'; end if;
  n := p_house::int;
  if n > 15 then raise exception 'maison invalide'; end if;
  if v.cards < need[n + 1] then raise exception 'style verrouillé'; end if;
  update public.rc_players set house = p_house where device = p_device;
  return true;
end $function$
