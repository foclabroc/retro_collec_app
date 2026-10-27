import 'dart:math';

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Moteur du duel Rétro Jump (port de foclabroc/retro_jump_app, sans bonus).
//  · Monde fixe de 360 × 640 unités, mis à l'échelle de l'écran : même parcours
//    et même vue pour tout le monde, quel que soit le téléphone.
//  · Parcours tiré de la graine du serveur (RjRng, mulberry32 en entiers 32 bits :
//    même suite en Android, en JavaScript et en WebAssembly).
//  · Plateformes mobiles et bugs : position calculée à partir du temps de la partie
//    (pas de l'instant où ils sont apparus) → identique chez les deux joueurs et les spectateurs.
//  · Physique à pas fixe (1/120 s), mêmes constantes que Rétro Jump.
// ═══════════════════════════════════════════════════════════════════════════

const kRjW = 360.0, kRjH = 640.0;
const kRjDuration = 120; // secondes de jeu
const _gravity = 1800.0, _jumpV = -820.0, _springV = -1300.0, _stompV = -900.0;
const _moveSpeed = 330.0, _moveAccel = 2200.0;
const _heroW = 44.0, _heroH = 30.0, _platW = 68.0, _platH = 14.0, _enemyW = 30.0, _enemyH = 23.0;
const kRjStep = 1 / 120;

/// Générateur pseudo-aléatoire mulberry32 (entiers 32 bits, identique sur toutes les plateformes).
class RjRng {
  int _s;
  RjRng(int seed) : _s = seed & 0xFFFFFFFF;

  /// a × b modulo 2³² sans dépasser 2⁵³ (exact en JavaScript)
  static int _mul(int a, int b) {
    final al = a & 0xFFFF, ah = (a >>> 16) & 0xFFFF;
    return (al * b + (((ah * b) & 0xFFFF) << 16)) & 0xFFFFFFFF;
  }

  int nextU32() {
    _s = (_s + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _s;
    t = _mul(t ^ (t >>> 15), t | 1);
    t = (t ^ ((t + _mul(t ^ (t >>> 7), t | 61)) & 0xFFFFFFFF)) & 0xFFFFFFFF;
    return (t ^ (t >>> 14)) & 0xFFFFFFFF;
  }

  double nextDouble() => nextU32() / 4294967296.0;
  bool nextBool() => (nextU32() & 1) == 1;
  int nextInt(int n) => (nextDouble() * n).floor().clamp(0, n - 1);
}

enum RjPlatType { normal, moving, breakable, spring }

class RjPlat {
  final double x0, y; // x au temps 0 (bord gauche), y = dessus
  final RjPlatType type;
  final double vx;
  final int color;
  double fall = 0; // cassée : distance de chute
  bool broken = false;
  RjPlat(this.x0, this.y, this.type, this.vx, this.color);

  /// Position à l'instant [t] (aller-retour entre les bords)
  double xAt(double t) => vx == 0 ? x0 : _bounce(x0 + vx * t, kRjW - _platW);
}

class RjEnemy {
  final double x0, y, vx, phase0;
  bool dead = false;
  double fall = 0;
  RjEnemy(this.x0, this.y, this.vx, this.phase0);
  bool get moving => vx != 0;
  double xAt(double t) => vx == 0 ? x0 : _enemyW / 2 + _bounce(x0 - _enemyW / 2 + vx * t, kRjW - _enemyW);
  double yAt(double t) => y + sin((phase0 + t) * 3) * 3 + fall;
}

/// Va-et-vient sur [0, len] (rebond sur les bords)
double _bounce(double s, double len) {
  final m = s % (2 * len); // toujours ≥ 0 en Dart
  return m <= len ? m : 2 * len - m;
}

/// Le monde (parcours) : identique pour tous à partir de la graine.
class RjWorld {
  final RjRng _rng;
  final List<RjPlat> plats = [];
  final List<RjEnemy> enemies = [];
  static const startY = kRjH - 60;
  double _topY = startY, _lastEnemyY = startY;

