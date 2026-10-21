import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game.dart';
import 'retro_theme.dart';
import 'update_check.dart';

// ═══════════════════════════════════════════════════════════════════════════
// « Quoi de neuf » : résumé des nouveautés de la version, affiché à chaque
// lancement jusqu'à ce que le joueur coche « Ne plus afficher ».
// À chaque version : mettre à jour _kNews (la clé dépend de kRetroCollecVersion).
// ═══════════════════════════════════════════════════════════════════════════

const _kNews = <(String, String, String)>[
  ('🏠', 'Pixel Trade a déménagé sur son propre serveur : plus de limite de joueurs pour les duels en direct',
      'Pixel Trade moved to its own server: no more player limit for live duels'),
  ('🛠', 'Message clair quand le serveur est momentanément indisponible', 'Clear message when the server is temporarily unavailable'),
  ('#', 'Aussi depuis la 1.0.16', 'Also since 1.0.16'),
  ('🃏', 'Nouveau thème « Mur de cartes » (par défaut) : tes cartes défilent en fond et se retournent de temps en temps',
      'New "Card wall" theme (default): your cards scroll in the background and flip now and then'),
  ('🎨', 'Thèmes refaits : 13 fonds aux couleurs plus douces, plus lisibles (Manettes, Cartouches, Pac-gommes, Synthwave…) ; « Aléatoire » toujours dispo',
      'Themes redone: 13 softer, easier-to-read backgrounds (Pads, Cartridges, Pellets, Synthwave…); "Random" still available'),
  ('#', 'Aussi depuis la 1.0.15', 'Also since 1.0.15'),
  ('🟢', 'Joueurs en ligne à jour en temps réel ; un joueur en partie affiche « En partie » (IN GAME sur sa borne) et ne peut plus être défié',
      'Online players updated in real time; a player in a game shows "In a game" (IN GAME on their cabinet) and can\'t be challenged'),
  ('🛒', 'Bourse : achète plusieurs cartes d\'un coup (sélection groupée)', 'Market: buy several cards at once (multi-select)'),
  ('💡', 'Voisinage : bornes illuminées (halo, fronton, écran qui pulse, lueur au sol)', 'Neighbors: lit-up cabinets (glow, marquee, pulsing screen, floor light)'),
  ('🏆', 'Profil : tous les trophées dans un déroulant, doré quand un palier est à récupérer ; trophée Sagas en 1 / 3 / 6',
      'Profile: all trophies in a drop-down, gold when a tier is ready; Sagas trophy now 1 / 3 / 6'),
  ('⚡', 'Appli plus légère pour le serveur : moins de vérifications en arrière-plan', 'Lighter on the server: fewer background checks'),
  ('#', 'Aussi depuis la 1.0.14', 'Also since 1.0.14'),
  ('🏆', 'Pastille sur le profil quand un palier de trophée est à récupérer', 'Badge on the profile when a trophy tier is ready to claim'),
  ('🪙', 'Les pièces et pixels des autres joueurs sont de nouveau visibles (borne et profil)', 'Other players\' coins and pixels are visible again (cabinet and profile)'),
  ('🔇', 'Musique : nouvelle option « Aucune » (les bruitages restent)', 'Music: new "None" option (sound effects stay on)'),
  ('#', 'Aussi depuis la 1.0.13', 'Also since 1.0.13'),
  ('🏆', 'Trophées : 24 trophées à 3 paliers (bronze, argent, or) dans ton profil, chaque palier rapporte des pièces (et des pixels pour l\'or)',
      'Trophies: 24 trophies with 3 tiers (bronze, silver, gold) in your profile, each tier pays coins (and pixels for gold)'),
  ('🥇', 'Tes 3 meilleurs trophées s\'affichent sur ton profil et sous l\'écran de ta borne (ou ceux que tu choisis)',
      'Your 3 best trophies show on your profile and under your cabinet screen (or the ones you pick)'),
  ('🎯', 'Défis de la semaine tournants : chaque lundi, 6 défis tirés parmi 12 (cadeaux, nouvelles cartes, quiz, ventes…)',
      'Rotating weekly challenges: every Monday, 6 challenges drawn from 12 (gifts, new cards, quiz, sales…)'),
  ('🕹', 'Voisinage : la salle d\'arcade « Pixel Arcade » remplace l\'immeuble, une borne par joueur avec podium pour les 3 premiers',
      'Neighbors: the "Pixel Arcade" hall replaces the tower, one arcade cabinet per player with a podium for the top 3'),
  ('📺', 'Écran allumé (PLAYING) quand le joueur est en ligne, OFFLINE sinon ; pseudo qui défile sur le fronton',
      'Screen lit (PLAYING) when the player is online, OFFLINE otherwise; name scrolling on the marquee'),
  ('🎨', '16 habillages de borne à débloquer avec tes cartes (« Thème » en haut du Voisinage)',
      '16 cabinet skins to unlock with your cards ("Theme" at the top of Neighbors)'),
  ('🔴', '4 en ligne : nouvelle grille façon borne d\'arcade, pion fantôme fléché et victoire illuminée',
      'Connect 4: new arcade-style grid, arrowed ghost disc and lit-up victory'),
  ('🧑', 'Nouveaux avatars : 30 personnages de jeux vidéo (Mario, Link, Samus, Sonic, Kirby…)',
      'New avatars: 30 video game characters (Mario, Link, Samus, Sonic, Kirby…)'),
  ('📦', 'Paquets : nouvelle vue en mosaïque, et un paquet entamé se reprend d\'un toucher',
      'Packs: new mosaic view, and a started pack resumes with one tap'),
  ('◀', 'Android : le bouton retour ouvre et ferme le menu', 'Android: the back button opens and closes the menu'),
  ('🌈', 'Cartes de saga numérotées, et filtrables dans la Bourse', 'Numbered saga cards, filterable in the Market'),
  ('💰', 'Bourse : tes nouvelles ventes sont mises en avant', 'Market: your new sales are highlighted'),
  ('🔔', 'Notifications Android avec l\'icône du jeu', 'Android notifications with the game icon'),
  ('#', 'Aussi depuis la 1.0.12', 'Also since 1.0.12'),
  ('💬', 'Duels : ajoute un petit mot à tes défis et revanches, et réponds aux défis reçus (« J\'arrive ! », « Dans 5 minutes »…)',
      'Duels: add a short message to your challenges and rematches, and reply to challenges ("Coming!", "In 5 minutes"…)'),
  ('🔥', 'Réactions en grand au milieu du plateau, et phrases rapides en partie (« Bien joué ! », « GG 🤝 »…)',
      'Big reactions in the middle of the board, and quick phrases in game ("Well played!", "GG 🤝"…)'),
  ('🔴', '4 en ligne : des pions plus grands', 'Connect 4: bigger discs'),
  ('🎮', 'Bonus / Jeux : « À toi de jouer » et invitations bien visibles, mis à jour en direct',
      'Bonus / Games: "Your turn" and invitations clearly visible, updated live'),
  ('☰', 'Menu plus compact : tout tient sur un écran', 'More compact menu: everything fits on one screen'),
  ('📊', 'Collection : tableau de bord replié, une flèche pour le déplier', 'Collection: collapsed dashboard, an arrow to expand it'),
  ('#', 'Aussi depuis la 1.0.11', 'Also since 1.0.11'),
  ('🌈', 'Sagas Mario, Sonic, Zelda et Pokémon : cartes holo rares (3,2 % par carte), avec leurs albums dans la Collection',
      'Mario, Sonic, Zelda and Pokémon sagas: rare holo cards (3.2% per card), with their albums in the Collection'),
  ('🎯', 'Défis de la semaine : 6 défis et un coffre (500 pièces, 2 pixels, 1 paquet premium), à la place des missions du jour',
      'Weekly challenges: 6 challenges and a chest (500 coins, 2 pixels, 1 premium pack), replacing daily missions'),
  ('🤝', 'Partager & parrainage : ton code, et un paquet premium chacun quand ton filleul a ouvert 5 paquets',
      'Share & referral: your code, and a premium pack each once your referral has opened 5 packs'),
  ('👏', 'Actualités : réagis aux exploits des joueurs 👏 🔥 😮', 'News: react to players\' feats 👏 🔥 😮'),
  ('🔍', 'Profil d\'un voisin : ses cartes qui te manquent, les tiennes qui lui manquent, et vos consoles comparées',
      'Neighbor profile: their cards you lack, yours they lack, and your systems compared'),
  ('🛒', 'Bourse : nouveau magasin (recherche, filtres, bonnes affaires), ventes, échanges et historique revus',
      'Exchange: new shop (search, filters, good deals), sales, trades and history redesigned'),
  ('🖼', 'Vitrine : « + » dans les cases vides, et glisse les cartes pour changer l\'ordre', 'Showcase: "+" in empty slots, and drag cards to reorder'),
  ('🎮', 'Collection : affiches de consoles animées, lignes Sagas et Full art', 'Collection: animated system posters, Sagas and Full art rows'),
  ('✨', 'Nouveaux titres d\'onglets, tour sans les joueurs absents depuis 7 jours', 'New tab titles, tower without players away for 7 days'),
  ('#', 'Aussi depuis la 1.0.10', 'Also since 1.0.10'),
  ('⚔', '4 en ligne et Console Wars gratuits : le gagnant gagne 150 pièces + 1 pixel, le perdant 10',
      'Connect 4 and Console Wars are free: the winner gets 150 coins + 1 pixel, the loser 10'),
  ('🖼', 'Nouvelles cartes Full Art, ultra rares, sur les épiques et légendaires', 'New ultra-rare Full Art cards, on epics and legendaries'),
  ('📰', 'Actualités : victoires, échanges, ventes, cadeaux, nouveaux joueurs… avec filtres', 'News: wins, trades, sales, gifts, new players… with filters'),
  ('🟢', 'Joueurs en ligne en bas du menu', 'Online players at the bottom of the menu'),
  ('🔀', 'Collection : choisis l\'ordre des consoles', 'Collection: choose the order of the systems'),
  ('🔊', 'Un seul bouton pour la musique et les bruitages, gardé au redémarrage', 'One button for music and sound effects, kept after restart'),
  ('🔑', 'Nouvel écran de connexion et nouvelle icône', 'New login screen and new icon'),
  ('#', 'Aussi depuis la 1.0.9', 'Also since 1.0.9'),
  ('🎨', '10 nouveaux thèmes plus épurés, avec un motif animé discret', '10 new cleaner themes, with a subtle animated pattern'),
  ('🎵', '8 nouvelles musiques, moins chiptune', '8 new music tracks, less chiptune'),
  ('🎲', 'Thème et musique en aléatoire par défaut (réglable dans les réglages)', 'Random theme and music by default (change it in the settings)'),
  ('🎉', 'Événements : nouveau look, les 5 prochains visibles avec leur compte à rebours', 'Events: new look, the next 5 shown with their countdown'),
  ('🏢', 'Pixel Tower : étages revus, pseudo en entier, « en ligne » sur le balcon', 'Pixel Tower: redesigned floors, full names, "online" on the balcony'),
  ('🟢', 'Joueurs en ligne : la liste des connectés, pour les défier ou aller à leur étage', 'Online players: list of who\'s connected, to challenge them or visit their floor'),
  ('🔍', 'Bourse : toucher un échange pour le voir en détail', 'Exchange: tap a trade to see it in detail'),
  ('📦', 'Lot de 5 : les paquets non ouverts restent en stock', 'Bundle of 5: unopened packs stay in stock'),
  ('📊', 'Collection : consoles triées de la plus complétée à la moins', 'Collection: systems sorted from most to least complete'),
  // pour ceux qui arrivent d'une version plus ancienne
  ('#', 'Aussi depuis la 1.0.8', 'Also since 1.0.8'),
  ('⚔', 'Défis reçus : une fenêtre s\'affiche quand on te défie en direct (Accepter, Refuser, Plus tard)',
      'Challenges: a window pops up when someone challenges you live (Accept, Decline, Later)'),
  ('🔴', 'Pastille sur « Bonus / Jeux » pour les invitations tour par tour et quand c\'est ton tour',
      'Badge on "Bonus / Games" for turn-based invitations and when it\'s your turn'),
  ('🕒', 'Dernière connexion des joueurs sur leur étage et leur profil', 'Players\' last login on their floor and profile'),
  ('🪙', 'On ne peut défier qu\'un joueur qui a au moins 50 pièces', 'You can only challenge players with at least 50 coins'),
  ('#', 'Aussi depuis la 1.0.7', 'Also since 1.0.7'),
  ('🚢', 'Console Wars : bataille navale à 2 avec une flotte de consoles, en direct ou tour par tour',
      'Console Wars: 2-player battleship with a fleet of consoles, live or turn-based'),
  ('🔴', '4 en ligne : défie un joueur, 50 pièces chacun, le gagnant rafle 100 + 1 pixel',
      'Connect 4: challenge a player, 50 coins each, the winner takes 100 + 1 pixel'),
  ('🎉', 'Événements : cadeaux, pixels ×2, défis à paliers… et des surprises à venir',
      'Events: gifts, double pixels, step challenges… and surprises to come'),
  ('🃏', 'Nouvel écran titre, musique dès l\'accueil et bouton son', 'New title screen, music from the start and a sound button'),
  ('💱', 'Bourse : onglets en carrés de couleur', 'Exchange: colored square tabs'),
  ('🔔', 'Notifications appli fermée plus fiables (réglage batterie)', 'More reliable notifications when the app is closed (battery setting)'),
  ('🔊', 'Version web : les bruitages marchent enfin', 'Web version: sound effects finally work'),
];

