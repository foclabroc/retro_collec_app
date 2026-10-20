CREATE OR REPLACE FUNCTION public.rc__duel_coins_trg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if (select coins from public.rc_players where device = new.p2) < new.stake then
    raise exception 'adversaire sans pièces';
  end if;
  return new;
end $function$
