create or replace function public.rc__roll_finish()
 returns integer
 language plpgsql
as $function$
declare x float := random(); m float := least(coalesce(public.rc__effect('holo_x'), 1), 5);
        g float := public.rc__cfg('gold', 0.5) / 100 * m;
begin
  return case when x < g then 2 when x < g + public.rc__cfg('holo', 5) / 100 * m then 1 else 0 end;
end $function$;
