-- 29/10/2026 : 4 nouvelles sagas (Crash Bandicoot, Donkey Kong, Mortal Kombat, Final Fantasy)
-- 10 cartes holo chacune, copies des cartes d'origine (rareté 3, album sg_<saga>). Relançable.

insert into public.rc_cards
select (jsonb_populate_record(null::public.rc_cards,
          to_jsonb(b) || jsonb_build_object(
            'id', 'sg_' || x.saga || '_' || lpad(x.n::text, 2, '0'),
            'sys', 'sg_' || x.saga, 'num', x.n, 'n', x.n,
            'rarity', 3, 'saga', x.saga, 'base', b.id))).*
  from (values
    ('crash', 1, 'psx_024'),
    ('crash', 2, 'psx_025'),
    ('crash', 3, 'psx_026'),
    ('crash', 4, 'psx_028'),
    ('crash', 5, 'gba_016'),
    ('crash', 6, 'gba_015'),
    ('crash', 7, 'ps2_009'),
    ('crash', 8, 'gamecube_014'),
    ('crash', 9, 'xbox_010'),
    ('crash', 10, 'psp_008'),
    ('dk', 1, 'colecovision_010'),
    ('dk', 2, 'atari7800_015'),
    ('dk', 3, 'nes_020'),
    ('dk', 4, 'snes_010'),
    ('dk', 5, 'snes_011'),
    ('dk', 6, 'gb_026'),
    ('dk', 7, 'n64_021'),
    ('dk', 8, 'gba_057'),
    ('dk', 9, 'wii_016'),
    ('dk', 10, 'wiiu_007'),
    ('mk', 1, 'mastersystem_052'),
    ('mk', 2, 'megadrive_052'),
    ('mk', 3, 'snes_040'),
    ('mk', 4, 'gb_059'),
    ('mk', 5, 'gamegear_058'),
    ('mk', 6, 'snes_097'),
    ('mk', 7, 'n64_049'),
    ('mk', 8, 'dreamcast_024'),
    ('mk', 9, 'psp_055'),
    ('mk', 10, 'wii_053'),
    ('ff', 1, 'psx_038'),
    ('ff', 2, 'psx_039'),
    ('ff', 3, 'psx_037'),
    ('ff', 4, 'gba_034'),
    ('ff', 5, 'gba_032'),
    ('ff', 6, 'ps2_015'),
    ('ff', 7, 'gamecube_029'),
    ('ff', 8, 'psp_010'),
    ('ff', 9, 'psp_015'),
    ('ff', 10, 'wii_020')
  ) as x(saga, n, base)
  join public.rc_cards b on b.id = x.base
on conflict (id) do nothing;

-- Trophée « Sagas » : or = les 12 sagas (au lieu de 8)
create or replace function public.rc__tpool()
 returns table(kind text, t1 integer, t2 integer, t3 integer, ord integer)
 language sql
 immutable
as $function$
  -- trophées à 3 paliers (bronze, argent, or) ; textes et icônes dans lib/trophies.dart
  values ('packs', 25, 100, 500, 1), ('cards', 100, 400, 1000, 2), ('consoles', 1, 5, 29, 3),
         ('legend', 1, 10, 50, 4), ('fullart', 1, 10, 30, 5), ('fuse', 5, 25, 100, 6),
         ('wins', 10, 50, 200, 7), ('gifts', 10, 50, 200, 8), ('sales', 5, 25, 100, 9),
         ('trades', 5, 25, 100, 10), ('gamedle', 10, 50, 200, 11), ('chest', 1, 5, 20, 12),
         ('sagas', 1, 3, 12, 13), ('days', 7, 30, 100, 14), ('epics', 10, 50, 200, 15), ('holo', 10, 50, 200, 16),
         ('gold', 5, 25, 100, 17), ('recycle', 50, 250, 1000, 18), ('quiz', 50, 250, 1000, 19), ('played', 20, 100, 400, 20),
         ('defis', 10, 50, 200, 21), ('premium', 5, 25, 100, 22), ('buys', 5, 25, 100, 23), ('firsttry', 1, 5, 20, 24),
         ('tourney', 1, 3, 10, 25) $function$;
alter function public.rc__tpool() owner to rc_owner;

notify pgrst, 'reload schema';

-- contrôle : 10 cartes par saga
select sys, count(*) from public.rc_cards where sys in ('sg_crash','sg_dk','sg_mk','sg_ff') group by sys order by sys;