  RjWorld(int seed) : _rng = RjRng(seed) {
    plats.add(RjPlat(kRjW / 2 - _platW / 2, startY, RjPlatType.normal, 0, 4));
    generateUntil(-kRjH);
  }

  /// Génère le parcours jusqu'à la hauteur [limitY]. L'écart entre deux plateformes
  /// solides reste sous la hauteur d'un saut normal (~185) : toujours faisable.
  void generateUntil(double limitY) {
    while (_topY > limitY) {
      final heightPts = (startY - _topY) / 10;
      final d = (heightPts / 3000).clamp(0.0, 1.0);
      final minGap = 55 + 35 * d;
      final maxGap = 95 + 70 * d;
      final gap = minGap + _rng.nextDouble() * (maxGap - minGap);
      final y = _topY - gap;
      final x = _rng.nextDouble() * (kRjW - _platW);
      final r = _rng.nextDouble();
      final type = r < 0.06
          ? RjPlatType.spring
          : r < 0.06 + 0.10 + 0.25 * d
              ? RjPlatType.moving
              : RjPlatType.normal;
      final vx = type == RjPlatType.moving ? (60 + 90 * d) * (_rng.nextBool() ? 1 : -1) : 0.0;
      plats.add(RjPlat(x, y, type, vx, _rng.nextInt(_kCartColors.length)));
      // piège : cartouche fissurée entre deux plateformes
      if (gap > 70 && _rng.nextDouble() < 0.12 + 0.20 * d) {
        final by = y + gap * (0.35 + _rng.nextDouble() * 0.3);
        final bx = _rng.nextDouble() * (kRjW - _platW);
        plats.add(RjPlat(bx, by, RjPlatType.breakable, 0, 0));
      }
      // bug (à partir de 200 pts, au moins 350 entre deux)
      if (heightPts > 200 && y < _lastEnemyY - 350 && _rng.nextDouble() < 0.10 + 0.15 * d) {
        final ex = _enemyW / 2 + _rng.nextDouble() * (kRjW - _enemyW);
        final moving = _rng.nextDouble() < 0.35 + 0.30 * d;
        final evx = moving ? (50 + 70 * d) * (_rng.nextBool() ? 1 : -1) : 0.0;
        enemies.add(RjEnemy(ex, y + gap / 2, evx, _rng.nextDouble() * 6));
        _lastEnemyY = y;
      }
      _topY = y;
    }
  }

  /// Génération au-dessus de [top] (rien n'est retiré : après une chute, la caméra peut
  /// redescendre suivre l'adversaire ; 2 min de partie = quelques centaines de plateformes)
  void keep(double top) => generateUntil(top - 120);
}

/// Mon héros (joueur) : physique à pas fixe.
class RjHero {
  final RjWorld w;
  double x = kRjW / 2, y = RjWorld.startY, vx = 0, vy = 0;
  double camY = 0, maxHeight = 0, squash = 0;
  bool dead = false, right = true;
  int score = 0;
  void Function(String sfx)? onSfx;
  RjHero(this.w);

  double get height => RjWorld.startY - y;

