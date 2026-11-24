-- 25/11/2026 : 7 nouvelles sagas (Mega Man, Tetris, Rayman, Pac-Man, Metroid, Disney, Star Wars)
-- 10 cartes holo chacune, copies des cartes d'origine (rarete 3, album sg_<saga>). Relancable. 100 % ASCII.

insert into public.rc_cards
select (jsonb_populate_record(null::public.rc_cards,
          to_jsonb(b) || jsonb_build_object(
            'id', 'sg_' || x.saga || '_' || lpad(x.n::text, 2, '0'),
            'sys', 'sg_' || x.saga, 'num', x.n, 'n', x.n,
            'rarity', 3, 'saga', x.saga, 'base', b.id))).*
  from (values
    ('megaman', 1, 'nes_053'),
    ('megaman', 2, 'nes_054'),
    ('megaman', 3, 'nes_055'),
    ('megaman', 4, 'gb_051'),
    ('megaman', 5, 'snes_035'),
    ('megaman', 6, 'megadrive_047'),
    ('megaman', 7, 'saturn_022'),
    ('megaman', 8, 'gba_062'),
    ('megaman', 9, 'psp_047'),
    ('megaman', 10, 'wii_050'),
    ('tetris', 1, 'gb_091'),
    ('tetris', 2, 'nes_090'),
    ('tetris', 3, 'gb_092'),
    ('tetris', 4, 'snes_090'),
    ('tetris', 5, 'n64_084'),
    ('tetris', 6, 'gbc_083'),
    ('tetris', 7, 'gba_094'),
    ('tetris', 8, 'wii_085'),
    ('tetris', 9, '3ds_060'),
    ('tetris', 10, 'switch_093'),
    ('rayman', 1, 'psx_063'),
    ('rayman', 2, 'n64_063'),
    ('rayman', 3, 'gbc_068'),
    ('rayman', 4, 'gba_081'),
    ('rayman', 5, 'gba_080'),
    ('rayman', 6, 'xbox_033'),
    ('rayman', 7, 'wii_069'),
    ('rayman', 8, 'wii_068'),
    ('rayman', 9, 'wiiu_026'),
    ('rayman', 10, '3ds_035'),
    ('pacman', 1, 'atari7800_031'),
    ('pacman', 2, 'atari2600_061'),
    ('pacman', 3, 'nes_064'),
    ('pacman', 4, 'gb_066'),
    ('pacman', 5, 'lynx_024'),
    ('pacman', 6, 'amiga1200_121'),
    ('pacman', 7, 'gbc_058'),
    ('pacman', 8, 'gba_070'),
    ('pacman', 9, 'gamecube_126'),
    ('pacman', 10, 'switch_049'),
    ('metroid', 1, 'nes_059'),
    ('metroid', 2, 'gb_056'),
    ('metroid', 3, 'snes_076'),
    ('metroid', 4, 'gba_068'),
    ('metroid', 5, 'gba_067'),
    ('metroid', 6, 'gamecube_050'),
    ('metroid', 7, 'gamecube_051'),
    ('metroid', 8, 'wii_052'),
    ('metroid', 9, '3ds_020'),
    ('metroid', 10, 'switch_036'),
    ('disney', 1, 'mastersystem_017'),
    ('disney', 2, 'nes_025'),
    ('disney', 3, 'nes_124'),
    ('disney', 4, 'megadrive_001'),
    ('disney', 5, 'megadrive_041'),
    ('disney', 6, 'snes_094'),
    ('disney', 7, 'gbc_094'),
    ('disney', 8, 'gba_047'),
    ('disney', 9, 'psp_035'),
    ('disney', 10, 'wii_015'),
    ('starwars', 1, 'atari2600_091'),
    ('starwars', 2, 'colecovision_042'),
    ('starwars', 3, 'snes_080'),
    ('starwars', 4, 'gamegear_082'),
    ('starwars', 5, 'n64_077'),
    ('starwars', 6, 'n64_075'),
    ('starwars', 7, 'gamecube_088'),
    ('starwars', 8, 'xbox_039'),
    ('starwars', 9, 'ps2_079'),
    ('starwars', 10, 'psp_039')
  ) as x(saga, n, base)
  join public.rc_cards b on b.id = x.base
on conflict (id) do nothing;

-- Trophees : Sagas (or = les 19 sagas) et Fan de sagas (or = 250 cartes de saga)
create or replace function public.rc__tpool()
 returns table(kind text, t1 integer, t2 integer, t3 integer, ord integer)
 language sql
 immutable
as $function$
  -- trophees a 3 paliers (bronze, argent, or) ; textes et icones dans lib/trophies.dart
  values ('packs', 25, 100, 500, 1), ('cards', 100, 400, 1000, 2), ('consoles', 1, 5, 29, 3),
         ('legend', 1, 10, 50, 4), ('fullart', 1, 10, 30, 5), ('fuse', 5, 25, 100, 6),
         ('wins', 10, 50, 200, 7), ('gifts', 10, 50, 200, 8), ('sales', 5, 25, 100, 9),
         ('trades', 5, 25, 100, 10), ('gamedle', 10, 50, 200, 11), ('chest', 1, 5, 20, 12),
         ('sagas', 1, 5, 19, 13), ('days', 7, 30, 100, 14), ('epics', 10, 50, 200, 15), ('holo', 10, 50, 200, 16),
         ('gold', 5, 25, 100, 17), ('recycle', 50, 250, 1000, 18), ('quiz', 50, 250, 1000, 19), ('played', 20, 100, 400, 20),
         ('defis', 10, 50, 200, 21), ('premium', 5, 25, 100, 22), ('buys', 5, 25, 100, 23), ('firsttry', 1, 5, 20, 24),
         ('tourney', 1, 3, 10, 25), ('pioche', 5, 30, 100, 26), ('express', 5, 30, 100, 27),
         ('wheel', 10, 50, 200, 28), ('pokemon', 10, 50, 185, 29),
         ('react', 10, 50, 200, 30), ('craft', 5, 25, 100, 31), ('sagacards', 25, 100, 250, 32),
         -- ajoutes le 7/11
         ('cartoon', 10, 40, 80, 33), ('dragonball', 50, 200, 556, 34), ('dbholo', 10, 50, 146, 35),
         ('sunday', 1, 4, 12, 36), ('podium', 1, 5, 20, 37), ('score', 1000, 5000, 15000, 38),
         ('boosters', 5, 25, 100, 39),
         -- ajoute le 24/11
         ('platine', 1, 5, 15, 40) $function$;

notify pgrst, 'reload schema';

-- controle : 70 cartes (10 par saga)
select saga, count(*) from public.rc_cards
 where saga in ('megaman', 'tetris', 'rayman', 'pacman', 'metroid', 'disney', 'starwars') group by saga order by saga;
