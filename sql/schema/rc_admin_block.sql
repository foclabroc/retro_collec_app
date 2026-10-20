CREATE OR REPLACE FUNCTION public.rc_admin_block(p_device text, p_sig text, p_pid text, p_on boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform public.rc__admin(p_device, p_sig, 'block|' || coalesce(p_pid, '') || '|' || case when p_on then '1' else '0' end);
  update public.rc_players set blocked = p_on where pid = p_pid;
  if not found then raise exception 'joueur inconnu'; end if;
  return p_on;
end $function$