  /// Un pas de [dt] secondes ; [t] = temps de la partie à la fin du pas ; [dir] = -1, 0 ou 1.
  void step(double dt, double t, double dir) {
    if (dead) return;
    final target = dir * _moveSpeed;
    if (vx < target) {
      vx = min(target, vx + _moveAccel * dt);
    } else if (vx > target) {
      vx = max(target, vx - _moveAccel * dt);
    }
    x += vx * dt;
    if (x < -_heroW / 2) x += kRjW + _heroW;
    if (x > kRjW + _heroW / 2) x -= kRjW + _heroW;
    if (dir.abs() > 0.05) right = dir > 0;

    final prevY = y;
    vy += _gravity * dt;
    y += vy * dt;
    if (squash > 0) squash = max(0, squash - dt * 5);

    for (final p in w.plats) {
      if (p.broken) p.fall += 520 * dt;
    }
    for (final e in w.enemies) {
      if (e.dead) e.fall += 480 * dt;
    }

    // atterrissage (en descente)
    if (vy > 0) {
      for (final p in w.plats) {
        if (p.broken) continue;
        if (p.y > camY + kRjH - 6) continue; // sous l'écran : pas de rebond
        final px = p.xAt(t);
        final overlap = (x + _heroW * 0.35) > px && (x - _heroW * 0.35) < px + _platW;
        if (!overlap || prevY > p.y + 1 || y < p.y) continue;
        if (p.type == RjPlatType.breakable) {
          p.broken = true;
          onSfx?.call('break');
          continue;
        }
        y = p.y;
        squash = 1;
        if (p.type == RjPlatType.spring) {
          vy = _springV;
          onSfx?.call('spring');
        } else {
          vy = _jumpV;
          onSfx?.call('jump');
        }
        break;
      }
    }

    // bugs : écrasés par au-dessus, sinon on tombe
    for (final e in w.enemies) {
      if (e.dead) continue;
      final ex = e.xAt(t), ey = e.yAt(t);
      final hitX = (x - ex).abs() < _enemyW / 2 + _heroW * 0.3;
      final hitY = y > ey - _enemyH / 2 && y - _heroH < ey + _enemyH / 2;
      if (!hitX || !hitY) continue;
      if (vy > 0 && prevY <= ey - _enemyH / 2 + 10) {
        e.dead = true;
        vy = _stompV;
        squash = 1;
        onSfx?.call('stomp');
      } else {
        _die();
        return;
      }
    }

    if (y - camY < kRjH * 0.45) camY = y - kRjH * 0.45;
    final h = RjWorld.startY - y;
    if (h > maxHeight) {
      maxHeight = h;
      score = (maxHeight / 10).floor();
    }
    w.keep(camY);
    if (y - _heroH > camY + kRjH + 10) _die();
  }

  void _die() {
    if (dead) return;
    dead = true;
    onSfx?.call('hurt');
  }
}

/// Positions reçues d'un autre joueur (≈ 10 par seconde), lues avec un peu de retard pour lisser.
class RjTrack {
  final String name;
  final int side;
  RjTrack(this.name, this.side);
  final List<(double t, double x, double h, bool right)> _s = [];
  int score = 0;
  bool dead = false;
  double lastT = -1;

  void add(double t, double x, double h, bool right, int sc, bool d) {
    if (t <= lastT) return;
    lastT = t;
    _s.add((t, x, h, right));
    if (_s.length > 40) _s.removeAt(0);
    score = max(score, sc);
    if (d) dead = true;
  }

  bool get has => _s.isNotEmpty;

