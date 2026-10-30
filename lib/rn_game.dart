part of 'connect4.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Course de jaquettes (30/10) : runner à obstacles, mêmes obstacles pour tous (graine du serveur).
//  · Duel en direct : parties `rc_rj` avec kind 'run' (même serveur que Rétro Jump, code client 'rn'),
//    2 min max, la plus grande distance gagne ; fantôme par LiveLink.sendPos (événement rjpos).
//  · Solo du jour : rc_rn_solo_* (classement + lots comme Rétro Jump).
//  · Moteur : rn_engine.dart. SQL : sql/2026-10-30_course_jaquettes.sql.
// ═══════════════════════════════════════════════════════════════════════════

final kRnDuel = DuelKind(
  code: 'rn',
  title: 'COURSE DE JAQUETTES',
  liveSub: '2 min · la plus longue distance gagne',
  turnSub: '',
  list: () async => (await RcServer.rjList()).where((g) => g['kind'] == 'run').toList(),
  online: () => RcServer.rjOnline('run'),
  top: () => RcServer.rjTop('run'),
  stats: () => RcServer.rjStats('run'),
  invite: RcServer.rnInvite,
  answer: RcServer.rjAnswer,
  thumb: (g) => const SizedBox(width: 40),
  page: (g) => RnGamePage(initial: g),
  liveOnly: true,
  header: const RjSoloCard(rn: true),
);

/// Case de la Salle de jeux
class CoverRunTile extends StatefulWidget {
  const CoverRunTile({super.key});
  @override
  State<CoverRunTile> createState() => _CoverRunTileState();
}

class _CoverRunTileState extends State<CoverRunTile> {
  int invites = 0, online = 0;
  int _lastBadge = -1;

  @override
  void initState() {
    super.initState();
    _load();
    DuelWatch.i.addListener(_onWatch);
  }

  @override
  void dispose() {
    DuelWatch.i.removeListener(_onWatch);
    super.dispose();
  }

  void _onWatch() {
    final b = DuelWatch.i.live.length;
    if (b == _lastBadge) return;
    _lastBadge = b;
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([kRnDuel.list(), RcServer.rjOnline('run')]);
      if (!mounted) return;
      setState(() {
        invites = r[0].where((g) => g['status'] == 'invite' && g['side'] == 2).length;
        online = r[1].length;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    const c = Color(0xFFFFB74D);
    return Material(
      color: kPanel,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => Connect4Lobby(kind: kRnDuel)));
          _load();
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(colors: [c.withOpacity(0.14), Colors.transparent]),
            boxShadow: [BoxShadow(color: invites > 0 ? const Color(0xFFE24B4A).withOpacity(0.6) : c.withOpacity(0.2), blurRadius: 18, spreadRadius: -6)],
          ),
          foregroundDecoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withOpacity(0.7), width: 2)),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                width: 100,
                height: 92,
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1B2A6B), Color(0xFF3B1F6E)])),
                child: const CustomPaint(painter: _RnThumbPainter()),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Row(children: [
                      Flexible(child: Text(t('Course de jaquettes', 'Cover Run'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: const Color(0x33FFB74D), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFFFB74D))),
                        child: Text(t('(bêta test)', '(beta test)'), style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                    const SizedBox(height: 3),
                    Text(t('Saute ou glisse entre les obstacles : solo du jour avec lots, ou duel en direct ($kDuelWin pièces + 1 pixel)',
                            'Jump or slide past the obstacles: daily solo with prizes, or live duel ($kDuelWin coins + 1 pixel)'),
                        style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    if (online > 0) ...[
                      const SizedBox(height: 4),
                      Text(t('$online en ligne', '$online online'), style: const TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w800)),
                    ],
                    if (invites > 0) ...[
                      const SizedBox(height: 6),
                      PulsePill(t('⚔ $invites défi${invites > 1 ? 's' : ''}', '⚔ $invites challenge${invites > 1 ? 's' : ''}')),
                    ],
                  ]),
                ),
              ),
              const Padding(padding: EdgeInsets.only(right: 12), child: Center(child: Icon(Icons.play_arrow_rounded, color: c, size: 32))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RnThumbPainter extends CustomPainter {
  const _RnThumbPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final g = size.height - 14;
    canvas.drawRect(Rect.fromLTWH(0, g, size.width, 3), Paint()..color = const Color(0xFF69F0AE));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width - 34, g - 20, 22, 20), const Radius.circular(3)), Paint()..color = const Color(0xFFEC407A));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(34, 18, 30, 9), const Radius.circular(3)), Paint()..color = const Color(0xFF5C6BC0));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(14, g - 26, 14, 26), const Radius.circular(4)), Paint()..color = kRnBlue.withOpacity(0.5));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(28, g - 40, 14, 26), const Radius.circular(4)), Paint()..color = kRnRed);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─── Entrées (toucher en haut = saut, en bas = glisse ; ↑ espace W / ↓ S) ───

