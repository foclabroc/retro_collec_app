-- ═══════════════════════════════════════════════════════════════════
-- PIXEL TRADE — série « Pokémon » (185 cartes, très très rares)   (relançable)
-- Cartes pk_001 … pk_185 (ordre des noms de fichiers), saga = 'pk' : hors paquets normaux,
-- tirées par rc__saga_roll à 0,15 % par carte de paquet (réglage en direct pk de rc_config.live).
-- Rareté 3 jusqu'à la 151, rareté 4 dès la 152 ; à partir de la 152 la carte sort toujours BRILLANTE (finition 1).
-- Les saga = 'pk' sont exclues du tirage des sagas, de la fabrication, de la fusion et du Gamedle (filtres saga is null / is not null existants).
-- Dossier à lancer : psql -U postgres -d postgres -f 2026-10-30_serie_pokemon.sql
-- ═══════════════════════════════════════════════════════════════════

insert into public.rc_cards (id, sys, num, rarity, title, saga)
select 'pk_' || lpad(n::text, 3, '0'), 'pk', n, case when n >= 152 then 4 else 3 end, t, 'pk'
  from (values
    (1, 'Bulbizarre'),
    (2, 'Herbizarre'),
    (3, 'Florizarre ex'),
    (4, 'Salameche'),
    (5, 'Reptincel'),
    (6, 'Dracaufeu ex'),
    (7, 'Carapuce'),
    (8, 'Carabaffe'),
    (9, 'Tortank ex'),
    (10, 'Chenipan'),
    (11, 'Chrysacier'),
    (12, 'Papilusion'),
    (13, 'Aspicot'),
    (14, 'Coconfort'),
    (15, 'Dardargnan'),
    (16, 'Roucool'),
    (17, 'Roucoups'),
    (18, 'Roucarnage'),
    (19, 'Rattata'),
    (20, 'Rattatac'),
    (21, 'Piafabec'),
    (22, 'Rapasdepic'),
    (23, 'Abo'),
    (24, 'Arbok ex'),
    (25, 'Pikachu'),
    (26, 'Raichu'),
    (27, 'Sabelette'),
    (28, 'Sablaireau'),
    (29, 'Nidoran'),
    (30, 'Nidorina'),
    (31, 'Nidoqueen'),
    (32, 'Nidoran'),
    (33, 'Nidorino'),
    (34, 'Nidoking'),
    (35, 'Melofee'),
    (36, 'Melodelfe'),
    (37, 'Goupix'),
    (38, 'Feunard ex'),
    (39, 'Rondoudou'),
    (40, 'Grodoudou ex'),
    (41, 'Nosferapti'),
    (42, 'Nosferalto'),
    (43, 'Mystherbe'),
    (44, 'Ortide'),
    (45, 'Rafflesia'),
    (46, 'Paras'),
    (47, 'Parasect'),
    (48, 'Mimitoss'),
    (49, 'Aeromite'),
    (50, 'Taupiqueur'),
    (51, 'Triopikeur'),
    (52, 'Miaouss'),
    (53, 'Persian'),
    (54, 'Psykokwak'),
    (55, 'Akwakwak'),
    (56, 'Ferosinge'),
    (57, 'Colossinge'),
    (58, 'Caninos'),
    (59, 'Arcanin'),
    (60, 'Ptitard'),
    (61, 'Tetarte'),
    (62, 'Tartard'),
    (63, 'Abra'),
    (64, 'Kadabra'),
    (65, 'Alakazam ex'),
    (66, 'Machoc'),
    (67, 'Machopeur'),
    (68, 'Mackogneur'),
    (69, 'Chetiflor'),
    (70, 'Boustiflor'),
    (71, 'Empiflor'),
    (72, 'Tentacool'),
    (73, 'Tentacruel'),
    (74, 'Racaillou'),
    (75, 'Gravalanch'),
    (76, 'Grolem ex'),
    (77, 'Ponyta'),
    (78, 'Galopa'),
    (79, 'Ramoloss'),
    (80, 'Flagadoss'),
    (81, 'Magneti'),
    (82, 'Magneton'),
    (83, 'Canarticho'),
    (84, 'Doduo'),
    (85, 'Dodrio'),
    (86, 'Otaria'),
    (87, 'Lamantine'),
    (88, 'Tadmorv'),
    (89, 'Grotadmorv'),
    (90, 'Kokiyas'),
    (91, 'Crustabri'),
    (92, 'Fantominus'),
    (93, 'Spectrum'),
    (94, 'Ectoplasma'),
    (95, 'Onix'),
    (96, 'Soporifik'),
    (97, 'Hypnomade'),
    (98, 'Krabby'),
    (99, 'Krabboss'),
    (100, 'Voltorbe'),
    (101, 'Electrode'),
    (102, 'Noeunoeuf'),
    (103, 'Noadkoko'),
    (104, 'Osselait'),
    (105, 'Ossatueur'),
    (106, 'Kicklee'),
    (107, 'Tygnon'),
    (108, 'Excelangue'),
    (109, 'Smogo'),
    (110, 'Smogogo'),
    (111, 'Rhinocorne'),
    (112, 'Rhinoferos'),
    (113, 'Leveinard'),
    (114, 'Saquedeneu'),
    (115, 'Kangourex ex'),
    (116, 'Hypotrempe'),
    (117, 'Hypocean'),
    (118, 'Poissirene'),
    (119, 'Poissoroy'),
    (120, 'Stari'),
    (121, 'Staross'),
    (122, 'M. Mime'),
    (123, 'Insecateur'),
    (124, 'Lippoutou ex'),
    (125, 'Elektek'),
    (126, 'Magmar'),
    (127, 'Scarabrute'),
    (128, 'Tauros'),
    (129, 'Magicarpe'),
    (130, 'Leviator'),
    (131, 'Lokhlass'),
    (132, 'Metamorph'),
    (133, 'Evoli'),
    (134, 'Aquali'),
    (135, 'Voltali'),
    (136, 'Pyroli'),
    (137, 'Porygon'),
    (138, 'Amonita'),
    (139, 'Amonistar'),
    (140, 'Kabuto'),
    (141, 'Kabutops'),
    (142, 'Ptera'),
    (143, 'Ronflex'),
    (144, 'Artikodin'),
    (145, 'Electhor ex'),
    (146, 'Sulfura'),
    (147, 'Minidraco'),
    (148, 'Draco'),
    (149, 'Dracolosse'),
    (150, 'Mewtwo'),
    (151, 'Mew ex'),
    (152, 'Bulbizarre'),
    (153, 'Herbizarre'),
    (154, 'Salameche'),
    (155, 'Reptincel'),
    (156, 'Carapuce'),
    (157, 'Carabaffe'),
    (158, 'Chenipan'),
    (159, 'Pikachu'),
    (160, 'Nidoking'),
    (161, 'Psykokwak'),
    (162, 'Tetarte'),
    (163, 'Machopeur'),
    (164, 'Saquedeneu'),
    (165, 'M. Mime'),
    (166, 'Amonita'),
    (167, 'Draco'),
    (168, 'Florizarre ex'),
    (169, 'Dracaufeu ex'),
    (170, 'Tortank ex'),
    (171, 'Arbok ex'),
    (172, 'Feunard ex'),
    (173, 'Grodoudou ex'),
    (174, 'Alakazam ex'),
    (175, 'Grolem ex'),
    (176, 'Kangourex ex'),
    (177, 'Lippoutou ex'),
    (178, 'Electhor ex'),
    (179, 'Mew ex'),
    (180, 'Florizarre ex'),
    (181, 'Dracaufeu ex'),
    (182, 'Tortank ex'),
    (183, 'Alakazam ex'),
    (184, 'Electhor ex'),
    (185, 'Mew ex')
  ) as x(n, t)
