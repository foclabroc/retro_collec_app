create or replace function public.rc__wbump(p_dev text, p_i integer, p_n integer)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if p_dev is null or p_n <= 0 then return; end if;
  perform public.rc__wk(p_dev);
  update public.rc_players set w_prog[p_i] = least(coalesce(w_prog[p_i], 0) + p_n, 9999) where device = p_dev;
  if p_i = 6 then perform public.rc__ev_bump(p_dev, 'epics', p_n); end if;  -- paquet avec une épique ou mieux
end $function$;
