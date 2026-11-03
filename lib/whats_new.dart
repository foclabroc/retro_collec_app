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
  ('🏃', 'Course de jaquettes refaite : un magasin de jeux rétro la nuit (étagères pleines de jaquettes, néons, sol ciré), et ton coureur est maintenant une cartouche !',
      'Cover Run remade: a retro game shop at night (shelves full of covers, neon signs, polished floor), and your runner is now a cartridge!'),
  ('🎮', 'Course plus jouable : vue plus grosse qui recule avec la vitesse, appui un peu en avance gardé, glisse tant que tu restes appuyé, ↓ en l\'air pour plonger, flèche d\'alerte quand un obstacle arrive vite',
      'Easier to play: bigger view that zooms out with speed, slightly early taps are kept, slide as long as you hold, ↓ in the air to dive, warning arrow when an obstacle comes fast'),
  ('🎨', 'Le choix du booster Pokémon montre bien 6 couleurs différentes',
      'The Pokémon booster choice now shows 6 different colours'),
  ('#', 'Aussi depuis la 1.0.42', 'Also since 1.0.42'),
  ('🏆', 'Actualité : nouvel onglet « Tops » avec les meilleurs joueurs (paquets ouverts, pièces gagnées, victoires de duels, Bourse, cadeaux envoyés, cartes) sur aujourd\'hui, 7 ou 30 jours',
      'News: new "Tops" tab with the best players (packs opened, coins earned, duel wins, Market, gifts sent, cards) for today, 7 or 30 days'),
  ('#', 'Aussi depuis la 1.0.41', 'Also since 1.0.41'),
  ('🔴', 'Nouveau booster Pokémon : 5 cartes Pokémon, 100 pixels dans la boutique (peut aussi être offert en récompense)',
      'New Pokémon booster: 5 Pokémon cards, 100 pixels in the shop (can also be given as a reward)'),
  ('⚡', 'Collection : le bouton « fusions » n\'affiche plus que les cartes fusionnables, avec deux nouveaux filtres « Fusion normales ×5 » et « Fusion brillantes ×3 »',
      'Collection: the "fusions" button now only shows cards you can fuse, with two new filters "Fuse normal ×5" and "Fuse holo ×3"'),
  ('⚡', 'Bonus : la Pioche du jour se rouvre à minuit sans quitter l\'onglet, et le Défi express avance en direct',
      'Bonus: the Daily draw reopens at midnight without leaving the tab, and the Express challenge progresses live'),
  ('🏆', '7 nouveaux trophées : Pioche chanceuse, Éclair (défis express), Roue de la fortune, Dresseur (Pokémon), Supporter (réactions de l\'Actu), Artisan (fabrication) et Fan de sagas',
      '7 new trophies: Lucky draw, Lightning (express challenges), Wheel of fortune, Trainer (Pokémon), Supporter (News reactions), Crafter and Saga fan'),
  ('#', 'Aussi depuis la 1.0.40', 'Also since 1.0.40'),
  ('🃏', 'Bonus : « Pioche du jour » (5 cartes face cachée, tu en choisis une, pas de seconde chance, toutes les cartes sauf Pokémon) et « Défi express » (une mission du jour, récompense à récupérer)',
      'Bonus: "Daily draw" (5 face-down cards, pick one, no second chance, any card except Pokémon) and "Express challenge" (a daily mission, reward to claim)'),
  ('👏', 'Actu : deux nouvelles réactions, « Merci » 🙏 et « Bravo » 🎉',
      'News: two new reactions, "Thanks" 🙏 and "Bravo" 🎉'),
  ('🗑', 'Messages : appui long sur ton message pour le supprimer',
      'Messages: long-press your message to delete it'),
  ('🔎', 'Collection : bouton « Possédées » sur les onglets Pokémon et Full art',
      'Collection: "Owned" button on the Pokémon and Full art tabs'),
  ('✨', 'Full art : reflet arc-en-ciel plus doux, sans lignes colorées qui traversent la carte',
      'Full art: softer rainbow shine, no coloured lines across the card'),
  ('🤝', 'Échanges : plus de « ta dernière tu ne l\'auras plus » à tort sur une carte que tu as en double',
      'Trades: no more wrong "you won\'t have it anymore" on a card you own twice'),
  ('#', 'Aussi depuis la 1.0.39', 'Also since 1.0.39'),
  ('🎡', 'Roue de la fortune : un tour toutes les 12 h, gains doublés (jusqu\'à 600 pièces, 2 000 en or) et une nouvelle case POKÉMON : la carte t\'attend dans « Cartes à ranger »',
      'Wheel of fortune: one spin every 12 h, doubled prizes (up to 600 coins, 2,000 when golden) and a new POKÉMON slot: the card waits in your card stock'),
  ('📅', 'Défis de la semaine plus longs : objectifs plus hauts et récompenses plus grosses (200 à 300 pièces)',
      'Longer weekly challenges: higher goals and bigger rewards (200 to 300 coins)'),
  ('🃏', 'Cartes Pokémon : effet brillant et étoiles dès la 152 (« Basic » avant), et affichage instantané (images gardées sur l\'appareil)',
      'Pokémon cards: shiny effect and stars from #152 ("Basic" before), and instant display (images kept on the device)'),
  ('🤝', 'Échanges : les cartes que tu proposes sortent de ton stock tant que l\'échange est en attente (rendues si annulé ou refusé)',
      'Trades: cards you offer leave your stock while the trade is pending (returned if cancelled or declined)'),
  ('🎮', 'Voisinage : un joueur en solo (Rétro Jump, Course) s\'affiche « En solo » au lieu de « Regarder », et le statut se met à jour en direct',
      'Neighborhood: a player in a solo run shows "Playing solo" instead of "Watch", updated live'),
  ('#', 'Aussi depuis la 1.0.38', 'Also since 1.0.38'),
  ('🏃', 'Course de jaquettes : plus de limite de temps, ça dure jusqu\'à ta chute et la vitesse augmente doucement. Rétro Jump : plus de limite de 2 minutes non plus',
      'Cover Run: no more time limit, it lasts until you fall and the speed slowly keeps rising. Retro Jump: no 2-minute limit either'),
  ('🕹️', 'Snake : virages plus faciles (swipe plus sensible, joystick plus stable, virages enchaînés mieux pris en compte)',
      'Snake: easier turns (more sensitive swipe, steadier joystick, chained turns handled better)'),
  ('#', 'Aussi depuis la 1.0.37', 'Also since 1.0.37'),
  ('🕹️', 'Snake : un joystick tactile remplace les flèches. Course de jaquettes : boutons « Sauter » et « Glisser » en bas de l\'écran',
      'Snake: a touch joystick replaces the arrows. Cover Run: "Jump" and "Slide" buttons at the bottom of the screen'),
  ('#', 'Aussi depuis la 1.0.36', 'Also since 1.0.36'),
  ('🃏', 'Le nombre de cartes Pokémon apparaît maintenant dans les profils (séries et comparaison entre joueurs)',
      'The number of Pokémon cards now shows in profiles (sets and player comparison)'),
  ('#', 'Aussi depuis la 1.0.35', 'Also since 1.0.35'),
  ('🛠', 'Correction : changer d\'avatar ou de pseudo ne bloque plus quand une carte de la vitrine n\'est plus possédée',
      'Fix: changing avatar or name no longer fails when a showcase card is no longer owned'),
  ('#', 'Aussi depuis la 1.0.34', 'Also since 1.0.34'),
  ('🃏', 'Les cartes Pokémon s\'affichent en plein cadre, avec leur propre dos de carte',
      'Pokémon cards now show full frame, with their own card back'),
  ('⚡', 'Fiche Pokémon épurée (nom, Bourse, Vitrine) et nouvelle ligne Pokémon dans la progression de la Collection',
      'Cleaner Pokémon card page (name, Exchange, Showcase) and a new Pokémon line in the Collection progress'),
  ('#', 'Aussi depuis la 1.0.33', 'Also since 1.0.33'),
  ('🃏', 'Nouvel onglet « Pokémon » dans la Collection : 185 cartes très très rares à trouver dans les paquets',
      'New "Pokémon" tab in the Collection: 185 very very rare cards to find in packs'),
  ('✨', 'À partir de la carte 152, les cartes Pokémon sortent toujours brillantes',
      'From card 152 on, Pokémon cards always come out shiny'),
  ('#', 'Aussi depuis la 1.0.32', 'Also since 1.0.32'),
  ('🏃', 'Nouveau jeu dans la Salle de jeux : la Course de jaquettes ! Saute et glisse pour aller le plus loin possible',
      'New game in the Game room: Cover Run! Jump and slide to go as far as you can'),
  ('🥇', 'Course solo du jour (même parcours pour tous, lots pour les 3 meilleurs) et duels en direct avec le fantôme de l\'adversaire',
      'Daily solo run (same course for everyone, prizes for the top 3) and live duels with your opponent\'s ghost'),
  ('#', 'Aussi depuis la 1.0.31', 'Also since 1.0.31'),
  ('★★', 'Onglet Full art : touche une carte que tu n\'as pas pour ouvrir la page « Fabriquer » et la fabriquer avec tes fragments',
      'Full art tab: tap a card you don\'t have to open the "Craft" page and craft it with your fragments'),
  ('🔢', 'Ton compteur de fragments est affiché en haut de l\'onglet Full art',
      'Your fragment counter is shown at the top of the Full art tab'),
  ('#', 'Aussi depuis la 1.0.30', 'Also since 1.0.30'),
  ('♻', 'Le recyclage ne donne plus de pièces mais des fragments de full art (mêmes quantités qu\'avant)',
      'Recycling no longer gives coins but full art fragments (same amounts as before)'),
  ('★', 'Une full art coûte 3 000 fragments (épique) ou 10 000 (légendaire)',
      'A full art costs 3,000 fragments (epic) or 10,000 (legendary)'),
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
