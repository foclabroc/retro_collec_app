-- ═══════════════════════════════════════════════════════════════════
-- PIXEL TRADE — série « Dessins animés » (80 cartes, très très rares) + booster   (relançable)
-- Cartes da_001 … da_080 (ordre de lib/da_list.dart), sys = saga = 'da' : comme la série Pokémon,
--   hors paquets normaux (sauf tirage très rare), hors sagas, fabrication, fusion, Pioche et Gamedle (filtres saga is null existants).
-- Rareté 3, sauf 13 cartes cultes en rareté 4 qui sortent toujours BRILLANTES (finition 1).
-- Tirage : rc__saga_roll, 0,15 % par carte de paquet (réglage en direct 'da' de rc_config.live).
-- Booster « Dessins animés » (kind 'cartoon') : 70 pixels, 5 cartes da au hasard.
-- Récompenses / cadeaux admin : packs.cartoon, cards.da (carte Dessin animé au hasard).
-- Les fonctions déjà en place sont modifiées par remplacement de texte (comme rc_pick pour Pokémon) : relançable sans risque.
-- Dossier à lancer : psql -U postgres -d postgres -f 2026-11-04_serie_dessins_animes.sql
-- ═══════════════════════════════════════════════════════════════════

-- 1) les 80 cartes
insert into public.rc_cards (id, sys, num, rarity, title, saga)
select 'da_' || lpad(n::text, 3, '0'), 'da', n, case when n in (1, 3, 4, 5, 6, 7, 8, 16, 21, 50, 55, 56, 64) then 4 else 3 end, t, 'da'
  from (values
    (1, 'Les Chevaliers du Zodiaque'),
    (2, 'Dragon Ball'),
    (3, 'Dragon Ball Z'),
    (4, 'Goldorak'),
    (5, 'Les Mystérieuses Cités d''Or'),
    (6, 'Ulysse 31'),
    (7, 'Capitaine Flam'),
    (8, 'Albator'),
    (9, 'Il était une fois… la Vie'),
    (10, 'Inspecteur Gadget'),
    (11, 'Les Maîtres de l''Univers'),
    (12, 'She-Ra'),
    (13, 'Transformers'),
    (14, 'G.I. Joe'),
    (15, 'Cosmocats'),
    (16, 'Les Tortues Ninja'),
    (17, 'Les Schtroumpfs'),
    (18, 'Bioman'),
    (19, 'Olive et Tom'),
    (20, 'Jeanne et Serge'),
    (21, 'Nicky Larson'),
    (22, 'Ken le Survivant'),
    (23, 'Signé Cat''s Eyes'),
    (24, 'Max et Compagnie'),
    (25, 'Sailor Moon'),
    (26, 'Juliette je t''aime'),
    (27, 'Princesse Sarah'),
    (28, 'Candy'),
    (29, 'Les Bisounours'),
    (30, 'Les Minipouss'),
    (31, 'Rémi sans famille'),
    (32, 'Tom Sawyer'),
    (33, 'Les Snorky'),
    (34, 'Les Gummi'),
    (35, 'La Bande à Picsou'),
    (36, 'Tic et Tac, les rangers du risque'),
    (37, 'Super Baloo'),
    (38, 'Myster Mask'),
    (39, 'Gargoyles'),
    (40, 'Batman, la série animée'),
    (41, 'Spider-Man'),
    (42, 'X-Men'),
    (43, 'Les Razmoket'),
    (44, 'Les Animaniacs'),
    (45, 'Les Tiny Toons'),
    (46, 'SOS Fantômes'),
    (47, 'Denver, le dernier dinosaure'),
    (48, 'Les Mondes Engloutis'),
    (49, 'Pole Position'),
    (50, 'Pokémon'),
    (51, 'La Famille Pirate'),
    (52, 'Samouraï Pizza Cats'),
    (53, 'Spirou'),
    (54, 'Les Aventures de Sonic'),
    (55, 'Lucky Luke'),
    (56, 'Les Aventures de Tintin'),
    (57, 'Les Animaux du Bois de Quat''sous'),
    (58, 'Le Bus magique'),
    (59, 'La Famille Delajungle'),
    (60, 'La Cour de récré'),
    (61, 'Jumanji'),
    (62, 'Hé Arnold !'),
    (63, 'Denis la Malice'),
    (64, 'Les Simpson'),
    (65, 'Il était une fois… l''Homme'),
    (66, 'Robotech'),
    (67, 'Cobra'),
    (68, 'Lady Oscar'),
    (69, 'M.A.S.K.'),
    (70, 'Rahan'),
    (71, 'Garfield et ses amis'),
    (72, 'Beetlejuice'),
    (73, 'Fly'),
    (74, 'Doug'),
    (75, 'Kangoo'),
    (76, 'Les Moomins'),
    (77, 'Les Entrechats'),
    (78, 'Bob l''éponge'),
    (79, 'Dragon Ball GT'),
    (80, 'Widget')
  ) as x(n, t)
on conflict (id) do update set title = excluded.title, rarity = excluded.rarity, sys = excluded.sys, saga = excluded.saga;

-- 2) tirage très rare dans les paquets (la série da est exclue du tirage des sagas)
CREATE OR REPLACE FUNCTION public.rc__saga_roll()
 RETURNS text
 LANGUAGE sql
AS $function$
  select case
    when random() < public.rc__cfg('pk', 0.15) / 100 then (select id from public.rc_cards where saga = 'pk' order by random() limit 1)
    when random() < public.rc__cfg('da', 0.15) / 100 then (select id from public.rc_cards where saga = 'da' order by random() limit 1)
    when random() < public.rc__cfg('saga', 3.2) / 100 then (select id from public.rc_cards where saga is not null and saga not in ('pk', 'da') order by random() limit 1)
  end $function$;