String get _prefKey => 'rc_news_hide_$kRetroCollecVersion';

/// Affiche le résumé si le joueur ne l'a pas masqué pour cette version.
Future<void> maybeShowWhatsNew(BuildContext context) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefKey) ?? false) return;
    if (!context.mounted) return;
    final hide = await showDialog<bool>(context: context, builder: (_) => const _WhatsNewDialog());
    if (hide == true) await prefs.setBool(_prefKey, true);
  } catch (_) {}
}

class _WhatsNewDialog extends StatefulWidget {
  const _WhatsNewDialog();
  @override
  State<_WhatsNewDialog> createState() => _WhatsNewDialogState();
}

class _WhatsNewDialogState extends State<_WhatsNewDialog> {
  bool _hide = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF14183A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: kGold, width: 1.5)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      title: Column(children: [
        Text(px(t('NOUVEAUTÉS', 'WHAT\'S NEW')), style: pixelStyle(size: 15), textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text('Pixel Trade v$kRetroCollecVersion',
            style: const TextStyle(color: Colors.white60, fontSize: 12), textAlign: TextAlign.center),
      ]),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(children: [
                for (final (i, n) in _kNews.indexed)
                  if (n.$1 == '#')
                    // intertitre (nouveautés d'une version précédente)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                      child: Text(px(t(n.$2, n.$3).toUpperCase()), style: pixelStyle(size: 8, color: Colors.white54, shadow: false)),
                    )
                  else
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: i == 0 ? kGold.withAlpha(46) : Colors.white.withAlpha(13),
                      borderRadius: BorderRadius.circular(10),
                      border: i == 0 ? Border.all(color: kGold.withAlpha(153)) : null,
                    ),
                    child: Row(children: [
                      Text(n.$1, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(t(n.$2, n.$3),
                            style: TextStyle(
                                fontSize: 13.5,
                                height: 1.25,
                                color: i == 0 ? kGold : Colors.white,
                                fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w500)),
                      ),
                    ]),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 4),
          CheckboxListTile(
            value: _hide,
            onChanged: (v) => setState(() => _hide = v ?? false),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: kGold,
            title: Text(t('Ne plus afficher', 'Don\'t show again'), style: const TextStyle(fontSize: 13.5)),
          ),
        ]),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        ElevatedButton(onPressed: () => Navigator.pop(context, _hide), child: Text(t('C\'est parti !', 'Let\'s go!'))),
      ],
    );
  }
}
