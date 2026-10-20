create or replace function public.rc__tro_ready(p_dev text)
 returns integer
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  -- paliers de trophées atteints mais pas encore récupérés (pastille du profil)
  select coalesce(sum(greatest(0, (case when x.n >= x.t[3] then 3 when x.n >= x.t[2] then 2 when x.n >= x.t[1] then 1 else 0 end) - x.got)), 0)::int
    from public.rc__tn(p_dev) x $function$;
