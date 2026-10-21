create or replace function public.rc__rt_me2()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare d text;
begin
  if tg_table_name = 'rc_feed_react' then
    select f.device into d from public.rc_feed f where f.id = new.feed_id;
    if d is not null and d <> new.device then
      perform public.rc__rt_safe(public.rc__rt_topic(d), 'me', '{"k":"react"}');
    end if;
  else -- rc_players (défis de la semaine, paquets, cartes) ou rc_trophy_n
    perform public.rc__rt_safe(public.rc__rt_topic(new.device), 'me', '{"k":"prog"}');
  end if;
  return null;
exception when others then
  return null;
end $function$;
