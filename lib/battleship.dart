part of 'connect4.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Console Wars : bataille navale à 2 (onglet « Bonus / Jeux »), même salon que
// le 4 en ligne. Grille 8 × 8, case (r, c) = r * 8 + c. Flotte de 5 consoles :
// Neo Geo 5, PlayStation 4, Mega Drive 3, NES 3, Game Boy 2 (côte à côte permis).
// Touché = on rejoue. Tout est vérifié par le serveur (rc_bs_*) ; la flotte
// adverse n'arrive au téléphone qu'une fois coulée (ou en fin de partie).
// ═══════════════════════════════════════════════════════════════════════════

const _kBsN = 8;
const _kSea = Color(0xFF0F4D8F), _kSea2 = Color(0xFF0A2F5E), _kSea3 = Color(0xFF06203F);
const _kRadar = Color(0xFF39FFB0);
const _kBsShips = [('neo', 5, 'Neo Geo'), ('ps', 4, 'PlayStation'), ('md', 3, 'Mega Drive'), ('nes', 3, 'NES'), ('gb', 2, 'Game Boy')];
int _bsLen(String k) => _kBsShips.firstWhere((s) => s.$1 == k).$2;
String _bsName(String k) => _kBsShips.firstWhere((s) => s.$1 == k).$3;

class _BsShip {
  final int r, c;
  final bool h;
  const _BsShip(this.r, this.c, this.h);
  List<int> cells(int n) => [for (var i = 0; i < n; i++) h ? r * _kBsN + c + i : (r + i) * _kBsN + c];
  Map<String, dynamic> json(String k) => {'k': k, 'r': r, 'c': c, 'h': h};
}

Map<String, _BsShip> _bsFleet(dynamic list) {
  final m = <String, _BsShip>{};
  for (final s in (list as List? ?? const [])) {
    final x = s as Map;
    m[x['k'] as String] = _BsShip(_i(x['r']), _i(x['c']), x['h'] == true);
  }
  return m;
}

bool _bsCanPlace(Map<String, _BsShip> f, String k, int r, int c, bool h) {
  final n = _bsLen(k);
  if (r < 0 || c < 0 || (h ? (r >= _kBsN || c + n > _kBsN) : (c >= _kBsN || r + n > _kBsN))) return false;
  final mine = _BsShip(r, c, h).cells(n).toSet();
  for (final e in f.entries) {
    if (e.key == k) continue;
    if (e.value.cells(_bsLen(e.key)).any(mine.contains)) return false;
  }
  return true;
}

Map<String, _BsShip> _bsRandom() {
  final rnd = Random();
  while (true) {
    final f = <String, _BsShip>{};
    var ok = true;
    for (final s in _kBsShips) {
      var placed = false;
      for (var t = 0; t < 300 && !placed; t++) {
        final h = rnd.nextBool(), r = rnd.nextInt(_kBsN), c = rnd.nextInt(_kBsN);
        if (_bsCanPlace(f, s.$1, r, c, h)) {
          f[s.$1] = _BsShip(r, c, h);
          placed = true;
        }
      }
      if (!placed) {
        ok = false;
        break;
      }
    }
    if (ok) return f;
  }
}

/// Image d'une console (horizontale, ou tournée d'un quart de tour)
Widget _bsShipImage(String k, bool h, double cell, {double opacity = 1, bool wreck = false}) {
  final n = _bsLen(k);
  Widget img = Image.asset('assets/bs/$k.png', fit: BoxFit.fill, filterQuality: FilterQuality.medium);
  if (wreck) {
    img = ColorFiltered(colorFilter: const ColorFilter.matrix([0.25, 0.25, 0.25, 0, 0, 0.2, 0.2, 0.2, 0, 0, 0.2, 0.2, 0.2, 0, 0, 0, 0, 0, 0.85, 0]), child: img);
  }
  final box = SizedBox(width: h ? n * cell : cell, height: h ? cell : n * cell, child: h ? img : RotatedBox(quarterTurns: 1, child: img));
  return Opacity(
    opacity: opacity,
    child: DecoratedBox(
      decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 6, offset: const Offset(0, 3))], borderRadius: BorderRadius.circular(cell * 0.18)),
      child: box,
    ),
  );
}

final kBsDuel = DuelKind(
  title: 'CONSOLE WARS',
  liveSub: '30 s par tir',
  turnSub: '24 h par tir',
  list: RcServer.bsList,
  online: RcServer.bsOnline,
  top: RcServer.bsTop,
  stats: RcServer.bsStats,
  invite: RcServer.bsInvite,
  answer: RcServer.bsAnswer,
  thumb: (g) => _BsThumb(g['my_shots'] as String? ?? ''),
  page: (g) => BattleGamePage(initial: g),
);

/// Mini grille des tirs (miniature des parties tour par tour)
class _BsThumb extends StatelessWidget {
  final String shots;
  final double width;
  const _BsThumb(this.shots, {this.width = 52});
  @override
  Widget build(BuildContext context) {
    final cell = (width - 6) / _kBsN;
    return Container(
      width: width,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_kSea, _kSea3], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var r = 0; r < _kBsN; r++)
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (var c = 0; c < _kBsN; c++)
              Builder(builder: (_) {
                final v = shots.length > r * _kBsN + c ? shots[r * _kBsN + c] : '0';
                return Container(
                  width: cell,
                  height: cell,
                  alignment: Alignment.center,
                  child: Container(
                    width: v == 'h' ? cell - 1 : (v == 'm' ? cell * 0.45 : cell - 1),
                    height: v == 'h' ? cell - 1 : (v == 'm' ? cell * 0.45 : cell - 1),
                    decoration: BoxDecoration(
                      shape: v == 'm' ? BoxShape.circle : BoxShape.rectangle,
                      borderRadius: v == 'm' ? null : BorderRadius.circular(1),
                      color: v == 'h' ? _kRed : (v == 'm' ? Colors.white70 : Colors.white.withOpacity(0.08)),
                    ),
                  ),
                );
              }),
          ]),
      ]),
    );
  }
}

/// Case de l'onglet Bonus / Jeux
class BattleTile extends StatefulWidget {
  const BattleTile({super.key});
  @override
  State<BattleTile> createState() => _BattleTileState();
}

