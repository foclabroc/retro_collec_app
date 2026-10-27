part of 'connect4.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Duel Rétro Jump en direct (27/10) : même parcours pour les deux (graine du serveur),
// sans bonus, 2 minutes max, le plus haut gagne. Mêmes gains que le 4 en ligne.
//  · Moteur : rj_engine.dart (monde 360 × 640, physique de Rétro Jump à pas fixe).
//  · Fantôme : ma position part ≈ 10 fois par seconde sur le canal de la partie
//    (LiveLink.sendPos → relais, sans passer par la base) ; celle de l'adversaire arrive
//    par LiveLink.positions et s'affiche en transparence (RjTrack, lissée).
//  · Serveur (sql/2026-10-27_duel_retro_jump.sql) : ma hauteur toutes les 2 s (rc_rj_score),
//    à la chute et à la fin des 2 min ; il décide du gagnant (rc__rj_settle).
//  · Spectateur : les deux joueurs en fantômes, caméra sur le plus haut.
// ═══════════════════════════════════════════════════════════════════════════

const _kRjGreen = Color(0xFF69F0AE);

final kRjDuel = DuelKind(
  code: 'rj',
  title: 'RÉTRO JUMP',
  liveSub: '2 min · le plus haut gagne',
  turnSub: '',
  list: RcServer.rjList,
  online: RcServer.rjOnline,
  top: RcServer.rjTop,
  stats: RcServer.rjStats,
  invite: RcServer.rjInvite,
  answer: RcServer.rjAnswer,
  thumb: (g) => const SizedBox(width: 40),
  page: (g) => RjGamePage(initial: g),
  liveOnly: true,
  header: const RjSoloCard(),
);

/// Case de la Salle de jeux
class RetroJumpTile extends StatefulWidget {
  const RetroJumpTile({super.key});
  @override
  State<RetroJumpTile> createState() => _RetroJumpTileState();
}

class _RetroJumpTileState extends State<RetroJumpTile> {
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
      final r = await Future.wait([RcServer.rjList(), RcServer.rjOnline()]);
      if (!mounted) return;
      setState(() {
        invites = r[0].where((g) => g['status'] == 'invite' && g['side'] == 2).length;
        online = r[1].length;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kPanel,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => Connect4Lobby(kind: kRjDuel)));
          _load();
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(colors: [_kRjGreen.withOpacity(0.14), Colors.transparent]),
            boxShadow: [BoxShadow(color: invites > 0 ? const Color(0xFFE24B4A).withOpacity(0.6) : _kRjGreen.withOpacity(0.2), blurRadius: 18, spreadRadius: -6)],
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kRjGreen.withOpacity(0.7), width: 2),
          ),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                width: 100,
                height: 92,
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1B2A6B), Color(0xFF3B1F6E)])),
                child: const CustomPaint(painter: _RjThumbPainter()),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('Rétro Jump', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 3),
                    Text(t('Course en direct sur le même parcours : 2 minutes, le plus haut gagne $kDuelWin pièces + 1 pixel',
                            'Live race on the same course: 2 minutes, the highest wins $kDuelWin coins + 1 pixel'),
                        style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    if (online > 0) ...[
                      const SizedBox(height: 4),
                      Text(t('$online en ligne', '$online online'), style: const TextStyle(color: _kRjGreen, fontSize: 12, fontWeight: FontWeight.w800)),
                    ],
                    if (invites > 0) ...[
                      const SizedBox(height: 6),
                      PulsePill(t('⚔ $invites défi${invites > 1 ? 's' : ''}', '⚔ $invites challenge${invites > 1 ? 's' : ''}')),
                    ],
                  ]),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Center(child: Icon(Icons.play_arrow_rounded, color: _kRjGreen, size: 32)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Miniature : trois cartouches et la fusée qui saute, son fantôme bleu derrière
class _RjThumbPainter extends CustomPainter {
  const _RjThumbPainter();
  @override
  void paint(Canvas canvas, Size size) {
    void cart(double x, double y, Color c) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, 34, 7), const Radius.circular(2)), Paint()..color = c);
      canvas.drawRect(Rect.fromLTWH(x + 5, y + 1.5, 24, 3), Paint()..color = Colors.white.withOpacity(0.28));
    }

    cart(10, size.height - 18, const Color(0xFF26A69A));
    cart(52, size.height * 0.5, const Color(0xFFEC407A));
    cart(18, 16, const Color(0xFF5C6BC0));
    canvas.save();
    canvas.translate(size.width * 0.38, size.height * 0.62);
    canvas.scale(0.55);
    rjDrawRocket(canvas, true, kRjBlue, 0, opacity: 0.5);
    canvas.restore();
    canvas.save();
    canvas.translate(size.width * 0.66, size.height * 0.42);
    canvas.scale(0.6);
    rjDrawRocket(canvas, false, kRjRed, 0);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─── La partie ─────────────────────────────────────────────────────────────

class RjGamePage extends StatefulWidget {
  final Map<String, dynamic> initial;
  final bool watch; // spectateur (rc_rj_watch : vue du joueur 1)
  const RjGamePage({super.key, required this.initial, this.watch = false});
  @override
  State<RjGamePage> createState() => _RjGamePageState();
}

