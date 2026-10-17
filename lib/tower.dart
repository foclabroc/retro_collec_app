import 'dart:math';

import 'package:flutter/material.dart';

import 'catalog.dart';
import 'game.dart';
import 'main.dart';
import 'notifs.dart';
import 'retro_theme.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Voisinage en immeuble (« Pixel Tower ») : un étage par joueur selon le
// classement, le n°1 au penthouse. Chaque joueur habille son étage avec un
// des 16 thèmes, débloqués au nombre de cartes (colonne serveur « house »).
// ═══════════════════════════════════════════════════════════════════════════

const _kMold = Color(0xFFEFE2C3);
const _kJoint = Color(0xFFA8946C);
const _kIron = Color(0xFF1C1D22);
const _kBrass = Color(0xFFC9A24A);
const _kLit = Color(0xFFFFD88A);

/// Thème d'un étage : revêtement, couleurs des fenêtres, volets et balcon, effet
class FloorTheme {
  final String fr, en;
  final int need; // cartes pour le débloquer
  final List<Color> bg; // dégradé de fond (horizontal, ou vertical si [vertical])
  final bool vertical;
  final String pattern; // stone, brick, wood, shoji, checker, stars, none
  final Color line; // joints / lames
  final Color frame, shutter, rail;
  final String fx; // ivy, neon, snow, spooky, gold
  const FloorTheme(this.fr, this.en, this.need, this.bg, this.pattern, this.line, this.frame, this.shutter, this.rail,
      {this.vertical = false, this.fx = ''});
  String get name => t(fr, en);
}

const kFloorThemes = [
  FloorTheme('Pierre', 'Stone', 0, [Color(0xFFD9C8A3)], 'stone', _kJoint, Color(0xFFFFF6DD), Color(0xFF3F6F8F), _kIron),
  FloorTheme('Brique', 'Brick', 0, [Color(0xFF9A4A36)], 'brick', Color(0xFF7F3A2A), Color(0xFFF3EAD6), Color(0xFF2E6A3A), _kIron),
  FloorTheme('Bois', 'Wood', 0, [Color(0xFF8A5A34)], 'wood', Color(0xFF74492A), Color(0xFFF6E7C8), Color(0xFFA03A2A), Color(0xFF3A2410)),
  FloorTheme('Lierre', 'Ivy', 50, [Color(0xFFD9C8A3)], 'stone', _kJoint, Color(0xFFFFF6DD), Color(0xFF3A6A3A), _kIron, fx: 'ivy'),
  FloorTheme('Néon', 'Neon', 100, [Color(0xFF1A1030)], 'none', Colors.transparent, Color(0xFFFF4FD8), Color(0xFF5A2DFF), Color(0xFF28E0FF), fx: 'neon'),
  FloorTheme('Art déco', 'Art deco', 150, [Color(0xFF1E2A2A), Color(0xFF2A3A3A), Color(0xFF1E2A2A)], 'none', Colors.transparent, Color(0xFFD9B45A),
      Color(0xFF1E2A2A), Color(0xFFD9B45A)),
  FloorTheme('Verre', 'Glass', 200, [Color(0xFF0F2C47), Color(0xFF16405F), Color(0xFF0F2C47)], 'none', Colors.transparent, Color(0xFFA9BCCF),
      Color(0xFF6F8399), Color(0xFFA9BCCF)),
  FloorTheme('Château', 'Castle', 250, [Color(0xFF77737C)], 'stone', Color(0xFF65616A), Color(0xFFD8D2C4), Color(0xFF6A1A1A), Color(0xFF2A2A2E)),
  FloorTheme('Japonais', 'Japanese', 300, [Color(0xFFEFE3C5)], 'shoji', Color(0xFF6B4A2B), Color(0xFF6B4A2B), Color(0xFFBB2222), Color(0xFF6B4A2B)),
  FloorTheme('Arcade', 'Arcade', 400, [Color(0xFF140A2E)], 'checker', Color(0xFF2A1B5A), Color(0xFFFFD166), Color(0xFFFF3DF0), Color(0xFFFF3DF0),
      fx: 'neon'),
  FloorTheme('Spatial', 'Space', 500, [Color(0xFF0B0E24)], 'stars', Colors.white, Color(0xFF7DFFB0), Color(0xFF2B3350), Color(0xFF8FA0D8)),
  FloorTheme('Sous-marin', 'Submarine', 600, [Color(0xFF0A4A6A), Color(0xFF06304A)], 'none', Colors.transparent, Color(0xFFFFE04D), Color(0xFFB5C3C9),
      Color(0xFFB5C3C9), vertical: true),
  FloorTheme('Plage', 'Beach', 700, [Color(0xFFF6E2B0)], 'wood', Color(0xFFE9D29A), Colors.white, Color(0xFF2BB3D8), Colors.white),
  FloorTheme('Neige', 'Snow', 800, [Color(0xFFEAF6FF)], 'brick', Color(0xFFCFE6F5), Color(0xFF8AB4D8), Color(0xFFC0392B), Color(0xFF5A7A98), fx: 'snow'),
  FloorTheme('Halloween', 'Halloween', 1000, [Color(0xFF2A1A3A), Color(0xFF1A1022)], 'none', Colors.transparent, Color(0xFFFF8A1A), Color(0xFF3A1A4A),
      Color(0xFFFF8A1A), vertical: true, fx: 'spooky'),
  FloorTheme('Or', 'Gold', 1200, [Color(0xFF5A3E08), Color(0xFF8A6A1A), Color(0xFF5A3E08)], 'none', Colors.transparent, Color(0xFFFFD166),
      Color(0xFFC9A227), Color(0xFFFFD166), fx: 'gold'),
];