class RnInput extends StatelessWidget {
  final RnHero? hero;
  final Widget child;
  final bool enabled;
  const RnInput({super.key, required this.hero, required this.child, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      return Focus(
        autofocus: true,
        onKeyEvent: (_, e) {
          final h = hero;
          if (e is KeyDownEvent && h != null && enabled) {
            final k = e.logicalKey;
            if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyW) h.jumpReq = true;
            if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.keyS) h.slideReq = true;
          }
          return KeyEventResult.handled;
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            final h = hero;
            if (h == null || !enabled) return;
            if (e.localPosition.dy < box.maxHeight / 2) {
              h.jumpReq = true;
            } else {
              h.slideReq = true;
            }
          },
          child: child,
        ),
      );
    });
  }
}

// ─── Piste d'un autre joueur (positions reçues en direct) ──────────────────

class RnTrack {
  final String name;
  final int side;
  RnTrack(this.name, this.side);
  final List<(double t, double x, double y, bool slide)> _s = [];
  int score = 0;
  bool dead = false;
  double lastT = -1;

  void add(double t, double x, double y, bool slide, int sc, bool d) {
    if (t <= lastT) return;
    lastT = t;
    _s.add((t, x, y, slide));
    if (_s.length > 40) _s.removeAt(0);
    score = max(score, sc);
    if (d) dead = true;
  }

  bool get has => _s.isNotEmpty;
  double get lastX => _s.isEmpty ? 0 : _s.last.$2;

  (double x, double y, bool slide)? at(double t) {
    if (_s.isEmpty) return null;
    if (t <= _s.first.$1) return (_s.first.$2, _s.first.$3, _s.first.$4);
    for (var i = _s.length - 1; i > 0; i--) {
      final a = _s[i - 1], b = _s[i];
      if (t >= a.$1 && t <= b.$1) {
        final k = b.$1 == a.$1 ? 1.0 : (t - a.$1) / (b.$1 - a.$1);
        return (a.$2 + (b.$2 - a.$2) * k, a.$3 + (b.$3 - a.$3) * k, b.$4);
      }
    }
    final l = _s.last;
    return (l.$2, l.$3, l.$4);
  }
}

// ─── La partie en duel ─────────────────────────────────────────────────────

class RnGamePage extends StatefulWidget {
  final Map<String, dynamic> initial;
  final bool watch;
  const RnGamePage({super.key, required this.initial, this.watch = false});
  @override
  State<RnGamePage> createState() => _RnGamePageState();
}

class _RnGamePageState extends State<RnGamePage> with SingleTickerProviderStateMixin {
  late Map<String, dynamic> g = widget.initial;
  late final RnWorld world = RnWorld(_i(g['seed'], 1));
  late final RnHero hero = RnHero(world)..onSfx = RcAudio.sfx;
  final Map<int, RnTrack> tracks = {};
  Duration _skew = Duration.zero;
  Ticker? _ticker;
  double simT = 0, _nextPos = 0, _nextScore = 2, _cam = 0;
  bool _started = false, _finalSent = false, _resultShown = false, _timeUp = false;
  int _lastCount = 99;
  Timer? _poll;
  StreamSubscription? _rt, _pos;
  WatchCtl? _wctl;

