-- ═══════════════════════════════════════════════════════════════════════════
-- Pixel Trade : valeurs de recyclage baissées (23/10/2026). Relançable.
-- Avant : 5 / 15 / 50 / 150 / 500 → un paquet mixte recyclé valait ≈ 135 pièces pour 100 payées
-- (boucle acheter → recycler gagnante une fois la collection presque complète).
-- Après : 2 / 5 / 20 / 60 / 200 (× 3 brillante, × 10 dorée, × 30 full art inchangés) → ≈ 55 pièces.
-- Utilisé par rc_recycle, rc_recycle_dupes, rc__items_value (valeurs admin), rc_admin_links.
-- Lancement : psql -U postgres -d postgres -f 2026-10-23_recyclage.sql
-- ═══════════════════════════════════════════════════════════════════════════
begin;

CREATE OR REPLACE FUNCTION public.rc__recycle_value(r integer, f integer)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select (array[2, 5, 20, 60, 200])[r + 1] * (array[1, 3, 10, 30])[least(greatest(f, 0), 3) + 1] $function$;

commit;