/// Thème d'un joueur (« house » côté serveur) ; par défaut un des 3 thèmes offerts, varié selon le joueur
int floorThemeOf(String? house, String pid) {
  final n = int.tryParse(house ?? '');
  if (n != null && n >= 0 && n < kFloorThemes.length) return n;
  return pid.hashCode.abs() % 3;
}

// ─── Fond de l'étage (revêtement) ──────────────────────────────────────────
class _FacadePainter extends CustomPainter {
  final FloorTheme th;
  _FacadePainter(this.th);

  @override
  void paint(Canvas c, Size s) {
    final r = Offset.zero & s;
    final bg = th.bg.length == 1
        ? (Paint()..color = th.bg.first)
        : (Paint()
          ..shader = LinearGradient(
            colors: th.bg,
            begin: th.vertical ? Alignment.topCenter : Alignment.centerLeft,
            end: th.vertical ? Alignment.bottomCenter : Alignment.centerRight,
          ).createShader(r));
    c.drawRect(r, bg);
    final p = Paint()..color = th.line;
    switch (th.pattern) {
      case 'stone':
      case 'brick':
        final h = th.pattern == 'stone' ? 26.0 : 10.0;
        final w = th.pattern == 'stone' ? 60.0 : 22.0;
        var row = 0;
        for (var y = h; y < s.height + h; y += h, row++) {
          c.drawRect(Rect.fromLTWH(0, y - 1, s.width, 1), p);
          for (var x = (row.isOdd ? w / 2 : 0.0); x < s.width; x += w) {
            c.drawRect(Rect.fromLTWH(x, y - h, 1, h), p);
          }
        }
      case 'wood':
        for (var x = 16.0; x < s.width; x += 18) {
          c.drawRect(Rect.fromLTWH(x, 0, 2, s.height), p);
        }
      case 'shoji':
        for (var x = 28.0; x < s.width; x += 31) {
          c.drawRect(Rect.fromLTWH(x, 0, 3, s.height), p);
        }
        c.drawRect(Rect.fromLTWH(0, s.height * 0.45, s.width, 2), p);
      case 'checker':
        for (var y = 0.0; y < s.height; y += 18) {
          for (var x = ((y / 18).round().isOdd ? 18.0 : 0.0); x < s.width; x += 36) {
            c.drawRect(Rect.fromLTWH(x, y, 18, 18), p);
          }
        }
      case 'stars':
        final rnd = Random(7);
        final sp = Paint()..color = Colors.white.withOpacity(0.8);
        for (var i = 0; i < (s.width * s.height / 900).round(); i++) {
          c.drawCircle(Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height), rnd.nextDouble() * 1.1 + 0.4, sp);
        }
    }
    if (th.fx == 'ivy') {
      final rnd = Random(3);
      final leaf = [Paint()..color = const Color(0xFF3F9A4A), Paint()..color = const Color(0xFF2E7A3A)];
      for (var i = 0; i < 90; i++) {
        final left = i.isEven;
        final x = left ? rnd.nextDouble() * s.width * 0.16 : s.width - rnd.nextDouble() * s.width * 0.14;
        c.drawCircle(Offset(x, rnd.nextDouble() * s.height), 2.4 + rnd.nextDouble() * 1.2, leaf[i % 2]);
      }
    }
    if (th.fx == 'snow') {
      c.drawRRect(RRect.fromRectAndCorners(Rect.fromLTWH(0, 0, s.width, 6), bottomLeft: const Radius.circular(6), bottomRight: const Radius.circular(6)),
          Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_FacadePainter o) => o.th != th;
}

/// Grille en fer forgé de l'ascenseur
class _GrillePainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF3A2A1E));
    final p = Paint()
      ..color = _kIron.withOpacity(0.85)
      ..strokeWidth = 2;
    for (var d = -s.height; d < s.width + s.height; d += 9) {
      c.drawLine(Offset(d, 0), Offset(d + s.height, s.height), p);
      c.drawLine(Offset(d + s.height, 0), Offset(d, s.height), p);
    }
    c.drawRect(Rect.fromLTWH(s.width - 3, 0, 3, s.height), Paint()..color = _kIron);
  }

  @override
  bool shouldRepaint(_GrillePainter o) => false;
}

