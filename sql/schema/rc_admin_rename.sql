create or replace function public.rc_admin_rename(p_device text, p_sig text, p_pid text, p_name text)
 returns text
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v_name text := left(trim(coalesce(p_name, '')), 24);
  v_key  text := public.rc__name_key(left(trim(coalesce(p_name, '')), 24));
begin
  perform public.rc__admin(p_device, p_sig, 'rename|' || coalesce(p_pid, '') || '|' || coalesce(p_name, ''));
  if v_key = '' then raise exception 'pseudo vide'; end if;
  if exists (select 1 from public.rc_players where name_key = v_key and pid <> p_pid) then return 'taken'; end if;
  update public.rc_players set name = v_name, name_key = v_key, updated_at = now() where pid = p_pid;
  if not found then raise exception 'joueur inconnu'; end if;
  return 'ok';
end $function$;
