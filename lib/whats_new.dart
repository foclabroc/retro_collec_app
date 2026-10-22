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
  ('🏆', 'Tournois ! Inscris-toi dans la Salle de jeux : matchs en direct au 4 en ligne ou à Console Wars, arbre en direct, lots et cagnotte pour le podium',
      'Tournaments! Sign up in the Game room: live Connect 4 or Console Wars matches, live bracket, prizes and a pot for the podium'),
  ('⚔', 'Quand ton match commence, une fenêtre te prévient : touche « Jouer » dans les 3 minutes (sinon forfait)',
      'When your match starts, a window tells you: tap "Play" within 3 minutes (or forfeit)'),
  ('🥇', 'Nouveau trophée « Champion » pour les tournois gagnés', 'New "Champion" trophy for tournaments won'),
  ('#', 'Aussi depuis la 1.0.19', 'Also since 1.0.19'),
  ('📖', 'Nouveau « Guide du jeu » dans le menu : score, raretés, paquets, Bourse, duels, défis… tout est expliqué',
      'New "Game guide" in the menu: score, rarities, packs, market, duels, challenges… everything explained'),
  ('⚡', 'Temps réel instantané : les joueurs apparaissent en ligne dès qu\'ils ouvrent le jeu, et tout arrive sans attendre',
      'Instant real time: players show online as soon as they open the game, and everything arrives right away'),
  ('👁', 'Duels : la liste des spectateurs est visible, et les spectateurs peuvent envoyer des réactions en direct',
      'Duels: see who\'s watching, and spectators can send live reactions'),
  ('🔎', 'Voisinage : « Trouver mes cartes manquantes » chez les joueurs qui les ont en double',
      'Neighbors: "Find my missing cards" from players who have them as duplicates'),
  ('✨', 'Pseudos décorés : emojis et symboles autorisés (ta connexion se fait toujours avec les lettres et chiffres)',
      'Decorated names: emojis and symbols allowed (you still log in with the letters and numbers)'),
  ('🚀', 'Version web plus rapide au lancement', 'Faster web version at startup'),
  ('🛡', 'Plus de sécurité : un nouveau compte peut utiliser la Bourse, les cadeaux et les échanges après 24 h',
      'More security: a new account can use the market, gifts and trades after 24 h'),
  ('#', 'Aussi depuis la 1.0.18', 'Also since 1.0.18'),
  ('🎮', '5 nouvelles consoles : 3DS, SG-1000, Dreamcast, Atari 7800 et Amiga CD32 (50 cartes chacune, 1600 cartes en tout)',
      '5 new systems: 3DS, SG-1000, Dreamcast, Atari 7800 and Amiga CD32 (50 cards each, 1,600 cards in total)'),
  ('⚡', 'Tout en temps réel : messages, notifications, échanges, Bourse, Actu, événements, défis, trophées et profils',
      'Everything in real time: messages, notifications, trades, market, news, events, challenges, trophies and profiles'),
  ('👁', 'Mode spectateur : regarde les duels en direct des autres joueurs (salon, liste En ligne, borne IN GAME)',
      'Spectator mode: watch other players\' live duels (lobby, Online list, IN GAME cabinet)'),
  ('🕹', 'Nouvel onglet « Salle de jeux » : 4 en ligne et Console Wars, avec le bouton « Jeux en cours »',
      'New "Game room" tab: Connect 4 and Console Wars, with a "Games in progress" button'),
  ('👤', 'Profil : Ma borne, Thème et Musique en haut ; tes séries en déroulant, et celles des autres sur leur profil',
      'Profile: My cabinet, Theme and Music at the top; your sets in a drop-down, and other players\' sets on their profile'),
  ('🏆', 'Trophée « Console complète » : l\'or demande maintenant les 19 consoles', '"Full system" trophy: gold now needs all 19 systems'),
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