/// Balcon : barre du haut + barreaux
class _RailPainter extends CustomPainter {
  final Color color;
  _RailPainter(this.color);
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = color;
    c.drawRect(Rect.fromLTWH(0, 0, s.width, 3), p);
    c.drawRect(Rect.fromLTWH(0, s.height - 2, s.width, 2), p);
    for (var x = 2.0; x < s.width; x += 5) {
      c.drawRect(Rect.fromLTWH(x, 0, 1.6, s.height), p);
    }
  }

  @override
  bool shouldRepaint(_RailPainter o) => o.color != color;
}

/// Jardinière fleurie
class _FlowersPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    c.drawRRect(RRect.fromRectAndCorners(Rect.fromLTWH(0, 0, s.width, s.height - 3), topLeft: const Radius.circular(3), topRight: const Radius.circular(3)),
        Paint()..color = const Color(0xFF3F8A3A));
    c.drawRect(Rect.fromLTWH(0, s.height - 3, s.width, 3), Paint()..color = const Color(0xFF7A4A2A));
    final pink = Paint()..color = const Color(0xFFFF5A7A), yellow = Paint()..color = const Color(0xFFFFD166);
    var i = 0;
    for (var x = 3.0; x < s.width - 2; x += 5, i++) {
      c.drawCircle(Offset(x, i.isEven ? 2.5 : 4.5), 1.8, i % 3 == 0 ? yellow : pink);
    }
  }

  @override
  bool shouldRepaint(_FlowersPainter o) => false;
}

// ─── Un étage ──────────────────────────────────────────────────────────────
/// Données d'un étage (ligne du classement ou de la recherche)
class FloorData {
  final String pid, name;
  final int avatar, score, cards, coins, theme;
  final int? rank;
  final bool online, me;
  const FloorData({
    required this.pid,
    required this.name,
    required this.avatar,
    required this.score,
    required this.cards,
    required this.coins,
    required this.theme,
    required this.online,
    required this.me,
    this.rank,
  });