class _BattleTileState extends State<BattleTile> {
  int myTurn = 0, invites = 0, online = 0;
  bool ready = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([RcServer.bsList(), RcServer.bsOnline()]);
      if (!mounted) return;
      setState(() {
        myTurn = r[0].where((g) => g['status'] == 'playing' && g['turn'] == g['side']).length;
        invites = r[0].where((g) => g['status'] == 'invite' && g['side'] == 2).length;
        online = r[1].length;
      });
    } catch (e) {
      // serveur pas encore à jour : la case reste visible mais grisée
      if (mounted && '$e'.contains('Could not find the function')) setState(() => ready = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF3EC7FF);
    final status = [
      if (myTurn > 0) t('$myTurn à toi de jouer', '$myTurn your turn'),
      if (invites > 0) t('$invites invitation${invites > 1 ? 's' : ''}', '$invites invitation${invites > 1 ? 's' : ''}'),
      if (online > 0) t('$online en ligne', '$online online'),
    ].join(' · ');
    return Opacity(
      opacity: ready ? 1 : 0.5,
      child: Material(
        color: kPanel,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            if (!ready) {
              toast(t('Bientôt disponible', 'Coming soon'));
              return;
            }
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => Connect4Lobby(kind: kBsDuel)));
            _load();
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(colors: [blue.withOpacity(0.16), Colors.transparent]),
              boxShadow: [BoxShadow(color: blue.withOpacity(0.25), blurRadius: 18, spreadRadius: -6)],
            ),
            foregroundDecoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: blue.withOpacity(0.75), width: 2)),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  width: 100,
                  decoration: const BoxDecoration(gradient: LinearGradient(colors: [_kSea, _kSea3], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
                  child: Stack(alignment: Alignment.center, children: [
                    Positioned(left: 10, top: 20, child: SizedBox(width: 60, height: 15, child: Image.asset('assets/bs/ps.png', fit: BoxFit.fill))),
                    Positioned(right: 12, bottom: 18, child: SizedBox(width: 34, height: 17, child: Image.asset('assets/bs/gb.png', fit: BoxFit.fill))),
                    Positioned(
                      right: 14,
                      top: 14,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0xFFFFF6C9), Color(0xFFFFB020), Color(0xFFFF4D1A), Color(0x00FF4D1A)])),
                      ),
                    ),
                    Positioned(left: 18, bottom: 16, child: Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white70))),
                  ]),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text('Console Wars', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 3),
                      Text(t('Bataille navale gratuite : coule la flotte adverse. Le gagnant gagne $kDuelWin pièces + 1 pixel, le perdant $kDuelLose',
                              'Free battleship: sink the enemy fleet. The winner gets $kDuelWin coins + 1 pixel, the loser $kDuelLose'),
                          style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      if (status.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(status, style: const TextStyle(color: blue, fontSize: 12, fontWeight: FontWeight.w800)),
                      ],
                    ]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: Badge(
                      isLabelVisible: myTurn + invites > 0,
                      label: Text('${myTurn + invites}'),
                      child: const Icon(Icons.play_arrow_rounded, color: blue, size: 32),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Grille ────────────────────────────────────────────────────────────────
/// Une grille 8 × 8 : mer (ta flotte) ou radar (flotte adverse)
class _BsBoard extends StatelessWidget {
  final bool radar;
  final Map<String, _BsShip> ships; // consoles dessinées
  final bool wrecks; // consoles grisées (coulées, sur le radar)
  final String shots; // tirs reçus sur cette grille : 0, m, h
  final Set<int> sunkCells;
  final Animation<double> anim; // scintillement des flammes, balayage du radar
  final int? aim;
  final Map<int, (String, int)> fx; // case → (sorte, numéro) pour les éclats
  final List<(String, _BsShip, bool)> overlay; // ombre pendant le placement : (console, position, possible)
  final String? lifted; // console soulevée (placement)
  final void Function(int cell)? onTap;
  final void Function(int? cell)? onHover;
  final bool labels;
  const _BsBoard({
    this.radar = false,
    this.ships = const {},
    this.wrecks = false,
    this.shots = '',
    this.sunkCells = const {},
    required this.anim,
    this.aim,
    this.fx = const {},
    this.overlay = const [],
    this.lifted,
    this.onTap,
    this.onHover,
    this.labels = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final lab = labels ? 14.0 : 0.0;
      final pad = box.maxWidth > 220 ? 6.0 : 3.0;
      final inner = box.maxWidth - lab - pad * 2;
      final cell = inner / _kBsN;
      final labStyle = pixelStyle(size: 6.5, color: radar ? _kRadar.withOpacity(0.6) : Colors.white38, shadow: false);
      int? cellAt(Offset p) {
        final x = p.dx - pad, y = p.dy - pad;
        if (x < 0 || y < 0 || x >= inner || y >= inner) return null;
        return (y ~/ cell).clamp(0, 7) * _kBsN + (x ~/ cell).clamp(0, 7);
      }

      final grid = Container(
        width: inner + pad * 2,
        height: inner + pad * 2,
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(pad * 2),
          gradient: radar
              ? const RadialGradient(colors: [Color(0xFF08372C), Color(0xFF031A16), Color(0xFF020F0D)], stops: [0, 0.7, 1])
              : const LinearGradient(colors: [_kSea, _kSea2, _kSea3], stops: [0, 0.55, 1], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          border: Border.all(color: (radar ? _kRadar : _kCyan).withOpacity(0.35), width: 2),
          boxShadow: [BoxShadow(color: radar ? const Color(0xFF0A0F22) : const Color(0xFF04142B), offset: const Offset(0, 5))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(pad),
          child: Stack(clipBehavior: Clip.none, children: [
            // quadrillage (+ balayage du radar)
            Positioned.fill(child: CustomPaint(painter: _BsGridPainter(radar: radar, anim: anim))),
            // consoles
            for (final e in ships.entries)
              if (e.key != lifted)
                Positioned(
                  left: e.value.c * cell + 1,
                  top: e.value.r * cell + 1,
                  child: _bsShipImage(e.key, e.value.h, cell - 2, wreck: wrecks),
                ),
            // ombre de placement
            for (final (k, s, ok) in overlay)
              Positioned(
                left: s.c * cell,
                top: s.r * cell,
                child: Container(
                  width: s.h ? _bsLen(k) * cell : cell,
                  height: s.h ? cell : _bsLen(k) * cell,
                  decoration: BoxDecoration(
                    color: (ok ? _kTeal : _kRed).withOpacity(0.35),
                    borderRadius: BorderRadius.circular(cell * 0.2),
                    border: Border.all(color: ok ? _kTeal : _kRed, width: 2),
                  ),
                ),
              ),
            // tirs
            for (var i = 0; i < shots.length && i < 64; i++)
              if (shots[i] != '0')
                Positioned(
                  left: (i % _kBsN) * cell,
                  top: (i ~/ _kBsN) * cell,
                  width: cell,
                  height: cell,
                  child: shots[i] == 'm' ? _BsMiss(fresh: fx[i]?.$1 == 'miss', key: ValueKey('m$i${fx[i]?.$2}')) : _BsFlame(anim: anim, sunk: sunkCells.contains(i)),
                ),
            // viseur
            if (aim != null)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 140),
                left: (aim! % _kBsN) * cell - 2,
                top: (aim! ~/ _kBsN) * cell - 2,
                width: cell + 4,
                height: cell + 4,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: _kRadar, width: 2),
                      color: _kRadar.withOpacity(0.12),
                      boxShadow: [BoxShadow(color: _kRadar.withOpacity(0.6), blurRadius: 10)],
                    ),
                  ),
                ),
              ),
            // éclats
            for (final e in fx.entries)
              Positioned(
                left: (e.key % _kBsN) * cell - cell * 1.5,
                top: (e.key ~/ _kBsN) * cell - cell * 1.5,
                width: cell * 4,
                height: cell * 4,
                child: IgnorePointer(child: _BsBurst(kind: e.value.$1, key: ValueKey('fx${e.key}${e.value.$2}'))),
              ),
          ]),
        ),
      );

      Widget body = grid;
      if (onTap != null || onHover != null) {
        body = MouseRegion(
          onHover: (e) => onHover?.call(cellAt(e.localPosition)),
          onExit: (_) => onHover?.call(null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => onHover?.call(cellAt(d.localPosition)),
            onTapUp: (d) {
              final c = cellAt(d.localPosition);
              if (c != null) onTap?.call(c);
            },
            child: grid,
          ),
        );
      }
      if (!labels) return body;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          SizedBox(width: lab + pad),
          for (var c = 1; c <= _kBsN; c++) SizedBox(width: cell, child: Center(child: Text('$c', style: labStyle))),
        ]),
        const SizedBox(height: 3),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: lab,
            child: Column(children: [
              SizedBox(height: pad),
              for (var r = 0; r < _kBsN; r++) SizedBox(height: cell, child: Center(child: Text('ABCDEFGH'[r], style: labStyle))),
            ]),
          ),
          body,
        ]),
      ]);
    });
  }
}

