# Pixel Trade — Changelog

## v1.0.24
_Version 1.0.24+25. Pas de cadeau de version._

- 🤖 **Duel Rétro Jump en direct** (`sql/2026-10-27_duel_retro_jump.sql`, `lib/rj_engine.dart`, `lib/rj_duel.dart`) : 3e jeu de la Salle de jeux, en direct seulement. Même parcours pour les deux (graine du serveur, `RjRng` mulberry32 identique Android / JS / Wasm), monde fixe 360 × 640, sans bonus, 2 min, le plus haut gagne (gains du 4 en ligne). Fantôme de l'adversaire par le relais (`rjpos`, ≈ 10 / s, `LiveLink.play` / `sendPos` / `positions`), hauteur au serveur toutes les 2 s (`rc_rj_score`, plafond 70 pts/s), déconnexion = tombé après 20 s. Spectateurs, réactions, Actu, journal admin, « En partie » partout (`rc__duel_busy`). Défis seulement vers les appli qui connaissent le jeu (`rc_players.rj_ok`, `rc_duel_ping(…, p_rj)`). **Relais à mettre à jour** (`selfhost/rc-realtime/server.js`).

## v1.0.23
_Version 1.0.23+24._

- 🕹️ **Bornes jouables** (`sql/2026-10-27_bornes_jouables.sql`, `lib/cab_games.dart`) : chaque borne du Voisinage lance un mini-jeu choisi par son propriétaire (Snake, Casse-briques, Esquive) ; écran de la borne en mode démo (jeu + record de la semaine / avatar, 3 s chacun) ; page de la borne `CabinetPage` (jouer, records de la semaine, profil, stats si c'est la mienne) ; partie `CabPlayPage` (`MiniGameView`, 60 pas / s, 340 × 440 logiques) ; choix du jeu `MyCabGamePicker` dans « Ma borne : jeu et habillage ». Record battu = +20 pièces (1 fois par jour et par borne, pas la sienne) ; propriétaire +1 pièce par partie d'un autre (5 par joueur, 30 par jour) ; records remis à zéro le lundi et au changement de jeu ; score impossible pour la durée refusé. Temps réel : `me` {k: cabrec} (toast au propriétaire), `rc_all` `cab`.
- 🎨 7 habillages de borne (`assets/arcade/*.webp`, `sql/2026-10-27_bornes_habillages.sql` : `rc_set_house`) : Game Boy 1 300, Bonbons 1 400, Forêt enchantée 1 500, Pirate 1 600, Égypte 1 700, Cyberpunk 1 800, Noël 1 900 cartes.
- 🎁 Cadeau de version : 600 pièces + 1 booster premium (`sql/2026-10-27_cadeau_1023.sql`, comptes créés avant le 27/10 9 h).
- 🎮 4 consoles : Game Boy et Amiga 1200 (100 cartes), Lynx et Supervision (50 cartes) → 23 consoles, 1 900 cartes ; sagas Kirby et Street Fighter (`sql/2026-10-27_consoles_gb_amiga1200_lynx_supervision_sagas.sql`) ; trophées or : 23 consoles, 8 sagas.
- ★★ Collection : onglet Full art (`library.dart`, `fullArtCards`, `_FullArtSlot`) ; icône des sagas 📚.
- 🔒 Limite d'inscriptions / connexions par IP : IPv6 comptée par /64 (`sql/2026-10-27_ip_v6_64.sql`, `rc__ip_key`).
- 🛠 `setState` après `await` protégés par `mounted` (13 endroits).
- ⭐ Paquets premium (achetés ou reçus en cadeau) et paquet gratuit comptés dans les défis et le trophée Premium (`sql/2026-10-27_premium_defis.sql` : `rc_pending.gk`, `rc_pick`).
- 🃏 Cartes de récompense dans un stock « Cartes à ranger » (`sql/2026-10-27_stock_cartes.sql` : `rc_card_stock`, `rc_stock_list`, `rc_stock_take`, `rc__grant`, `rc_notifs.cards`) ; page `CardStockPage` (`packs.dart`).
- 🚀 Full art allégé (`cards.dart`) : prisme en un dessin, fond sans flou, capture réduite, couche en cache.
- ⚔ Défi accepté : `DuelWatch.watchOut` ouvre la partie hors du salon.
- 🔄 Échange : filtre « Qu'il n'a pas » ; `Game.i.sync()` sur les événements temps réel trade / sale / gift.

## v1.0.22
_Version 1.0.22+23._

- 🏅 Paliers de collection gagnés affichés dans le récapitulatif du paquet (`_milestones`, `packs.dart`).
- ♻️ **Recyclage rééquilibré** (`sql/2026-10-23_recyclage.sql`) : 2 / 5 / 20 / 60 / 200 pièces au lieu de 5 / 15 / 50 / 150 / 500
  (× 3 brillante, × 10 dorée, × 30 full art inchangés). Un paquet mixte recyclé valait ≈ 135 pièces pour 100 payées.
- ✨ Full art plus fréquentes : réglage en direct `fullart` = 3 % des épiques / légendaires (au lieu de 0,2 % : aucune n'était encore sortie). Valeur par défaut de l'appli (`rcLive`) et de l'admin passée à 3.

## v1.0.21
_Version 1.0.21+22._

- ⚡ **Déchirer et tout voir** : bouton sous le paquet à déchirer → toutes les cartes d'un coup (récapitulatif).
- 🏆 Tournois : fenêtre de félicitations pour le podium (lots, cagnotte), paquets des lots nommés « Tournoi X · … »
  (`sql/2026-10-22_tournois_suite.sql`), score des manches vu de son côté, plus de « Voir le plateau » en partie de tournoi.
- Pas de fenêtre de défi pendant l'ouverture d'un paquet ni pendant un match de tournoi (montrée juste après).
- Corrigé : case « Paquet entamé » fantôme (« Ouvrir un autre », réponses en retard, erreurs prises pour « déjà ouvert ») ;
  messages du chat affichés en double après un envoi.

## v1.0.20
_Version 1.0.20+21._

- 🏆 **Tournois** (Salle de jeux) : créés par l'admin (4 en ligne ou Console Wars, 4 / 8 / 16 places, inscription gratuite
  ou payante avec cagnotte 100 % ou 70 / 30, lots pour le 1er, le 2e et les demi-finalistes), arbre tiré au sort avec
  exemptés, matchs en direct (1 manche, finale en 2 manches gagnantes, nul rejoué), forfait après 3 min d'absence,
  arbre en direct avec matchs à regarder, podium, annonce dans l'Actu (`sql/2026-10-22_tournois.sql`).
- Fenêtre « Ton match commence ! », ouverture automatique de chaque partie, rappel 10 min avant le début.
- Trophée **Champion** (1 / 3 / 10 tournois gagnés), section Tournois dans le Guide.

## v1.0.19
_Version 1.0.19+20._

- 📖 **Guide du jeu** (menu latéral) : cartes, raretés, finitions, calcul du score, paquets, pièces et pixels, doublons,
  Bourse, échanges, cadeaux, duels, défis, trophées, voisinage, parrainage.
- **Temps réel instantané** : en ligne dès l'ouverture du jeu, hors ligne quelques secondes après la fermeture (présence tenue
  par le relais), événements sans attente, reconnexion plus rapide, moins de vérifications en arrière-plan.