  factory FloorData.of(Map<String, dynamic> p, {int? rank}) {
    final pid = p['pid'] as String? ?? '';
    final me = pid == Game.i.pid;
    return FloorData(
      pid: pid,
      name: p['name'] as String? ?? '?',
      avatar: me ? Game.i.avatar : (p['avatar'] as num? ?? 0).toInt(),
      score: me ? Game.i.score : (p['score'] as num? ?? 0).toInt(),
      cards: me ? Game.i.cards : (p['cards'] as num? ?? 0).toInt(),
      coins: me ? Game.i.coins : (p['coins'] as num? ?? 0).toInt(),
      theme: floorThemeOf(me ? Game.i.house : p['house'] as String?, pid),
      online: me || p['online'] == true,
      me: me,
      rank: rank ?? (p['rank'] as num?)?.toInt(),
    );
  }
}

String pctOf(int cards) => '${Catalog.cards.isEmpty ? 0 : (cards * 100 ~/ Catalog.cards.length)} %';

const kFloorH = 92.0, kPentH = 112.0, kCorniceH = 8.0;

class TowerFloor extends StatelessWidget {
  final FloorData d;
  final int level; // numéro d'étage (0 = penthouse)
  final bool penthouse, elevator, shaft;
  final int index; // pour varier volets / fleurs / détails
  final VoidCallback? onTap, onGift;
  const TowerFloor({
    super.key,
    required this.d,
    required this.level,
    this.penthouse = false,
    this.elevator = false,
    this.shaft = true,
    this.index = 0,
    this.onTap,
    this.onGift,
  });

