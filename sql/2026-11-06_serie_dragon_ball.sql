-- ═════════════════════════════════════════════════════════════════
-- PIXEL TRADE — série « Dragon Ball » (200 cartes) + booster Dragon Ball   (relançable)
-- Cartes db_001 … db_200 (ordre de lib/db_list.dart), sys = saga = 'db' : comme Pokémon et Dessins animés,
--   hors paquets normaux (sauf tirage rare), hors sagas, fabrication, fusion, Pioche et Gamedle (filtres saga is null existants).
-- Rareté du jeu de cartes : commune → 2, rare → 3, holo → 4 (toujours BRILLANTE, finition 1).
-- Tirage : rc__saga_roll, 0,15 % par carte de paquet (réglage en direct 'db' de rc_config.live).
-- Booster « Dragon Ball » (kind 'dragonball') : 400 PIÈCES, 12 cartes db différentes :
--   8 communes, 2 rares, 1 rare (30 % : holo), 1 holo.
-- Récompenses / cadeaux admin : packs.dragonball, cards.db (carte Dragon Ball au hasard).
-- Fonctions déjà en place modifiées par remplacement de texte (textes posés par la série Dessins animés du 4/11).
-- À lancer par l'outil SQL (accents) ; sinon : psql -U postgres -d postgres -f 2026-11-06_serie_dragon_ball.sql
-- ═════════════════════════════════════════════════════════════════

