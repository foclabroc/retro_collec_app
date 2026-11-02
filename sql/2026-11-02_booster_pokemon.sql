-- Booster Pokémon : 100 pixels, 5 cartes Pokémon (série pk) au hasard.
CREATE OR REPLACE FUNCTION public.rc__special_cost(p_kind text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case p_kind when 'star' then 15 when 'sconsole' then 25 when 'gold' then 40 when 'pokemon' then 100 end $function$;
alter function public.rc__special_cost(text) owner to rc_owner;

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
  if p_kind = 'pokemon' then  -- 5 cartes Pokémon au hasard
    for i in 1..5 loop
      select id into c from public.rc_cards where saga = 'pk' order by random() limit 1;
      if c is null then raise exception 'catalogue vide'; end if;
      res := res || jsonb_build_object('c', c, 'f', case when substr(c, 4)::int >= 152 then 1 else 0 end, 'r', 3);
    end loop;
    return res;
  end if;
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
    if sg is not null then c := sg; r := 3; f := case when sg like 'pk\_%' and substr(sg, 4)::int >= 152 then 1 else 0 end; got_epic := true; end if;
    res := res || jsonb_build_object('c', c, 'f', f, 'r', r);
    c := null;
  end loop;
  return res;
end $function$;
alter function public.rc__draw_pack(text, text, integer) owner to rc_owner;

-- une carte Pokémon (rareté 3) ne remet pas le compteur d'épiques à zéro
do $$
declare d text;
begin
  d := pg_get_functiondef('public.rc_pick(text,integer,text)'::regprocedure);
  if d like '%if r >= 3 then got_epic := true; end if;%' then
    execute replace(d, 'if r >= 3 then got_epic := true; end if;', 'if r >= 3 and coalesce(pd.gk, pd.kind) <> ''pokemon'' then got_epic := true; end if;');
  end if;
end $$;

-- récompenses / cadeaux admin
create or replace function public.rc__rw_clean(r jsonb)
 returns jsonb
 language plpgsql
 immutable
as $function$
declare out jsonb := '{}'::jsonb; m jsonb := '{}'::jsonb; k text; v text; n int;
begin
  if r is null or jsonb_typeof(r) <> 'object' then return '{}'::jsonb; end if;
  n := least(greatest(coalesce((r->>'coins')::int, 0), 0), 100000); if n > 0 then out := out || jsonb_build_object('coins', n); end if;
  n := least(greatest(coalesce((r->>'pixels')::int, 0), 0), 1000);  if n > 0 then out := out || jsonb_build_object('pixels', n); end if;
  n := least(greatest(coalesce((r->>'lots')::int, 0), 0), 5);       if n > 0 then out := out || jsonb_build_object('lots', n); end if;
  for k, v in select key, value from jsonb_each_text(coalesce(r->'packs', '{}'::jsonb)) loop
    n := least(greatest(coalesce(v::int, 0), 0), 10);
    if k in ('mixte', 'premium', 'mystery', 'star', 'gold', 'pokemon') and n > 0 then m := m || jsonb_build_object(k, n); end if;
  end loop;
  if m <> '{}'::jsonb then out := out || jsonb_build_object('packs', m); end if;
  m := '{}'::jsonb;
  for k, v in select key, value from jsonb_each_text(coalesce(r->'cards', '{}'::jsonb)) loop
    n := least(greatest(coalesce(v::int, 0), 0), 10);
    if k in ('0', '1', '2', '3', '4', 'pk') and n > 0 then m := m || jsonb_build_object(k, n); end if;
  end loop;
  if m <> '{}'::jsonb then out := out || jsonb_build_object('cards', m); end if;
  return out;
end $function$;
alter function public.rc__rw_clean(jsonb) owner to rc_owner;

create or replace function public.rc__grant(p_dev text, p_reward jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  r jsonb := public.rc__rw_clean(p_reward);
  k text; v text; n int; i int; c text; cards jsonb := '[]'::jsonb;
  lbl text;
begin
  -- rc.gift_from (réglage de la transaction) : nom du donneur des paquets offerts, « Pixel Trade » par défaut (tournois : « Tournoi X »)
  if r = '{}'::jsonb then return jsonb_build_object('cards', cards); end if;
  update public.rc_players
     set coins = coins + coalesce((r->>'coins')::int, 0),
         pixels = pixels + coalesce((r->>'pixels')::int, 0),
         lots = lots + 5 * coalesce((r->>'lots')::int, 0)
   where device = p_dev;
  for k, v in select key, value from jsonb_each_text(coalesce(r->'packs', '{}'::jsonb)) loop
    lbl := case k when 'mixte' then 'mixte' when 'premium' then 'premium' when 'mystery' then 'mystère'
                  when 'star' then 'Étoile' when 'gold' then 'Rétro d''or' when 'pokemon' then 'Pokémon' end;
    for i in 1 .. v::int loop
      insert into public.rc_gifts (receiver, giver, giver_name, kind)
      values (p_dev, null, coalesce(nullif(current_setting('rc.gift_from', true), ''), 'Pixel Trade') || ' · ' || lbl, k);
    end loop;
  end loop;
  for k, v in select key, value from jsonb_each_text(coalesce(r->'cards', '{}'::jsonb)) loop
    for i in 1 .. v::int loop
      -- 'pk' = une carte Pokémon au hasard
      if k = 'pk' then
        select id into c from public.rc_cards where saga = 'pk' order by random() limit 1;
      else
        select id into c from public.rc_cards where rarity = k::int and saga is null order by random() limit 1;
      end if;
      if c is not null then
        -- la carte attend dans le stock « Cartes à ranger » : le joueur la voit avant qu'elle entre dans sa collection
        insert into public.rc_card_stock (device, card, finish, giver_name)
        values (p_dev, c, 0, coalesce(nullif(current_setting('rc.gift_from', true), ''), 'Pixel Trade'));
        cards := cards || jsonb_build_object('c', c, 'r', (select rarity from public.rc_cards where id = c), 'f', 0, 'stock', true);
      end if;
    end loop;
  end loop;
  return r || jsonb_build_object('cards', cards);
end $function$;
alter function public.rc__grant(text, jsonb) owner to rc_owner;

notify pgrst, 'reload schema';
