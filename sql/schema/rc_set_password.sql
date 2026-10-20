CREATE OR REPLACE FUNCTION public.rc_set_password(p_device text, p_hash text, p_sig text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform public.rc__check(p_sig, p_device || '|password|' || coalesce(p_hash, ''));
  if coalesce(length(p_hash), 0) <> 64 then raise exception 'mot de passe invalide'; end if;
  update public.rc_players set pass_hash = extensions.crypt(p_hash, extensions.gen_salt('bf', 8)),
         pass_fail = 0, pass_lock = null, updated_at = now()
   where device = p_device;
  return found;
end $function$
