create or replace function public.rc__rt_me()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if tg_table_name = 'rc_trades' then
    if tg_op = 'INSERT' then
      perform public.rc__rt_safe(public.rc__rt_topic(new.receiver), 'me', '{"k":"trade"}');
    elsif new.status is distinct from old.status then
      perform public.rc__rt_safe(public.rc__rt_topic(new.sender), 'me', '{"k":"trade"}');
      perform public.rc__rt_safe(public.rc__rt_topic(new.receiver), 'me', '{"k":"trade"}');
    end if;
  elsif tg_table_name = 'rc_market' then
    if new.buyer is not null and old.buyer is null then
      perform public.rc__rt_safe(public.rc__rt_topic(new.seller), 'me', '{"k":"sale"}');
    end if;
  elsif tg_table_name = 'rc_gifts' then
    perform public.rc__rt_safe(public.rc__rt_topic(new.receiver), 'me', '{"k":"gift"}');
  end if;
  return null;
exception when others then
  return null;
end $function$;
