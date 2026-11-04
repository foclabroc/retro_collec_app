-- Booster Dessins animés (kind 'cartoon') : 70 pixels au lieu de 100   (relançable)
CREATE OR REPLACE FUNCTION public.rc__special_cost(p_kind text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case p_kind when 'star' then 15 when 'sconsole' then 25 when 'gold' then 40 when 'pokemon' then 100 when 'cartoon' then 70 end $function$;
alter function public.rc__special_cost(text) owner to rc_owner;
notify pgrst, 'reload schema';
select public.rc__special_cost('cartoon') as prix_dessins_animes;  -- 70
