create or replace function public.rc__give(p_dev text, p_card text, p_f integer, p_n integer)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  insert into public.rc_owned (device, card, finish, qty) values (p_dev, p_card, p_f, p_n)
  on conflict (device, card, finish) do update set qty = public.rc_owned.qty + excluded.qty;
  -- trophées : légendaires et Full art obtenues
  if exists (select 1 from public.rc_cards where id = p_card and rarity = 4) then perform public.rc__tbump(p_dev, 'legend', p_n); end if;
  if p_f = 3 then perform public.rc__tbump(p_dev, 'fullart', p_n); end if;
end $function$;
