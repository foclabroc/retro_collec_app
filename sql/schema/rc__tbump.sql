create or replace function public.rc__tbump(p_dev text, p_kind text, p_n integer)
 returns void
 language sql
 security definer
 set search_path to 'public'
as $function$
  insert into public.rc_trophy_n (device, kind, n)
  select p_dev, p_kind, p_n where p_dev is not null and p_kind is not null and coalesce(p_n, 0) > 0
  on conflict (device, kind) do update set n = public.rc_trophy_n.n + excluded.n $function$;
