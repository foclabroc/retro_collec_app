CREATE OR REPLACE FUNCTION public.rc__ref_check(p_dev text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v public.rc_players; s public.rc_players;
begin
  select * into v from public.rc_players where device = p_dev for update;
  if v.referrer is null or v.ref_paid or v.packs < 5 or v.days < 2 then return; end if;
  select * into s from public.rc_players where device = v.referrer;
  update public.rc_players set ref_paid = true where device = p_dev;
  if s.device is null then return; end if;
  insert into public.rc_gifts (receiver, giver, giver_name, kind) values (p_dev, null, 'Parrainage · ' || s.name, 'premium');
  insert into public.rc_gifts (receiver, giver, giver_name, kind) values (s.device, null, 'Parrainage · ' || v.name, 'premium');
end $function$
