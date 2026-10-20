CREATE OR REPLACE FUNCTION public.rc__has(p_dev text, p text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select not exists (
    select 1 from public.rc__items(p) i
      left join public.rc_owned o on o.device = p_dev and o.card = i.card and o.finish = i.finish
     where coalesce(o.qty, 0) < i.n) $function$
