create or replace function public.rc__act_cab()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  begin
    if tg_table_name = 'rc_cab_paid' then
      perform public.rc__act(new.device, 'reward', 2, 'record de borne battu');
    elsif tg_table_name = 'rc_cab_runs' and new.comm then
      perform public.rc__act(new.owner, 'reward', 2, 'commission de borne');
    end if;
  exception when others then null;
  end;
  return new;
end $function$;
