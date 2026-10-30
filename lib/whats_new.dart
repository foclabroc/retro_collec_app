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
  ('♻', 'Le recyclage ne donne plus de pièces mais des fragments de full art (mêmes quantités qu\'avant)',
      'Recycling no longer gives coins but full art fragments (same amounts as before)'),
  ('★★', 'Fabrique une full art avec tes fragments : 3 000 pour une épique, 10 000 pour une légendaire (bouton sur la fiche de la carte)',
      'Craft a full art with your fragments: 3,000 for an epic, 10,000 for a legendary (button on the card page)'),
  ('#', 'Aussi depuis la 1.0.29', 'Also since 1.0.29'),
  ('♻', 'Le recyclage ne donne plus de pièces mais des fragments de full art (mêmes quantités qu\'avant)',
      'Recycling no longer gives coins but full art fragments (same amounts as before)'),
  ('★★', 'Fabrique une full art avec tes fragments : 3 000 pour une épique, 10 000 pour une légendaire (bouton sur la fiche de la carte)',
      'Craft a full art with your fragments: 3,000 for an epic, 10,000 for a legendary (button on the card page)'),
  ('#', 'Aussi depuis la 1.0.29', 'Also since 1.0.29'),
  ('🎮', '6 nouvelles consoles : Atari 2600 et Wii (100 cartes), ColecoVision, Saturn, Wii U et Xbox (50 cartes) : 400 cartes de plus à collectionner',
      '6 new systems: Atari 2600 and Wii (100 cards), ColecoVision, Saturn, Wii U and Xbox (50 cards): 400 more cards to collect'),
  ('📚', '4 nouvelles sagas en cartes holo : Crash Bandicoot, Donkey Kong, Mortal Kombat et Final Fantasy (10 cartes chacune)',
      '4 new holo sagas: Crash Bandicoot, Donkey Kong, Mortal Kombat and Final Fantasy (10 cards each)'),
  ('🏆', 'Trophées : l\'or de « Console complète » demande les 29 consoles, celui de « Sagas » les 12 sagas',
      'Trophies: "Full system" gold needs all 29 systems, "Sagas" gold all 12 sagas'),
  ('#', 'Aussi depuis la 1.0.28', 'Also since 1.0.28'),
  ('★', 'Les full art comptent comme des cartes à part, seulement dans l\'onglet Full art, et s\'ajoutent au total',
      'Full arts count as separate cards, only in the Full art tab, and add to the total'),
  ('📦', '« Ouvrir un autre » propose le même paquet que celui que tu viens d\'ouvrir', '"Open another" offers the same pack you just opened'),
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