-- 1) les 200 cartes
insert into public.rc_cards (id, sys, num, rarity, title, saga)
select 'db_' || lpad(n::text, 3, '0'), 'db', n, r, t, 'db'
  from (values
    (1, 2, 'Goku (singe géant)'),
    (2, 3, 'Goku'),
    (3, 4, 'Goku'),
    (4, 2, 'Goku'),
    (5, 4, 'Goku'),
    (6, 2, 'Goku'),
    (7, 4, 'Goku'),
    (8, 2, 'Goku'),
    (9, 2, 'Goku'),
    (10, 3, 'Goku'),
    (11, 3, 'Vegeta'),
    (12, 4, 'Vegeta'),
    (13, 4, 'Vegeta'),
    (14, 2, 'Vegeta'),
    (15, 4, 'Vegeta'),
    (16, 4, 'Vegeta'),
    (17, 2, 'Vegeta'),
    (18, 2, 'Vegeta'),
    (19, 4, 'Vegeta'),
    (20, 3, 'Gohan'),
    (21, 2, 'Gohan'),
    (22, 2, 'Gohan'),
    (23, 4, 'Gohan'),
    (24, 4, 'Gohan'),
    (25, 4, 'Gohan'),
    (26, 3, 'Gohan'),
    (27, 2, 'Gohan'),
    (28, 2, 'Trunks'),
    (29, 2, 'Trunks'),
    (30, 2, 'Trunks'),
    (31, 3, 'Trunks'),
    (32, 3, 'Trunks'),
    (33, 3, 'Trunks'),
    (34, 2, 'Piccolo'),
    (35, 2, 'Piccolo'),
    (36, 4, 'Piccolo'),
    (37, 4, 'Piccolo'),
    (38, 4, 'Piccolo'),
    (39, 3, 'Piccolo'),
    (40, 3, 'Cell'),
    (41, 2, 'Cell'),
    (42, 2, 'Cell'),
    (43, 4, 'Cell'),
    (44, 4, 'Cell'),
    (45, 2, 'Freezer'),
    (46, 2, 'Freezer'),
    (47, 2, 'Freezer'),
    (48, 3, 'Freezer'),
    (49, 3, 'Freezer'),
    (50, 2, 'Majin Boo'),
    (51, 2, 'Majin Boo'),
    (52, 4, 'Majin Boo'),
    (53, 4, 'Majin Boo'),
    (54, 4, 'Boo'),
    (55, 2, 'Boo'),
    (56, 2, 'Krillin'),
    (57, 2, 'Krillin'),
    (58, 2, 'Krillin'),
    (59, 3, 'Krillin'),
    (60, 2, 'Goten'),
    (61, 2, 'Goten'),
    (62, 2, 'Goten'),
    (63, 2, 'Gotenks'),
    (64, 4, 'Gotenks'),
    (65, 4, 'Gotenks'),
    (66, 2, 'Yamcha'),
    (67, 2, 'Yamcha'),
    (68, 4, 'Yamcha'),
    (69, 2, 'Tenshinhan'),
    (70, 2, 'Tenshinhan'),
    (71, 2, 'Tenshinhan'),
    (72, 2, 'Tortue Géniale'),
    (73, 4, 'Tortue Géniale'),
    (74, 2, 'Tortue Géniale'),
    (75, 2, 'Mr Satan'),
    (76, 2, 'Mr Satan'),
    (77, 2, 'Mr Satan'),
    (78, 4, 'Bulma'),
    (79, 3, 'Bulma'),
    (80, 3, 'Bulma'),
    (81, 3, 'C-18'),
    (82, 2, 'C-18'),
    (83, 2, 'C-18'),
    (84, 3, 'C-17'),
    (85, 4, 'C-17'),
    (86, 2, 'C-17'),
    (87, 4, 'Roi Piccolo'),
    (88, 2, 'Roi Piccolo'),
    (89, 2, 'Roi Piccolo'),
    (90, 4, 'Oob'),
    (91, 3, 'Oob'),
    (92, 4, 'Oob'),
    (93, 2, 'Baby'),
    (94, 4, 'Baby'),
    (95, 4, 'Baby'),
    (96, 2, 'Chaozu'),
    (97, 2, 'Chaozu'),
    (98, 2, 'Jackie Chun'),
    (99, 3, 'Jackie Chun'),
    (100, 2, 'Dendé'),
    (101, 2, 'Dendé'),
    (102, 2, 'C-16'),
    (103, 2, 'C-16'),
    (104, 2, 'Dabura'),
    (105, 4, 'Dabura'),
    (106, 2, 'Pilaf'),
    (107, 2, 'Pilaf'),
    (108, 2, 'Nappa'),
    (109, 2, 'Nappa'),
    (110, 2, 'Lunch'),
    (111, 3, 'Lunch'),
    (112, 2, 'Tao Paï Paï'),
    (113, 2, 'Tao Paï Paï'),
    (114, 2, 'C-20'),
    (115, 2, 'C-20'),
    (116, 2, 'Babidi'),
    (117, 3, 'Babidi'),
    (118, 2, 'Videl'),
    (119, 3, 'Videl'),
    (120, 2, 'Radditz'),
    (121, 3, 'Radditz'),
    (122, 3, 'Ginyu'),
    (123, 2, 'Ginyu'),
    (124, 2, 'Vegeto'),
    (125, 4, 'Vegeto'),
    (126, 2, 'Pan'),
    (127, 2, 'Pan'),
    (128, 4, 'Gogeta'),
    (129, 4, 'Gogeta'),
    (130, 4, 'Bardock'),
    (131, 2, 'Bardock'),
    (132, 2, 'Cooler'),
    (133, 4, 'Cooler'),
    (134, 3, 'Karine'),
    (135, 3, 'Tambourin'),
    (136, 2, 'Kaïo'),
    (137, 3, 'Zabon'),
    (138, 3, 'Recoome'),
    (139, 2, 'Chichi'),
    (140, 3, 'C-19'),
    (141, 2, 'Vieux Kaïo Shin'),
    (142, 4, 'Paikuhan'),
    (143, 2, 'Oolong'),
    (144, 2, 'Plume'),
    (145, 3, 'Général Red'),
    (146, 2, 'Maître des Grues'),
    (147, 2, 'Drum'),
    (148, 2, 'Cymbale'),
    (149, 3, 'Tout-Puissant'),
    (150, 2, 'Saibaman'),
    (151, 2, 'Dodoria'),
    (152, 2, 'Guldo'),
    (153, 2, 'Jeece'),
    (154, 2, 'Barta'),
    (155, 3, 'Nail'),
    (156, 2, 'Cell Junior'),
    (157, 2, 'Mr Popo'),
    (158, 2, 'Roi Cold'),
    (159, 2, 'Pui Pui'),
    (160, 3, 'Yakon'),
    (161, 3, 'Kibito'),
    (162, 2, 'Gyumao'),
    (163, 4, 'Kiwi'),
    (164, 2, 'Kaïo Shin'),
    (165, 2, 'Yajirobé'),
    (166, 4, 'Garlic Junior'),
    (167, 4, 'Général Rild'),
    (168, 4, 'Upa'),
    (169, 2, 'Great Saiyaman'),
    (170, 2, 'Spopovitch'),
    (171, 3, 'Janemba'),
    (172, 3, 'Roi Vegeta'),
    (173, 2, 'Bra'),
    (174, 2, 'Toma'),
    (175, 4, 'Super C-17'),
    (176, 2, 'Dr Brief'),
    (177, 2, 'Mutaïto'),
    (178, 2, 'Docteur Myû'),
    (179, 4, 'Li Shenron'),
    (180, 3, 'Grand Kaïo'),
    (181, 2, 'Roi Enma'),
    (182, 2, 'Bibidi'),
    (183, 2, 'Ninja Violet'),
    (184, 2, 'Commandant Blue'),
    (185, 2, 'Mighty Mask'),
    (186, 4, 'Assistant Noir'),
    (187, 2, 'Sergent Métallique'),
    (188, 2, 'Lanfan'),
    (189, 2, 'Pamputt'),
    (190, 2, 'Bactérie'),
    (191, 2, 'Guilan'),
    (192, 2, 'Nam'),
    (193, 2, 'Boum'),
    (194, 2, 'Toto le Lapin'),
    (195, 2, 'Baba la Voyante'),
    (196, 2, 'Franky 8 (c-8)'),
    (197, 2, 'Malone'),
    (198, 2, 'Combattant Mystérieux'),
    (199, 2, 'Bubbles'),
    (200, 2, 'Grégory')
  ) as x(n, r, t)
