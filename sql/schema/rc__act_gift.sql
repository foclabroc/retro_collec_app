create or replace function public.rc__act_gift()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  begin
    if new.giver is not null and exists (select 1 from public.rc_players where device = new.giver) then
      perform public.rc__act(new.giver, 'gift', 2, 'offre un paquet cadeau à', null, null, new.receiver);
    else
      perform public.rc__act(new.receiver, 'gift_in', 2,
        'reçoit un cadeau' || coalesce(' de « ' || nullif(new.giver_name, '') || ' »', ''));
    end if;
  exception when others then null;
  end;
  return new;
end $function$;
