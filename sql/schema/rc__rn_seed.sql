create or replace function public.rc__rn_seed(p_day date)
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare s int;
begin
  insert into public.rc_rn_day (day, seed) values (p_day, floor(random() * 2147483646)::int + 1)
  on conflict (day) do nothing;
  select seed into s from public.rc_rn_day where day = p_day;
  return s;
end $function$;
