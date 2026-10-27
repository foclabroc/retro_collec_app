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
  ('🎁', 'Cadeau de mise à jour : 600 pièces et un booster premium (dans Paquets → Cadeaux reçus)',
      'Update gift: 600 coins and a premium pack (in Packs → Gifts received)'),
  ('🎮', '4 nouvelles consoles : Game Boy et Amiga 1200 (100 cartes), Lynx et Supervision (50 cartes) : 1 900 cartes en tout',
      '4 new systems: Game Boy and Amiga 1200 (100 cards), Lynx and Supervision (50 cards): 1,900 cards in all'),
  ('📚', '2 nouvelles sagas en cartes holo : Kirby et Street Fighter',
      '2 new holo sagas: Kirby and Street Fighter'),
  ('★★', 'Collection : nouvel onglet Full art avec toutes les épiques et légendaires, case vide tant que tu ne l\'as pas en full art',
      'Collection: new Full art tab with every epic and legendary, empty slot until you own it in full art'),
  ('🃏', 'Cartes offertes en récompense : elles attendent dans « Cartes à ranger » (onglet Paquets) pour les voir avant de les ranger dans ta collection',
      'Reward cards now wait in "Cards to store" (Packs tab) so you can look at them before adding them to your collection'),
  ('⭐', 'Les paquets premium (achetés ou reçus) et le paquet gratuit comptent enfin pour les défis de la semaine et le trophée Premium',
      'Premium packs (bought or received) and the free pack now count for weekly challenges and the Premium trophy'),
  ('⚔', 'Quand ton défi est accepté, la page de la partie s\'ouvre toute seule, même si tu as quitté le salon',
      'When your challenge is accepted, the game page opens by itself, even if you left the lobby'),
  ('🔄', 'Échange : filtre « Qu\'il n\'a pas » dans « Je donne » ; ta collection et tes consoles se mettent à jour tout de suite après un échange',
      'Trade: new "He doesn\'t have" filter in "I give"; your collection and consoles update instantly after a trade'),
  ('🚀', 'Cartes full art beaucoup plus fluides (moins de lag)',
      'Full art cards run much smoother (less lag)'),
  ('#', 'Aussi depuis la 1.0.22', 'Also since 1.0.22'),
  ('✨', 'Les cartes full art sortent bien plus souvent : 3 % des épiques et légendaires (au lieu de 0,2 %)',
      'Full art cards now drop much more often: 3% of epics and legendaries (instead of 0.2%)'),
  ('🏅', 'Les paliers de collection gagnés (25, 50, 75, 100 % d\'une console ou d\'une saga) s\'affichent dans le récapitulatif du paquet',
      'Collection milestones you reach (25, 50, 75, 100% of a console or saga) now show in the pack summary'),
  ('♻️', 'Recyclage rééquilibré : commune 2, peu commune 5, rare 20, épique 60, légendaire 200 pièces (acheter des paquets pour les recycler rapportait plus qu\'ils ne coûtaient)',
      'Recycling rebalanced: common 2, uncommon 5, rare 20, epic 60, legendary 200 coins (buying packs to recycle them paid more than they cost)'),
  ('#', 'Aussi depuis la 1.0.21', 'Also since 1.0.21'),
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
