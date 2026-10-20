CREATE OR REPLACE FUNCTION public.rc__not_blocked(p_dev text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if exists (select 1 from public.rc_players where device = p_dev and blocked) then
    raise exception 'compte bloqué : échanges, ventes, achats et cadeaux désactivés';
  end if;
end $function$
