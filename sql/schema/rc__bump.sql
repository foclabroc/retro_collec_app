create or replace function public.rc__bump(p_dev text, p_kind text, p_n integer)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if p_kind in ('open', 'trade') then perform public.rc__wbump(p_dev, p_kind, p_n); end if;  -- défis de la semaine
  if p_kind = 'open' then
    perform public.rc__ref_check(p_dev);  -- parrainage
    insert into public.rc_daily (day, packs) values (public.rc__today(), p_n)
    on conflict (day) do update set packs = public.rc_daily.packs + p_n;  -- stats admin
  elsif p_kind = 'recycle' then
    perform public.rc__ev_bump(p_dev, 'recycle', p_n);
  end if;
  return '[]'::jsonb;
end $function$;
