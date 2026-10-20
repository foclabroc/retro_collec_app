CREATE OR REPLACE FUNCTION public.rc__roll_finish(p_r integer)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
begin
  if p_r >= 3 and random() < public.rc__cfg('fullart', 0.2) / 100 then return 3; end if;
  return public.rc__roll_finish();
end $function$