on conflict (id) do update set title = excluded.title, rarity = excluded.rarity, sys = excluded.sys, saga = excluded.saga;

-- 2) tirage rare dans les paquets normaux (la série db est exclue du tirage des sagas)
CREATE OR REPLACE FUNCTION public.rc__saga_roll()
 RETURNS text
 LANGUAGE sql
AS $function$
  select case
    when random() < public.rc__cfg('pk', 0.15) / 100 then (select id from public.rc_cards where saga = 'pk' order by random() limit 1)
    when random() < public.rc__cfg('da', 0.15) / 100 then (select id from public.rc_cards where saga = 'da' order by random() limit 1)
    when random() < public.rc__cfg('db', 0.15) / 100 then (select id from public.rc_cards where saga = 'db' order by random() limit 1)
    when random() < public.rc__cfg('saga', 3.2) / 100 then (select id from public.rc_cards where saga is not null and saga not in ('pk', 'da', 'db') order by random() limit 1)
  end $function$;
alter function public.rc__saga_roll() owner to rc_owner;

-- 3) prix du booster : 400 pièces (payé comme les paquets de la boutique)
create or replace function public.rc__pack_price(k text)
 returns integer
 language sql
 stable
as $function$
  select (case k when 'free' then 0 when 'mixte' then public.rc__cfg('mixte', 100)::int when 'console' then public.rc__cfg('console', 150)::int
                 when 'premium' then public.rc__cfg('premium', 400)::int
                 when 'mystery' then public.rc__cfg('mystery', 120)::int when 'dragonball' then 400
                 when 'gift' then 0 when 'lot' then 0 end)
         * (100 - public.rc__promo(k)) / 100 $function$;
alter function public.rc__pack_price(text) owner to rc_owner;

-- 4) le booster : 12 cartes db différentes
create or replace function public.rc__draw_db()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
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
end $function$;
alter function public.rc__draw_db() owner to rc_owner;

