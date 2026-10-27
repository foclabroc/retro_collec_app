part of 'connect4.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Spectateur : regarder les duels en direct des autres joueurs (1.0.18).
//  · LiveGames.i : liste des duels en direct en cours (rc_live_games), rechargée
//    sur l'événement 'duels' du canal commun (live_events.dart) tant que quelqu'un l'affiche.
//  · watchGame / watchPlayer : ouvre la page de jeu habituelle en mode « watch »
//    (Connect4GamePage / BattleGamePage, vue du joueur 1, rien à toucher),
//    les coups arrivent par LiveLink.watch (canal de la partie).
//  · Points d'entrée : salon (« 👁 À regarder », « Regarder » à la place de « Occupé »)
//    et liste « En ligne » (bouton 👁 sur un joueur en partie).
// ═══════════════════════════════════════════════════════════════════════════

class LiveGames extends ChangeNotifier {
  static final i = LiveGames();
  List<Map<String, dynamic>> list = [];
  bool _busy = false;

  /// Quelqu'un affiche la liste (sinon pas la peine de recharger sur événement)
  bool get watched => hasListeners;

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      list = await RcServer.liveGames();
      notifyListeners();
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  /// Parties d'un jeu sans moi dedans
  List<Map<String, dynamic>> others(String game) =>
      list.where((g) => g['game'] == game && _pid(g, 'p1') != Game.i.pid && _pid(g, 'p2') != Game.i.pid).toList();

  Map<String, dynamic>? ofPid(String pid) => list.where((g) => _pid(g, 'p1') == pid || _pid(g, 'p2') == pid).firstOrNull;

  static String? _pid(Map g, String k) => (g[k] as Map?)?['pid'] as String?;
}

/// Ouvre une partie en spectateur
Future<void> watchGame(BuildContext context, String game, int id) async {
  try {
    final st = switch (game) { 'bs' => await RcServer.bsWatch(id), 'rj' => await RcServer.rjWatch(id), _ => await RcServer.c4Watch(id) };
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => switch (game) {
              'bs' => BattleGamePage(initial: st, watch: true),
              'rj' => RjGamePage(initial: st, watch: true),
              _ => Connect4GamePage(initial: st, watch: true),
            }));
  } catch (e) {
    toast(t('Cette partie est terminée', 'This game is over'));
    LiveGames.i.refresh();
  }
}

/// Regarder la partie en direct d'un joueur (liste « En ligne »)
Future<void> watchPlayer(BuildContext context, String pid) async {
  await LiveGames.i.refresh();
  final g = LiveGames.i.ofPid(pid);
  if (!context.mounted) return;
  if (g == null) {
    toast(t('Sa partie vient de se terminer', 'Their game just ended'));
    return;
  }
  await watchGame(context, g['game'] as String, _i(g['id']));
}

/// Carte d'une partie à regarder : « A vs B » + bouton Regarder
class WatchGameRow extends StatelessWidget {
  final Map<String, dynamic> g;
  final bool showGame;
  const WatchGameRow({super.key, required this.g, this.showGame = false});

  @override
  Widget build(BuildContext context) {
    final p1 = g['p1'] as Map? ?? const {}, p2 = g['p2'] as Map? ?? const {};
    final bs = g['game'] == 'bs', rj = g['game'] == 'rj';
    final setup = g['phase'] == 'setup';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFB57BFF).withOpacity(0.6)),
      ),
      child: Row(children: [
        SizedBox(
          width: 64,
          height: 38,
          child: Stack(children: [
            Positioned(left: 0, child: _avatar(_i(p1['avatar']), size: 34, ring: bs ? _kCyan : _kRed)),
            Positioned(left: 26, child: _avatar(_i(p2['avatar']), size: 34, ring: bs ? _kNeon : rj ? kRjBlue : _kYellow)),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p1['name'] ?? '?'}  vs  ${p2['name'] ?? '?'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
            Text(
              [
                if (showGame) bs ? '🚢 Console Wars' : rj ? '🚀 Rétro Jump' : t('🔴 4 en ligne', '🔴 Connect 4'),
                rj
                    ? '${_i(g['h1'])} – ${_i(g['h2'])} pts'
                    : setup
                        ? t('placement des flottes', 'placing fleets')
                        : t('${_i(g['moves'])} coups', '${_i(g['moves'])} moves'),
              ].join(' · '),
              style: const TextStyle(fontSize: 11.5, color: Colors.white60),
            ),
          ]),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7B3DFF), foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
          onPressed: () => watchGame(context, g['game'] as String, _i(g['id'])),
          child: Text(t('👁 Regarder', '👁 Watch'), style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
      ]),
    );
  }
}

/// Liste des duels à regarder (se recharge toute seule tant qu'elle est affichée)
class WatchList extends StatefulWidget {
  final String? game; // null : tous les jeux
  final Widget Function(int n)? header;
  const WatchList({super.key, this.game, this.header});
  @override
  State<WatchList> createState() => _WatchListState();
}

class _WatchListState extends State<WatchList> {
  @override
  void initState() {
    super.initState();
    LiveGames.i.addListener(_up);
    LiveGames.i.refresh();
  }

  void _up() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    LiveGames.i.removeListener(_up);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.game == null ? [...LiveGames.i.others('c4'), ...LiveGames.i.others('bs'), ...LiveGames.i.others('rj')] : LiveGames.i.others(widget.game!);
    if (l.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.header != null) widget.header!(l.length),
      for (final g in l) WatchGameRow(g: g, showGame: widget.game == null),
    ]);
  }
}