  /// Position à l'instant [t] (interpolée), null s'il n'y a rien
  (double x, double h, bool right)? at(double t) {
    if (_s.isEmpty) return null;
    if (t <= _s.first.$1) return (_s.first.$2, _s.first.$3, _s.first.$4);
    for (var i = _s.length - 1; i > 0; i--) {
      final a = _s[i - 1], b = _s[i];
      if (t >= a.$1 && t <= b.$1) {
        final k = b.$1 == a.$1 ? 1.0 : (t - a.$1) / (b.$1 - a.$1);
        final x = (b.$2 - a.$2).abs() > kRjW / 2 ? b.$2 : a.$2 + (b.$2 - a.$2) * k; // passage d'un bord à l'autre
        return (x, a.$3 + (b.$3 - a.$3) * k, b.$4);
      }
    }
    final l = _s.last;
    return (l.$2, l.$3, l.$4);
  }
}

// ─── Dessin ────────────────────────────────────────────────────────────────

const _kCartColors = [
  Color(0xFF5C6BC0), Color(0xFF26A69A), Color(0xFFAB47BC),
  Color(0xFFEF6C00), Color(0xFF7CB342), Color(0xFFEC407A),
];
const kRjRed = Color(0xFFE02020), kRjBlue = Color(0xFF2F8CFF);
const _dark = Color(0xFF0D0F14);

const _robotMap = [
  '......Y......',
  '......X......',
  '..XXXXXXXXX..',
  '.XXXXXXXXXXX.',
  '.XWWXXXXXWWX.',
  '.XWBXXXXXWBX.',
  '.XXXXXXXXXXX.',
  '.XXXKKKKKXXX.',
  '..XXXXXXXXX..',
  '...XX...XX...',
  '..XXX...XXX..',
];

const _bugFrames = [
  ['...HHH...', '..HWHWH..', 'L.XXDXX.L', '.XXSDSXX.', 'LXXXDXXXL', '.XSXDXSX.', 'L.XXDXX.L'],
  ['...HHH...', '..HWHWH..', '..XXDXX..', 'LXXSDSXXL', '.XXXDXXX.', 'LXSXDXSXL', '..XXDXX..'],
];

/// Robot de Rétro Jump, pieds en (0, 0), dans la couleur [body]
void rjDrawRobot(Canvas c, bool right, Color body, {double opacity = 1}) {
  const p = 3.4;
  final cols = _robotMap.first.length;
  final rows = _robotMap.length;
  final ox = -cols * p / 2;
  final oy = -rows * p;
  final dark = Color.lerp(body, Colors.black, 0.6)!;
  final paint = Paint();
  for (var r = 0; r < rows; r++) {
    final row = right ? _robotMap[r] : _robotMap[r].replaceAll('WB', 'BW');
    for (var col = 0; col < cols; col++) {
      final ch = row[col];
      if (ch == '.') continue;
      final color = switch (ch) {
        'X' => body,
        'W' => Colors.white,
        'Y' => const Color(0xFFFFD740),
        'K' => dark,
        _ => _dark,
      };
      paint.color = color.withOpacity(opacity);
      c.drawRect(Rect.fromLTWH(ox + col * p, oy + r * p, p + 0.2, p + 0.2), paint);
    }
  }
}

/// Un coureur à dessiner (moi, l'adversaire en fantôme, ou un joueur vu en spectateur)
class RjRunner {
  final double x, h; // h = hauteur au-dessus du départ (unités du monde)
  final bool right;
  final Color color;
  final String? label;
  final bool ghost, dead;
  final double squash;
  const RjRunner(this.x, this.h, this.right, this.color, {this.label, this.ghost = false, this.dead = false, this.squash = 0});
}

class RjPainter extends CustomPainter {
  final RjWorld world;
  final double camY, t;
  final List<RjRunner> runners;
  final List<(double h, String label, Color color)> lines; // repères de hauteur (record de l'adversaire…)
  RjPainter({required this.world, required this.camY, required this.t, required this.runners, this.lines = const []});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / kRjW;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(s);
    _background(canvas);
    for (final p in world.plats) {
      final sy = p.y + p.fall - camY;
      if (sy < -30 || sy > kRjH + 30) continue;
      _cartridge(canvas, p, Offset(p.xAt(t), sy));
    }
    for (final e in world.enemies) {
      final sy = e.yAt(t) - camY;
      if (sy < -30 || sy > kRjH + 30) continue;
      _bug(canvas, e, Offset(e.xAt(t), sy));
    }
    for (final l in lines) {
      _line(canvas, l.$1, l.$2, l.$3);
    }
    // fantômes d'abord, moi par-dessus
    for (final r in runners.where((r) => r.ghost)) {
      _runner(canvas, r);
    }
    for (final r in runners.where((r) => !r.ghost)) {
      _runner(canvas, r);
    }
    canvas.restore();
  }