- **Spectateurs visibles** (👁 N) et **réactions en direct** des spectateurs pendant les duels.
- **Voisinage → « Trouver mes cartes manquantes »** : voisins qui les ont en double, filtre par console, échange préparé.
- **Pseudos décorés** : emojis et symboles affichés (24 caractères) ; connexion et @mentions sur les lettres et chiffres.
- **Messages** : `@tous` de l'admin prévient tous les joueurs.
- **Sécurité** : 5 comptes par jour et par connexion, Bourse / cadeaux / échanges 24 h après la création d'un compte,
  cadeaux de version réservés aux comptes existants, blocage des connexions ratées par adresse, relais limité par adresse.
- **Web plus rapide** : WebAssembly, police intégrée, jaquettes gardées dans le cache du navigateur.
- Admin : courriers et cadeaux de l'admin dans le Journal.

## v1.0.18
_Version 1.0.18+19._

- 🎁 **Cadeau de mise à jour** : 600 pièces, 8 pixels et 1 booster premium (dans Paquets → Cadeaux reçus), une fois par joueur (`rc_upgrade_gift`).
- **5 nouvelles consoles** : 3DS, SG-1000, Dreamcast, Atari 7800 et Amiga CD32, 50 cartes chacune (1600 cartes, 19 séries),
  descriptions en français et en anglais ; trophée « Console complète » en 1 / 5 / 19.
- **Temps réel partout** : messages, notifications, échanges, ventes, Bourse, Actu, événements, défis, trophées, profils et
  collections ouverts, joueurs qui arrivent ou partent.
- **Mode spectateur** : regarder les duels en direct des autres (salon « À regarder », liste En ligne, borne IN GAME).
- **Onglet « Salle de jeux »** : 4 en ligne et Console Wars sortis de Bonus, bouton « Jeux en cours ».
- **Profil** : Ma borne / Thème / Musique en haut ; « Mes séries » en déroulant, « Ses séries » sur le profil des autres.

## v1.0.17
- Bascule sur le serveur maison (`api.foclabroc.duckdns.org`), message « Serveur indisponible » / « Pas de connexion au serveur ».

## v1.0.16
- Thème « Mur de cartes » par défaut, 13 thèmes plus doux, cadeau de mise à jour (500 pièces).

## v1.0.15
_Version 1.0.15+16._

- **Thèmes refaits** : 12 nouveaux fonds colorés (Envahisseurs, Blocs, Cerise, Mandarine, Lagon, Raisin, Citron,
  Menthe, Corail, Ciel, Bonbon, Rétro gris). Motif fixe ou animation lente ; les fonds fixes ne sont plus redessinés en continu.