-- 5) remplacements de texte dans les fonctions en place
do $$
declare d text; rec record;
begin
  for rec in
    select * from (values
      -- booster Dragon Ball
      ('public.rc__draw_pack(text,text,integer)',
       $a$  if p_kind = 'cartoon' then$a$,
       $b$  if p_kind = 'dragonball' then return public.rc__draw_db(); end if;  -- 12 cartes Dragon Ball
  if p_kind = 'cartoon' then$b$),
      -- carte db tirée dans un paquet normal : brillante si holo
      ('public.rc__draw_pack(text,text,integer)',
       $a$when sg like 'da\_%' and (select rarity from public.rc_cards where id = sg) >= 4 then 1 else 0 end;$a$,
       $b$when sg ~ '^(da|db)_' and (select rarity from public.rc_cards where id = sg) >= 4 then 1 else 0 end;$b$),
      ('public.rc_open(text,text,text,text)',
       $a$when sg like 'da\_%' and (select rarity from public.rc_cards where id = sg) >= 4 then 1 else 0 end;$a$,
       $b$when sg ~ '^(da|db)_' and (select rarity from public.rc_cards where id = sg) >= 4 then 1 else 0 end;$b$),
      -- booster db : ne remet pas le compteur d'épiques à zéro
      ('public.rc_pick(text,integer,text)',
       $a$coalesce(pd.gk, pd.kind) not in ('pokemon', 'cartoon') then$a$,
       $b$coalesce(pd.gk, pd.kind) not in ('pokemon', 'cartoon', 'dragonball') then$b$),
      -- récompenses / cadeaux admin
      ('public.rc__rw_clean(jsonb)',
       $a$'star', 'gold', 'pokemon', 'cartoon') and n > 0$a$,
       $b$'star', 'gold', 'pokemon', 'cartoon', 'dragonball') and n > 0$b$),
      ('public.rc__rw_clean(jsonb)',
       $a$'3', '4', 'pk', 'da') and n > 0$a$,
       $b$'3', '4', 'pk', 'da', 'db') and n > 0$b$),
      ('public.rc__grant(text,jsonb)',
       $a$when 'cartoon' then 'Dessins animés' end;$a$,
       $b$when 'cartoon' then 'Dessins animés' when 'dragonball' then 'Dragon Ball' end;$b$),
      ('public.rc__grant(text,jsonb)',
       $a$      if k = 'da' then$a$,
       $b$      if k = 'db' then  -- une carte Dragon Ball au hasard
        select id into c from public.rc_cards where saga = 'db' order by random() limit 1;
      elsif k = 'da' then$b$),
      -- réglage en direct 'db'
      ('public.rc__live()',
       $a$'da', public.rc__cfg('da', 0.15),$a$,
       $b$'da', public.rc__cfg('da', 0.15), 'db', public.rc__cfg('db', 0.15),$b$),
      ('public.rc_admin_set_live(text,text,text)',
       $a$'fullart', 'pk', 'da') then$a$,
       $b$'fullart', 'pk', 'da', 'db') then$b$),
      ('public.rc_admin_x(text,text,text,text)',
       $a$'fullart', 'pk', 'da', 'mixte'$a$,
       $b$'fullart', 'pk', 'da', 'db', 'mixte'$b$),
      -- trophée « sagas » : les cartes db ne comptent pas comme cartes de saga
      ('public.rc__tn(text)',
       $a$cc.saga is not null and cc.saga not in ('pk', 'da'))$a$,
       $b$cc.saga is not null and cc.saga not in ('pk', 'da', 'db'))$b$),
      -- fiche joueur de l'admin : nombre de cartes db
      ('public.rc__adm_player(text)',
       $a$    'da', (select count(distinct card) from rc_owned where device = v.device and card like 'da\_%'),$a$,
       $b$    'da', (select count(distinct card) from rc_owned where device = v.device and card like 'da\_%'),
    'db', (select count(distinct card) from rc_owned where device = v.device and card like 'db\_%'),$b$)
    ) as x(fn, a, b)
  loop
    if to_regprocedure(rec.fn) is null then
      raise notice 'fonction absente (ignorée) : %', rec.fn;
      continue;
    end if;
    d := pg_get_functiondef(to_regprocedure(rec.fn));
    if position(rec.b in d) > 0 then
      continue;  -- déjà fait
    elsif position(rec.a in d) = 0 then
      raise notice 'texte introuvable dans % : %', rec.fn, left(rec.a, 60);
      continue;
    end if;
    execute replace(d, rec.a, rec.b);
  end loop;
end $$;

-- 6) réglage par défaut (garde une valeur déjà posée par l'admin)
update public.rc_config set value = jsonb_build_object('db', 0.15) || value where key = 'live' and not (value ? 'db');

notify pgrst, 'reload schema';

-- contrôles : 200 cartes (119 communes, 37 rares, 44 holos), prix 400, et aucune ligne « introuvable » dans les notices
select count(*) as cartes, count(*) filter (where rarity = 2) as communes, count(*) filter (where rarity = 3) as rares,
       count(*) filter (where rarity = 4) as holos, public.rc__pack_price('dragonball') as prix
  from public.rc_cards where saga = 'db';