  int get id => _i(g['id']);
  bool get watch => widget.watch;
  int get side => watch ? 1 : _i(g['side'], 1);
  int get oppSide => 3 - side;
  bool get playing => g['status'] == 'playing';
  Map get opp => g['opp'] as Map? ?? const {};
  Map get me => g['me'] as Map? ?? const {};
  String get oppName => opp['name'] as String? ?? '?';
  String get meName => watch ? me['name'] as String? ?? '?' : Game.i.name;
  DateTime? get _startAt => DateTime.tryParse(g['start_at'] as String? ?? '');

  double get _now {
    final s = _startAt;
    if (s == null) return -9;
    return DateTime.now().add(_skew).difference(s).inMicroseconds / 1e6;
  }

  @override
  void initState() {
    super.initState();
    _setSkew();
    tracks[1] = RnTrack(watch ? meName : (side == 1 ? meName : oppName), 1);
    tracks[2] = RnTrack(watch ? oppName : (side == 2 ? meName : oppName), 2);
    if (playing) _wctl = WatchCtl('rj', id, spectator: watch);
    if (watch) {
      LiveLink.i.watch('rj', id);
    } else {
      LiveLink.i.play('rj', id);
      DuelWatch.i.inGame++;
    }
    _pos = LiveLink.i.positions.listen(_onPos);
    _rt = LiveLink.i.events.listen((e) {
      if (e['game'] == 'rj' && _i(e['gid']) == id) _refresh();
    });
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
    _ticker = createTicker(_onTick)..start();
    if (g['status'] == 'done') WidgetsBinding.instance.addPostFrameCallback((_) => _showResult());
    _refresh();
  }

  @override
  void dispose() {
    if (watch) {
      LiveLink.i.unwatch();
    } else {
      LiveLink.i.unplay();
      DuelWatch.i.inGame--;
      if (playing && !hero.dead && !_finalSent && _started) RcServer.rjScore(id, hero.score, true).catchError((_) => <String, dynamic>{});
    }
    _ticker?.dispose();
    _poll?.cancel();
    _rt?.cancel();
    _pos?.cancel();
    _wctl?.dispose();
    super.dispose();
  }

  void _setSkew() {
    final now = DateTime.tryParse(g['now'] as String? ?? '');
    if (now != null) _skew = now.difference(DateTime.now());
  }

  Future<void> _refresh() async {
    try {
      final n = watch ? await RcServer.rjWatch(id) : await RcServer.rjState(id);
      if (mounted) _apply(n);
    } catch (_) {}
  }

  void _apply(Map<String, dynamic> n) {
    final wasPlaying = playing;
    g = n;
    _setSkew();
    final o = tracks[watch ? 2 : oppSide]!;
    o.score = max(o.score, _i(n['h_opp']));
    if (n['dead_opp'] == true) o.dead = true;
    if (watch) {
      tracks[1]!.score = max(tracks[1]!.score, _i(n['h_me']));
      if (n['dead_me'] == true) tracks[1]!.dead = true;
    }
    if (mounted) setState(() {});
    if (wasPlaying && !playing) _showResult();
  }

  void _onPos(Map<String, dynamic> p) {
    final s = _i(p['s']);
    if (s != 1 && s != 2) return;
    if (!watch && s == side) return;
    tracks[s]!.add(_i(p['t']) / 1000, (p['x'] as num? ?? 0) / 10, (p['h'] as num? ?? 0) / 10, p['r'] == 1, _i(p['sc']), p['d'] == 1);
  }

