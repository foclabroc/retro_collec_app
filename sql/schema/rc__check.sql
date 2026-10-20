CREATE OR REPLACE FUNCTION public.rc__check(p_sig text, p text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
begin
  if p_sig is distinct from public.rc__sig(p) then raise exception 'signature invalide'; end if;
end $function$
