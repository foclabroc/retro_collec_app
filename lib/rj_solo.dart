part of 'connect4.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Rétro Jump solo du jour (27/10) : un parcours par jour, le même pour tous (graine du serveur),
// parties illimitées, le meilleur score du jour compte. Le lendemain, les 3 premiers sont
// récompensés (1er 500 pièces + 2 pixels, 2e 300 + 1 pixel, 3e 100) et inscrits dans l'historique.
// SQL : sql/2026-10-27_rj_solo.sql (rc_rj_solo_start / _end / _board / _winners).
// Entrée : RjSoloCard dans le salon Rétro Jump (DuelKind.header).
// ═══════════════════════════════════════════════════════════════════════════

/// « 300 🪙 + 2 ▦ »
String _rjPrize(dynamic r) {
  final m = r is Map ? r : const {};
  final c = _i(m['coins']), p = _i(m['pixels']);
  return [if (c > 0) '$c 🪙', if (p > 0) '$p ▦'].join(' + ');
}

String _rjDay(String? d) {
  final x = DateTime.tryParse(d ?? '');
  if (x == null) return d ?? '';
  const mois = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return t('${x.day} ${mois[x.month - 1]}', '${months[x.month - 1]} ${x.day}');
}

const _kPlaceIcons = ['🥇', '🥈', '🥉'];

/// Lance une partie solo puis revient avec le classement à jour (null si pas lancée)
Future<Map<String, dynamic>?> _rjSoloPlay(BuildContext context) async {
  Map<String, dynamic> st;
  try {
    st = await RcServer.rjSoloStart();
  } catch (e) {
    toast(errText(e));
    return null;
  }
  if (!context.mounted) return null;
  final r = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => RjSoloRunPage(start: st)));
  Game.i.sync();
  return r;
}

/// Case du salon : mon record du jour, le leader, les lots, Jouer
class RjSoloCard extends StatefulWidget {
  const RjSoloCard({super.key});
  @override
  State<RjSoloCard> createState() => _RjSoloCardState();
}