  @override
  Widget build(BuildContext context) {
    final th = kFloorThemes[d.theme];
    final h = penthouse ? kPentH : kFloorH;
    final neon = th.fx == 'neon';
    final lit = d.online;
    final litColors = th.fx == 'spooky'
        ? const [Color(0xFFFFB36B), Color(0xFFFF7A1A)]
        : const [Color(0xFFFFF0CF), _kLit, Color(0xFFE8A85A)];

    Widget window({required double w, required double hh, Widget? child, bool small = false}) => Container(
          width: w,
          height: hh,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(small ? 12 : 16)),
            border: Border.all(color: penthouse ? const Color(0xFFFFE7A3) : th.frame, width: 3),
            gradient: lit && !small || (small && lit && index.isOdd)
                ? LinearGradient(colors: litColors, begin: Alignment.topCenter, end: Alignment.bottomCenter)
                : null,
            color: lit && !small || (small && lit && index.isOdd) ? null : const Color(0xFF1B2752),
            boxShadow: [
              BoxShadow(color: penthouse ? kGold : _kMold, spreadRadius: 3),
              if (neon) BoxShadow(color: th.frame.withOpacity(0.7), blurRadius: 12, spreadRadius: 3),
              if (lit && !small) BoxShadow(color: _kLit.withOpacity(0.35), blurRadius: 14),
            ],
          ),
          child: small
              ? CustomPaint(painter: _CrossPainter(penthouse ? const Color(0xFFFFE7A3) : th.frame))
              : ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(12)), child: child),
        );

    final mainW = penthouse ? 78.0 : 50.0, mainH = penthouse ? 82.0 : 58.0;
    final shutters = !penthouse && index.isEven;
    final flowers = !penthouse && index % 3 != 1;
    final main = SizedBox(
      width: mainW + (shutters ? 30 : 6),
      height: mainH + 8,
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
        if (shutters) ...[
          Positioned(left: 0, top: 0, width: 9, height: mainH, child: _shutter(th.shutter)),
          Positioned(right: 0, top: 0, width: 9, height: mainH, child: _shutter(th.shutter)),
        ],
        Positioned(
          top: 0,
          child: window(
            w: mainW,
            hh: mainH,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: ColorFiltered(
                  colorFilter: lit ? const ColorFilter.mode(Colors.transparent, BlendMode.dst) : const ColorFilter.matrix(_kDim),
                  child: Image.asset(
                    'assets/avatars/avatar_${(d.avatar.abs() % kAvatars.length).toString().padLeft(2, '0')}.webp',
                    filterQuality: FilterQuality.none,
                    fit: BoxFit.fitWidth,
                    errorBuilder: (_, __, ___) => const SizedBox(),
                  ),
                ),
              ),
            ),
          ),
        ),
        // clé de voûte
        Positioned(top: -9, child: ClipPath(clipper: _KeyClipper(), child: Container(width: 10, height: 9, color: penthouse ? kGold : _kMold))),
        if (flowers) Positioned(bottom: 6, left: shutters ? 13 : 1, right: shutters ? 13 : 1, height: 9, child: CustomPaint(painter: _FlowersPainter())),
        Positioned(
          bottom: -2,
          left: shutters ? 4 : -6,
          right: shutters ? 4 : -6,
          height: 14,
          child: CustomPaint(painter: _RailPainter(penthouse ? _kBrass : th.rail)),
        ),
      ]),
    );

    final plaque = Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF2A2420), Color(0xFF1A1612)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: d.me ? const Color(0xFF5DCAA5) : penthouse || th.fx == 'gold' ? const Color(0xFFFFD166) : neon ? th.frame : _kBrass,
          width: 2,
        ),
        boxShadow: [
          if (d.me) const BoxShadow(color: Color(0x885DCAA5), blurRadius: 10),
          if (neon && !d.me) BoxShadow(color: th.frame.withOpacity(0.6), blurRadius: 8),
        ],
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              if (d.online)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: const BoxDecoration(color: Color(0xFF5DCAA5), shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0xFF5DCAA5), blurRadius: 5)]),
                ),
              Flexible(
                child: Text(d.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: penthouse ? 15 : 14, color: penthouse ? const Color(0xFFFFD166) : const Color(0xFFFFF3D6))),
              ),
              if (d.me)
                Container(
                  margin: const EdgeInsets.only(left: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(4)),
                  child: Text(t('TOI', 'YOU'), style: pixelStyle(size: 7, color: const Color(0xFF2A1800), shadow: false)),
                ),
            ]),
            Text.rich(
              TextSpan(children: [
                if (d.rank != null) TextSpan(text: '#${d.rank} · '),
                TextSpan(text: t('${d.score} pts · ', '${d.score} pts · ')),
                TextSpan(text: pctOf(d.cards), style: const TextStyle(color: Color(0xFF9FE0C4), fontWeight: FontWeight.w900)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFFD8C8A0), height: 1.3),
            ),
            Text(t('${d.cards} cartes · 🪙 ${d.coins}', '${d.cards} cards · 🪙 ${d.coins}'),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Color(0xFFFFD166), fontWeight: FontWeight.w800, height: 1.3)),
          ]),
        ),
        if (onGift != null)
          GestureDetector(
            onTap: onGift,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Opacity(opacity: Notifs.i.canGift ? 1 : 0.35, child: const Text('🎁', style: TextStyle(fontSize: 18))),
            ),
          ),
      ]),
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: h + kCorniceH,
        child: Column(children: [
          SizedBox(
            height: h,
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _FacadePainter(th))),
              if (penthouse) Positioned.fill(child: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [const Color(0x30FFD166), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter)))),
              if (d.me) Positioned(left: shaft ? 46 : 0, top: 0, bottom: 0, width: 5, child: Container(color: const Color(0xFF5DCAA5))),
              Row(children: [
                if (shaft)
                  SizedBox(
                    width: 46,
                    child: Stack(alignment: Alignment.center, children: [
                      Positioned.fill(child: CustomPaint(painter: _GrillePainter())),
                      if (elevator) _cabin(d.avatar),
                      Positioned(
                        top: h * 0.42 - 11,
                        child: Container(
                          width: 32,
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1F3A73),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Text(penthouse ? 'PH' : '$level', textAlign: TextAlign.center, style: pixelStyle(size: 8, color: Colors.white, shadow: false)),
                        ),
                      ),
                    ]),
                  ),
                const SizedBox(width: 8),
                if (!penthouse) Padding(padding: const EdgeInsets.only(bottom: 8), child: window(w: 24, hh: 58, small: true)),
                if (!penthouse) const SizedBox(width: 4),
                Padding(padding: const EdgeInsets.only(top: 6), child: main),
                const SizedBox(width: 6),
                Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 8), child: plaque)),
                const SizedBox(width: 6),
                if (!penthouse) Padding(padding: const EdgeInsets.only(bottom: 8), child: window(w: 24, hh: 58, small: true)),
                const SizedBox(width: 8),
              ]),
              if (penthouse) const Positioned(right: 10, top: 4, child: Text('👑', style: TextStyle(fontSize: 20))),
            ]),
          ),
          // corniche
          Container(
            height: kCorniceH,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_kMold, _kMold, _kJoint], stops: [0, 0.45, 0.45], begin: Alignment.topCenter, end: Alignment.bottomCenter),
              boxShadow: [BoxShadow(color: Color(0x30000000), offset: Offset(0, 3))],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _shutter(Color c) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [c, c, Colors.black26, Colors.black26],
            stops: const [0, 0.75, 0.75, 1],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            tileMode: TileMode.repeated,
          ),
        ),
      );

  Widget _cabin(int avatar) => Container(
        width: 36,
        height: 62,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFD6B45A), Color(0xFF9A7A2A)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          border: Border.all(color: const Color(0xFF4A3A10), width: 2),
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Image.asset('assets/avatars/avatar_${(Game.i.avatar.abs() % kAvatars.length).toString().padLeft(2, '0')}.webp',
              width: 24, height: 24, filterQuality: FilterQuality.none, errorBuilder: (_, __, ___) => const SizedBox()),
        ),
      );
}

