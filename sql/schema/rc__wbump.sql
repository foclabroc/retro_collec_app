create or replace function public.rc__wbump(p_dev text, p_kind text, p_n integer)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare k text[];
begin
  if p_dev is null or coalesce(p_n, 0) <= 0 then return; end if;
  -- trophées : cadeaux, ventes, duels gagnés, Gamedle (comptés même hors des défis de la semaine)
  perform public.rc__tbump(p_dev, case p_kind when 'gift' then 'gifts' when 'sale' then 'sales' when 'win' then 'wins' when 'gamedle' then 'gamedle'
    when 'quiz' then 'quiz' when 'play' then 'played' when 'premium' then 'premium' end, p_n);
  k := public.rc__wkinds();
  if not (p_kind = any(k)) then return; end if;  -- pas au programme cette semaine
  perform public.rc__wk(p_dev);
  update public.rc_players set w_prog[array_position(k, p_kind)] =
         least(coalesce(w_prog[array_position(k, p_kind)], 0) + p_n, 9999)
   where device = p_dev;
end $function$;