  void _onTick(Duration _) {
    if (!mounted) return;
    final now = _now;
    if (!_started) {
      final left = (-now).ceil();
      if (left != _lastCount && left >= 0 && left <= 3 && playing) {
        _lastCount = left;
        RcAudio.sfx(left == 0 ? 'powerup' : 'tier');
      }
      if (now >= 0 && playing) {
        _started = true;
        simT = now.clamp(0, kRnDuration.toDouble());
        _nextPos = simT;
        _nextScore = simT + 2;
      }
      setState(() {});
      return;
    }
    final target = now.clamp(0.0, kRnDuration.toDouble());
    if (!watch && !hero.dead && !_timeUp && playing) {
      if (target - simT > 0.25) simT = target - 0.25;
      while (simT + kRnStep <= target) {
        simT += kRnStep;
        hero.step(kRnStep, simT);
        if (hero.dead) break;
      }
      if (simT >= _nextPos || hero.dead) {
        _nextPos = simT + 0.1;
        _sendPos();
      }
      if (hero.dead) {
        _finish();
      } else if (now >= kRnDuration) {
        _timeUp = true;
        _finish();
      } else if (simT >= _nextScore) {
        _nextScore = simT + 2;
        RcServer.rjScore(id, hero.score, false).then((n) {
          if (mounted) _apply(n);
        }).catchError((_) {});
      }
    } else {
      simT = target;
    }
    _view(simT);
    setState(() {});
  }

  void _sendPos() => LiveLink.i.sendPos({
        's': side,
        't': (simT * 1000).round(),
        'x': (hero.x * 10).round(),
        'h': (hero.y * 10).round(),
        'r': hero.sliding ? 1 : 0,
        'sc': hero.score,
        'd': hero.dead ? 1 : 0,
      });

