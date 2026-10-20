create or replace function public.rc__roll(p_min integer)
 returns integer
 language plpgsql
as $function$
declare x float := random() * 100; m float := least(coalesce(public.rc__effect('rare_x'), 1), 5);
begin
  if p_min >= 3 then return case when x < 15 then 4 else 3 end; end if;
  if p_min = 2 then return case when x < 5 then 4 when x < 25 then 3 else 2 end; end if;
  -- normal : légendaire 0,8 %, épique 3,2 %, rare 10 %, peu commune 26 %, commune 60 % (épique et légendaire × effet « rare_x »)
  return case when x < 0.8 * m then 4 when x < 4 * m then 3 when x < 4 * m + 10 then 2 when x < 4 * m + 36 then 1 else 0 end;
end $function$;
