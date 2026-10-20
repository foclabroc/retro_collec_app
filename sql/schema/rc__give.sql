create or replace function public.rc__give(p_dev text, p_card text, p_f integer, p_n integer)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  insert into public.rc_owned (device, card, finish, qty) values (p_dev, p_card, p_f, p_n)
  on conflict (device, card, finish) do update set qty = public.rc_owned.qty + excluded.qty;
  -- trophées : épiques, légendaires, brillantes, dorées et Full art obtenues
  perform public.rc__tbump(p_dev, case (select rarity from public.rc_cards where id = p_card) when 3 then 'epics' when 4 then 'legend' end, p_n);
  perform public.rc__tbump(p_dev, case p_f when 1 then 'holo' when 2 then 'gold' when 3 then 'fullart' end, p_n);
end $function$;