on conflict (id) do nothing;
-- rc__saga_roll
CREATE OR REPLACE FUNCTION public.rc__saga_roll()
 RETURNS text
 LANGUAGE sql
AS $function$
  select case
    when random() < public.rc__cfg('pk', 0.15) / 100 then (select id from public.rc_cards where saga = 'pk' order by random() limit 1)
    when random() < public.rc__cfg('saga', 3.2) / 100 then (select id from public.rc_cards where saga is not null and saga <> 'pk' order by random() limit 1)
  end $function$;

-- rc__draw_pack
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
    if sg is not null then c := sg; r := 3; f := case when sg like 'pk\_%' and substr(sg, 4)::int >= 152 then 1 else 0 end; got_epic := true; end if;
    res := res || jsonb_build_object('c', c, 'f', f, 'r', r);
    c := null;
  end loop;
  return res;
end $function$;

-- rc_open
CREATE OR REPLACE FUNCTION public.rc_open(p_device text, p_kind text, p_sys text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v public.rc_players;
  price int := public.rc__pack_price(p_kind);
  scope text := case when p_kind = 'console' then p_sys else null end;
  n int := 5; x float;
  i int; r int; f int; c text; sg text; is_new boolean; got_epic boolean := false; nnew int := 0;
  res jsonb := '[]'::jsonb; ev jsonb := '[]'::jsonb; gid bigint;
begin
  perform public.rc__check(p_sig, p_device || '|open|' || coalesce(p_kind, '') || '|' || coalesce(p_sys, ''));
  if price is null then raise exception 'paquet inconnu'; end if;
  if p_kind = 'console' and not exists (select 1 from public.rc_cards where sys = p_sys) then
    raise exception 'console inconnue';
  end if;
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  if p_kind = 'free' then
    if public.rc__free_in(p_device) > 0 then raise exception 'paquet gratuit pas encore prêt'; end if;
    update public.rc_players set last_free = public.rc__today(), last_free_at = now() where device = p_device;
  elsif p_kind = 'gift' then
    -- un cadeau précis (p_sys = son numéro) ou le plus ancien
    select g.id into gid from public.rc_gifts g
     where g.receiver = p_device and g.opened_at is null
       and (coalesce(p_sys, '') = '' or g.id::text = p_sys)
     order by g.id limit 1 for update;
    if gid is null then raise exception 'aucun cadeau'; end if;
    update public.rc_gifts set opened_at = now() where id = gid;
  elsif p_kind = 'lot' then
    if v.lots < 1 then raise exception 'aucun paquet du lot'; end if;
    update public.rc_players set lots = lots - 1 where device = p_device;
  elsif v.coins < price then
    raise exception 'pas assez de pièces';
  else
    update public.rc_players set coins = coins - price where device = p_device;
  end if;

  if p_kind = 'mystery' then
    x := random();
    n := case when x < 0.5 then 3 when x < 0.9 then 5 else 8 end;
  end if;

  for i in 1..n loop
    if i = n and p_kind = 'premium' then r := public.rc__roll(2); else r := public.rc__roll(0); end if;
    if i = n and not got_epic and v.pity >= 29 then r := public.rc__roll(3); end if;
    select id into c from public.rc_cards
     where rarity = r and saga is null and (scope is null or sys = scope) order by random() limit 1;
    if c is null then
      select id, rarity into c, r from public.rc_cards
       where rarity <= r and saga is null and (scope is null or sys = scope) order by rarity desc, random() limit 1;
    end if;
    if c is null then raise exception 'catalogue vide'; end if;
    if r >= 3 then got_epic := true; end if;
    f := public.rc__roll_finish(r);
    sg := public.rc__saga_roll();  -- carte de saga
    if sg is not null then c := sg; r := 3; f := case when sg like 'pk\_%' and substr(sg, 4)::int >= 152 then 1 else 0 end; got_epic := true; end if;
    is_new := public.rc__is_new(p_device, c, f);
    if is_new then nnew := nnew + 1; end if;
    perform public.rc__give(p_device, c, f, 1);
    res := res || jsonb_build_object('c', c, 'f', f, 'r', r, 'n', is_new);
    c := null;
  end loop;

  update public.rc_players set packs = packs + 1, pity = case when got_epic then 0 else pity + 1 end,
         pixels = pixels + 1
   where device = p_device;
  ev := ev || public.rc__bump(p_device, 'open', 1);
  if got_epic then  -- défi : carte épique ou mieux
    perform public.rc__wbump(p_device, 'epic', 1);
    perform public.rc__ev_bump(p_device, 'epics', 1);
  end if;
  perform public.rc__wbump(p_device, 'new', nnew);  -- défi : nouvelles cartes
  if p_kind in ('free', 'premium') then perform public.rc__wbump(p_device, p_kind, 1); end if;  -- défis : paquet gratuit, premium
  ev := ev || public.rc__milestones(p_device);
  perform public.rc__rescore(p_device);
  select * into v from public.rc_players where device = p_device;
  return jsonb_build_object('cards', res, 'coins', v.coins, 'pity', v.pity, 'score', v.score, 'events', ev,
                            'lots', v.lots, 'pixels', v.pixels,
                            'gifts', (select count(*)::int from public.rc_gifts g where g.receiver = p_device and g.opened_at is null));
end $function$;

alter function public.rc__saga_roll() owner to rc_owner;


notify pgrst, 'reload schema';

-- contrôle : 185
select count(*) from public.rc_cards where saga = 'pk';
