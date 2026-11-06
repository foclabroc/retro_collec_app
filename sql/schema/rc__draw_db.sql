CREATE OR REPLACE FUNCTION public.rc__draw_db()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  i int; r int; c text; rr int; got text[] := '{}'; res jsonb := '[]'::jsonb;
begin
  for i in 1..12 loop
    r := case when i <= 8 then 2 when i <= 10 then 3 when i = 11 then case when random() < 0.3 then 4 else 3 end else 4 end;
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
end $function$