class _BsGridPainter extends CustomPainter {
  final bool radar;
  final Animation<double> anim;
  _BsGridPainter({required this.radar, required this.anim}) : super(repaint: radar ? anim : null);

  @override
  void paint(Canvas canvas, Size s) {
    final cell = s.width / _kBsN;
    final line = Paint()
      ..color = (radar ? _kRadar : const Color(0xFF8CD2FF)).withOpacity(radar ? 0.16 : 0.14)
      ..strokeWidth = 1;
    for (var i = 1; i < _kBsN; i++) {
      canvas.drawLine(Offset(i * cell, 0), Offset(i * cell, s.height), line);
      canvas.drawLine(Offset(0, i * cell), Offset(s.width, i * cell), line);
    }
    if (!radar) {
      // reflets sur l'eau
      final w = Paint()..color = Colors.white.withOpacity(0.05);
      canvas.drawOval(Rect.fromCenter(center: Offset(s.width * 0.25, s.height * 0.3), width: s.width * 0.5, height: s.height * 0.07), w);
      canvas.drawOval(Rect.fromCenter(center: Offset(s.width * 0.72, s.height * 0.72), width: s.width * 0.4, height: s.height * 0.05), w);
      return;
    }
    final c = s.center(Offset.zero);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = _kRadar.withOpacity(0.12)
      ..strokeWidth = 1;
    for (final f in [0.18, 0.36, 0.54]) {
      canvas.drawCircle(c, s.width * f, ring);
    }
    // balayage
    final a = anim.value * 2 * pi;
    final sweep = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * pi,
        colors: [_kRadar.withOpacity(0.0), _kRadar.withOpacity(0.0), _kRadar.withOpacity(0.28)],
        stops: const [0, 0.78, 1],
        transform: GradientRotation(a),
      ).createShader(Rect.fromCircle(center: c, radius: s.width));
    canvas.drawCircle(c, s.width, sweep);
    // lignes d'écran
    final scan = Paint()..color = Colors.black.withOpacity(0.16);
    for (var y = 0.0; y < s.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, s.width, 1), scan);
    }
  }

  @override
  bool shouldRepaint(_BsGridPainter o) => o.radar != radar;
}

/// Case touchée : flammes qui vacillent (ou croix si la console est coulée)
class _BsFlame extends StatelessWidget {
  final Animation<double> anim;
  final bool sunk;
  const _BsFlame({required this.anim, this.sunk = false});
  @override
  Widget build(BuildContext context) {
    if (sunk) {
      return Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(color: const Color(0xCC3A1220), borderRadius: BorderRadius.circular(3), border: Border.all(color: _kRed, width: 1.5)),
        child: const FittedBox(child: Padding(padding: EdgeInsets.all(4), child: Text('✕', style: TextStyle(color: Color(0xFFFF8A95), fontWeight: FontWeight.w900)))),
      );
    }
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) {
        final f = 0.5 + 0.5 * sin(anim.value * 2 * pi * 9);
        return Transform.scale(
          scale: 0.86 + 0.16 * f,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                const Color(0xFFFFF6C9),
                const Color(0xFFFFB020),
                Color.lerp(const Color(0xFFFF4D1A), const Color(0xFFFF7A1A), f)!,
                const Color(0x99C3202E),
                const Color(0x00C3202E),
              ], stops: const [0, 0.22, 0.45, 0.65, 0.75]),
            ),
          ),
        );
      },
    );
  }
}

/// Tir à l'eau : point blanc, et onde qui s'élargit quand il vient d'arriver
class _BsMiss extends StatefulWidget {
  final bool fresh;
  const _BsMiss({this.fresh = false, super.key});
  @override
  State<_BsMiss> createState() => _BsMissState();
}

class _BsMissState extends State<_BsMiss> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  @override
  void initState() {
    super.initState();
    if (widget.fresh) c.forward();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: c,
        builder: (_, __) => Stack(alignment: Alignment.center, children: [
          if (c.isAnimating)
            FractionallySizedBox(
              widthFactor: 0.3 + 1.2 * c.value,
              heightFactor: 0.3 + 1.2 * c.value,
              child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(1 - c.value), width: 2))),
            ),
          FractionallySizedBox(
            widthFactor: 0.3,
            heightFactor: 0.3,
            child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.8), boxShadow: const [BoxShadow(color: Colors.white38, blurRadius: 6)])),
          ),
        ]),
      );
}

/// Éclats d'un tir : feu et débris (touché, coulé) ou gerbe d'eau (raté)
class _BsBurst extends StatefulWidget {
  final String kind; // hit, sunk, miss
  const _BsBurst({required this.kind, super.key});
  @override
  State<_BsBurst> createState() => _BsBurstState();
}

class _BsBurstState extends State<_BsBurst> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();
  late final List<(double, double, double, Color)> bits;

  @override
  void initState() {
    super.initState();
    final r = Random();
    final cols = widget.kind == 'miss' ? const [Colors.white, Color(0xFFBFE6FF), Color(0xFF6CC4FF)] : const [Color(0xFFFFF6C9), Color(0xFFFFB020), Color(0xFFFF4D1A), Color(0xFFC3202E), Color(0xFF555555)];
    final n = widget.kind == 'sunk' ? 46 : (widget.kind == 'hit' ? 30 : 18);
    bits = List.generate(n, (_) => (r.nextDouble() * 2 * pi, 0.4 + r.nextDouble() * (widget.kind == 'sunk' ? 1.0 : 0.7), 2 + r.nextDouble() * 3.5, cols[r.nextInt(cols.length)]));
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: c, builder: (_, __) => CustomPaint(painter: _BurstPainter(bits, c.value, widget.kind == 'miss')));
}

