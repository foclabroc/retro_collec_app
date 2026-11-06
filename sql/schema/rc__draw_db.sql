create or replace function public.rc__draw_db()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  i int; r int; c text; rr int; got text[] := '{}'; res jsonb := '[]'::jsonb;
begin
  for i in 1..8 loop
    r := case when i <= 5 then 2 when i = 6 then 3 when i = 7 then case when random() < 0.3 then 4 else 3 end else 4 end;
    select id, rarity into c, rr from public.rc_cards
     where saga = 'db' and rarity = r and not (id = any(got)) order by random() limit 1;
    if c is null then
      select id, rarity into c, rr from public.rc_cards where saga = 'db' order by random() limit 1;
    end if;
    if c is null then raise exception 'catalogue vide'; end if;
    got := got || c;
    res := res || jsonb_build_object('c', c, 'f', case when rr >= 4 then 1 else 0 end, 'r', rr);
    c := null;
  end loop;
  return res;
end $function$;