const _kDim = <double>[
  0.4, 0, 0, 0, 0,
  0, 0.4, 0, 0, 0,
  0, 0, 0.45, 0, 0,
  0, 0, 0, 1, 0,
];

class _CrossPainter extends CustomPainter {
  final Color c;
  _CrossPainter(this.c);
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = c;
    canvas.drawRect(Rect.fromLTWH(s.width / 2 - 1, 0, 2, s.height), p);
    canvas.drawRect(Rect.fromLTWH(0, s.height / 2 - 1, s.width, 2), p);
  }

  @override
  bool shouldRepaint(_CrossPainter o) => o.c != c;
}

class _KeyClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(0, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width * 0.75, s.height)
    ..lineTo(s.width * 0.25, s.height)
    ..close();
  @override
  bool shouldReclip(_KeyClipper o) => false;
}

// ─── Toit et rez-de-chaussée ───────────────────────────────────────────────
const kRoofH = 122.0;

class TowerRoof extends StatelessWidget {
  const TowerRoof({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: kRoofH,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
          Positioned(
            top: 6,
            child: Text('PIXEL TOWER', style: pixelStyle(size: 11, color: const Color(0xFFFFD166)).copyWith(letterSpacing: 2, shadows: const [
              Shadow(color: Color(0xFFEF9F27), blurRadius: 8),
              Shadow(color: Color(0xFFEF9F27), blurRadius: 16),
            ])),
          ),
          // cheminées
          Positioned(left: 40, bottom: 70, child: _chimney()),
          Positioned(right: 44, bottom: 70, child: _chimney()),
          // toit en zinc
          Positioned(left: -4, right: -4, bottom: 12, height: 64, child: CustomPaint(painter: _MansardPainter())),
          // lucarnes
          Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [for (final l in [true, false, true]) _dormer(l)]),
          ),
          // corniche
          Positioned(
            left: -8,
            right: -8,
            bottom: 0,
            height: 12,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: const LinearGradient(
                    colors: [_kMold, _kMold, Color(0xFFC7B48C), Color(0xFFC7B48C), _kJoint],
                    stops: [0, 0.4, 0.4, 0.7, 0.7],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter),
              ),
            ),
          ),
        ]),
      );

  Widget _chimney() => Container(
        width: 18,
        height: 34,
        decoration: const BoxDecoration(
          color: Color(0xFF8A4232),
          border: Border(top: BorderSide(color: Color(0xFF6B2E20), width: 4)),
        ),
      );

  Widget _dormer(bool lit) => Container(
        width: 30,
        height: 38,
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 3),
        decoration: const BoxDecoration(color: _kMold, borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
        child: Container(
          decoration: BoxDecoration(
            color: lit ? _kLit : const Color(0xFF24325E),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            border: Border.all(color: const Color(0xFFFFF6DD), width: 2),
            boxShadow: [if (lit) BoxShadow(color: _kLit.withOpacity(0.6), blurRadius: 8)],
          ),
        ),
      );
}

