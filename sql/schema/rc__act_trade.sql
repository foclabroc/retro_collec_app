create or replace function public.rc__act_trade()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare g int; w int; s text;
begin
  begin
    g := coalesce(array_length(array_remove(string_to_array(coalesce(new.give, ''), ','), ''), 1), 0);
    w := coalesce(array_length(array_remove(string_to_array(coalesce(new.want, ''), ','), ''), 1), 0);
    s := g || ' carte' || case when g > 1 then 's' else '' end || ' contre ' || w;
    if tg_op = 'INSERT' then
      perform public.rc__act(new.sender, 'trade_offer', 2, 'propose un échange (' || s || ') à', null, null, new.receiver);
    elsif new.status is distinct from old.status then
      if new.status = 'accepted' then
        perform public.rc__act(new.sender,   'trade_ok', 2, 'échange accepté (' || s || ') avec', null, null, new.receiver);
        perform public.rc__act(new.receiver, 'trade_ok', 2, 'accepte l''échange (' || s || ') de', null, null, new.sender);
      elsif new.status = 'refused' then
        perform public.rc__act(new.receiver, 'trade_no', 2, 'refuse l''échange de', null, null, new.sender);
      elsif new.status = 'cancelled' then
        perform public.rc__act(new.sender, 'trade_no', 2, 'annule son échange avec', null, null, new.receiver);
      elsif new.status = 'failed' then
        perform public.rc__act(new.receiver, 'trade_no', 2, 'échange impossible (cartes plus là) avec', null, null, new.sender);
      end if;
    end if;
  exception when others then null;
  end;
  return new;
end $function$;
