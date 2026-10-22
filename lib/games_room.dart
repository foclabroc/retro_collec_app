import 'package:flutter/material.dart';

import 'connect4.dart';
import 'game.dart';
import 'layout.dart';
import 'main.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Onglet « Salle de jeux » (8) : les jeux à 2 joueurs (4 en ligne, Console Wars),
// sortis de « Bonus / Jeux », et le bouton « Jeux en cours » (duels en direct
// des autres joueurs, à regarder en spectateur : WatchList de spectate.dart).
// ═══════════════════════════════════════════════════════════════════════════

class GamesRoomScreen extends StatefulWidget {
  const GamesRoomScreen({super.key});
  @override
  State<GamesRoomScreen> createState() => GamesRoomScreenState();
}

class GamesRoomScreenState extends State<GamesRoomScreen> {
  static GamesRoomScreenState? current;

  @override
  void initState() {
    super.initState();
    current = this;
  }

  @override
  void dispose() {
    if (current == this) current = null;
    super.dispose();
  }

  /// Onglet affiché : liste des parties en cours à jour
  void load() => LiveGames.i.refresh();

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TabHeader(t('Salle de jeux', 'Game room'), icon: 'games'),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () => LiveGames.i.refresh(),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: const [
            _LiveGamesButton(),
            SizedBox(height: 12),
            Connect4Tile(),
            SizedBox(height: 12),
            BattleTile(),
          ]),
        ),
      ),
    ]);
  }
}

/// Bouton « Jeux en cours » : nombre de duels en direct à regarder
class _LiveGamesButton extends StatelessWidget {
  const _LiveGamesButton();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LiveGames.i,
      builder: (context, _) {
        final n = LiveGames.i.others('c4').length + LiveGames.i.others('bs').length;
        return Material(
          color: kPanel,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LiveGamesPage())),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: n > 0 ? kGold : Colors.white12),
              ),
              child: Row(children: [
                const Text('👁', style: TextStyle(fontSize: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('Jeux en cours', 'Live games'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(
                      n == 0
                          ? t('Aucune partie en direct pour l\'instant', 'No live game right now')
                          : t('$n partie${n > 1 ? 's' : ''} à regarder en direct', '$n game${n > 1 ? 's' : ''} to watch live'),
                      style: TextStyle(fontSize: 12, color: n > 0 ? kGold : Colors.white54),
                    ),
                  ]),
                ),
                const Icon(Icons.chevron_right, color: Colors.white54),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Page « Jeux en cours » : duels en direct des autres joueurs
class LiveGamesPage extends StatelessWidget {
  const LiveGamesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Jeux en cours', 'Live games'))),
      body: MaxWidth(
        child: RefreshIndicator(
          onRefresh: () => LiveGames.i.refresh(),
          child: ListenableBuilder(
            listenable: LiveGames.i,
            builder: (context, _) {
              final empty = LiveGames.i.others('c4').isEmpty && LiveGames.i.others('bs').isEmpty;
              return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
                Text(t('Touche une partie pour la regarder en direct', 'Tap a game to watch it live'),
                    style: const TextStyle(color: Colors.white38, fontSize: 12)),
                const SizedBox(height: 8),
                const WatchList(),
                if (empty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Text(t('Aucune partie en direct pour l\'instant.\nLa liste se met à jour toute seule.',
                            'No live game right now.\nThe list updates by itself.'),
                        textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
                  ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}