class _MansardPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final path = Path()
      ..moveTo(s.width * 0.06, 0)
      ..lineTo(s.width * 0.94, 0)
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    c.save();
    c.clipPath(path);
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF5D6B7C));
    final p = Paint()..color = const Color(0xFF4A5666);
    for (var x = 14.0; x < s.width; x += 16) {
      c.drawRect(Rect.fromLTWH(x, 0, 2, s.height), p);
    }
    c.drawRect(Rect.fromLTWH(0, 0, s.width, 6), Paint()..color = Colors.white.withOpacity(0.12));
    c.restore();
  }

  @override
  bool shouldRepaint(_MansardPainter o) => false;
}

class TowerLobby extends StatelessWidget {
  final int gifts;
  final VoidCallback onGifts, onSearch;
  const TowerLobby({super.key, required this.gifts, required this.onGifts, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    Widget sign(String icon, String label, Color bg, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _kBrass, width: 2),
              boxShadow: const [BoxShadow(color: Color(0x59000000), offset: Offset(0, 3))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(icon, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
              Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
            ]),
          ),
        );
    return Column(children: [
      SizedBox(
        height: 112,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
          Positioned.fill(child: CustomPaint(painter: _FacadePainter(const FloorTheme('', '', 0, [Color(0xFFC7B48C)], 'brick', _kJoint, _kMold, _kMold, _kMold)))),
          // auvent rayé
          Positioned(left: 6, right: 6, top: 6, height: 18, child: CustomPaint(painter: _AwningPainter())),
          Positioned(
            top: 30,
            child: Text('PIXEL TOWER · 1923', style: pixelStyle(size: 7, color: const Color(0xFF2A1F0C), shadow: false).copyWith(letterSpacing: 2)),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            sign('✉ $gifts', t('Cadeaux', 'Gifts'), const Color(0xFF2E5670), onGifts),
            const SizedBox(width: 12),
            // porte cochère
            Container(
              width: 70,
              height: 72,
              decoration: const BoxDecoration(
                color: Color(0xFF5A3420),
                borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
                border: Border(top: BorderSide(color: _kMold, width: 4), left: BorderSide(color: _kMold, width: 4), right: BorderSide(color: _kMold, width: 4)),
              ),
              child: Stack(alignment: Alignment.topCenter, children: [
                Container(width: 2, color: const Color(0xFF2A160C)),
                Positioned(
                  top: 8,
                  child: Container(
                    width: 34,
                    height: 16,
                    decoration: BoxDecoration(color: _kLit.withOpacity(0.55), borderRadius: const BorderRadius.vertical(top: Radius.circular(17))),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            sign('🔍', t('Chercher', 'Search'), const Color(0xFF3A2A18), onSearch),
          ]),
        ]),
      ),
      // trottoir pavé
      SizedBox(height: 44, width: double.infinity, child: CustomPaint(painter: _CobblePainter())),
    ]);
  }
}

class _AwningPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width * 0.97, s.height)
      ..lineTo(s.width * 0.03, s.height)
      ..close();
    c.save();
    c.clipPath(path);
    var i = 0;
    for (var x = 0.0; x < s.width; x += 14, i++) {
      c.drawRect(Rect.fromLTWH(x, 0, 14, s.height), Paint()..color = i.isEven ? const Color(0xFFB8283A) : const Color(0xFFF3EAD6));
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_AwningPainter o) => false;
}

