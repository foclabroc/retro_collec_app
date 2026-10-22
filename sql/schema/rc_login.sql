CREATE OR REPLACE FUNCTION public.rc_login(p_name text, p_hash text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v public.rc_players;
begin
  select * into v from public.rc_players
   where name_key = public.rc__name_key(left(trim(coalesce(p_name, '')), 24)) for update;
  if v.device is null or v.pass_hash is null then raise exception 'identifiants incorrects'; end if;
  if v.pass_lock is not null and v.pass_lock > now() then raise exception 'trop de tentatives'; end if;
  if extensions.crypt(coalesce(p_hash, ''), v.pass_hash) <> v.pass_hash then
    update public.rc_players
       set pass_fail = case when pass_fail + 1 >= 5 then 0 else pass_fail + 1 end,
           pass_lock = case when pass_fail + 1 >= 5 then now() + interval '15 minutes' else pass_lock end
     where device = v.device;
    return null;  -- (pas d'exception : sinon le compteur d'erreurs serait annulé)
  end if;
  update public.rc_players set pass_fail = 0, pass_lock = null where device = v.device;
  return v.device;
end $function$
