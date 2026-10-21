create or replace function public.rc__rt_player()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare r record;
begin
  if tg_table_name = 'rc_players' then
    perform public.rc__rt_safe('rc_all', 'player', jsonb_build_object('pid', new.pid));
  elsif tg_op = 'DELETE' then
    for r in select distinct p.pid from old_rows o join public.rc_players p on p.device = o.device loop
      perform public.rc__rt_safe('rc_all', 'player', jsonb_build_object('pid', r.pid));
    end loop;
  else
    for r in select distinct p.pid from new_rows o join public.rc_players p on p.device = o.device loop
      perform public.rc__rt_safe('rc_all', 'player', jsonb_build_object('pid', r.pid));
    end loop;
  end if;
  return null;
exception when others then
  return null;
end $function$;