class _RjGamePageState extends State<RjGamePage> with SingleTickerProviderStateMixin {
  late Map<String, dynamic> g = widget.initial;
  late final RjWorld world = RjWorld(_i(g['seed'], 1));
  late final RjHero hero = RjHero(world)..onSfx = RcAudio.sfx;
  final Map<int, RjTrack> tracks = {};
  Duration _skew = Duration.zero; // heure du serveur - heure du téléphone
  Ticker? _ticker;
  double simT = 0, _nextPos = 0, _nextScore = 2, _viewCam = 0;
  bool _started = false, _finalSent = false, _resultShown = false, _timeUp = false;
  int _lastCount = 99;
  Timer? _poll;
  StreamSubscription? _rt, _pos;
  WatchCtl? _wctl;
  final Map<int, double> _pointers = {};
  final Set<LogicalKeyboardKey> _keys = {};
  final _focus = FocusNode();
  double _boxW = 1;

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

  /// Temps de la partie (secondes depuis le départ, négatif pendant le compte à rebours)
  double get _now {
    final s = _startAt;
    if (s == null) return -9;
    return DateTime.now().add(_skew).difference(s).inMicroseconds / 1e6;
  }

  @override
  void initState() {
    super.initState();
    _setSkew();
    tracks[1] = RjTrack(watch ? meName : (side == 1 ? meName : oppName), 1);
    tracks[2] = RjTrack(watch ? oppName : (side == 2 ? meName : oppName), 2);
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
      // quitter pendant la partie = tomber ici
      if (playing && !hero.dead && !_finalSent && _started) RcServer.rjScore(id, hero.score, true).catchError((_) => <String, dynamic>{});
    }
    _ticker?.dispose();
    _poll?.cancel();
    _rt?.cancel();
    _pos?.cancel();
    _wctl?.dispose();
    _focus.dispose();
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
    // hauteurs connues du serveur (si le fantôme n'est pas encore arrivé)
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
    if (!watch && s == side) return; // ma propre position (ou une fausse)
    tracks[s]!.add(_i(p['t']) / 1000, (p['x'] as num? ?? 0).toDouble(), (p['h'] as num? ?? 0).toDouble(), p['r'] == 1, _i(p['sc']), p['d'] == 1);
  }

  // ── boucle ──
  void _onTick(Duration _) {
    if (!mounted) return;
    final now = _now;
    if (!_started) {
      // compte à rebours
      final left = (-now).ceil();
      if (left != _lastCount && left >= 0 && left <= 3 && playing) {
        _lastCount = left;
        RcAudio.sfx(left == 0 ? 'powerup' : 'tier');
      }
      if (now >= 0 && playing) {
        _started = true;
        simT = now.clamp(0, kRjDuration.toDouble());
        _nextPos = simT;
        _nextScore = simT + 2;
      }
      _view(now.clamp(0, 999).toDouble());
      setState(() {});
      return;
    }
    final target = now.clamp(0.0, kRjDuration.toDouble());
    if (!watch && !hero.dead && !_timeUp && playing) {
      // pas fixes jusqu'au temps de la partie (au plus 0,25 s de retard rattrapé)
      if (target - simT > 0.25) simT = target - 0.25;
      final dir = _dir();
      while (simT + kRjStep <= target) {
        simT += kRjStep;
        hero.step(kRjStep, simT, dir);
        if (hero.dead) break;
      }
      if (simT >= _nextPos || hero.dead) {
        _nextPos = simT + 0.1;
        _sendPos();
      }
      if (hero.dead) {
        _finish(true);
      } else if (now >= kRjDuration) {
        _timeUp = true;
        _finish(true);
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

  /// Ma position aux autres (≈ 10 par seconde)
  void _sendPos() => LiveLink.i.sendPos({
        's': side,
        't': (simT * 1000).round(),
        'x': hero.x.round(),
        'h': hero.height.round(),
        'r': hero.right ? 1 : 0,
        'sc': hero.score,
        'd': hero.dead ? 1 : 0,
      });

  /// Chute, abandon ou fin des 2 min : hauteur définitive au serveur (réessaie si le réseau coupe)
  Future<void> _finish(bool dead) async {
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

  /// Caméra affichée : la mienne tant que je joue, sinon celle du plus haut encore en course
  void _view(double t) {
    if (!watch && !hero.dead && !_timeUp) {
      _viewCam = hero.camY;
      return;
    }
    double? target;
    final rt = t - 0.15;
    double best = -1e9;
    for (final tr in tracks.values) {
      if (!watch && tr.side == side) continue;
      final p = tr.at(rt);
      if (p == null) continue;
      final alive = !tr.dead;
      final h = p.$2 + (alive ? 100000 : 0); // on préfère suivre un joueur encore en course
      if (h > best) {
        best = h;
        target = RjWorld.startY - p.$2 - kRjH * 0.45;
      }
    }
    target ??= watch ? 0.0 : hero.camY;
    target = min(target, 0.0);
    _viewCam += (target - _viewCam) * 0.12;
    world.keep(_viewCam);
  }

  double _dir() {
    var d = 0.0;
    if (_pointers.isNotEmpty) d = _pointers.values.last < _boxW / 2 ? -1 : 1;
    final l = _keys.contains(LogicalKeyboardKey.arrowLeft) || _keys.contains(LogicalKeyboardKey.keyA) || _keys.contains(LogicalKeyboardKey.keyQ);
    final r = _keys.contains(LogicalKeyboardKey.arrowRight) || _keys.contains(LogicalKeyboardKey.keyD);
    if (l != r) d = l ? -1 : 1;
    return d;
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
      stats = await RcServer.rjStats();
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
        content: Text(t('Tu seras compté tombé à ${hero.score} points.', 'You will count as fallen at ${hero.score} points.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Continuer', 'Keep playing'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Abandonner', 'Give up'))),
        ],
      ),
    );
    if (ok == true) {
      hero.dead = true;
      await _finish(true);
    }
    return ok == true;
  }

  // ── affichage ──
  String _clock() {
    final left = (kRjDuration - max(0.0, _now)).clamp(0, kRjDuration).ceil();
    return '${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}';
  }

  List<RjRunner> _runners() {
    final rt = simT - 0.15; // un peu de retard : on lit entre deux positions reçues
    final l = <RjRunner>[];
    for (final tr in tracks.values) {
      if (!watch && tr.side == side) continue;
      final col = watch && tr.side == 1 ? kRjRed : kRjBlue;
      final p = tr.at(rt);
      if (p == null) {
        // pas encore de nouvelles : sur la plateforme de départ
        if (!_started || !tr.has) l.add(RjRunner(kRjW / 2 + (tr.side == 1 ? -14 : 14), 0, tr.side == 1, col, label: tr.name, ghost: !watch));
        continue;
      }
      l.add(RjRunner(p.$1, p.$2, p.$3, col, label: tr.dead ? '💀 ${tr.name}' : tr.name, ghost: !watch, dead: tr.dead));
    }
    if (!watch) l.add(RjRunner(hero.x, hero.height, hero.right, kRjRed, squash: hero.squash, dead: hero.dead));
    return l;
  }

  List<(double, String, Color)> _lines() {
    final l = <(double, String, Color)>[];
    for (final tr in tracks.values) {
      if (!watch && tr.side == side) continue;
      if (tr.score <= 0) continue;
      l.add((tr.score * 10.0, '🏁 ${tr.name} ${tr.score}', watch && tr.side == 1 ? kRjRed : kRjBlue));
    }
    if (!watch && hero.score > 0 && (hero.dead || _timeUp)) l.add((hero.score * 10.0, '🏁 ${t('Toi', 'You')} ${hero.score}', kRjRed));
    return l;
  }

  Widget _scoreChip(String name, int av, int score, Color c, {bool dead = false, bool right = false}) {
    final children = [
      _avatar(av, size: 30, ring: c),
      const SizedBox(width: 6),
      Flexible(
        child: Column(crossAxisAlignment: right ? CrossAxisAlignment.end : CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
          Text('${dead ? '💀 ' : ''}$score', style: pixelStyle(size: 10, color: c, shadow: false)),
        ]),
      ),
    ];
    return Expanded(
      child: Row(mainAxisAlignment: right ? MainAxisAlignment.end : MainAxisAlignment.start, children: right ? children.reversed.toList() : children),
    );
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
      banner = oppTr.dead ? t('En attente du résultat…', 'Waiting for the result…') : t('💥 Tombé à ${hero.score} !\n$oppName doit faire mieux', '💥 Fell at ${hero.score}!\n$oppName must beat it');
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
            title: Text('RÉTRO JUMP', style: pixelStyle(size: 12)),
            actions: [WatchersChip(_wctl), const SizedBox(width: 6)],
          ),
          body: SafeArea(
            top: false,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                child: Row(children: [
                  _scoreChip(watch ? meName : t('Toi', 'You'), myAv, myScore, kRjRed, dead: myDead),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(10), border: Border.all(color: _kRjGreen.withOpacity(0.6))),
                    child: Text(_started ? _clock() : '2:00', style: pixelStyle(size: 12, color: now > kRjDuration - 10 && playing ? const Color(0xFFFF8A95) : Colors.white, shadow: false)),
                  ),
                  _scoreChip(oppName, _i(opp['avatar']), oppTr.score, kRjBlue, dead: oppTr.dead, right: true),
                ]),
              ),
              Expanded(
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
                              CustomPaint(painter: RjPainter(world: world, camY: _viewCam, t: simT, runners: _runners(), lines: _lines())),
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
                                    t('Touche à gauche ou à droite de l\'écran (ou ← →) pour te déplacer.\nMême parcours pour vous deux : le plus haut gagne !',
                                        'Touch the left or right of the screen (or ← →) to move.\nSame course for both: the highest wins!'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700, shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
                                  ),
                                ),
                            ]),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              if (watch && duelFriendly(g))
                Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(duelFriendlyText, style: const TextStyle(color: Colors.white54, fontSize: 11.5))),
            ]),
          ),
        ),
      ),
    );
  }
}
