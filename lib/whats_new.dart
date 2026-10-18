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
  ('⚔', 'Défis reçus : une fenêtre s\'affiche quand on te défie en direct (Accepter, Refuser, Plus tard)',
      'Challenges: a window pops up when someone challenges you live (Accept, Decline, Later)'),
  ('🔴', 'Pastille sur « Bonus / Jeux » pour les invitations tour par tour et quand c\'est ton tour',
      'Badge on "Bonus / Games" for turn-based invitations and when it\'s your turn'),
  ('🕒', 'Dernière connexion des joueurs sur leur étage et leur profil', 'Players\' last login on their floor and profile'),
  ('🪙', 'On ne peut défier qu\'un joueur qui a au moins 50 pièces', 'You can only challenge players with at least 50 coins'),
  // pour ceux qui arrivent d'une version plus ancienne
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
        Text(t('NOUVEAUTÉS', 'WHAT\'S NEW'), style: pixelStyle(size: 15), textAlign: TextAlign.center),
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
                      child: Text(t(n.$2, n.$3).toUpperCase(), style: pixelStyle(size: 8, color: Colors.white54, shadow: false)),
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