- **Sagas Resident Evil et Castlevania** : 2 nouvelles sagas de cartes holo, avec leurs albums et logos dans la Collection.
- **Bourse : achat groupé** : sélection de plusieurs cartes et achat en une fois (`rc_market_buy_many`).
- **Bornes illuminées** au Voisinage : halo, fronton, écran qui pulse, reflet, lueur au sol.
- **Trophées** : tous dans un déroulant au profil (fermé par défaut, doré s'il y a des paliers à récupérer) ;
  trophée Sagas en 1 / 3 / 6 (or = les 6 sagas), paliers déjà gagnés conservés.
- **Serveur moins sollicité** : `rc_me` ne renvoie la collection que si elle a changé, vérifications coupées
  en arrière-plan / onglet caché, défis vérifiés toutes les 20 s au repos.
- **Admin** : journal d'activité des joueurs (Outils → Activité).
- **Joueurs en ligne** : en ligne = vu il y a moins de 75 s (au lieu de 10 min), compteur du menu mis à jour toutes les 10-20 s ;
  « ⚔ En partie » dans la liste et IN GAME sur la borne pendant un duel en direct (bouton Défier grisé) ;
  salon des duels rechargé si le joueur défié est parti.

## v1.0.14
_Version 1.0.14+15._

- **Pastille trophées** : une pastille sur le profil (menu) signale les paliers de trophées à récupérer.
- **Pièces et pixels des autres joueurs** de nouveau visibles : sous leur borne au Voisinage et en haut de leur profil.
- **Musique « Aucune »** (Profil → Musique) : coupe toute la musique, les bruitages restent. Le bouton son de l'écran titre suit le réglage son, plus la musique seule.

## v1.0.13
_Version 1.0.13+14._

- **Trophées** : 24 trophées à 3 paliers (bronze, argent, or) au profil : paquets, cartes, consoles et sagas complètes,
  jours de connexion, épiques, légendaires, brillantes, dorées, Full art, fusions, recyclage, duels joués et gagnés, cadeaux,
  ventes, achats, échanges, Gamedle (et du premier coup), quiz, défis de la semaine, coffres, paquets premium.
  Chaque palier se récupère (100, 300, puis 800 pièces + 3 pixels). 3 trophées en vitrine, visibles sur le profil
  et sous l'écran de la borne : les meilleurs automatiquement, ou ceux qu'on choisit. L'historique déjà joué est repris.
- **Défis de la semaine tournants** : chaque lundi, 6 défis tirés au hasard (les mêmes pour tous) parmi 12 :
  paquets, cadeaux (remplace le recyclage), échanges, duels gagnés, Gamedle, épique, duels joués, nouvelles cartes,
  quiz, ventes à la Bourse, paquet gratuit plusieurs jours, paquets premium.
- **Nouveaux avatars : 30 personnages de jeux vidéo** (Mario, Luigi, Peach, Bowser, Yoshi, Toad, Link, Samus, Kirby, Sonic, Tails,
  Fox, Donkey Kong, Lara Croft, Deadpool…), détourés (fond transparent). Ils remplacent les 18 anciens
  (les joueurs gardent leur numéro d'avatar, seule l'image change).
  Sur l'écran des bornes, l'avatar flotte sans fond (va-et-vient et légère bascule, plus calme si la borne est éteinte).
  Au profil, l'avatar passe dans un carré arrondi au dégradé de couleurs tiré au hasard, qui pulse.
- Cartes de saga : un nom trop long passe sur 2 lignes (police un peu réduite) au lieu d'être coupé.
- **Voisinage : la salle « Pixel Arcade »** remplace l'immeuble. Chaque joueur a sa borne d'arcade : pseudo sur le fronton,
  avatar et score à l'écran (allumé avec PLAYING qui clignote s'il est en ligne, OFFLINE sinon), pseudo qui défile s'il est trop long, 🎁 pour offrir un paquet, badge 1P sur la sienne.
  Podium pour les 3 premiers (projecteur sur le n°1), puis rangées de 3 bornes ; comptoir en bas (cadeaux, recherche).
- **16 habillages de borne** dessinés (pierre, brique, bois, lierre, néon, art déco, verre, château, japonais, arcade, spatial,
  sous-marin, plage, neige, Halloween, or), mêmes paliers de cartes que les anciens thèmes d'étage (rien à changer côté serveur).
- **4 en ligne : nouvelle grille** façon borne d'arcade : double cadre néon (cyan et rose), rivets, reflet vitré,
  pieds ; trous creusés ; pion fantôme translucide avec flèche dorée qui bouge et colonne surlignée en doré ;
  à la victoire, les 4 pions clignotent et un trait lumineux les relie.
- **Paquets : vue en mosaïque** (stock, paquet gratuit en grand, boutique en grille) ; les pièces et pixels du bandeau
  ouvrent la boutique / les boosters Pixels. Un paquet entamé (choix du booster quitté) reste dans le stock et se reprend
  d'un toucher ; plus d'erreur « aucun booster à choisir ».