  void _background(Canvas canvas) {
    // le ciel fonce en montant : bleu nuit → violet → noir étoilé
    final hPts = (RjWorld.startY - camY - kRjH) / 10;
    final k = (hPts / 2500).clamp(0.0, 1.0);
    final top = Color.lerp(const Color(0xFF1B2A6B), const Color(0xFF07051A), k)!;
    final bottom = Color.lerp(const Color(0xFF3B1F6E), const Color(0xFF140A33), k)!;
    canvas.drawRect(const Rect.fromLTWH(0, 0, kRjW, kRjH),
        Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]).createShader(const Rect.fromLTWH(0, 0, kRjW, kRjH)));
    // étoiles (défilement lent)
    final star = Paint()..color = Colors.white.withOpacity(0.18 + 0.3 * k);
    final off = (-camY * 0.3) % 160;
    for (var i = 0; i < 26; i++) {
      final sx = (i * 137.0) % kRjW;
      final sy = ((i * 89.0) % 160) + off - 160;
      for (var r = 0; r < 6; r++) {
        canvas.drawRect(Rect.fromLTWH(sx, sy + r * 160, 2, 2), star);
      }
    }
    // repères de hauteur tous les 250 points
    final mark = Paint()..color = Colors.white.withOpacity(0.07);
    final first = ((RjWorld.startY - camY - kRjH) / 2500).floor();
    for (var n = max(1, first); n <= first + 2; n++) {
      final sy = RjWorld.startY - n * 2500 - camY;
      if (sy < -10 || sy > kRjH + 10) continue;
      canvas.drawRect(Rect.fromLTWH(0, sy, kRjW, 1), mark);
      _text(canvas, '${n * 250}', Offset(4, sy - 13), Colors.white.withOpacity(0.25), 10);
    }
  }

  void _cartridge(Canvas canvas, RjPlat p, Offset o) {
    final body = switch (p.type) {
      RjPlatType.moving => Colors.lightBlueAccent.shade400,
      RjPlatType.breakable => const Color(0xFF6D4C41),
      _ => _kCartColors[p.color % _kCartColors.length],
    };
    final op = p.broken ? 0.5 : 1.0;
    canvas.save();
    if (p.broken) {
      canvas.translate(o.dx + _platW / 2, o.dy + _platH / 2);
      canvas.rotate(0.25);
      canvas.translate(-(o.dx + _platW / 2), -(o.dy + _platH / 2));
    }
    final rect = RRect.fromRectAndCorners(Rect.fromLTWH(o.dx, o.dy, _platW, _platH),
        topLeft: const Radius.circular(4), topRight: const Radius.circular(4), bottomLeft: const Radius.circular(2), bottomRight: const Radius.circular(2));
    canvas.drawRRect(rect, Paint()..color = body.withOpacity(op));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(o.dx + 10, o.dy + 3, _platW - 20, _platH - 7), const Radius.circular(2)),
        Paint()..color = Colors.white.withOpacity(0.28 * op));
    final notch = Paint()..color = Colors.black.withOpacity(0.35 * op);
    for (var i = 0; i < 5; i++) {
      canvas.drawRect(Rect.fromLTWH(o.dx + 14 + i * 9, o.dy + _platH - 3, 5, 3), notch);
    }
    if (p.type == RjPlatType.breakable) {
      final crack = Paint()
        ..color = Colors.black.withOpacity(0.6 * op)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawPath(
          Path()
            ..moveTo(o.dx + 22, o.dy)
            ..lineTo(o.dx + 28, o.dy + 6)
            ..lineTo(o.dx + 24, o.dy + 10)
            ..lineTo(o.dx + 31, o.dy + _platH)
            ..moveTo(o.dx + 46, o.dy)
            ..lineTo(o.dx + 41, o.dy + 7)
            ..lineTo(o.dx + 47, o.dy + _platH),
          crack);
    }
    if (p.type == RjPlatType.spring) {
      final cx = o.dx + _platW / 2;
      final path = Path()..moveTo(cx - 6, o.dy);
      for (var i = 0; i < 4; i++) {
        path.lineTo(i.isEven ? cx + 6 : cx - 6, o.dy - 3 - i * 3);
      }
      canvas.drawPath(path, Paint()
        ..color = Colors.amberAccent
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 9, o.dy - 16, 18, 4), const Radius.circular(2)), Paint()..color = Colors.amberAccent);
    }
    canvas.restore();
  }

  void _bug(Canvas canvas, RjEnemy e, Offset c) {
    final body = e.moving ? const Color(0xFFE040FB) : const Color(0xFF76FF03);
    final dark = e.moving ? const Color(0xFF6A1B9A) : const Color(0xFF33691E);
    const p = 3.3;
    final rows = _bugFrames[(t * 5 + e.phase0).floor().isEven ? 0 : 1];
    final cols = rows.first.length;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    if (e.dead) canvas.rotate(pi);
    final paint = Paint();
    for (var r = 0; r < rows.length; r++) {
      for (var col = 0; col < cols; col++) {
        final ch = rows[r][col];
        if (ch == '.') continue;
        paint.color = switch (ch) { 'X' => body, 'W' => Colors.white, _ => dark }.withOpacity(e.dead ? 0.6 : 1);
        canvas.drawRect(Rect.fromLTWH(-cols * p / 2 + col * p, -rows.length * p / 2 + r * p, p + 0.2, p + 0.2), paint);
      }
    }
    canvas.restore();
  }

  void _line(Canvas canvas, double h, String label, Color color) {
    final sy = RjWorld.startY - h - camY;
    if (sy < 0 || sy > kRjH) return;
    final paint = Paint()
      ..color = color.withOpacity(0.7)
      ..strokeWidth = 1.5;
    for (var x = 0.0; x < kRjW; x += 14) {
      canvas.drawLine(Offset(x, sy), Offset(x + 8, sy), paint);
    }
    _text(canvas, label, Offset(kRjW - 6, sy - 14), color, 10, right: true);
  }

  void _runner(Canvas canvas, RjRunner r) {
    final sy = RjWorld.startY - r.h - camY;
    final op = r.ghost ? 0.45 : 1.0;
    if (sy < 8) {
      // au-dessus de l'écran : flèche en haut
      _arrow(canvas, r.x.clamp(14.0, kRjW - 14), 8, true, r.color, r.label);
      return;
    }
    if (sy > kRjH + 36) {
      if (!r.dead) _arrow(canvas, r.x.clamp(14.0, kRjW - 14), kRjH - 8, false, r.color, r.label);
      return;
    }
    canvas.save();
    canvas.translate(r.x, sy);
    canvas.scale(1 + 0.15 * r.squash, 1 - 0.2 * r.squash);
    if (r.dead) canvas.rotate(pi);
    rjDrawRobot(canvas, r.right, r.color, opacity: op);
    canvas.restore();
    if (r.label != null) _text(canvas, r.label!, Offset(r.x, sy - 52), Colors.white.withOpacity(r.ghost ? 0.75 : 0.95), 10, center: true);
  }

  void _arrow(Canvas canvas, double x, double y, bool up, Color color, String? label) {
    final p = Path();
    if (up) {
      p.moveTo(x, y - 4);
      p.lineTo(x - 7, y + 6);
      p.lineTo(x + 7, y + 6);
    } else {
      p.moveTo(x, y + 4);
      p.lineTo(x - 7, y - 6);
      p.lineTo(x + 7, y - 6);
    }
    p.close();
    canvas.drawPath(p, Paint()..color = color);
    if (label != null) _text(canvas, label, Offset(x, up ? y + 8 : y - 22), Colors.white70, 9, center: true);
  }

  void _text(Canvas canvas, String s, Offset at, Color color, double size, {bool center = false, bool right = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w800, shadows: const [Shadow(color: Colors.black, blurRadius: 3)])),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 140);
    final dx = center ? at.dx - tp.width / 2 : right ? at.dx - tp.width : at.dx;
    tp.paint(canvas, Offset(dx, at.dy));
  }

  @override
  bool shouldRepaint(covariant RjPainter old) => true;
}
