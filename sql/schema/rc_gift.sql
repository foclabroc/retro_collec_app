create or replace function public.rc_gift(p_device text, p_to_pid text, p_sig text)
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v public.rc_players; dest public.rc_players; n int;
begin
  perform public.rc__check(p_sig, p_device || '|gift|' || p_to_pid);
  perform public.rc__not_new(p_device);
  perform public.rc__not_blocked(p_device);
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  n := case when v.gift_day = public.rc__today() then v.gift_n else 0 end;
  if n >= 3 then raise exception 'cadeau déjà offert'; end if;
  select * into dest from public.rc_players where pid = p_to_pid for update;
  if dest.device is null then raise exception 'joueur inconnu'; end if;
  if dest.device = p_device then raise exception 'pas à toi-même'; end if;
  if exists (select 1 from public.rc_gifts g where g.giver = p_device and g.receiver = dest.device
              and (g.created_at at time zone 'Europe/Paris')::date = public.rc__today()) then
    raise exception 'déjà offert à ce joueur';
  end if;
  if (select count(*) from public.rc_gifts g where g.receiver = dest.device and g.opened_at is null) >= 10 then
    raise exception 'trop de cadeaux';
  end if;
  insert into public.rc_gifts (receiver, giver, giver_name) values (dest.device, p_device, v.name);
  update public.rc_players set gift_day = public.rc__today(), gift_n = n + 1 where device = p_device;
  perform public.rc__ev_bump(p_device, 'gifts_sent', 1);  -- défi : paquets offerts
  perform public.rc__wbump(p_device, 'gift', 1);  -- défi de la semaine : cadeaux envoyés
  return true;
end $function$
