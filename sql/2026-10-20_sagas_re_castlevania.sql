-- ═══════════════════════════════════════════════════════════════════════════
-- PIXEL TRADE — 2 nouvelles sagas : Resident Evil et Castlevania   (relançable)
-- Comme Mario / Sonic / Zelda / Pokémon : 10 cartes holo chacune, copies des
-- cartes d'origine (même jaquette), rangées dans l'album sg_<saga>, rareté 3.
-- Les cartes de saga sortent toujours à 3,2 % par carte de paquet (rc__saga_roll),
-- réparties entre les 60 cartes de saga.
-- ═══════════════════════════════════════════════════════════════════════════

insert into public.rc_cards
select (jsonb_populate_record(null::public.rc_cards,
          to_jsonb(b) || jsonb_build_object(
            'id', 'sg_' || x.saga || '_' || lpad(x.n::text, 2, '0'),
            'sys', 'sg_' || x.saga, 'num', x.n, 'n', x.n,
            'rarity', 3, 'saga', x.saga, 'base', b.id))).*
  from (values
    ('re', 1, 'psx_064'), ('re', 2, 'psx_065'), ('re', 3, 'psx_066'), ('re', 4, 'n64_065'), ('re', 5, 'gbc_071'),
    ('re', 6, 'gamecube_073'), ('re', 7, 'gamecube_067'), ('re', 8, 'gamecube_071'), ('re', 9, 'ps2_038'), ('re', 10, 'switch_067'),
    ('castlevania', 1, 'nes_013'), ('castlevania', 2, 'nes_014'), ('castlevania', 3, 'nes_015'), ('castlevania', 4, 'snes_069'),
    ('castlevania', 5, 'megadrive_009'), ('castlevania', 6, 'psx_020'), ('castlevania', 7, 'n64_011'), ('castlevania', 8, 'gba_014'),
    ('castlevania', 9, 'gba_013'), ('castlevania', 10, 'ps2_008')
  ) as x(saga, n, base)
  join public.rc_cards b on b.id = x.base
on conflict (id) do nothing;

-- contrôle : doit afficher 2 lignes à 10
select saga, count(*) from public.rc_cards where saga in ('re', 'castlevania') group by saga;
