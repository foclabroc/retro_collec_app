CREATE OR REPLACE FUNCTION public.rc__draw_pack(p_kind text, p_sys text, p_pity integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  scope text := case when p_kind in ('console', 'sconsole') then p_sys else null end;
  n int := 5; x float;
  i int; r int; f int; c text; sg text; got_epic boolean := false;
  res jsonb := '[]'::jsonb;
begin
  if p_kind = 'mystery' then
    x := random();
    n := case when x < 0.5 then 3 when x < 0.9 then 5 else 8 end;
  end if;
  for i in 1..n loop
    if i = n and p_kind in ('premium', 'sconsole') then r := public.rc__roll(2);   -- rare ou mieux
    elsif i = n and p_kind = 'star' then r := public.rc__roll(3);                   -- épique ou mieux
    elsif i = n and p_kind = 'gold' then r := case when random() < 0.5 then 4 else public.rc__roll(0) end;
    else r := public.rc__roll(0); end if;
    if i = n and not got_epic and p_pity >= 29 and r < 3 then r := public.rc__roll(3); end if;
    select id into c from public.rc_cards
     where rarity = r and saga is null and (scope is null or sys = scope) order by random() limit 1;
    if c is null then
      select id, rarity into c, r from public.rc_cards
       where rarity <= r and saga is null and (scope is null or sys = scope) order by rarity desc, random() limit 1;
    end if;
    if c is null then raise exception 'catalogue vide'; end if;
    if r >= 3 then got_epic := true; end if;
    f := public.rc__roll_finish(r);
    if p_kind = 'sconsole' and i = n - 1 then f := greatest(f, 1); end if;   -- une brillante garantie
    if p_kind = 'gold' and i = n and r < 4 then f := 2; end if;              -- sinon légendaire : dorée garantie
    sg := public.rc__saga_roll();  -- carte de saga
    if sg is not null then c := sg; r := 3; f := 0; got_epic := true; end if;
    res := res || jsonb_build_object('c', c, 'f', f, 'r', r);
    c := null;
  end loop;
  return res;
end $function$
