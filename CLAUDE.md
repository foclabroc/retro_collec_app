# Pixel Trade (retro_collec_app)

Jeu de cartes à collectionner (jaquettes rétro) en **Flutter + Supabase**, par foclabroc.
Web : https://foclabroc.github.io/retro_collec_app/

## Règles de travail (obligatoires)

- Répondre **en français**, court et direct.
- **Ne jamais pousser sans accord** : montrer les changements, commit en local, pousser seulement après « pousse ».
- **SQL avant le code** : donner le fichier SQL d'abord, l'utilisateur le lance dans le SQL Editor de Supabase, puis il dit « pousse ».
- Fichiers SQL **relançables** (`create or replace`, `if not exists`), rangés dans `sql/AAAA-MM-JJ_sujet.sql`.
- **Maquette HTML : toujours demander d'abord** (« je te fais une maquette ? »), ne jamais en lancer une sans accord. Pour une petite retouche, coder directement.
- **Économiser** : réponses courtes, ne lire que les parties utiles des fichiers, pas de gros affichages inutiles. Une conversation par chantier.
- Ne jamais commiter la clé de signature (keystore, `key.properties`) : elle est dans le secret GitHub `DEBUG_KEYSTORE_B64`.
- Commits terminés par les lignes `Co-Authored-By` / `Claude-Session`.
- **Après chaque push réussi : mettre à jour ce `CLAUDE.md`** (« À faire », carte des fichiers, règles) pour qu'il reste juste.

## Compiler et publier

- Pas de Flutter dans le sandbox : syntaxe vérifiable avec `tree-sitter-language-pack` (Python), compilation réelle en poussant puis en suivant `web.yml` (`gh run list` / `gh run watch`).
- **Web** : `web.yml` se lance à chaque push sur `main` (GitHub Pages). Le service worker garde l'ancienne version : fermer/rouvrir l'onglet ou recharger 2 fois.
- **APK** : `apk.yml` à lancer à la main (Actions → APK Android → Run workflow, cocher « publier »). Avant : monter la version dans `lib/update_check.dart` (`kRetroCollecVersion`) **et** `pubspec.yaml` (`x.y.z+n`), sinon l'APK va dans l'ancienne release.
- Si un run reste bloqué « In progress » : le groupe de concurrence de `web.yml` est `pages-web`.

## Serveur (Supabase)

- Toutes les fonctions sont des RPC `security definer`, appelées avec une signature : `_sig('<device>|<payload>')`, sel `'rc-collec#7b2e-foc'`, vérifiée par `rc__check(p_sig, payload)`.
- Admin : signature `'<device>|admin|<payload>'` + compte dans `rc_admins` (par pid, modifiable seulement dans Supabase). Les actions admin sont notées dans `rc_admin_log`.
- Tables clés : `rc_players`, `rc_cards`, `rc_owned`, `rc_market`, `rc_trades`, `rc_gifts`, `rc_events` (+ `rc_events_prog`, `rc_events_got`), `rc_c4` / `rc_bs` (duels), `rc_chat`, `rc_config` (`min_version`, `live`, `banner`, `maintenance`), `rc_mail` (+ `rc_mail_to`, `rc_mail_got`), `rc_polls`, `rc_pending`, `rc_pack_log`, `rc_daily`.
- Code actuel des fonctions : `sql/schema/` (un fichier par fonction). **Le lire avant de modifier une fonction** ; le tenir à jour après chaque nouveau fichier SQL.
- Récompenses (événements, paliers, courrier) en JSON : `{"coins":500,"pixels":5,"lots":1,"packs":{"premium":1,"star":1},"cards":{"3":1}}` → `rc__grant` côté serveur, `lib/rewards.dart` côté appli. Paquets possibles : mixte, premium, mystery, star, gold (pas console : il faut choisir la console).
- Voisinage : joueurs vus dans les **7 derniers jours** (`rc_board`, `rc_rank`, `rc_my_floor`). Le champ `house` d'un joueur = numéro de son habillage de borne (index de `kFloorThemes` dans `arcade.dart`, ne pas réordonner).

## Fichiers Flutter (lib/)

- `main.dart` : coque, menu latéral, onglets (0 Collection, 1 Paquets, 2 Bonus, 3 Bourse, 4 Messages, 5 Voisinage, 6 Actu, 7 Défis), `TabHeader` (pièces / pixels cliquables → Paquets), bandeau d'info.
- `game.dart` : état du joueur, constantes, prix (`kPackPrice`, `kPackBase`, `kPackPromo`, `lotPrice`), `applyLive`, `rcLive`.
- `server.dart` : tous les appels RPC.
- Bornes du Voisinage : `assets/arcade/<id>.webp` en 360 × 594, fond transparent, écran noir à la même place sur toutes (zone écran / fronton dans `arcade.dart`). Générées avec Gemini en retouchant la borne « pierre » (une image par discussion).
- `packs.dart` : onglet Paquets (mosaïque : stock, paquet gratuit, boutique, lot), ouverture animée, cadeaux.
- `cards.dart` (rendu `CardView`), `catalog.dart` (catalogue, sagas), `sagas.dart`, `library.dart` / `album.dart` (Collection).
- `market.dart` / `bourse.dart` (Bourse), `trades.dart`.
- `arcade.dart` (Voisinage « Pixel Arcade » : `ArcadeCabinet`, habillages `kFloorThemes` → `assets/arcade/*.webp`, `FloorData`, page d'habillage), `neighbors.dart` (salle : podium + rangées de 3), `profile.dart`, `house.dart`.
- `connect4.dart`, `battleship.dart` (Console Wars), `duel_watch.dart`, `duel_msg.dart`.
- `events.dart` (événements, effets, défis à paliers), `defis.dart` (défis de la semaine), `rewards.dart` (récompenses + éditeur admin).
- `admin.dart` + `admin_tools.dart` : page admin (Comptes, Liens, Stats cliquables, Chat, Outils : courrier / cadeau ciblé, sondage, événements, bandeau, maintenance, réglages en direct, version minimale, Bourse, recherche de carte, journal).
- `inbox.dart` (courrier / sondage à l'ouverture), `update_check.dart` (mise à jour, version minimale, maintenance), `notifs.dart`, `push.dart`.

## À faire

1. Avatars : refaire avec de nouveaux assets.
