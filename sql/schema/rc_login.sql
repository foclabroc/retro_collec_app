create or replace function public.rc_login(p_name text, p_hash text)
 returns text
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v public.rc_players; k text; v_ip text := coalesce(public.rc__ip(), 'local');
begin
  k := public.rc__name_key(left(trim(coalesce(p_name, '')), 24));
  -- une IP qui a raté 30 connexions en 1 h (tous pseudos) attend ; 5 ratés sur ce pseudo en 15 min aussi
  if (select count(*) from public.rc_ip_log l where l.ip = v_ip and l.kind = 'login_fail' and l.at > now() - interval '1 hour') >= 30
     or (select count(*) from public.rc_ip_log l where l.ip = v_ip and l.kind = 'login_fail' and l.name = k and at > now() - interval '15 minutes') >= 5 then
    raise exception 'trop de tentatives';
  end if;
  select * into v from public.rc_players where name_key = k;
  if v.device is null or v.pass_hash is null or extensions.crypt(coalesce(p_hash, ''), v.pass_hash) <> v.pass_hash then
    insert into public.rc_ip_log (ip, kind, name) values (v_ip, 'login_fail', k);
    if random() < 0.02 then delete from public.rc_ip_log where at < now() - interval '2 days'; end if;  -- ménage
    if v.device is null or v.pass_hash is null then raise exception 'identifiants incorrects'; end if;
    return null;  -- (pas d'exception : sinon l'erreur notée serait annulée)
  end if;
  update public.rc_players set pass_fail = 0, pass_lock = null where device = v.device;
  return v.device;
end $function$
