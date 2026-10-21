# Pixel Trade (retro_collec_app)

Jeu de cartes à collectionner (jaquettes rétro) en **Flutter + Supabase**, par foclabroc.
Web : https://foclabroc.github.io/retro_collec_app/

## Règles de travail (obligatoires)

- Répondre **en français**, court et direct.
- **Ne jamais pousser sans accord** : montrer les changements, commit en local, pousser seulement après « pousse ».
- **SQL avant le code** : donner le fichier SQL d'abord, l'utilisateur le lance dans le SQL Editor de Supabase, puis il dit « pousse ».
- Fichiers SQL **relançables** (`create or replace`, `if not exists`), rangés dans `sql/AAAA-MM-JJ_sujet.sql`.
- **Nouvelle table (depuis le 30/10/2026)** : Supabase ne donne plus l'accès API automatiquement. Une table lue seulement par les RPC `security definer` n'a besoin d'aucun `GRANT` ; une table lue directement en REST par l'appli → `grant select (colonnes…) on public.t to anon;` colonne par colonne, **jamais `device`**.
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
- Défis de la semaine : réservoir `rc__wpool` (id, type, objectif, récompense ; ne pas renuméroter), 6 tirés chaque lundi par `rc__wsel` (mêmes pour tous), suivis par `rc__wbump(device, type, n)`. Types : open, gift, trade, win, gamedle, epic, play, new, quiz, sale, free, premium (texte et icône dans `defis.dart`).
- Trophées : paliers dans `rc__tpool` (bronze / argent / or), compteurs `rc_trophy_n` (via `rc__tbump`, branché dans `rc__give`, `rc__wbump`, `rc_fuse`, `rc_trade_answer`, `rc_week_claim`), paquets / cartes / consoles lus en direct (`rc__tn`), paliers récupérés `rc_trophy_got`, vitrine choisie `rc_players.trophies` (« wins,,cards »), cases vides remplies par les meilleurs paliers (`rc__tshow_k`), envoyée avec les paliers par `rc__tshow` (`rc_board`, `rc_profile`). Textes et icônes : `lib/trophies.dart`.
- Cadeau de passage de version : `rc_upgrade_got` (device, ver), versé dans `rc_trophies` (seule la 1.0.13+ l'appelle) ; pour une prochaine version, appeler la même logique depuis une fonction que seule la nouvelle version utilise.
- Journal d'activité (admin) : table `rc_activity` (30 jours, sans le chat), remplie **uniquement par déclencheurs** (`rc__act_*` sur `rc_players`, `rc_pending`, `rc_market`, `rc_trades`, `rc_gifts`, `rc_c4` / `rc_bs`, `rc_gamedle`, `rc_*_got`, `rc_milestones`, `rc_trophy_n`) via `rc__act` : une ligne par joueur et par transaction (libellé le plus précis gagne, deux actions connues = deux lignes), avec ± pièces / pixels ; mouvement inconnu = `coins`. Lecture : `rc_admin_activity` (groupe, pseudo, pagination par id). Page `AdminActivityPage` dans `admin_tools.dart`. Nouvelle action à journaliser : ajouter un déclencheur, pas toucher aux fonctions du jeu.
- Bourse, achat groupé : `rc_market_buy_many(device, "card:f:prixmax,…", sig)` (30 max, offre la moins chère, cartes vendues / plus chères / trop chères passées) → `rc__market_buy1` (même logique que `rc_market_buy`, sans signature : à garder synchronisées). Côté appli : mode « ☑ Plusieurs » / appui long dans `MarketGroupsState` (`picks`, `_pickBar`).
- Sagas (6) : Mario, Sonic, Zelda, Pokémon, Resident Evil (`re`), Castlevania. Définies dans `kSagas` (`catalog.dart` : 10 cartes d'origine + 3 de l'affiche + couleurs), logo `assets/sagas/<id>.webp`, cartes serveur `sg_<id>_NN` (rareté 3, `saga` = id) ajoutées par copie de la carte d'origine (voir `sql/2026-10-20_sagas_re_castlevania.sql` pour en ajouter une).
- Charge serveur (Supabase t4g.nano, Irlande : CPU à crédits → pics de 1–2 s si sollicité en continu) : `rc_me(device, sig, p_have)` renvoie `owned` seulement si son md5 (`oh`) diffère de `p_have` (`Game.ownedHash`, remis à null dès qu'une autre réponse fournit `owned` sans `oh`). Vérifications coupées quand l'appli est en arrière-plan / onglet caché (`HomeShellState._away`), `DuelWatch` toutes les 20 s au repos (10 s si partie / défi / page de duel). Mesurer avec `pg_stat_statements` avant d'optimiser.
- **En ligne** = `seen_at` de moins de **75 s** (`rc_board`, `rc_find`, `rc_profile`, `rc_c4_online`, `rc_bs_online`) ; `seen_at` mis à jour par `rc_duel_ping` (toutes les 10-20 s au premier plan, mais réécrit seulement s'il date de plus de 30 s : garder « 30 s + intervalle du ping » sous 75 s). Défi en direct refusé si l'autre n'a pas été vu depuis 2 min (`rc_c4_invite` / `rc_bs_invite`, plus large exprès). `rc_duel_ping` renvoie aussi `online` (nombre) → `DuelWatch.online` → compteur du menu (`OnlineMenuTile`). `rc_board` renvoie aussi `busy` (duel en direct en cours, même règle que les salons) → `FloorData.busy` : « ⚔ En partie » dans la liste En ligne (Défier grisé), IN GAME sur la borne.
- **Realtime (duels)** : triggers `rc_c4_rt` / `rc_bs_rt` → `rc__rt_duel` → `realtime.send({game, gid, status}, 'duel', rc__rt_topic(device), false)` vers p1 et p2 (canal public `rc_` + sha256('rt|' + device)[0..24], tiré du device **secret**, jamais du pid ; clé `gid` et pas `id`, que `realtime.send` prendrait pour l'id du message). Côté appli `live_link.dart` (`LiveLink.i`, WebSocket Phoenix, heartbeat 25 s, reconnexion 2→30 s, démarré / coupé avec `DuelWatch`). Sur message : `DuelWatch.refresh`, salon `_load`, page de partie `_refresh`. `LiveLink.connected` = abonnement accepté **et** un message déjà reçu ; alors polling de secours ralenti (salon 12 s, partie ×5 : 10 s direct / 30 s tour par tour), sinon rythme normal. Realtime gratuit : 200 clients simultanés max. Dans le connecteur MCP, éviter `drop trigger` (bloqué) : utiliser `create or replace trigger`.
- Voisinage : joueurs vus dans les **7 derniers jours** (`rc_board`, `rc_rank`, `rc_my_floor`). Le champ `house` d'un joueur = numéro de son habillage de borne (index de `kFloorThemes` dans `arcade.dart`, ne pas réordonner).

## Fichiers Flutter (lib/)

- `main.dart` : coque, menu latéral, onglets (0 Collection, 1 Paquets, 2 Bonus, 3 Bourse, 4 Messages, 5 Voisinage, 6 Actu, 7 Défis), `TabHeader` (pièces / pixels cliquables → Paquets), bandeau d'info.
- `game.dart` : état du joueur, constantes, prix (`kPackPrice`, `kPackBase`, `kPackPromo`, `lotPrice`), `applyLive`, `rcLive`.
- Avatars (dans `game.dart`) : 30 images `assets/avatars/avatar_NN.webp` 256 × 256 détourées (fond transparent), liseré = `kAvatars` (ne pas réordonner). `avatarWidget` (rond, fond blanc, partout), `AvatarFloat` (sans fond, flotte : écran des bornes), `AvatarPulseSquare` (carré dégradé aléatoire qui pulse : profils).
- `server.dart` : tous les appels RPC.
- `retro_theme.dart` : 13 thèmes de fond (`kThemes`, `RcMotif`) en couleurs sourdes (réglage du 21/10 : couleur 90 %, luminosité 76 %, motifs à 60 % via `_kMotif`). Animés : Envahisseurs, Menthe (`kAnimatedMotifs`) et Mur de cartes (`CardWall` : 36 jaquettes du joueur, complétées au hasard, mur incliné qui glisse en diagonale sous un voile du dégradé). Les 10 autres sont fixes (dessinés seulement au changement de thème). `bg` = `surface` (fond foncé des feuilles et dialogues). Ne pas proposer de flou derrière les panneaux (54 usages de `kPanel`, coûteux sur les thèmes animés).
- Bornes du Voisinage : `assets/arcade/<id>.webp` en 360 × 594, fond transparent, écran noir à la même place sur toutes (zone écran / fronton dans `arcade.dart`). Générées avec Gemini en retouchant la borne « pierre » (une image par discussion).
- `packs.dart` : onglet Paquets (mosaïque : stock, paquet gratuit, boutique, lot), ouverture animée, cadeaux. Bouton « Cadeau suivant / Déchirer le suivant / Ouvrir un autre » protégé contre le double appui (`_againBusy`).
- `cards.dart` (rendu `CardView`), `catalog.dart` (catalogue, sagas), `sagas.dart`, `library.dart` / `album.dart` (Collection).
- `market.dart` / `bourse.dart` (Bourse), `trades.dart`.
- `arcade.dart` (Voisinage « Pixel Arcade » : `ArcadeCabinet` (effets de lumière des bornes en ligne : une animation de 6 s par borne, `_lit`), habillages `kFloorThemes` → `assets/arcade/*.webp`, `FloorData`, page d'habillage, fond `ArcadeCarpet` « salle d'arcade la nuit » : mur teinté par `surface` + lueur `line`, néon `accent2` à 58 % de la hauteur, damier en perspective), `neighbors.dart` (salle : podium + rangées de 3), `profile.dart`, `house.dart`.
- Vitrine du profil (`profile.dart`) : `showcaseGrid` / `showcaseCardW`, cartes de 150 px max, 3 par ligne sur téléphone, les 6 sur une ligne en grand écran.
- `connect4.dart`, `battleship.dart` (Console Wars), `duel_watch.dart`, `duel_msg.dart`, `live_link.dart` (Realtime).
- `trophies.dart` (trophées : `MyTrophies` au profil (vitrine + liste complète dans un déroulant `open`), `OtherTrophies`, `TrophyMedal`, `myTrophyShow` pour la borne).
- `events.dart` (événements, effets, défis à paliers), `defis.dart` (défis de la semaine), `rewards.dart` (récompenses + éditeur admin).
- `admin.dart` + `admin_tools.dart` : page admin (Comptes (« vus aujourd'hui » triés du dernier vu), Journal (`_FeedTab` : activité de tous les joueurs via `rc_admin_feed(before)`, 150 lignes par page, mêmes textes que la fiche joueur via `_adminEvent`, une ligne par action vue de l'initiateur, cadeaux du jeu (sans donneur) vus du receveur), Liens, Stats cliquables, Chat, Outils : courrier / cadeau ciblé, sondage, événements, bandeau, maintenance, réglages en direct, version minimale, Bourse, recherche de carte, activité des joueurs, journal admin).
- `audio.dart` (`RcAudio`) : musique et bruitages ; réglage `rc_track2` = n° de morceau, -1 aléatoire, -2 aucune (`homeTrackNone` bloque toute musique, bruitages gardés).
- `inbox.dart` (courrier / sondage à l'ouverture), `update_check.dart` (mise à jour, version minimale, maintenance), `notifs.dart`, `push.dart`.

## À faire

1. Thèmes : refaits le 21/10 (13 thèmes). Attendre le retour de l'utilisateur après test web. (Opacité : essais à 93 % / 100 % refusés, ne pas reproposer.)
2. Nouveau mini-jeu à 2 joueurs, en direct et en tour par tour asynchrone (comme 4 en ligne / Console Wars). Jeu à choisir.