class _BurstPainter extends CustomPainter {
  final List<(double, double, double, Color)> bits;
  final double t;
  final bool water;
  _BurstPainter(this.bits, this.t, this.water);
  @override
  void paint(Canvas canvas, Size s) {
    if (t >= 1) return;
    final c = s.center(Offset.zero);
    final p = Paint();
    if (!water && t < 0.35) {
      p.color = const Color(0xFFFFE08A).withOpacity(1 - t / 0.35);
      canvas.drawCircle(c, s.width * 0.18 * (0.6 + t * 2), p);
    }
    for (final (a, v, sz, col) in bits) {
      final d = v * s.width * 0.5 * Curves.easeOut.transform(t);
      final fall = water ? -s.width * 0.25 * t + s.width * 0.6 * t * t : s.width * 0.15 * t * t;
      p.color = col.withOpacity((1 - t).clamp(0.0, 1.0));
      canvas.drawRect(Rect.fromCenter(center: c + Offset(cos(a) * d, sin(a) * d * (water ? 0.6 : 1) + fall), width: sz, height: sz), p);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter o) => o.t != t;
}

// ─── Partie ────────────────────────────────────────────────────────────────
class BattleGamePage extends StatefulWidget {
  final Map<String, dynamic> initial;
  const BattleGamePage({super.key, required this.initial});
  @override
  State<BattleGamePage> createState() => _BattleGamePageState();
}

class _BattleGamePageState extends State<BattleGamePage> with TickerProviderStateMixin {
  late Map<String, dynamic> g = widget.initial;
  bool busy = false, _resultShown = false;
  Timer? _poll, _tick;
  Duration _skew = Duration.zero;
  late final AnimationController anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600))..repeat();
  late final AnimationController shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  int? _aim;
  final Map<int, (String, int)> _fxRadar = {}, _fxMine = {};
  int _fxN = 0;
  String? _bannerText, _bannerSub, _bannerKind;
  Timer? _bannerT;
  String? _emoMe, _emoOpp, _emoOppAt;
  Timer? _emoMeT, _emoOppT;

  // placement
  Map<String, _BsShip> _fleet = {};
  final _boardKey = GlobalKey(), _stackKey = GlobalKey();
  final Map<String, GlobalKey> _dockKeys = {for (final s in _kBsShips) s.$1: GlobalKey()};
  String? _dragK;
  bool _dragH = true, _dragFromBoard = false, _moved = false;
  int _grab = 0;
  Offset _dragStart = Offset.zero, _dragPos = Offset.zero;
  _BsShip? _ghost;
  bool _ghostOk = false;
  double _cell = 30;

  int get id => _i(g['id']);
  bool get live => g['mode'] == 'live';
  int get side => _i(g['side'], 1);
  String get phase => g['phase'] as String? ?? g['status'] as String? ?? '';
  bool get setup => phase == 'setup';
  bool get playing => phase == 'playing';
  bool get done => phase == 'done';
  bool get myTurn => (playing || setup) && _i(g['turn']) == side;
  bool get placed => g['my_fleet'] != null;
  int get stake => _i(g['stake'], kC4Stake);
  Map get opp => g['opp'] as Map? ?? const {};
  String get oppName => opp['name'] as String? ?? '?';
  String get myShots => (g['my_shots'] as String?) ?? '0' * 64;
  String get oppShots => (g['opp_shots'] as String?) ?? '0' * 64;
  int _hits(String s) => 'h'.allMatches(s).length;

  @override
  void initState() {
    super.initState();
    _setSkew();
    _emoOppAt = g['emo_opp_at'] as String?;
    _poll = Timer.periodic(Duration(seconds: live ? 2 : 6), (_) => _refresh());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      final s = _left().inSeconds;
      if (live && playing && myTurn && s <= 10 && s > 0) RcAudio.tick();
      if ((playing || setup) && _left().isNegative) _refresh();
    });
    if (done) WidgetsBinding.instance.addPostFrameCallback((_) => _showResult());
    _refresh();
    DuelWatch.i.inGame++;
  }

  @override
  void dispose() {
    DuelWatch.i.inGame--;
    _poll?.cancel();
    _tick?.cancel();
    _bannerT?.cancel();
    _emoMeT?.cancel();
    _emoOppT?.cancel();
    anim.dispose();
    shake.dispose();
    super.dispose();
  }

  void _setSkew() {
    final now = DateTime.tryParse(g['now'] as String? ?? '');
    if (now != null) _skew = now.difference(DateTime.now());
  }

  Duration _left() {
    final dl = DateTime.tryParse(g['deadline'] as String? ?? '');
    if (dl == null) return Duration.zero;
    return dl.difference(DateTime.now().add(_skew));
  }

  Map<String, _BsShip> get _oppSunk => _bsFleet(g['opp_sunk']);

  Set<int> _sunkCells(Map<String, _BsShip> f) => {for (final e in f.entries) ...e.value.cells(_bsLen(e.key))};

  /// Mes consoles coulées (toutes leurs cases touchées)
  Map<String, _BsShip> _mySunk(Map<String, _BsShip> f, String shots) => {
        for (final e in f.entries)
          if (e.value.cells(_bsLen(e.key)).every((c) => c < shots.length && shots[c] == 'h')) e.key: e.value
      };

  void _apply(Map<String, dynamic> n) {
    final beforeMine = myShots, beforeOpp = oppShots, beforeSunk = _oppSunk.keys.toSet();
    final beforeMySunk = _mySunk(_bsFleet(g['my_fleet']), oppShots).keys.toSet();
    final wasActive = playing || setup, wasPhase = phase, wasMyTurn = myTurn;
    setState(() => g = n);
    _setSkew();
    if (wasPhase == 'setup' && playing) {
      RcAudio.sfx('powerup');
      _banner('go', t('BATAILLE !', 'BATTLE!'), myTurn ? t('Tu tires en premier', 'You shoot first') : t('$oppName tire en premier', '$oppName shoots first'));
    }
    // mes tirs
    final ms = myShots;
    for (var i = 0; i < ms.length && i < beforeMine.length; i++) {
      if (beforeMine[i] == '0' && ms[i] != '0') {
        final nowSunk = _oppSunk.keys.toSet().difference(beforeSunk);
        if (ms[i] == 'h' && nowSunk.isNotEmpty) {
          _fx(true, i, 'sunk');
          RcAudio.sfx('break');
          RcAudio.sfx('tier');
          _banner('sunk', t('${_bsName(nowSunk.first).toUpperCase()}\nCOULÉE !', '${_bsName(nowSunk.first).toUpperCase()}\nSUNK!'), done ? '' : t('Tu rejoues', 'Shoot again'));
          _shake();
        } else if (ms[i] == 'h') {
          _fx(true, i, 'hit');
          RcAudio.sfx('hurt');
          _banner('hit', t('TOUCHÉ !', 'HIT!'), done ? '' : t('Tu rejoues', 'Shoot again'));
          _shake();
        } else {
          _fx(true, i, 'miss');
          RcAudio.sfx('stomp');
          _banner('miss', t('À L\'EAU…', 'MISS…'), t('Au tour de $oppName', '$oppName\'s turn'));
        }
      }
    }
    // ses tirs
    final os = oppShots;
    final mySunkNow = _mySunk(_bsFleet(g['my_fleet']), os).keys.toSet().difference(beforeMySunk);
    for (var i = 0; i < os.length && i < beforeOpp.length; i++) {
      if (beforeOpp[i] == '0' && os[i] != '0') {
        if (os[i] == 'h') {
          _fx(false, i, mySunkNow.isNotEmpty ? 'sunk' : 'hit');
          RcAudio.sfx('hurt');
          _shake();
        } else {
          _fx(false, i, 'miss');
          RcAudio.sfx('stomp');
        }
      }
    }
    if (mySunkNow.isNotEmpty) _banner('sunk', t('TA ${_bsName(mySunkNow.first).toUpperCase()}\nCOULÉE', 'YOUR ${_bsName(mySunkNow.first).toUpperCase()}\nSUNK'), '');
    if (!wasMyTurn && myTurn && playing) RcAudio.correct();
    final at = n['emo_opp_at'] as String?;
    if (at != null && at != _emoOppAt) {
      _emoOppAt = at;
      _bubble(false, n['emo_opp'] as String? ?? '👍');
    }
    if (wasActive && done) _showResult();
  }

  void _fx(bool radar, int cell, String kind) {
    final m = radar ? _fxRadar : _fxMine;
    final n = ++_fxN;
    setState(() => m[cell] = (kind, n));
    Timer(const Duration(milliseconds: 900), () {
      if (mounted && m[cell]?.$2 == n) setState(() => m.remove(cell));
    });
  }

  void _shake() => shake.forward(from: 0);

  void _banner(String kind, String text, String sub) {
    _bannerT?.cancel();
    setState(() {
      _bannerKind = kind;
      _bannerText = text;
      _bannerSub = sub;
    });
    _bannerT = Timer(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => _bannerText = null);
    });
  }

  Future<void> _refresh() async {
    try {
      final n = await RcServer.bsState(id);
      if (mounted) _apply(n);
    } catch (_) {}
  }

  Future<void> _shoot(int cell) async {
    if (busy) return;
    if (!playing || !myTurn) {
      RcAudio.wrong();
      toast(playing ? t('Ce n\'est pas ton tour', 'It\'s not your turn') : t('La partie est terminée', 'The game is over'));
      return;
    }
    if (myShots[cell] != '0') {
      RcAudio.wrong();
      return;
    }
    setState(() {
      busy = true;
      _aim = null;
    });
    RcAudio.sfx('jump');
    try {
      _apply(await RcServer.bsShoot(id, cell));
    } catch (e) {
      RcAudio.wrong();
      toast(errText(e));
      _refresh();
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _place() async {
    if (busy || _fleet.length < 5) return;
    setState(() => busy = true);
    try {
      RcAudio.sfx('continue');
      _apply(await RcServer.bsPlace(id, [for (final e in _fleet.entries) e.value.json(e.key)]));
    } catch (e) {
      RcAudio.wrong();
      toast(errText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  void _bubble(bool me, String emo) {
    RcAudio.sfx('spring');
    setState(() => me ? _emoMe = emo : _emoOpp = emo);
    final timer = Timer(const Duration(milliseconds: 1900), () {
      if (mounted) setState(() => me ? _emoMe = null : _emoOpp = null);
    });
    if (me) {
      _emoMeT?.cancel();
      _emoMeT = timer;
    } else {
      _emoOppT?.cancel();
      _emoOppT = timer;
    }
  }

  Future<void> _emote(String e) async {
    _bubble(true, e);
    try {
      await RcServer.bsEmote(id, e);
    } catch (_) {}
  }

  Future<void> _resign() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Abandonner ?', 'Resign?')),
        content: Text(stake > 0
            ? t('Ta mise de $stake pièces est perdue, ton adversaire gagne.', 'You lose your $stake coins bet, your opponent wins.')
            : t('Ton adversaire gagne. Tu reçois quand même $kDuelLose pièces.', 'Your opponent wins. You still get $kDuelLose coins.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Continuer', 'Keep playing'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Abandonner', 'Resign'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      _apply(await RcServer.bsResign(id));
    } catch (e) {
      toast(errText(e));
    }
  }

  void _rules() => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('Règles', 'Rules')),
          content: Text(t(
            'Chacun place 5 consoles (Neo Geo 5 cases, PlayStation 4, Mega Drive 3, NES 3, Game Boy 2), côte à côte si tu veux, mais sans chevauchement.\n\n'
                'Tire sur le radar : touché, tu rejoues ; à l\'eau, c\'est à l\'autre. Coule toute la flotte adverse pour gagner $kDuelWin pièces + 1 pixel (le perdant reçoit $kDuelLose pièces). Partie gratuite ; gains seulement contre un joueur inscrit depuis au moins un jour, 4 parties payées par jour contre le même adversaire.\n\n'
                'En direct : 2 minutes pour placer, 30 secondes par tir. Tour par tour : 24 heures. Placement pas fini à temps = flotte au hasard ; tir pas joué = tir au hasard, 3 fois de suite = abandon.',
            'Each player places 5 consoles (Neo Geo 5 cells, PlayStation 4, Mega Drive 3, NES 3, Game Boy 2), side by side if you like, but not overlapping.\n\n'
                'Shoot on the radar: hit, you shoot again; miss, it\'s the other player\'s turn. Sink the whole enemy fleet to win $kDuelWin coins + 1 pixel (the loser gets $kDuelLose coins). Free game; rewards only against players who joined at least a day ago, 4 paid games a day against the same opponent.\n\n'
                'Live: 2 minutes to place, 30 seconds per shot. Turn-based: 24 hours. Not placed in time = random fleet; no shot = random shot, 3 in a row = forfeit.',
          )),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );

  Future<void> _showResult() async {
    if (_resultShown || !mounted) return;
    _resultShown = true;
    final w = (g['winner'] as num?)?.toInt();
    if (w == side) {
      RcAudio.win();
    } else {
      RcAudio.lose();
    }
    Game.i.sync();
    Map<String, dynamic> stats = {};
    try {
      stats = await RcServer.bsStats();
    } catch (_) {}
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;
    final shots = myShots.replaceAll('0', '').length;
    final again = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _BsResultDialog(g: g, side: side, stats: stats, shots: shots, hits: _hits(myShots)),
    );
    if (!mounted) return;
    if (again == true) {
      Navigator.of(context).pop({'pid': opp['pid'], 'name': opp['name'], 'avatar': _i(opp['avatar']), 'mode': g['mode']});
    } else if (again == false) {
      Navigator.of(context).pop();
    }
  }

  // ── placement : glisser depuis le quai ou la mer, toucher pour tourner ──
  Rect? _rectOf(GlobalKey k) {
    final b = k.currentContext?.findRenderObject() as RenderBox?;
    if (b == null || !b.hasSize) return null;
    return b.localToGlobal(Offset.zero) & b.size;
  }

  /// Grille seule (sans les repères A–H / 1–8)
  Rect? get _gridRect {
    final r = _rectOf(_boardKey);
    if (r == null) return null;
    const lab = 14.0, pad = 6.0;
    final inner = r.width - lab - pad * 2;
    _cell = inner / _kBsN;
    return Rect.fromLTWH(r.left + lab + pad, r.top + r.height - inner - pad, inner, inner);
  }

  void _down(PointerDownEvent e) {
    if (placed || !setup) return;
    final p = e.position;
    final grid = _gridRect;
    if (grid != null && grid.contains(p)) {
      final c = ((p.dx - grid.left) / _cell).floor(), r = ((p.dy - grid.top) / _cell).floor();
      for (final s in _fleet.entries) {
        final cells = s.value.cells(_bsLen(s.key));
        if (cells.contains(r * _kBsN + c)) {
          _dragK = s.key;
          _dragH = s.value.h;
          _dragFromBoard = true;
          _grab = s.value.h ? c - s.value.c : r - s.value.r;
          break;
        }
      }
    }
    if (_dragK == null) {
      for (final e2 in _dockKeys.entries) {
        if (_fleet.containsKey(e2.key)) continue;
        final rr = _rectOf(e2.value);
        if (rr != null && rr.contains(p)) {
          _dragK = e2.key;
          _dragH = true;
          _dragFromBoard = false;
          _grab = _bsLen(e2.key) ~/ 2;
          break;
        }
      }
    }
    if (_dragK == null) return;
    _dragStart = p;
    _dragPos = p;
    _moved = false;
    RcAudio.sfx('jump');
    _updateGhost();
  }

  void _move(PointerMoveEvent e) {
    if (_dragK == null) return;
    _dragPos = e.position;
    if ((_dragPos - _dragStart).distance > 8) _moved = true;
    _updateGhost();
  }

  void _updateGhost() {
    final grid = _gridRect;
    final k = _dragK!;
    if (grid == null || (_dragFromBoard && !_moved)) {
      setState(() => _ghost = null);
      return;
    }
    final n = _bsLen(k);
    final rr = Rect.fromLTRB(grid.left - _cell, grid.top - _cell, grid.right + _cell, grid.bottom + _cell);
    if (!rr.contains(_dragPos)) {
      setState(() => _ghost = null);
      return;
    }
    var r = ((_dragPos.dy - grid.top) / _cell).floor(), c = ((_dragPos.dx - grid.left) / _cell).floor();
    if (_dragH) {
      c -= _grab;
    } else {
      r -= _grab;
    }
    r = r.clamp(0, _dragH ? _kBsN - 1 : _kBsN - n);
    c = c.clamp(0, _dragH ? _kBsN - n : _kBsN - 1);
    setState(() {
      _ghost = _BsShip(r, c, _dragH);
      _ghostOk = _bsCanPlace(_fleet, k, r, c, _dragH);
    });
  }

  void _up(PointerUpEvent e) {
    final k = _dragK;
    if (k == null) return;
    _dragK = null;
    if (_dragFromBoard && !_moved) {
      _ghost = null;
      _rotate(k);
      return;
    }
    if (_ghost != null && _ghostOk) {
      _fleet[k] = _ghost!;
      RcAudio.sfx('stomp');
    } else if (_ghost != null) {
      RcAudio.wrong();
    }
    setState(() => _ghost = null);
  }

  void _cancel(PointerCancelEvent e) => setState(() {
        _dragK = null;
        _ghost = null;
      });

  void _rotate(String k) {
    final x = _fleet[k]!, n = _bsLen(k), h = !x.h;
    final tries = <(int, int)>[(0, 0)];
    for (var s = 1; s < n; s++) {
      tries.add(h ? (0, -s) : (-s, 0));
    }
    for (var s = 1; s <= 2; s++) {
      tries.add(h ? (s, 0) : (0, s));
      tries.add(h ? (-s, 0) : (0, -s));
    }
    for (final (dr, dc) in tries) {
      if (_bsCanPlace(_fleet, k, x.r + dr, x.c + dc, h)) {
        setState(() => _fleet[k] = _BsShip(x.r + dr, x.c + dc, h));
        RcAudio.sfx('spring');
        return;
      }
    }
    RcAudio.wrong();
    setState(() {});
    toast(t('Pas la place pour la tourner ici : glisse-la ailleurs', 'No room to turn it here: drag it elsewhere'));
  }

  // ── écrans ──
  Widget _player(String name, int avatar, Color ring, bool on, String? emo, int hits, {bool right = false}) {
    final left = _left();
    final limit = live ? (setup ? 120 : 30) : 86400;
    final frac = on ? (left.inSeconds / limit).clamp(0.0, 1.0) : 1.0;
    final warn = on && live && left.inSeconds <= 10;
    String timer() {
      final d = left.isNegative ? Duration.zero : left;
      return live ? '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}' : '${d.inHours} h ${(d.inMinutes % 60).toString().padLeft(2, '0')}';
    }

    return Expanded(
      child: Stack(clipBehavior: Clip.none, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: kPanel,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: on ? kGold : Colors.transparent, width: 2),
            boxShadow: [if (on) BoxShadow(color: kGold.withOpacity(0.35), blurRadius: 14, spreadRadius: -4)],
          ),
          child: Row(textDirection: right ? TextDirection.rtl : TextDirection.ltr, children: [
            SizedBox(
              width: 44,
              height: 44,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox.expand(child: CircularProgressIndicator(value: frac, strokeWidth: 3, color: warn ? _kRed : ring, backgroundColor: Colors.white10)),
                avatarWidget(avatar, size: 34),
              ]),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(crossAxisAlignment: right ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                Text(t('$hits / 17 touchés', '$hits / 17 hits'), style: const TextStyle(fontSize: 10.5, color: Colors.white54)),
                if (on && !done) Text(timer(), style: pixelStyle(size: 7.5, color: warn ? _kRed : _kGoldHi, shadow: false)),
              ]),
            ),
          ]),
        ),
        if (emo != null)
          Positioned(
            top: -14,
            right: right ? null : 8,
            left: right ? 8 : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)]),
              child: Text(emo, style: const TextStyle(fontSize: 17)),
            ),
          ),
      ]),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Row(children: [
          _player(t('Toi', 'You'), Game.i.avatar, _kCyan, myTurn && !done, _emoMe, _hits(myShots)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Column(children: [
              const _Coin(size: 16),
              Text(g['friendly'] != null ? '0' : '${duelPrize(stake)}', style: pixelStyle(size: 8.5, color: _kGoldHi, shadow: false)),
              Text(stake > 0 ? 'POT' : g['friendly'] != null ? t('AMICAL', 'FRIENDLY') : 'GAIN', style: const TextStyle(fontSize: 9, color: Colors.white54, fontWeight: FontWeight.w800)),
            ]),
          ),
          _player(oppName, _i(opp['avatar']), _kNeon, !myTurn && !done && (playing || setup), _emoOpp, _hits(oppShots), right: true),
        ]),
      );

  Widget _setupView(double width) {
    final boardW = min(width - 24, 440.0);
    if (placed) {
      return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
        _header(),
        const SizedBox(height: 10),
        Text(t('Ta flotte est prête !', 'Your fleet is ready!'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(height: 4),
        Text(t('En attente de la flotte de $oppName…', 'Waiting for $oppName\'s fleet…'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
        const SizedBox(height: 14),
        Center(child: SizedBox(width: boardW, child: _BsBoard(ships: _bsFleet(g['my_fleet']), anim: anim))),
      ]);
    }
    final dragging = _dragK;
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _cancel,
      child: Stack(key: _stackKey, children: [
        SingleChildScrollView(
          physics: dragging != null ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          child: Column(children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(text: t('Glisse', 'Drag'), style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
                TextSpan(text: t(' les consoles sur la mer · ', ' the consoles onto the sea · ')),
                TextSpan(text: t('touche', 'tap'), style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
                TextSpan(text: t(' une console pour la tourner', ' a console to turn it')),
              ]),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 4),
            if (live || _left().inHours < 1)
              Text(t('Temps pour placer : ${max(0, _left().inMinutes)}:${(max(0, _left().inSeconds) % 60).toString().padLeft(2, '0')} · sinon flotte au hasard', 'Time to place: ${max(0, _left().inMinutes)}:${(max(0, _left().inSeconds) % 60).toString().padLeft(2, '0')} · else a random fleet'),
                  style: pixelStyle(size: 7, color: _kGoldHi, shadow: false)),
            const SizedBox(height: 10),
            SizedBox(
              key: _boardKey,
              width: boardW,
              child: _BsBoard(
                ships: _fleet,
                anim: anim,
                lifted: _dragFromBoard && _moved ? dragging : null,
                overlay: [if (_ghost != null && dragging != null) (dragging, _ghost!, _ghostOk)],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
              for (final s in _kBsShips)
                Opacity(
                  key: _dockKeys[s.$1],
                  opacity: _fleet.containsKey(s.$1) || (dragging == s.$1 && _moved) ? 0.35 : 1,
                  child: Container(
                    width: (boardW - 8) / 2,
                    padding: const EdgeInsets.fromLTRB(8, 7, 8, 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.15)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Align(alignment: Alignment.centerLeft, child: _bsShipImage(s.$1, true, 20)),
                      const SizedBox(height: 4),
                      Text.rich(TextSpan(children: [
                        TextSpan(text: s.$3, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                        TextSpan(text: t(' · ${s.$2} cases', ' · ${s.$2} cells'), style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      ])),
                    ]),
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            SizedBox(
              width: boardW,
              child: Row(children: [
                OutlinedButton(
                  onPressed: () {
                    RcAudio.sfx('stomp');
                    setState(() => _fleet = _bsRandom());
                  },
                  child: Text(t('🎲 Au hasard', '🎲 Random')),
                ),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: () => setState(() => _fleet = {}), child: Text(t('Tout retirer', 'Clear'))),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
                  onPressed: _fleet.length == 5 && !busy ? _place : null,
                  child: Text(t('Prêt !', 'Ready!'), style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ]),
            ),
          ]),
        ),
        // console qui suit le doigt
        if (dragging != null && (_moved || !_dragFromBoard))
          Builder(builder: (context) {
            final sb = _stackKey.currentContext?.findRenderObject() as RenderBox?;
            if (sb == null) return const SizedBox();
            final local = sb.globalToLocal(_dragPos);
            final n = _bsLen(dragging);
            return Positioned(
              left: local.dx - (_dragH ? (_grab + 0.5) * _cell : _cell / 2),
              top: local.dy - (_dragH ? _cell / 2 : (_grab + 0.5) * _cell) - (_dragFromBoard ? 0 : 0),
              child: IgnorePointer(child: SizedBox(width: (_dragH ? n : 1) * _cell, height: (_dragH ? 1 : n) * _cell, child: _bsShipImage(dragging, _dragH, _cell, opacity: 0.85))),
            );
          }),
      ]),
    );
  }

  Widget _battleView(double width) {
    final radarW = min(width - 24, 440.0);
    final oppSunk = _oppSunk;
    final myFleet = _bsFleet(g['my_fleet']);
    final mySunk = _mySunk(myFleet, oppShots);
    return ListView(padding: const EdgeInsets.only(bottom: 20), children: [
      _header(),
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(
          done
              ? TextSpan(text: (g['winner'] as num?)?.toInt() == side ? t('Victoire !', 'Victory!') : t('Défaite', 'Defeat'))
              : TextSpan(children: [
                  TextSpan(text: myTurn ? t('À toi de tirer ! ', 'Your shot! ') : t('$oppName vise ta flotte…', '$oppName is aiming at your fleet…')),
                  if (myTurn) TextSpan(text: t('◎ vise une case', '◎ pick a cell'), style: const TextStyle(color: _kRadar)),
                ]),
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
        ),
      ),
      // radar
      Center(
        child: Container(
          width: radarW + 20,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF26304F), Color(0xFF141A33)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [BoxShadow(color: Color(0xFF0A0F22), offset: Offset(0, 7)), BoxShadow(color: Colors.black45, blurRadius: 20, offset: Offset(0, 12))],
          ),
          child: Column(children: [
            Row(children: [
              AnimatedBuilder(
                animation: anim,
                builder: (_, __) => Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _kRadar.withOpacity((anim.value * 6) % 1 < 0.5 ? 1 : 0.3), boxShadow: const [BoxShadow(color: _kRadar, blurRadius: 6)]),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(child: Text(px('RADAR · ${oppName.toUpperCase()}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: pixelStyle(size: 7, color: _kRadar, shadow: false))),
              Text(t('TIR ${myShots.replaceAll('0', '').length + 1}', 'SHOT ${myShots.replaceAll('0', '').length + 1}'), style: pixelStyle(size: 7, color: const Color(0xFF9FB4D8), shadow: false)),
            ]),
            const SizedBox(height: 7),
            _BsBoard(
              radar: true,
              ships: oppSunk,
              wrecks: !done || true,
              shots: myShots,
              sunkCells: _sunkCells(oppSunk),
              anim: anim,
              aim: myTurn && playing ? _aim : null,
              fx: _fxRadar,
              onTap: _shoot,
              onHover: (c) {
                if (c != _aim && (c == null || myShots[c] == '0')) setState(() => _aim = c);
              },
            ),
          ]),
        ),
      ),
      // ma flotte + sa flotte
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: min((width - 24) * 0.48, 220),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(left: 2, bottom: 5), child: Text(t('TA FLOTTE', 'YOUR FLEET'), style: pixelStyle(size: 6.5, color: Colors.white54, shadow: false))),
              _BsBoard(ships: myFleet, shots: oppShots, sunkCells: _sunkCells(mySunk), anim: anim, fx: _fxMine, labels: false),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(left: 2, bottom: 6), child: Text(t('SA FLOTTE', 'THEIR FLEET'), style: pixelStyle(size: 6.5, color: Colors.white54, shadow: false))),
              for (final s in _kBsShips)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Opacity(
                    opacity: oppSunk.containsKey(s.$1) ? 0.45 : 1,
                    child: Row(children: [
                      SizedBox(
                        width: s.$2 * 11.0,
                        height: 12,
                        child: oppSunk.containsKey(s.$1) ? ColorFiltered(colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.saturation), child: Image.asset('assets/bs/${s.$1}.png', fit: BoxFit.fill)) : Image.asset('assets/bs/${s.$1}.png', fit: BoxFit.fill),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(s.$3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, decoration: oppSunk.containsKey(s.$1) ? TextDecoration.lineThrough : null)),
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
        ]),
      ),
      if (playing) ...[
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final e in _kEmotes)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkResponse(
                onTap: () => _emote(e),
                radius: 24,
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: kPanel, shape: BoxShape.circle, border: Border.all(color: Colors.white12)),
                  child: Text(e, style: const TextStyle(fontSize: 18)),
                ),
              ),
            ),
        ]),
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Row(children: [
          if (playing)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4A1D2A), foregroundColor: const Color(0xFFFFC4CF)),
              onPressed: _resign,
              icon: const Icon(Icons.flag),
              label: Text(t('Abandonner', 'Resign'), style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          if (done)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
              onPressed: () {
                _resultShown = false;
                _showResult();
              },
              icon: const Icon(Icons.emoji_events),
              label: Text(t('Résultat', 'Result'), style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          const Spacer(),
          OutlinedButton(onPressed: _rules, child: Text(t('Règles', 'Rules'))),
          const SizedBox(width: 8),
          IconButton(
            tooltip: t('Son', 'Sound'),
            onPressed: () => setState(() => RcAudio.enabled = !RcAudio.enabled),
            icon: Icon(RcAudio.enabled ? Icons.volume_up : Icons.volume_off, color: Colors.white70),
            style: IconButton.styleFrom(backgroundColor: Colors.white10),
          ),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final bannerColors = switch (_bannerKind) {
      'miss' => const [Color(0xFF1C7ED6), Color(0xFF0A2F5E)],
      'sunk' => const [Color(0xFFC3202E), Color(0xFF5A0D16)],
      'go' => const [Color(0xFF7B3DFF), Color(0xFF2A1360)],
      _ => const [Color(0xFFFF7A1A), Color(0xFFC3202E)],
    };
    return MaxWidth(
      max: 560,
      child: Scaffold(
        appBar: AppBar(
          title: Text(setup && !placed ? t('LE PORT', 'THE HARBOR') : 'CONSOLE WARS', style: pixelStyle(size: 12)),
          actions: [ListenableBuilder(listenable: Game.i, builder: (_, __) => CoinChip(Game.i.coins)), const SizedBox(width: 12)],
        ),
        body: LayoutBuilder(
          builder: (context, box) => AnimatedBuilder(
            animation: shake,
            builder: (_, child) {
              final v = shake.value;
              return Transform.translate(offset: Offset(v == 0 || v == 1 ? 0 : sin(v * pi * 8) * 5 * (1 - v), 0), child: child);
            },
            child: Stack(children: [
              Positioned.fill(
                child: g['status'] == 'invite'
                    ? Center(child: Text(t('En attente de la réponse de $oppName…', 'Waiting for $oppName to answer…'), style: const TextStyle(fontWeight: FontWeight.w800)))
                    : setup
                        ? _setupView(box.maxWidth)
                        : _battleView(box.maxWidth),
              ),
              // bannière (touché, à l'eau, coulée)
              IgnorePointer(
                child: Align(
                  alignment: const Alignment(0, -0.2),
                  child: AnimatedScale(
                    scale: _bannerText == null ? 0.5 : 1,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutBack,
                    child: AnimatedOpacity(
                      opacity: _bannerText == null ? 0 : 1,
                      duration: const Duration(milliseconds: 180),
                      child: Transform.rotate(
                        angle: -0.07,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: bannerColors),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white24, width: 2),
                            boxShadow: [BoxShadow(color: bannerColors.first.withOpacity(0.6), blurRadius: 30)],
                          ),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(_bannerText ?? '', textAlign: TextAlign.center, style: pixelStyle(size: 14, color: Colors.white, shadow: false).copyWith(height: 1.6)),
                            if ((_bannerSub ?? '').isNotEmpty)
                              Text(_bannerSub!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Fin de partie
class _BsResultDialog extends StatefulWidget {
  final Map<String, dynamic> g;
  final int side, shots, hits;
  final Map<String, dynamic> stats;
  const _BsResultDialog({required this.g, required this.side, required this.stats, required this.shots, required this.hits});
  @override
  State<_BsResultDialog> createState() => _BsResultDialogState();
}

class _BsResultDialogState extends State<_BsResultDialog> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  final _rnd = Random();
  late final List<_Bit> bits;
  int shown = 0;
  bool pixel = false;
  Timer? _count;

  bool get win => (widget.g['winner'] as num?)?.toInt() == widget.side;
  int get stake => _i(widget.g['stake'], kC4Stake);

  @override
  void initState() {
    super.initState();
    const cols = [_kRed, _kYellow, _kCyan, _kNeon, _kTeal, Colors.white];
    bits = List.generate(win && !duelFriendly(widget.g) ? 140 : 0, (_) => _Bit((_rnd.nextDouble() - 0.5) * 2.2, -_rnd.nextDouble() * 2.4 - 0.6, 3 + _rnd.nextDouble() * 4, cols[_rnd.nextInt(cols.length)], _rnd.nextDouble() * 6));
    if (win && !duelFriendly(widget.g)) {
      c.forward();
      _count = Timer.periodic(const Duration(milliseconds: 30), (tm) {
        if (!mounted) return tm.cancel();
        setState(() => shown = min(shown + 2, duelPrize(stake)));
        if (shown % 10 == 0) RcAudio.sfx('coin');
        if (shown >= duelPrize(stake)) {
          tm.cancel();
          setState(() => pixel = true);
          RcAudio.sfx('powerup');
        }
      });
    }
  }

  @override
  void dispose() {
    _count?.cancel();
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opp = (widget.g['opp'] as Map?)?['name'] as String? ?? '?';
    final reason = widget.g['reason'];
    final sub = win
        ? (reason == 'timeout'
            ? t('$opp n\'a pas joué à temps', '$opp ran out of time')
            : reason == 'resign'
                ? t('$opp a abandonné', '$opp resigned')
                : t('Toute la flotte de $opp est par le fond', '$opp\'s whole fleet is sunk'))
        : (reason == 'timeout'
            ? (stake > 0 ? t('Temps écoulé : ta mise est perdue', 'Time out: you lose your bet') : t('Temps écoulé', 'Time out'))
            : reason == 'resign'
                ? (stake > 0 ? t('Tu as abandonné : ta mise est perdue', 'You resigned: you lose your bet') : t('Tu as abandonné', 'You resigned'))
                : t('$opp a coulé ta flotte', '$opp sank your fleet'));
    final acc = widget.shots == 0 ? 0 : (widget.hits * 100 / widget.shots).round();
    return Stack(children: [
      Positioned.fill(child: IgnorePointer(child: AnimatedBuilder(animation: c, builder: (_, __) => CustomPaint(painter: _ConfettiPainter(bits, c.value))))),
      Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.8, end: 1),
          duration: const Duration(milliseconds: 380),
          curve: Curves.elasticOut,
          builder: (_, s, child) => Transform.scale(scale: s, child: child),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 340,
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF2A1F5E), Color(0xFF141A4C)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: kGold, width: 2),
                boxShadow: [BoxShadow(color: kGold.withOpacity(0.45), blurRadius: 36, spreadRadius: -8)],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(win ? '🏆' : '💥', style: const TextStyle(fontSize: 46)),
                const SizedBox(height: 6),
                Text(px(win ? t('VICTOIRE !', 'VICTORY!') : t('DÉFAITE', 'DEFEAT')), style: pixelStyle(size: 15, color: win ? _kGoldHi : const Color(0xFFFF8A95), shadow: false)),
                const SizedBox(height: 6),
                Text(duelFriendly(widget.g) ? '$sub\n$duelFriendlyText' : sub, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const _Coin(size: 22),
                  const SizedBox(width: 8),
                  Text(duelFriendly(widget.g) ? '0' : win ? '+$shown' : duelLoseText(stake), style: pixelStyle(size: 18, color: _kGoldHi, shadow: false)),
                  if (win && pixel) ...[const SizedBox(width: 10), Text('+1 ▦', style: pixelStyle(size: 11, color: _kGoldHi, shadow: false))],
                ]),
                const SizedBox(height: 8),
                Wrap(alignment: WrapAlignment.center, spacing: 14, children: [
                  Text.rich(TextSpan(children: [TextSpan(text: t('Tirs ', 'Shots ')), TextSpan(text: '${widget.shots}', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white))]),
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  Text.rich(TextSpan(children: [TextSpan(text: t('Précision ', 'Accuracy ')), TextSpan(text: '$acc %', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white))]),
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  Text.rich(TextSpan(children: [TextSpan(text: t('Série ', 'Streak ')), TextSpan(text: '${_i(widget.stats['streak'])}${_i(widget.stats['streak']) > 1 ? ' 🔥' : ''}', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white))]),
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ]),
                const SizedBox(height: 14),
                Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _kNeon, foregroundColor: Colors.white),
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.replay),
                    label: Text(t('Revanche', 'Rematch'), style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  OutlinedButton(onPressed: () => Navigator.pop(context, false), child: Text(t('Salon', 'Lobby'))),
                  TextButton(onPressed: () => Navigator.pop(context), child: Text(t('Voir le radar', 'See the radar'))),
                ]),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}