class _CobblePainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF4A4A56));
    c.drawRect(Rect.fromLTWH(0, 0, s.width, 8), Paint()..color = const Color(0xFFA9A9B4));
    final p = Paint()..color = const Color(0xFF6A6A76);
    var row = 0;
    for (var y = 14.0; y < s.height; y += 12, row++) {
      for (var x = row.isOdd ? 7.0 : 0.0; x < s.width; x += 14) {
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, y), width: 11, height: 9), const Radius.circular(4)), p);
      }
    }
  }

  @override
  bool shouldRepaint(_CobblePainter o) => false;
}

// ─── Choix du thème de mon étage ──────────────────────────────────────────
class FloorThemePage extends StatefulWidget {
  const FloorThemePage({super.key});
  @override
  State<FloorThemePage> createState() => _FloorThemePageState();
}

class _FloorThemePageState extends State<FloorThemePage> {
  late int sel = floorThemeOf(Game.i.house, Game.i.pid);
  bool busy = false;

  Future<void> _apply() async {
    setState(() => busy = true);
    try {
      await RcServer.setHouse('$sel');
      Game.i.house = '$sel';
      toast(t('Thème « ${kFloorThemes[sel].fr} » appliqué à ton étage', '« ${kFloorThemes[sel].en} » theme applied to your floor'));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      toast(errText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final g = Game.i;
    final th = kFloorThemes[sel];
    final ok = g.cards >= th.need;
    final current = floorThemeOf(g.house, g.pid);
    final unlocked = kFloorThemes.where((x) => g.cards >= x.need).length;
    final me = FloorData(
      pid: g.pid,
      name: g.name,
      avatar: g.avatar,
      score: g.score,
      cards: g.cards,
      coins: g.coins,
      theme: sel,
      online: true,
      me: true,
    );
    return Scaffold(
      appBar: AppBar(title: Text(t('Thème de mon étage', 'My floor theme'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
        // aperçu
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: const BoxDecoration(border: Border.symmetric(vertical: BorderSide(color: _kMold, width: 8))),
            child: TowerFloor(d: me, level: 0, shaft: false, index: 0),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800), minimumSize: const Size.fromHeight(46)),
          onPressed: busy || !ok || sel == current ? null : _apply,
          child: Text(
            !ok
                ? t('Se débloque à ${th.need} cartes (encore ${th.need - g.cards})', 'Unlocks at ${th.need} cards (${th.need - g.cards} to go)')
                : sel == current
                    ? t('Thème actuel', 'Current theme')
                    : t('Choisir « ${th.fr} »', 'Pick « ${th.en} »'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 14),
        Text(t('$unlocked / ${kFloorThemes.length} débloqués · tu as ${g.cards} cartes (${pctOf(g.cards)})',
                '$unlocked / ${kFloorThemes.length} unlocked · you have ${g.cards} cards (${pctOf(g.cards)})'),
            style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, box) {
          final cols = box.maxWidth > 560 ? 6 : 4;
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.82,
            children: [
              for (var i = 0; i < kFloorThemes.length; i++) _swatch(i, g.cards >= kFloorThemes[i].need),
            ],
          );
        }),
      ]),
    );
  }

  Widget _swatch(int i, bool ok) {
    final th = kFloorThemes[i];
    return GestureDetector(
      onTap: () => setState(() => sel = i),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2E2620),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: sel == i ? kGold : Colors.transparent, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _FacadePainter(th))),
              Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (var k = 0; k < 3; k++)
                    Container(
                      width: 12,
                      height: 18,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: k == 1 ? _kLit : const Color(0xFF1B2752),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        border: Border.all(color: th.frame, width: 2),
                      ),
                    ),
                ]),
              ),
              Positioned(left: 0, right: 0, bottom: 3, height: 3, child: Container(color: th.rail)),
              if (!ok) Positioned.fill(child: Container(color: Colors.black54, child: const Icon(Icons.lock, color: Colors.white70, size: 18))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(5, 4, 5, 5),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(th.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFFFF3D6))),
              Text(th.need == 0 ? t('offert', 'free') : t('${th.need} cartes', '${th.need} cards'),
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: ok ? const Color(0xFF9FE0C4) : const Color(0xFFFFD166))),
            ]),
          ),
        ]),
      ),
    );
  }
}
