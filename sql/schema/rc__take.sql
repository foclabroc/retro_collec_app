CREATE OR REPLACE FUNCTION public.rc__take(p_dev text, p_card text, p_f integer, p_n integer)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
declare v int;
begin
  select qty into v from public.rc_owned where device = p_dev and card = p_card and finish = p_f for update;
  if v is null or v < p_n then return false; end if;
  if v = p_n then
    delete from public.rc_owned where device = p_dev and card = p_card and finish = p_f;
  else
    update public.rc_owned set qty = qty - p_n where device = p_dev and card = p_card and finish = p_f;
  end if;
  return true;
end $function$
