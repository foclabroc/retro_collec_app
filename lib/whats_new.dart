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
  ('⚡', 'Déchirer et tout voir : un bouton sous le paquet montre toutes tes cartes d\'un coup',
      'Tear and see all: a button under the pack shows all your cards at once'),
  ('🏆', 'Tournois : fenêtre de félicitations pour le podium, lots au nom du tournoi, score des manches plus clair en finale',
      'Tournaments: congrats window for the podium, prizes named after the tournament, clearer round score in the final'),
  ('🔕', 'Plus de fenêtre de défi pendant l\'ouverture d\'un paquet ou un match de tournoi : elle arrive juste après',
      'No more challenge window while opening a pack or during a tournament match: it shows right after'),
  ('🛠', 'Corrigé : « Paquet entamé » qui restait affiché pour rien, messages du chat parfois en double',
      'Fixed: "Started pack" showing for nothing, chat messages sometimes shown twice'),
  ('#', 'Aussi depuis la 1.0.20', 'Also since 1.0.20'),
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