alter function public.rc__saga_roll() owner to rc_owner;

-- 3) prix du booster
CREATE OR REPLACE FUNCTION public.rc__special_cost(p_kind text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case p_kind when 'star' then 15 when 'sconsole' then 25 when 'gold' then 40 when 'pokemon' then 100 when 'cartoon' then 70 end $function$;
alter function public.rc__special_cost(text) owner to rc_owner;

-- 4) remplacements de texte dans les fonctions en place
do $$
declare d text; fn text; a text; b text; rec record;
begin
  for rec in
    select * from (values
      -- booster : 5 cartes da (brillantes si rareté 4)
      ('public.rc__draw_pack(text,text,integer)',
       $a$  if p_kind = 'pokemon' then  -- 5 cartes Pokémon au hasard$a$,
       $b$  if p_kind = 'cartoon' then  -- 5 cartes Dessins animés au hasard (rareté 4 : brillante)
    for i in 1..5 loop
      select id, rarity into c, r from public.rc_cards where saga = 'da' order by random() limit 1;
      if c is null then raise exception 'catalogue vide'; end if;
      res := res || jsonb_build_object('c', c, 'f', case when r >= 4 then 1 else 0 end, 'r', 3);
    end loop;
    return res;
  end if;
  if p_kind = 'pokemon' then  -- 5 cartes Pokémon au hasard$b$),
      -- carte da tirée dans un paquet normal : brillante si rareté 4
      ('public.rc__draw_pack(text,text,integer)',
       $a$f := case when sg like 'pk\_%' and substr(sg, 4)::int >= 152 then 1 else 0 end;$a$,
       $b$f := case when sg like 'pk\_%' and substr(sg, 4)::int >= 152 then 1 when sg like 'da\_%' and (select rarity from public.rc_cards where id = sg) >= 4 then 1 else 0 end;$b$),
      ('public.rc_open(text,text,text,text)',
       $a$f := case when sg like 'pk\_%' and substr(sg, 4)::int >= 152 then 1 else 0 end;$a$,
       $b$f := case when sg like 'pk\_%' and substr(sg, 4)::int >= 152 then 1 when sg like 'da\_%' and (select rarity from public.rc_cards where id = sg) >= 4 then 1 else 0 end;$b$),
      -- booster da : ne remet pas le compteur d'épiques à zéro
      ('public.rc_pick(text,integer,text)',
       $a$coalesce(pd.gk, pd.kind) <> 'pokemon' then$a$,
       $b$coalesce(pd.gk, pd.kind) not in ('pokemon', 'cartoon') then$b$),
      -- récompenses / cadeaux admin
      ('public.rc__rw_clean(jsonb)',
       $a$'star', 'gold', 'pokemon') and n > 0$a$,
       $b$'star', 'gold', 'pokemon', 'cartoon') and n > 0$b$),
      ('public.rc__rw_clean(jsonb)',
       $a$'3', '4', 'pk') and n > 0$a$,
       $b$'3', '4', 'pk', 'da') and n > 0$b$),
      ('public.rc__grant(text,jsonb)',
       $a$when 'pokemon' then 'Pokémon' end;$a$,
       $b$when 'pokemon' then 'Pokémon' when 'cartoon' then 'Dessins animés' end;$b$),
      ('public.rc__grant(text,jsonb)',
       $a$      if k = 'pk' then$a$,
       $b$      if k = 'da' then  -- une carte Dessin animé au hasard
        select id into c from public.rc_cards where saga = 'da' order by random() limit 1;
      elsif k = 'pk' then$b$),
      -- réglage en direct 'da'
      ('public.rc__live()',
       $a$'pk', public.rc__cfg('pk', 0.15),$a$,
       $b$'pk', public.rc__cfg('pk', 0.15), 'da', public.rc__cfg('da', 0.15),$b$),
      ('public.rc_admin_set_live(text,text,text)',
       $a$'fullart', 'pk') then$a$,
       $b$'fullart', 'pk', 'da') then$b$),
      ('public.rc_admin_x(text,text,text,text)',
       $a$'fullart', 'pk', 'mixte'$a$,
       $b$'fullart', 'pk', 'da', 'mixte'$b$),
      -- trophée « sagas » : les cartes da ne comptent pas comme cartes de saga
      ('public.rc__tn(text)',
       $a$cc.saga is not null and cc.saga <> 'pk')$a$,
       $b$cc.saga is not null and cc.saga not in ('pk', 'da'))$b$),
      -- fiche joueur de l'admin : nombre de cartes da
      ('public.rc__adm_player(text)',
       $a$    'pk', (select count(distinct card) from rc_owned where device = v.device and card like 'pk\_%'),$a$,
       $b$    'pk', (select count(distinct card) from rc_owned where device = v.device and card like 'pk\_%'),
    'da', (select count(distinct card) from rc_owned where device = v.device and card like 'da\_%'),$b$)
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

-- 5) réglage par défaut (garde une valeur déjà posée par l'admin)
update public.rc_config set value = jsonb_build_object('da', 0.15) || value where key = 'live' and not (value ? 'da');

notify pgrst, 'reload schema';

-- contrôles : 80 cartes dont 13 en rareté 4, et aucune ligne « introuvable » dans les notices ci-dessus
select count(*) as cartes, count(*) filter (where rarity = 4) as rarete_4 from public.rc_cards where saga = 'da';