  Future<void> _finish() async {
    if (_finalSent) return;
    _finalSent = true;
    if (hero.dead) {
      RcAudio.lose();
      _sendPos();
    }
    for (var k = 0; k < 4; k++) {
      try {
        final n = await RcServer.rjScore(id, hero.score, true);
        if (mounted) _apply(n);
        return;
      } catch (_) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  /// Caméra : la mienne tant que je cours, sinon le coureur encore en course le plus loin
  void _view(double t) {
    if (!watch && !hero.dead && !_timeUp) {
      _cam = hero.x;
      return;
    }
    double? target;
    double best = -1e9;
    for (final tr in tracks.values) {
      if (!watch && tr.side == side) continue;
      final p = tr.at(t - 0.15);
      if (p == null) continue;
      final v = p.$1 + (tr.dead ? 0 : 100000);
      if (v > best) {
        best = v;
        target = p.$1;
      }
    }
    target ??= watch ? 0.0 : hero.x;
    _cam += (target - _cam) * 0.15;
  }

  Future<void> _showResult() async {
    if (_resultShown || !mounted) return;
    _resultShown = true;
    final w = (g['winner'] as num?)?.toInt();
    if (watch) {
      RcAudio.sfx(w == 0 ? 'shield' : 'powerup');
      setState(() {});
      return;
    }
    if (w == side) {
      RcAudio.win();
    } else if (w == 0) {
      RcAudio.sfx('shield');
    } else if (!hero.dead) {
      RcAudio.lose();
    }
    Game.i.sync();
    Map<String, dynamic> stats = {};
    try {
      stats = await RcServer.rjStats('run');
    } catch (_) {}
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    final again = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _ResultDialog(g: g, side: side, stats: stats),
    );
    if (!mounted) return;
    if (again == true) {
      Navigator.of(context).pop({'pid': opp['pid'], 'name': opp['name'], 'avatar': _i(opp['avatar']), 'mode': 'live'});
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<bool> _confirmQuit() async {
    if (watch || !playing || hero.dead || _timeUp || !_started) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Abandonner ?', 'Give up?')),
        content: Text(t('Tu seras compté arrêté à ${hero.score} m.', 'You will count as stopped at ${hero.score} m.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Continuer', 'Keep playing'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Abandonner', 'Give up'))),
        ],
      ),
    );
    if (ok == true) {
      hero.dead = true;
      await _finish();
    }
    return ok == true;
  }

  String _clock() {
    final left = (kRnDuration - max(0.0, _now)).clamp(0, kRnDuration).ceil();
    return '${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}';
  }

  List<RnRunner> _runners() {
    final rt = simT - 0.15;
    final l = <RnRunner>[];
    for (final tr in tracks.values) {
      if (!watch && tr.side == side) continue;
      final col = watch && tr.side == 1 ? kRnRed : kRnBlue;
      final p = tr.at(rt);
      if (p == null) {
        if (!_started || !tr.has) l.add(RnRunner(0, 0, col, label: tr.name, ghost: !watch));
        continue;
      }
      l.add(RnRunner(p.$1, p.$2, col, sliding: p.$3, label: tr.dead ? '💀 ${tr.name}' : tr.name, ghost: !watch, dead: tr.dead));
    }
    if (!watch) l.add(RnRunner(hero.x, hero.y, kRnRed, sliding: hero.sliding, dead: hero.dead));
    return l;
  }

  List<(double, String, Color)> _lines() {
    final l = <(double, String, Color)>[];
    for (final tr in tracks.values) {
      if (!watch && tr.side == side) continue;
      if (tr.score <= 0 || !tr.dead) continue;
      l.add((tr.score.toDouble(), '🏁 ${tr.name} ${tr.score} m', watch && tr.side == 1 ? kRnRed : kRnBlue));
    }
    if (!watch && hero.score > 0 && (hero.dead || _timeUp)) l.add((hero.score.toDouble(), '🏁 ${t('Toi', 'You')} ${hero.score} m', kRnRed));
    return l;
  }

  Widget _chip(String name, int av, int score, Color c, {bool dead = false, bool right = false}) {
    final children = [
      _avatar(av, size: 30, ring: c),
      const SizedBox(width: 6),
      Flexible(
        child: Column(crossAxisAlignment: right ? CrossAxisAlignment.end : CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
          Text('${dead ? '💀 ' : ''}$score m', style: pixelStyle(size: 10, color: c, shadow: false)),
        ]),
      ),
    ];
    return Expanded(child: Row(mainAxisAlignment: right ? MainAxisAlignment.end : MainAxisAlignment.start, children: right ? children.reversed.toList() : children));
  }

  @override
  Widget build(BuildContext context) {
    final now = _now;
    final oppTr = tracks[watch ? 2 : oppSide]!;
    final w = (g['winner'] as num?)?.toInt();
    final done = g['status'] == 'done';
    final myScore = watch ? tracks[1]!.score : hero.score;
    final myAv = watch ? _i(me['avatar']) : Game.i.avatar;
    final myDead = watch ? tracks[1]!.dead : hero.dead;
    String? banner;
    if (!_started && playing) {
      final c = (-now).ceil();
      banner = c > 3 ? t('Prêt ?', 'Ready?') : c > 0 ? '$c' : 'GO !';
    } else if (done && watch) {
      banner = w == 0 ? t('Égalité !', 'Tie!') : '🏆 ${w == 1 ? meName : oppName}';
    } else if (!watch && hero.dead && !done) {
      banner = oppTr.dead ? t('En attente du résultat…', 'Waiting for the result…') : t('💥 Arrêté à ${hero.score} m !\n$oppName doit faire mieux', '💥 Stopped at ${hero.score} m!\n$oppName must beat it');
    } else if (!watch && _timeUp && !done) {
      banner = t('⏱ Temps écoulé !', '⏱ Time\'s up!');
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmQuit() && mounted) Navigator.of(context).pop();
      },
      child: WatchLayer(
        ctl: _wctl,
        child: Scaffold(
          backgroundColor: const Color(0xFF07051A),
          appBar: AppBar(
            title: Text(t('COURSE DE JAQUETTES', 'COVER RUN'), style: pixelStyle(size: 12)),
            actions: [WatchersChip(_wctl), const SizedBox(width: 6)],
          ),
          body: SafeArea(
            top: false,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                child: Row(children: [
                  _chip(watch ? meName : t('Toi', 'You'), myAv, myScore, kRnRed, dead: myDead),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFFB74D).withOpacity(0.6))),
                    child: Text(_started ? _clock() : '2:00', style: pixelStyle(size: 12, color: now > kRnDuration - 10 && playing ? const Color(0xFFFF8A95) : Colors.white, shadow: false)),
                  ),
                  _chip(oppName, _i(opp['avatar']), oppTr.score, kRnBlue, dead: oppTr.dead, right: true),
                ]),
              ),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: kRnW / kRnH,
                    child: RnInput(
                      hero: watch ? null : hero,
                      enabled: _started && !hero.dead && !_timeUp,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(fit: StackFit.expand, children: [
                          CustomPaint(painter: RnPainter(world: world, camX: _cam, runners: _runners(), lines: _lines())),
                          if (banner != null)
                            Center(
                              child: Container(
                                margin: const EdgeInsets.all(20),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(14)),
                                child: Text(px(banner), textAlign: TextAlign.center, style: pixelStyle(size: banner.length <= 4 ? 30 : 12, color: Colors.white, shadow: false).copyWith(height: 1.6)),
                              ),
                            ),
                          if (!_started && playing && !watch)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 14,
                              child: Text(
                                t('Touche en haut (ou ↑ / espace) pour sauter, en bas (ou ↓) pour glisser.\nMêmes obstacles pour vous deux : la plus longue distance gagne !',
                                    'Tap the top (or ↑ / space) to jump, the bottom (or ↓) to slide.\nSame obstacles for both: the longest distance wins!'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700, shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
                              ),
                            ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
              if (duelTour(g))
                Padding(padding: const EdgeInsets.only(bottom: 6, top: 2), child: Text(duelTourNote(g), textAlign: TextAlign.center, style: const TextStyle(color: kGold, fontSize: 11.5, fontWeight: FontWeight.w800)))
              else if (watch && duelFriendly(g))
                Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(duelFriendlyText, style: const TextStyle(color: Colors.white54, fontSize: 11.5))),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── Une partie solo ───────────────────────────────────────────────────────

class RnSoloRunPage extends StatefulWidget {
  final Map<String, dynamic> start; // {run, seed, day, best}
  const RnSoloRunPage({super.key, required this.start});
  @override
  State<RnSoloRunPage> createState() => _RnSoloRunPageState();
}

class _RnSoloRunPageState extends State<RnSoloRunPage> with SingleTickerProviderStateMixin {
  late Map<String, dynamic> st = widget.start;
  late RnWorld world;
  late RnHero hero;
  Ticker? _ticker;
  Duration? _t0;
  Duration _now = Duration.zero;
  double simT = 0;
  int _lastCount = 99;
  bool _sent = false, _timeUp = false;
  Map<String, dynamic>? _result;
  List<Map> _top = [];

  int get best => _i(st['best']);
  bool get over => hero.dead || _timeUp;

  @override
  void initState() {
    super.initState();
    DuelWatch.i.inGame++;
    _reset();
    _ticker = createTicker(_onTick)..start();
    RcServer.rnSoloBoard().then((b) {
      if (mounted) setState(() => _top = ((b['top'] as List?) ?? const []).cast<Map>().take(3).toList());
    }).catchError((_) {});
  }

  void _reset() {
    world = RnWorld(_i(st['seed'], 1));
    hero = RnHero(world)..onSfx = RcAudio.sfx;
    simT = 0;
    _t0 = null;
    _lastCount = 99;
    _sent = false;
    _timeUp = false;
    _result = null;
  }

  @override
  void dispose() {
    DuelWatch.i.inGame--;
    _ticker?.dispose();
    if (!_sent) RcServer.rnSoloEnd(_i(st['run']), hero.score).catchError((_) => <String, dynamic>{});
    super.dispose();
  }

  void _onTick(Duration el) {
    if (!mounted) return;
    _now = el;
    _t0 ??= el + const Duration(seconds: 3);
    final t = (el - _t0!).inMicroseconds / 1e6;
    if (t < 0) {
      final c = (-t).ceil();
      if (c != _lastCount) {
        _lastCount = c;
        RcAudio.sfx('tier');
      }
    } else if (!over) {
      if (_lastCount != 0) {
        _lastCount = 0;
        RcAudio.sfx('powerup');
      }
      if (t - simT > 0.25) simT = t - 0.25;
      while (simT + kRnStep <= t) {
        simT += kRnStep;
        hero.step(kRnStep, simT);
        if (hero.dead) break;
      }
      if (!hero.dead && simT >= kRnDuration) _timeUp = true;
      if (over) _end();
    } else {
      simT = t;
    }
    setState(() {});
  }

  Future<void> _end() async {
    if (_sent) return;
    _sent = true;
    RcAudio.lose();
    for (var k = 0; k < 3; k++) {
      try {
        final r = await RcServer.rnSoloEnd(_i(st['run']), hero.score);
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
      final s = await RcServer.rnSoloStart();
      if (!mounted) return;
      setState(() {
        st = s;
        _reset();
      });
    } catch (e) {
      toast(errText(e));
    }
  }

  List<(double, String, Color)> _lines() => [
        for (var k = 0; k < _top.length; k++)
          if (_top[k]['me'] != true) (_i(_top[k]['score']).toDouble(), '${_kPlaceIcons[k]} ${_top[k]['name']} ${_top[k]['score']} m', k == 0 ? _kGoldHi : kRnBlue),
        if (best > 0) (best.toDouble(), t('🏁 Ton record $best m', '🏁 Your best $best m'), kRnRed),
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
          Text(r['record'] == true ? t('NOUVEAU RECORD !', 'NEW BEST!') : t('PERDU !', 'GAME OVER'), style: pixelStyle(size: 12, color: r['record'] == true ? _kGoldHi : Colors.white, shadow: false)),
          const SizedBox(height: 10),
          Text('${_i(r['score'])} m', style: pixelStyle(size: 22, color: Colors.white, shadow: false)),
          const SizedBox(height: 8),
          if (r['error'] == true)
            Text(t('Score pas envoyé (réseau)', 'Score not sent (network)'), style: const TextStyle(color: Color(0xFFFF8A95)))
          else
            Text(
              rank != null
                  ? t('Ton meilleur : ${r['best']} m · ${rank}e sur ${r['players']}', 'Your best: ${r['best']} m · #$rank of ${r['players']}')
                  : t('Ton meilleur : ${r['best']} m', 'Your best: ${r['best']} m'),
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
          Center(child: Text('${hero.score} m', style: pixelStyle(size: 12, color: _kRjGreen, shadow: false))),
          const SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: AspectRatio(
            aspectRatio: kRnW / kRnH,
            child: RnInput(
              hero: hero,
              enabled: count <= 0 && !over,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(fit: StackFit.expand, children: [
                  CustomPaint(painter: RnPainter(world: world, camX: hero.x, runners: [RnRunner(hero.x, hero.y, kRnRed, sliding: hero.sliding, dead: hero.dead)], lines: _lines())),
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
                        t('Touche en haut (ou ↑ / espace) pour sauter, en bas (ou ↓) pour glisser', 'Tap the top (or ↑ / space) to jump, the bottom (or ↓) to slide'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700, shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
                      ),
                    ),
                  if (over && _result == null) const Center(child: CircularProgressIndicator(color: _kRjGreen)),
                  if (_result != null) _resultBox(),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
