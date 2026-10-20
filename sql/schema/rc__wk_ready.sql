CREATE OR REPLACE FUNCTION public.rc__wk_ready(p_dev text)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when p.w_week is distinct from public.rc__week() then 0 else
    (select count(*)::int from generate_series(1, 6) i
      where p.w_prog[i] >= (public.rc__wgoals())[i] and (p.w_claim & (1 << (i - 1))) = 0)
    + case when (p.w_claim & 63) = 63 and (p.w_claim & 64) = 0 then 1 else 0 end end
    from public.rc_players p where p.device = p_dev $function$