class _RjSoloCardState extends State<RjSoloCard> {
  Map<String, dynamic>? b;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await RcServer.rjSoloBoard();
      if (mounted) setState(() => b = r);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final top = (b?['top'] as List?) ?? const [];
    final lead = top.isEmpty ? null : top.first as Map;
    final rank = b?['rank'];
    final prizes = (b?['prizes'] as List?) ?? const [];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RjSoloPage()));
          _load();
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kRjGreen.withOpacity(0.7), width: 1.5),
            gradient: const LinearGradient(colors: [Color(0xFF123A3A), Color(0xFF12184E)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: Row(children: [
            const SizedBox(width: 44, height: 56, child: CustomPaint(painter: _RjRocketIcon())),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('SOLO DU JOUR', 'DAILY SOLO'), style: pixelStyle(size: 10, color: _kRjGreen, shadow: false)),
                const SizedBox(height: 4),
                Text(t('Même parcours pour tous aujourd\'hui · les 3 premiers gagnent', 'Same course for everyone today · top 3 win'),
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
                if (prizes.length == 3)
                  Text('🥇 ${_rjPrize(prizes[0])}  🥈 ${_rjPrize(prizes[1])}  🥉 ${_rjPrize(prizes[2])}',
                      style: const TextStyle(fontSize: 11.5, color: _kGoldHi, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(
                  [
                    if (_i(b?['best']) > 0) t('Ton record : ${b!['best']}${rank != null ? ' (${rank}e)' : ''}', 'Your best: ${b!['best']}${rank != null ? ' (#$rank)' : ''}'),
                    if (lead != null) t('1er : ${lead['name']} ${lead['score']}', '1st: ${lead['name']} ${lead['score']}'),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: Colors.white54),
                ),
              ]),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _kRjGreen, foregroundColor: const Color(0xFF06281B), visualDensity: VisualDensity.compact),
              onPressed: () async {
                final r = await _rjSoloPlay(context);
                if (r != null && mounted) setState(() => b = r);
              },
              child: Text(t('Jouer', 'Play'), style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _RjRocketIcon extends CustomPainter {
  const _RjRocketIcon();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height - 4);
    rjDrawRocket(canvas, true, kRjRed, 0);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Page du solo : lots, mon record, classement du jour, gagnants d'hier, historique
class RjSoloPage extends StatefulWidget {
  const RjSoloPage({super.key});
  @override
  State<RjSoloPage> createState() => _RjSoloPageState();
}

class _RjSoloPageState extends State<RjSoloPage> {
  Map<String, dynamic>? b;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await RcServer.rjSoloBoard();
      if (mounted) setState(() => b = r);
    } catch (e) {
      toast(errText(e));
    }
  }

  Widget _row(Map p, int place, {bool gold = false}) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p['me'] == true ? _kRjGreen : place <= 3 ? _kGoldHi.withOpacity(0.5) : Colors.white10),
        ),
        child: Row(children: [
          SizedBox(
            width: 30,
            child: Text(place <= 3 ? _kPlaceIcons[place - 1] : '$place', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 6),
          _avatar(_i(p['avatar']), size: 30),
          const SizedBox(width: 8),
          Expanded(child: Text(p['me'] == true ? t('${p['name']} (toi)', '${p['name']} (you)') : p['name'] as String? ?? '?', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
          if (p['reward'] != null) Padding(padding: const EdgeInsets.only(right: 8), child: Text(_rjPrize(p['reward']), style: const TextStyle(fontSize: 11.5, color: _kGoldHi))),
          Text('${p['score']}', style: pixelStyle(size: 10, color: gold ? _kGoldHi : Colors.white, shadow: false)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final top = ((b?['top'] as List?) ?? const []).cast<Map>();
    final yest = ((b?['yesterday'] as List?) ?? const []).cast<Map>();
    final prizes = (b?['prizes'] as List?) ?? const [];
    final best = _i(b?['best']);
    return MaxWidth(
      max: 640,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('SOLO DU JOUR', 'DAILY SOLO'), style: pixelStyle(size: 12)),
          actions: [
            IconButton(
              tooltip: t('Historique des gagnants', 'Winners history'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RjWinnersPage())),
              icon: const Icon(Icons.emoji_events_outlined),
            ),
          ],
        ),
        body: b == null
            ? const Center(child: CircularProgressIndicator(color: kGold))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.fromLTRB(14, 10, 14, 24), children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _kRjGreen.withOpacity(0.7), width: 1.5),
                      gradient: const LinearGradient(colors: [Color(0xFF123A3A), Color(0xFF12184E)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                          t('Le même parcours pour tout le monde aujourd\'hui. Joue autant que tu veux : ton meilleur score compte. Demain, les 3 premiers sont récompensés.',
                              'The same course for everyone today. Play as much as you like: your best score counts. Tomorrow, the top 3 get rewarded.'),
                          style: const TextStyle(color: Color(0xFFCFD3FF), fontSize: 12.5, height: 1.4)),
                      const SizedBox(height: 10),
                      if (prizes.length == 3)
                        Wrap(spacing: 12, runSpacing: 4, children: [
                          for (var k = 0; k < 3; k++) Text('${_kPlaceIcons[k]} ${_rjPrize(prizes[k])}', style: const TextStyle(color: _kGoldHi, fontWeight: FontWeight.w900)),
                        ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: Text(
                            best > 0
                                ? t('Ton record du jour : $best${b!['rank'] != null ? ' · ${b!['rank']}e sur ${b!['players']}' : ''}',
                                    'Your best today: $best${b!['rank'] != null ? ' · #${b!['rank']} of ${b!['players']}' : ''}')
                                : t('Pas encore joué aujourd\'hui', 'Not played today yet'),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: _kRjGreen, foregroundColor: const Color(0xFF06281B)),
                          onPressed: () async {
                            final r = await _rjSoloPlay(context);
                            if (r != null && mounted) setState(() => b = r);
                          },
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(t('Jouer', 'Play'), style: const TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  Text(t('Classement du jour', 'Today\'s ranking'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  const SizedBox(height: 8),
                  if (top.isEmpty)
                    Text(t('Personne n\'a encore joué aujourd\'hui : à toi d\'ouvrir le bal !', 'Nobody has played today yet: be the first!'), style: const TextStyle(color: Colors.white54)),
                  for (var k = 0; k < top.length; k++) _row(top[k], k + 1, gold: k < 3),
                  if (yest.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(t('Gagnants d\'hier', 'Yesterday\'s winners'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(height: 8),
                    for (final w in yest) _row(w, _i(w['place']), gold: true),
                  ],
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RjWinnersPage())),
                      icon: const Icon(Icons.history),
                      label: Text(t('Historique des gagnants', 'Winners history')),
                    ),
                  ),
                ]),
              ),
      ),
    );
  }
}

/// Historique des gagnants (60 derniers jours)
class RjWinnersPage extends StatefulWidget {
  const RjWinnersPage({super.key});
  @override
  State<RjWinnersPage> createState() => _RjWinnersPageState();
}

class _RjWinnersPageState extends State<RjWinnersPage> {
  List<Map<String, dynamic>>? days;

  @override
  void initState() {
    super.initState();
    RcServer.rjSoloWinners().then((l) {
      if (mounted) setState(() => days = l);
    }).catchError((e) {
      if (mounted) setState(() => days = []);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaxWidth(
      max: 640,
      child: Scaffold(
        appBar: AppBar(title: Text(t('GAGNANTS DU SOLO', 'SOLO WINNERS'), style: pixelStyle(size: 12))),
        body: days == null
            ? const Center(child: CircularProgressIndicator(color: kGold))
            : days!.isEmpty
                ? Center(child: Text(t('Pas encore de gagnant : le premier jour se termine à minuit.', 'No winner yet: the first day ends at midnight.'), style: const TextStyle(color: Colors.white54)))
                : ListView(padding: const EdgeInsets.fromLTRB(14, 10, 14, 24), children: [
                    for (final d in days!)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                        decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white10)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_rjDay(d['day'] as String?), style: const TextStyle(fontWeight: FontWeight.w900, color: _kRjGreen)),
                          const SizedBox(height: 6),
                          for (final w in ((d['list'] as List?) ?? const []).cast<Map>())
                            Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Row(children: [
                                Text(_kPlaceIcons[(_i(w['place'], 1) - 1).clamp(0, 2)], style: const TextStyle(fontSize: 16)),
                                const SizedBox(width: 8),
                                _avatar(_i(w['avatar']), size: 26),
                                const SizedBox(width: 8),
                                Expanded(child: Text(w['pid'] == Game.i.pid ? t('${w['name']} (toi)', '${w['name']} (you)') : w['name'] as String? ?? '?', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                                Text('${w['score']}', style: pixelStyle(size: 9, color: Colors.white, shadow: false)),
                                const SizedBox(width: 10),
                                Text(_rjPrize(w['reward']), style: const TextStyle(fontSize: 11.5, color: _kGoldHi)),
                              ]),
                            ),
                        ]),
                      ),
                  ]),
      ),
    );
  }
}

// ─── Une partie solo ───────────────────────────────────────────────────────

class RjSoloRunPage extends StatefulWidget {
  final Map<String, dynamic> start; // {run, seed, day, best}
  const RjSoloRunPage({super.key, required this.start});
  @override
  State<RjSoloRunPage> createState() => _RjSoloRunPageState();
}

class _RjSoloRunPageState extends State<RjSoloRunPage> with SingleTickerProviderStateMixin {
  late Map<String, dynamic> st = widget.start;
  late RjWorld world;
  late RjHero hero;
  Ticker? _ticker;
  Duration? _t0; // instant du « GO » (temps du ticker)
  Duration _now = Duration.zero;
  double simT = 0;
  int _lastCount = 99;
  bool _sent = false;
  Map<String, dynamic>? _result; // classement renvoyé à la fin
  List<Map> _top = [];
  final Map<int, double> _pointers = {};
  final Set<LogicalKeyboardKey> _keys = {};
  final _focus = FocusNode();
  double _boxW = 1;

  int get best => _i(st['best']);

  @override
  void initState() {
    super.initState();
    _reset();
    _ticker = createTicker(_onTick)..start();
    RcServer.rjSoloBoard().then((b) {
      if (mounted) setState(() => _top = ((b['top'] as List?) ?? const []).cast<Map>().take(3).toList());
    }).catchError((_) {});
  }

  void _reset() {
    world = RjWorld(_i(st['seed'], 1));
    hero = RjHero(world)..onSfx = RcAudio.sfx;
    simT = 0;
    _t0 = null;
    _lastCount = 99;
    _sent = false;
    _result = null;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _focus.dispose();
    // quitter en cours de partie : le score atteint compte quand même
    if (!_sent && hero.score > 0) RcServer.rjSoloEnd(_i(st['run']), hero.score).catchError((_) => <String, dynamic>{});
    super.dispose();
  }

  void _onTick(Duration el) {
    if (!mounted) return;
    _now = el;
    _t0 ??= el + const Duration(seconds: 3); // 3, 2, 1, GO
    final t = (el - _t0!).inMicroseconds / 1e6;
    if (t < 0) {
      final c = (-t).ceil();
      if (c != _lastCount) {
        _lastCount = c;
        RcAudio.sfx('tier');
      }
    } else if (!hero.dead) {
      if (_lastCount != 0) {
        _lastCount = 0;
        RcAudio.sfx('powerup');
      }
      if (t - simT > 0.25) simT = t - 0.25;
      final dir = _dir();
      while (simT + kRjStep <= t) {
        simT += kRjStep;
        hero.step(kRjStep, simT, dir);
        if (hero.dead) break;
      }
      if (hero.dead) _end();
    } else {
      simT = t; // le monde continue de bouger derrière le résultat
    }
    setState(() {});
  }

  Future<void> _end() async {
    if (_sent) return;
    _sent = true;
    RcAudio.lose();
    for (var k = 0; k < 3; k++) {
      try {
        final r = await RcServer.rjSoloEnd(_i(st['run']), hero.score);
        if (!mounted) return;
        if (r['record'] == true) RcAudio.win();
        setState(() => _result = r);
        return;
      } catch (_) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    if (mounted) setState(() => _result = {'score': hero.score, 'error': true});
  }

  Future<void> _again() async {
    try {
      final s = await RcServer.rjSoloStart();
      if (!mounted) return;
      setState(() {
        st = s;
        _reset();
      });
    } catch (e) {
      toast(errText(e));
    }
  }

  double _dir() {
    var d = 0.0;
    if (_pointers.isNotEmpty) d = _pointers.values.last < _boxW / 2 ? -1 : 1;
    final l = _keys.contains(LogicalKeyboardKey.arrowLeft) || _keys.contains(LogicalKeyboardKey.keyA) || _keys.contains(LogicalKeyboardKey.keyQ);
    final r = _keys.contains(LogicalKeyboardKey.arrowRight) || _keys.contains(LogicalKeyboardKey.keyD);
    if (l != r) d = l ? -1 : 1;
    return d;
  }

  List<(double, String, Color)> _lines() => [
        for (var k = 0; k < _top.length; k++)
          if (_top[k]['me'] != true) (_i(_top[k]['score']) * 10.0, '${_kPlaceIcons[k]} ${_top[k]['name']} ${_top[k]['score']}', k == 0 ? _kGoldHi : kRjBlue),
        if (best > 0) (best * 10.0, t('🏁 Ton record $best', '🏁 Your best $best'), kRjRed),
      ];

  Widget _resultBox() {
    final r = _result!;
    final rank = r['rank'];
    return Center(
      child: Container(
        margin: const EdgeInsets.all(22),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        decoration: BoxDecoration(color: const Color(0xEE141A4C), borderRadius: BorderRadius.circular(16), border: Border.all(color: _kRjGreen, width: 1.5)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(r['record'] == true ? t('NOUVEAU RECORD !', 'NEW BEST!') : t('PERDU !', 'GAME OVER'),
              style: pixelStyle(size: 12, color: r['record'] == true ? _kGoldHi : Colors.white, shadow: false)),
          const SizedBox(height: 10),
          Text('${_i(r['score'])}', style: pixelStyle(size: 22, color: Colors.white, shadow: false)),
          const SizedBox(height: 8),
          if (r['error'] == true)
            Text(t('Score pas envoyé (réseau)', 'Score not sent (network)'), style: const TextStyle(color: Color(0xFFFF8A95)))
          else
            Text(
              rank != null
                  ? t('Ton meilleur : ${r['best']} · ${rank}e sur ${r['players']}', 'Your best: ${r['best']} · #$rank of ${r['players']}')
                  : t('Ton meilleur : ${r['best']}', 'Your best: ${r['best']}'),
              style: const TextStyle(color: Colors.white70),
            ),
          const SizedBox(height: 12),
          Row(mainAxisSize: MainAxisSize.min, children: [
            OutlinedButton(onPressed: () => Navigator.of(context).pop(r['error'] == true ? null : r), child: Text(t('Classement', 'Ranking'))),
            const SizedBox(width: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _kRjGreen, foregroundColor: const Color(0xFF06281B)),
              onPressed: _again,
              icon: const Icon(Icons.replay),
              label: Text(t('Rejouer', 'Play again'), style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t0 = _t0;
    final count = t0 == null ? 3 : (-(_now - t0).inMicroseconds / 1e6).ceil();
    return Scaffold(
      backgroundColor: const Color(0xFF07051A),
      appBar: AppBar(
        title: Text(t('SOLO DU JOUR', 'DAILY SOLO'), style: pixelStyle(size: 12)),
        actions: [
          Center(child: Text('${hero.score}', style: pixelStyle(size: 12, color: _kRjGreen, shadow: false))),
          const SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: AspectRatio(
            aspectRatio: kRjW / kRjH,
            child: LayoutBuilder(builder: (context, box) {
              _boxW = box.maxWidth;
              return Focus(
                focusNode: _focus,
                autofocus: true,
                onKeyEvent: (_, e) {
                  if (e is KeyDownEvent) _keys.add(e.logicalKey);
                  if (e is KeyUpEvent) _keys.remove(e.logicalKey);
                  return KeyEventResult.handled;
                },
                child: Listener(
                  onPointerDown: (e) => _pointers[e.pointer] = e.localPosition.dx,
                  onPointerMove: (e) => _pointers[e.pointer] = e.localPosition.dx,
                  onPointerUp: (e) => _pointers.remove(e.pointer),
                  onPointerCancel: (e) => _pointers.remove(e.pointer),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(fit: StackFit.expand, children: [
                      CustomPaint(
                        painter: RjPainter(
                          world: world,
                          camY: hero.camY,
                          t: simT,
                          runners: [RjRunner(hero.x, hero.height, hero.right, kRjRed, squash: hero.squash, dead: hero.dead)],
                          lines: _lines(),
                        ),
                      ),
                      if (count > 0)
                        Center(child: Text('$count', style: pixelStyle(size: 34, color: Colors.white, shadow: false)))
                      else if (count == 0 && simT < 0.6)
                        Center(child: Text('GO !', style: pixelStyle(size: 30, color: _kRjGreen, shadow: false))),
                      if (count > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 14,
                          child: Text(
                            t('Touche à gauche ou à droite (ou ← →) pour te déplacer', 'Touch left or right (or ← →) to move'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700, shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
                          ),
                        ),
                      if (hero.dead && _result == null) const Center(child: CircularProgressIndicator(color: _kRjGreen)),
                      if (_result != null) _resultBox(),
                    ]),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
