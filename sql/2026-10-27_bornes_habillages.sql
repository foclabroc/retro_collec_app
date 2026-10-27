-- 27/10/2026 : 7 habillages de borne de plus (n° 16 à 22) : Game Boy 1300, Bonbons 1400, Forêt enchantée 1500,
-- Pirate 1600, Égypte 1700, Cyberpunk 1800, Noël 1900 cartes. Même ordre que kFloorThemes (arcade.dart). Relançable.

create or replace function public.rc_set_house(p_device text, p_house text, p_sig text)
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v public.rc_players; n int;
  need int[] := array[0, 0, 0, 50, 100, 150, 200, 250, 300, 400, 500, 600, 700, 800, 1000, 1200,
                      1300, 1400, 1500, 1600, 1700, 1800, 1900];  -- cartes pour chaque habillage de borne
begin
  perform public.rc__check(p_sig, p_device || '|house|' || coalesce(p_house, ''));
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  if coalesce(p_house, '') !~ '^[0-9]{1,2}$' then raise exception 'maison invalide'; end if;
  n := p_house::int;
  if n >= array_length(need, 1) then raise exception 'maison invalide'; end if;
  if v.cards < need[n + 1] then raise exception 'style verrouillé'; end if;
  update public.rc_players set house = p_house where device = p_device;
  return true;
end $function$;
alter function public.rc_set_house(text, text, text) owner to rc_owner;

-- PostgREST : prendre en compte les nouvelles fonctions
notify pgrst, 'reload schema';