- **Retour Android** : chaque appui ouvre ou ferme le panneau latéral.
- **Notifications Android** : icône du jeu (silhouette blanche dans la barre d'état, icône en couleur dans la notification).
- **Sagas** : cartes numérotées (#01…#10), sagas dans les filtres de console (Bourse, échanges) et dans les séries du profil.
- **Duels** : message quand l'adversaire répond à ton défi ; Entrée envoie le défi / la revanche.
- **Bourse** : nouvelles ventes mises en avant dans « Vendre » (pastille rouge) ; sur PC / écran large, acheter une carte
  ne ferme plus l'écran principal.
- **Profil** : dernière connexion connue (au jour près) quand l'heure exacte manque.
- **Web** : la musique repart bien du début à la fin du morceau.
- **Voisinage** : bouton cadeau des bornes en icône ; sur le web, moquette qui ne déborde plus sur le menu et projecteur du
  podium en faisceau flou.
- **Page admin** (réservée aux admins) : comptes, liens suspects, stats cliquables, chat signalé, courrier et cadeau ciblé,
  sondage, événements, bandeau, maintenance, réglages en direct, version minimale, offres de la Bourse, recherche de carte, journal.

## v1.0.12
_Version 1.0.12+13._

- **Duels : messages** — un petit mot avec un défi ou une revanche (phrase toute faite ou texte de 60 caractères,
  filtré comme le chat), affiché dans la fenêtre « X te défie ! » et dans le salon ; réponses rapides de l'invité
  (« J'arrive ! », « Dans 5 minutes »…, ou texte), vues par celui qui attend. SQL : patch_duels_messages.sql.
- **Duels : réactions en grand** au milieu du plateau avec le nom, boutons plus gros, phrases rapides en partie
  (« Bien joué ! », « Oups 😅 », « GG 🤝 », « Pas mal ! »).
- **4 en ligne** : les pions posés remplissent tout le trou (avant : trop petits), pion fantôme plus grand.
- **Bonus / Jeux** : pastilles qui pulsent (à toi de jouer, invitations, tour de roue), halo rouge, cases mises à jour en direct.
- **Menu** plus compact (tout tient sur un écran) ; **Collection** : tableau de bord replié par défaut, flèche pour le déplier.

## v1.0.11
_Version 1.0.11+12._

- **Sagas** (Collection : sélecteur « 🎮 Consoles | 🌈 Sagas ») : Mario, Sonic, Zelda et Pokémon, 10 cartes chacune.
  Une carte de saga est une version holographique (cadre arc-en-ciel qui tourne, halo de la couleur de la saga, logo,
  reflet holo qui suit le doigt, numéro) d'une carte existante ; elle va uniquement dans l'album de sa saga. Chaque
  carte tirée dans un paquet a 3,2 % de chance d'être une carte de saga (aussi rare qu'une épique). Ni fabrication ni
  fusion. Affiches animées (logo, éventail des 3 meilleures cartes). Paliers : 5/10 → 100 pièces, 10/10 → 500 pièces
  + 2 pixels ; nouvelles « carte de saga » et « saga complète » dans les Actualités. SQL : patch_sagas.sql.
- **Profil d'un voisin** : rubriques « 🎯 Il a, tu n'as pas » (ses doubles d'abord, toucher = demander en échange) et
  « 🔁 Tu as, il n'a pas » (toucher = lui proposer la carte), avec « Tout voir » ; les séries deviennent « Vous deux,
  console par console » (ta barre et la sienne, la plus avancée en vert).
- **Actualités : réactions** 👏 🔥 😮 sous chaque nouvelle (une par joueur, toucher la même l'enlève). Pastille sur
  Actualités quand d'autres joueurs réagissent à tes exploits. SQL : patch_social.sql.
- **Parrainage** (case sous « Partager ») : ton code PT-XXXXXX, ajouté au message de partage ; le filleul l'entre à
  l'inscription ou pendant sa première semaine ; quand il a ouvert 5 paquets et joué 2 jours différents, vous recevez
  chacun un paquet premium dans le stock. 10 filleuls au plus. SQL : patch_social.sql.
- **Défis de la semaine** (nouvel onglet « Défis » dans le menu, sous Paquets) : 6 défis du lundi au dimanche (ouvrir
  10 paquets, recycler 30 doublons, 3 échanges/achats/ventes, gagner 2 duels qui rapportent, réussir 3 Gamedle,
  obtenir une carte épique ou mieux). Bouton « Récupérer 150 🪙 » quand un défi est fini, pastille dans le menu.
  Les 6 récupérés : coffre de 500 pièces + 2 pixels + 1 paquet premium dans le stock. Remplacent les missions du jour
  (retirées de l'onglet Paquets). SQL : patch_defis_semaine.sql.
- **Voisinage** : la tour n'affiche plus les joueurs absents depuis plus de 7 jours (ils reviennent dès qu'ils se
  reconnectent).
- **Collection** : les affiches des consoles sont animées (rayons qui tournent, console qui flotte, lueur, reflet,
  bandeau, barre qui se remplit, étoiles sur les séries complètes) et n'ont plus la trame de points.
- **Titres des onglets** : majuscules pixel blanches avec un halo et un soulignement de la couleur du thème, et l'icône
  de l'onglet dans une pastille lumineuse (sur les écrans assez larges). Le titre rétrécit si la place manque : pièces
  et pixels gardent toujours leur taille.
- **Partager ce jeu à tes amis** : case en bas du panneau latéral (sous Joueurs en ligne). Sur Android, ouvre la fenêtre
  de partage du téléphone (SMS, WhatsApp, Messenger…) avec le lien du dernier APK et celui de la version web de test,
  plus ton pseudo ; sur le web, le texte est copié pour le coller dans un message.
- **Vitrine** : un « + » dans chaque case vide ouvre mes cartes, de la plus rare à la moins rare (dans leur meilleure
  finition) pour en ajouter une ; maintenir une carte puis la faire glisser sur une autre case change l'ordre.
- **Bourse, autres onglets revus** dans le style du magasin :
  - Vendre : « En vente » en grille (prix sur la carte, bouton rouge « Retirer » sous chaque carte, avec confirmation)
    et « Vendues récemment » à part (tampon VENDUE, acheteur, total sur 7 jours) ; recherche dans le choix des cartes.
  - Échanges : pastilles Reçus / Envoyés / Terminés, échanges en cartes compactes (tu donnes ⇄ tu reçois, écart de
    valeur, Détail / Refuser / Accepter).
  - Historique : bilan total (gagné, dépensé, échanges), pastilles Tout / Ventes / Achats / Échanges, regroupé par
    jour, « Voir plus » par pages de 50 (SQL : rc_history_page dans patch_bourse_magasin.sql).
- **Bourse, nouveau magasin** : recherche par nom, filtres en pastilles (Manquantes d'un toucher ; console, rareté,
  finition et tri dans une fenêtre), rubriques « 🎯 Il te manque », « 💰 Bonnes affaires » (au moins 20 % sous le prix
  moyen payé sur 30 jours) et « 🔥 Nouveautés » (du jour), puis la grille de toutes les cartes en vente avec le prix
  sur chaque carte et le nombre d'offres. SQL : patch_bourse_magasin.sql.
- **Bourse** : dans la liste des offres d'une carte, la carte s'affiche en entier (image et titre) même quand on ne l'a pas,
  dans la finition de l'offre la moins chère (avant : silhouette grise et « #023 »).
- **Bourse** : toucher la carte dans la liste des offres l'ouvre en grand (on peut la faire tourner au doigt).
- **Full art comptées** : nouveau raccourci « ★★ full art » dans Collection (ouvre la liste filtrée) et case « full art »
  dans les statistiques, à côté des brillantes et des dorées.
- Titres pixel restants sans majuscules accentuées (fin de partie du 4 en ligne « DEFAITE », intertitres des événements).

## v1.0.10
- **4 en ligne et Console Wars gratuits** : plus de mise. Le gagnant gagne 150 pièces + 1 pixel, le perdant 10 pièces
  de consolation (match nul au 4 en ligne : 10 chacun). On peut défier tout le monde, même sans pièces.
  Anti-triche : gains seulement contre un joueur inscrit depuis au moins un jour, et 4 parties payées par jour
  contre le même adversaire ; au-delà, partie amicale (sans gains).
  Le joueur est prévenu avant de jouer : « 🤝 Amicale » dans la liste des joueurs avec la raison, confirmation avant
  d'envoyer le défi, et rappel dans la fenêtre d'attente, la fenêtre de défi reçu et pendant la partie.
  SQL : patch_duels_gratuits.sql.
- **Joueurs en ligne dans le menu** : une case « 🟢 Joueurs en ligne · N » en bas du panneau latéral ouvre la liste
  des connectés (Défier, Étage).
- **Ordre des consoles** : menu déroulant à côté de « Mes consoles » (les plus complètes, les moins complètes,
  les plus anciennes, les plus récentes, nom, ordre habituel), mémorisé.
- **Accents dans les titres en police pixel** : « ÉVÉNEMENTS » s'affichait « éVéNEMENTS » (la police n'a pas de
  majuscules accentuées) ; les titres pixel passent sans accent sur les majuscules.
- **Écran de connexion** : au premier lancement, « CONNEXION » (pseudo + mot de passe, ou code de sauvegarde),
  et en dessous « NOUVEAU JOUEUR » pour créer son profil (pseudo, mot de passe, avatar).
- **Nouvelle icône**, plus visible : trois boosters (rouge, or, vert) en éventail et le logo PIXEL TRADE de l'écran titre, sur fond bleu vif.
- **Game Boy Color** : la carte de la console montrait une Game Boy classique, c'est maintenant une vraie Game Boy Color.
- **Cartes Full Art** (nouvelle finition, épiques et légendaires seulement) : 0,2 % de chance sur chaque épique
  ou légendaire tirée. L'écran du jeu en décor, la jaquette dans un cadre doré à sa forme (large, carrée, haute),
  plaque gravée avec le titre ; fixe, seul le brillant (prisme, or) suit l'inclinaison. Compte 6× au classement
  (le double d'une dorée), recyclage 30×. Filtre « Full art ★★ » dans les cartes, actu « X a obtenu Y en full art ».
  SQL : patch_fullart.sql (à lancer après la sortie de l'APK).
- **Actualités enrichies** : victoires et matchs nuls au 4 en ligne et à Console Wars (avec la mise et l'abandon),
  échanges conclus (avec la plus belle carte), ventes de la Bourse (épique ou mieux), paquets offerts, nouveaux joueurs,
  séries de connexion (7, 30, 100, 365 jours), paquets ouverts (100e, 250e, 500e…), séries à 50 %.
  Filtres (Tout, Duels, Cartes, Échanges, Joueurs), intertitres Aujourd'hui / Hier, deux avatars pour les duels.
  SQL : patch_actu_plus.sql.
- **Son** : un seul bouton 🔊 (écran titre, profil, 4 en ligne) coupe ou remet la musique et les bruitages ensemble,
  et le réglage est gardé au redémarrage de l'appli (avant, les bruitages se rallumaient).

## v1.0.9
- **Étages de la Pixel Tower revus** : le rang à gauche (médailles or, argent, bronze pour le podium) au lieu du numéro
  d'étage, plus d'ascenseur ni de fenêtre de droite : la plaque prend toute la largeur et le pseudo s'affiche en entier
  (il rétrécit s'il est très long). « En ligne » ou « vu 02:19 » sur le balcon, sous l'avatar. Plaque sur 3 lignes :
  pseudo · points, % de collection et sa barre · cartes et pièces. Bouton « 🎁 Offrir » (« Offert ✓ » après).
- **Événements, nouveau look** : l'événement phare en grande affiche (émoji animé, décor, compte à rebours, bouton
  « Récupérer » qui brille), frise des 14 prochains jours, une carte par événement avec son étiquette (cadeau, effet, défi),
  défis en piste avec des coffres à ouvrir, terminés réduits à une ligne.
  Chaque événement a son décor animé, réglable depuis le serveur : l'émoji (chauves-souris, flocons, ballons, pixels…)
  et son mouvement (traverse, chute, montée, pluie, feu d'artifice).
  Les 5 prochains événements sont toujours visibles en entier (titre, texte, récompense) avec leur compte à rebours
  à la seconde, mais verrouillés (« 🔒 Disponible le 24/10 à 00:00 ») jusqu'à leur début.
- **Nouveaux thèmes** : 10 thèmes plus épurés remplacent les 15 anciens (Minuit, Arcade, Game Boy, Océan, Or, Couchant,
  Forêt, Ardoise, Prune, Néon). Fond en dégradé, lueur de la couleur du thème et motif discret qui défile lentement
  (étoiles, grille, vagues, lucioles…). Les boutons, barres et titres prennent la couleur du thème.
  Le titre de l'onglet devient « Collection ».
- **Paquets en stock** : le lot de 5 ouvre le 1er paquet, puis « Déchirer le suivant (3 en stock) ». Si on quitte l'écran,
  les paquets restants vont dans « 📦 En stock » en haut de l'onglet Paquets (avec les cadeaux reçus).
- **Collection triée** : les consoles s'affichent de la plus complétée à la moins complétée.
- **Nouvelles musiques** : 8 nouveaux morceaux moins chiptune (Pixel Quest, Block World, Level Up, Game On, Retro Wave,
  Lo-fi Gaming, Study Time, Game Show), au même volume. Musique et thème sont en « Aléatoire » par défaut :
  un morceau et un thème différents à chaque lancement (on peut toujours en choisir un fixe dans les réglages).
- **Bourse, échanges en détail** : toucher un échange (ou « Voir le détail ») ouvre une page avec les cartes en grand,
  leur rareté et finition, « ✨ Nouvelle pour toi » ou « Tu en as déjà 2 », « ⚠ Ta dernière » pour celles que tu donnes,
  la valeur de chaque côté, et les boutons Accepter / Refuser. Toucher une carte ouvre sa fiche.
- **Joueurs en ligne** : bouton 🟢 en haut du Voisinage avec la liste des connectés, « Défier » (4 en ligne ou
  Console Wars, grisé sous 50 pièces) et « Étage » pour descendre jusqu'à eux.

## v1.0.8
- **Dernière connexion des joueurs** : sur la plaque de chaque étage du Voisinage (« vu à 14:32 », « vu hier », « vu le 12/10 », ou « en ligne »)
  et sur le profil (« Dernière connexion : aujourd'hui à 14:32 (il y a 3 h) »).
- **Défis reçus** (4 en ligne, Console Wars) : un défi en direct s'affiche dans une fenêtre, où que tu sois dans l'appli
  (adversaire, jeu, mise, compte à rebours de 2 min), avec Accepter (la partie s'ouvre), Refuser ou Plus tard.
  Invitations tour par tour et parties où c'est ton tour : pastille sur « Bonus / Jeux » dans le menu, et notification
  appli fermée. Vérification légère toutes les 10 s, seulement appli ouverte.
- On ne peut défier qu'un joueur qui a au moins 50 pièces (« Sans pièces » dans la liste des joueurs).

## v1.0.7
- **4 en ligne** (onglet renommé « Bonus / Jeux ») : défie un autre joueur, 50 pièces de mise chacun,
  le gagnant remporte 100 pièces + 1 pixel (match nul : mises rendues). Section **En direct** (joueurs en ligne, 1 minute par coup)
  et **Tour par tour** (24 h par coup) ; délai dépassé = abandon. Coups vérifiés par le serveur.
  Salon façon borne d'arcade : tes stats (victoires, défaites, série, gain), joueurs en ligne avec leur bilan,
  miniatures des parties tour par tour, meilleurs joueurs de la semaine, résultats avec **Revanche**,
  attente du défi avec compte à rebours. En partie : chronos autour des avatars, pion qui vise la colonne,
  dernier coup entouré, **réactions** 👍😮😂🔥👏 vues par l'adversaire, sons (coupables), règles, et écran de fin
  avec trophée, pièces qui défilent et confettis.
- **Console Wars** (Bonus / Jeux) : bataille navale à 2 avec une flotte de consoles (Neo Geo, PlayStation, Mega Drive,
  NES, Game Boy) sur une grille 8 × 8. Même salon que le 4 en ligne (En direct : 2 min pour placer, 30 s par tir ;
  Tour par tour : 24 h), 50 pièces chacun, le gagnant rafle 100 + 1 pixel. Placement en glissant les consoles,
  toucher pour les tourner (côte à côte permis), ou au hasard. Radar avec balayage et viseur, touché = on rejoue,
  explosions, flammes, gerbes d'eau, épaves des consoles coulées, réactions, sons et écran de fin.
  La flotte adverse n'est jamais envoyée au téléphone avant d'être coulée.
- **Écran titre revu** : trois cartes en éventail (halos épique et rare qui pulsent, carte dorée qui flotte),
  logo avec reflet, ciel étoilé et sol néon. Le panneau du joueur affiche aussi les pixels et les nouvelles
  (paquet gratuit prêt ou dans combien de temps, 4 en ligne à toi de jouer, cadeaux reçus).
- La **musique démarre dès l'écran titre** (sur le web, à la première touche), avec un bouton son en haut à droite.
- **Bourse** : les 4 onglets deviennent des carrés de couleur avec leur icône (Acheter vert, Vendre orange,
  Échanges bleu, Historique violet).
- **Version web** : les bruitages marchent enfin (quiz, roue, 4 en ligne…), les mêmes que sur Android.
- **Événements** (menu) : fêtes, défis et annonces mis en ligne directement depuis le serveur, sans mise à jour
  de l'appli, avec une pastille sur le menu quand un nouvel événement arrive. Trois sortes :
  - **annonces** avec cadeau à récupérer (pièces, pixels) et bouton « Y aller » vers un onglet ;
  - **événements à effet** : pixels doublés à l'ouverture des boosters, paquet gratuit plus fréquent… ;
  - **défis** : objectif suivi par le serveur (boosters ouverts, parties de 4 en ligne gagnées, Gamedle trouvés)
    avec des paliers de récompenses et une barre de progression.
  Les événements à venir restent mystérieux : ni nom ni contenu, seulement le compte à rebours.
- **Notifications appli fermée** plus fiables : au premier lancement, si l'économie de batterie d'Android endort l'appli,
  un écran explique les 2 réglages à faire (batterie « Aucune restriction », démarrage automatique sur Xiaomi, Oppo,
  Realme, Huawei, Samsung…) avec un bouton qui ouvre directement chaque réglage. Dans les Réglages, la ligne
  « Notifications appli fermée » indique la dernière vérification faite en arrière-plan.
- Gamedle : en tapant un nom de jeu, le champ remonte en haut de l'écran et la liste des propositions n'est plus cachée par le clavier.
- Voisinage : plaque des joueurs plus large (toutes les infos visibles) ; la fenêtre de gauche laisse la place au balcon.
- Voisinage : titre lisible, raccourcis « Mon étage », « Mon thème » et « Profil » sous le titre.

## v1.0.6
- **Pixels** : chaque booster ouvert rapporte 1 pixel, quel que soit le paquet (tout le monde part de zéro).
  Les pixels s'échangent contre des **boosters spéciaux** :
  - **Booster Étoile** (15 pixels) : 5 cartes dont une épique ou mieux ;
  - **Booster Console+** (25 pixels) : la console de ton choix, une rare ou mieux et une brillante garanties ;
  - **Booster Rétro d'or** (40 pixels) : une légendaire… ou une carte dorée garantie.
  Ils passent aussi par le choix parmi 6 boosters, et chacun des 6 respecte la garantie.
- Boutique : une ligne « Boosters Pixels » avec sa jauge ouvre le sous-menu des boosters spéciaux
  (il se ferme en glissant vers le bas).
- Compteur de pixels à côté des pièces, en haut de chaque onglet et dans le menu.
- Récap d'ouverture : « +1 pixel » et ton total.
- **Voisinage en immeuble** : la « Pixel Tower », un immeuble en pierre où chaque joueur a son étage selon le classement
  (le n°1 au penthouse). Fenêtres allumées et mention « en ligne » pour les joueurs connectés, balcons fleuris, ascenseur à grille,
  plaque avec score, % de collection, cartes et pièces. Le hall donne accès aux cadeaux et à la recherche.
- **Thème de mon étage** (à la place de la maison) : 16 thèmes (pierre, brique, bois, lierre, néon, art déco, verre,
  château, japonais, arcade, spatial, sous-marin, plage, neige, Halloween, or), débloqués au nombre de cartes.
- Fiche d'une carte : les boutons de fusion (brillante, dorée) restent visibles, grisés avec le compte (ex. 3/5).
- Collection : toucher une rareté du tableau de bord affiche tes cartes de cette rareté.
- Correction : les titres des onglets ne sont plus coupés (« Ma collect… »), ils se réduisent pour tenir.

## v1.0.5
- **Nouveau dos des cartes** : une salle d'arcade aux couleurs de Pixel Trade, et l'icône de l'appli assortie.
- **10 nouveaux thèmes animés** (Réglages > Thème) : Synthwave, Galaxie, Pixel ciel, Salle d'arcade, Terminal,
  Océan, Donjon, Blocs, Aurore et Circuit — des fonds bien visibles, avec un aperçu animé dans le choix du thème,
  et un choix « Aléatoire » qui change de thème à chaque lancement.
- **Fiche d'une carte** : flèches ‹ › (ou glisser l'écran, ou flèches du clavier) pour passer à la carte
  possédée précédente / suivante, dans l'ordre de l'album ou de la liste d'où on vient (filtres et tri compris).
- **Ouverture des paquets** : le paquet s'ouvre aussi de dos. Ouvert de dos, les cartes sortent de dos
  (on les retourne une à une) ; ouvert de face, elles sortent déjà de face.
- **Choix du booster** : à chaque paquet, 6 boosters de couleurs différentes tournent en cercle et tu en choisis un.
  Chaque booster a son propre contenu ; après l'ouverture, on te montre la plus belle carte que tu as ratée
  et dans quel booster elle était. Si l'appli se ferme avant le choix, il t'attend au retour.
  Les paquets cadeaux, eux, arrivent dans un booster de couleur au hasard.
- **Paquet gratuit toutes les 6 heures** (au lieu d'un par jour), avec un compte à rebours dans la boutique.
- Titres longs : le nom de la carte se réduit ou passe sur deux lignes au lieu d'être coupé.
- Bourse : le nom du vendeur (le moins cher s'il y en a plusieurs) dans la liste des cartes à acheter.
- Bonus : la roue de la fortune passe dans une case, comme Gamedle et le quiz (elle s'ouvre en plein écran).
- Version web plus rapide à lancer : le catalogue se télécharge pendant le chargement et reste en cache.
- Correction : « Cadeau suivant » ouvre bien le cadeau suivant (on retombait sur la liste vide des cadeaux).

## v1.0.4
- **Gamedle** (onglet Bonus) : le jeu du jour, le même pour tout le monde. 6 essais : la jaquette pixelisée
  se précise à chaque essai, et chaque proposition indique si la console, l'année (⬆️ ⬇️) et le genre
  correspondent. Console donnée d'entrée, puis un indice de plus à chaque erreur (année, genre,
  développeur, initiales du titre) et, après 2 erreurs, un joker « 4 propositions ».
  Jusqu'à 100 pièces, résultat à partager en émojis.
- **Actualités** (menu) : les exploits des joueurs — légendaire ou dorée obtenue, série complétée, Gamedle trouvé.
- **Roue en or** : tous les 7 jours de connexion d'affilée, gains en pièces doublés, cartes meilleures
  et case **JACKPOT** (1000 pièces + une légendaire).
- La roue fait la fête : confettis selon le lot, la roue tremble pour les gros gains, vrai bouton « SUPER ! ».
- Correctif : les cases « CARTE » et « RARE » de la roue renvoyaient une erreur.
- **Mode tablette** (et PC en version web) : menu toujours visible à gauche, tableau de bord sur une ligne,
  plus de colonnes, fiche de la carte et offres de la Bourse affichées à côté de la liste.
  Sur téléphone, rien ne change (toujours en portrait). Réglages › **Affichage** pour forcer un mode
  (le mode tablette s'essaie aussi sur téléphone, en paysage).
- **Version web** : https://foclabroc.github.io/retro_collec_app/ (musique en mp3 sur iPhone / Safari).
- APK compilé par GitHub Actions (onglet Actions › APK Android), signé avec la même clé.

## v1.0.3
- 🎁 **Cadeau : 800 pièces offertes** à tous les joueurs (une seule fois, au premier lancement de la v1.0.3).
- Écran **Nouveautés** au lancement, avec « Ne plus afficher ».
- **4 nouvelles consoles** : PSP, Game Gear, GameCube et PS2 (50 cartes).
- Nouvelle rubrique **Bourse** (remplace Marché et Échanges) : Acheter · Vendre · Échanges · Historique.
  - Marché **groupé par carte** : prix le plus bas et nombre de lots, offres triées du moins cher au plus cher ;
    tri récents / moins chers / plus rares.
  - **Historique** : ventes, achats et échanges terminés, avec le bilan des pièces.
- Encadré **Bourse sur chaque carte** : « 3 en vente dès 40 → Acheter », Vendre, et **Échanger** (liste des joueurs
  qui l'ont en double, échange pré-rempli en une touche).
- **Voisinage** en parcelles : une **maison par joueur**, **12 maisons** à choisir (chalet, cottage, gîte d'hiver,
  ryokan, villa, dôme, manoir, château…), certaines débloquées par la collection (100 à 700 cartes).
- **Paquets cadeaux** : jusqu'à **3 paquets à offrir par jour** (un par joueur). En haut de l'onglet Paquets,
  « Cadeaux reçus » ouvre la **liste des donateurs** (pseudo, date) avec un bouton Ouvrir pour chaque paquet.
- **Lot de 5 paquets mixtes** (500 pièces) : **gratuit chaque samedi** ; les paquets du lot s'ouvrent un par un.
- **Fusion** : 5 exemplaires normaux d'une carte → 1 brillante, 3 brillantes → 1 dorée (depuis la fiche de la carte).
- **Notifications Android**, même appli fermée (environ toutes les 15 min) : paquet cadeau reçu, carte vendue,
  proposition d'échange, mention dans les messages, paquet gratuit du jour, lot gratuit du samedi.
  Désactivables dans les réglages.
- **Ma collection** repensée : tableau de bord (progression, raretés, raccourcis, dernières cartes) et consoles
  en **posters rétro**.
- **Filtres et tri** dans les albums (bouton ⚙) : possédées, manquantes, doublons, brillantes, dorées, rareté, genre ;
  tri par numéro, rareté, année, nom ou exemplaires. **Recherche** dans toutes ses cartes (🔍 dans Collection).
- **Thèmes d'interface** (réglages) : Rétro bleu, Game Boy, Néon, Coucher de soleil, Arcade noir.
- Menu latéral accessible depuis n'importe quel écran (glisser depuis le bord gauche).
- **Nouveaux boosters « Booster Retrogaming »** (recto et verso) : à l'ouverture, fais tourner le paquet avec ton doigt
  comme une carte, puis glisse le long du pointillé en haut pour le déchirer.
- **18 nouveaux avatars** en pixel art (chevalier, mage, ninja, robot, viking…).
- **5 nouvelles musiques** chiptune : Pixel Town, Night Arcade, Treasure Hunt, Chill Cartridge, Boss Rush.
- Correctif : retour arrière pendant l'achat d'un paquet → le paquet n'est plus perdu (résumé des cartes).

## v1.0.2
- Nouvel onglet **Bonus** : roue de la fortune (un tour gratuit par jour : pièces ou carte) et quiz rétro.
- Nouvel onglet **Voisinage** : tous les joueurs (classement, recherche), leur profil, leurs statistiques et leur album ;
  **offre un paquet** à un joueur chaque jour. Mon profil et les réglages sont accessibles en haut de l'onglet.
- **Paquet mystère** (120 pièces) : 3, 5 ou… 8 cartes !
- **Paquets cadeaux** reçus des autres joueurs, à ouvrir dans l'onglet Paquets.
- **Cartes animées** : éclat lumineux et étoiles sur les légendaires, les dorées et les épiques brillantes.
- **Statistiques** de collection : complétion par rareté, brillantes / dorées, valeur, cartes les plus précieuses.
- Vente facilitée : vendre depuis le Marché, vente groupée des doublons, prix conseillé ; 12 lots en vente.
- Notifications dans l'appli : pastilles sur les onglets, message quand une carte est vendue ou un paquet offert.
- **Messages** : chat entre joueurs (120 caractères, 1 message / 10 s), mentions **@pseudo** avec notification,
  filtre de gros mots, liens et numéros masqués, appui long pour signaler un message.
- **Menu latéral** à gauche (bouton ☰ ou glisser depuis le bord) : toutes les rubriques avec leurs pastilles, profil en haut.
- Cartes brillantes et boosters plus éclatants (reflet holo sans voile terne).
- Choix de la musique dans les réglages (Good Morning, Shop, Mountain) ; gyroscope désactivé par défaut.

## v1.0.1
- Nouveau : **Quiz rétro** (onglet Paquets) — devine le jeu à partir de sa capture d'écran, 10 questions,
  12 secondes par question, combos. 5 pièces par bonne réponse, jusqu'à 100 pièces par jour.

## v1.0.0
- 10 séries de 100 cartes (Master System, NES, Super Nintendo, Nintendo 64, PlayStation,
  Game Boy Advance, Mega Drive, Game Boy Color, Switch, Neo Geo), 5 raretés, finitions brillante et dorée.
- Paquets : gratuit chaque jour, mixte, console, premium ; épique garantie au 30e paquet.
- Ouverture animée : déchirer le paquet, suspense selon la rareté, effets épique / légendaire, reflet holo au gyroscope.
- Album par console, fiche de chaque jeu (capture, année, développeur, éditeur, genre, description).
- Recyclage des doublons, fabrication d'une carte précise, paliers de série récompensés.
- Marché entre joueurs, échanges (5 cartes contre 5), profils publics avec vitrine et collection, classement.
- Missions du jour et bonus de connexion.
- Écran de bienvenue (pseudo, avatar), compte protégé par mot de passe, code de sauvegarde.
- Confirmation avant l'achat d'un paquet, choix de la console en grille.
- Français / English (automatique ou au choix), fiches des jeux traduites.
- Catalogue des cartes vérifié à chaque lancement (nouvelles cartes, textes).
