# Pixel Trade — Changelog

## v1.0.6
- **Pixels** : chaque booster ouvert rapporte 1 pixel (tout le monde part de zéro). Une jauge en haut de la boutique
  montre où tu en es, et les pixels s'échangent contre des **boosters spéciaux** :
  Booster Étoile (15 pixels, une épique ou mieux), Booster Console+ (25 pixels, console au choix,
  une rare ou mieux et une brillante) et Booster Rétro d'or (40 pixels, une légendaire ou une carte dorée).

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
