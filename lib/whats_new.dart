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
  ('🎁', 'Cadeau de mise à jour (si tu ne l\'as pas déjà eu) : 600 pièces et un booster premium, dans Paquets → Cadeaux reçus',
      'Update gift (if you haven\'t had it yet): 600 coins and a premium pack, in Packs → Gifts received'),
  ('🚀', 'Rétro Jump solo du jour : même parcours pour tous, joue autant que tu veux. Le lendemain, les 3 meilleurs gagnent 500, 300 et 100 pièces (+ pixels) ; historique des gagnants dans le salon',
      'Daily solo Rétro Jump: same course for everyone, play as much as you like. The next day, the top 3 win 500, 300 and 100 coins (+ pixels); winners history in the lobby'),
  ('🛡️', 'Plus de défi quand tu es déjà en partie (ou ton adversaire), et la fusée remplace le robot dans Rétro Jump',
      'No more challenges while you (or your opponent) are already in a game, and the rocket replaces the robot in Rétro Jump'),
  ('🏆', 'Tournois de Rétro Jump : l\'admin peut maintenant en organiser, et tu peux défier un joueur en ligne à Rétro Jump depuis la liste des joueurs en ligne',
      'Rétro Jump tournaments: the admin can now set them up, and you can challenge an online player to Rétro Jump from the online list'),
  ('🎯', 'Plus de défi qui arrive pendant une partie solo, et un bouton Scores dans « Solo du jour »',
      'No more challenges popping up during a solo run, and a Scores button in "Daily solo"'),
  ('#', 'Aussi depuis la 1.0.24', 'Also since 1.0.24'),
  ('🤖', 'Nouveau duel dans la Salle de jeux : Rétro Jump en direct ! Même parcours pour vous deux, ton adversaire apparaît en fantôme, 2 minutes et le plus haut gagne',
      'New duel in the Game room: live Rétro Jump! Same course for both of you, your opponent shows up as a ghost, 2 minutes and the highest wins'),
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
