create or replace function public.rc__trade_return(p_id bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare t public.rc_trades; it record;
begin
  select * into t from public.rc_trades where id = p_id;
  if t.id is null or not coalesce(t.held, false) then return; end if;
  for it in select * from public.rc__items(t.give) loop
    perform public.rc__give(t.sender, it.card, it.finish, it.n);
  end loop;
  update public.rc_trades set held = false where id = t.id;
  perform public.rc__rescore(t.sender);
end $function$
