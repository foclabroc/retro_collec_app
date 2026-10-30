import 'dart:math';

import 'package:flutter/material.dart';

import 'rj_engine.dart' show RjRng;

// ═══════════════════════════════════════════════════════════════════════════
// Course de jaquettes (30/10) : runner en mètres, pas fixe 1/120 s (même suite chez tous les joueurs).
//  · Obstacles tirés de la graine du serveur (RjRng, même suite VM / JS / Wasm) : mêmes pour les deux joueurs.
//  · Vitesse v(t) = min(10 + 0,1 t, 22) m/s : ≈ 1 900 m en 2 min. Le serveur plafonne à 100 + 24 m/s
//    (sql/2026-10-30_course_jaquettes.sql : garder synchronisé).
//  · Toucher en haut = saut, en bas (ou ↓ / S) = glisse ; ↑ / Espace / W = saut.
// ═══════════════════════════════════════════════════════════════════════════

const kRnW = 360.0, kRnH = 480.0;
const kRnDuration = 120; // secondes de jeu
const kRnStep = 1 / 120;
const kRnPxM = 20.0; // pixels par mètre
const kRnHeroX = 80.0; // position du coureur à l'écran
const kRnGround = 380.0;
const _gravity = 30.0, _jumpV = 9.5, _slideT = 0.5;
const _heroHalf = 0.3, _heroH = 1.2, _slideH = 0.6;
const _obsW = 1.2, _gndH = 0.9, _airLow = 0.8, _airHigh = 1.6;
const kRnRed = Color(0xFFE02020), kRnBlue = Color(0xFF2F8CFF);

double rnSpeed(double t) => min(10 + 0.1 * max(t, 0), 22.0);

class RnObs {
  final double x;
  final bool air; // barre en l'air : il faut glisser dessous
  const RnObs(this.x, this.air);
}

class RnWorld {
  final RjRng _r;
  final List<RnObs> obs = [];
  double _next = 30;
  RnWorld(int seed) : _r = RjRng(seed);

  void generateUntil(double d) {
    while (_next < d) {
      final air = _r.nextDouble() < 0.4;
      obs.add(RnObs(_next, air));
      final t = (-10 + sqrt(100 + 0.2 * _next)) / 0.1; // instant où l'on atteint cette distance
      final v = min(10 + 0.1 * t, 22.0);
      _next += _obsW + 2 + v * (0.95 + _r.nextDouble() * 0.8);
    }
  }
}

class RnHero {
  final RnWorld world;
  RnHero(this.world);
  double x = 0, y = 0, vy = 0, slide = 0;
  bool dead = false, jumpReq = false, slideReq = false;
  void Function(String sfx)? onSfx;

  int get score => x.floor();
  bool get sliding => slide > 0 && y == 0;

  void step(double dt, double t) {
    if (dead) return;
    x += rnSpeed(t) * dt;
    world.generateUntil(x + 40);
    if (jumpReq && y == 0) {
      vy = _jumpV;
      slide = 0;
      onSfx?.call('jump');
    }
    if (slideReq) {
      if (y == 0) {
        slide = _slideT;
      } else {
        vy -= 40 * dt * 4; // plonge vite si on appuie en l'air
      }
    }
    jumpReq = false;
    slideReq = false;
    if (slide > 0) slide -= dt;
    if (y > 0 || vy > 0) {
      vy -= _gravity * dt;
      y += vy * dt;
      if (y <= 0) {
        y = 0;
        vy = 0;
      }
    }
    final h = sliding ? _slideH : _heroH;
    for (final o in world.obs) {
      if (o.x > x + 2) break;
      if (o.x + _obsW < x - _heroHalf) continue;
      if (x + _heroHalf < o.x) continue;
      final hit = o.air ? (y + h > _airLow && y < _airHigh) : y < _gndH;
      if (hit) {
        dead = true;
        onSfx?.call('hit');
        return;
      }
    }
  }
}

/// Un coureur à dessiner (moi, fantôme ou joueur regardé) ; x en mètres, y = hauteur en mètres
class RnRunner {
  final double x, y;
  final bool sliding, dead, ghost;
  final Color color;
  final String? label;
  const RnRunner(this.x, this.y, this.color, {this.sliding = false, this.dead = false, this.ghost = false, this.label});
}

class RnPainter extends CustomPainter {
  final RnWorld world;
  final double camX; // mètre affiché sous le coureur
  final List<RnRunner> runners;
  final List<(double, String, Color)> lines; // repères (mètres, texte, couleur)
  RnPainter({required this.world, required this.camX, required this.runners, this.lines = const []});

  double _sx(double m) => kRnHeroX + (m - camX) * kRnPxM;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / kRnW, size.height / kRnH);
    const rect = Rect.fromLTWH(0, 0, kRnW, kRnH);
    canvas.drawRect(rect, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2B1B5E), Color(0xFF12102A)]).createShader(rect));
    // étagère de jeux en fond (défilement lent)
    final off = (camX * kRnPxM * 0.3) % 480;
    for (var k = 0; k < 12; k++) {
      var x = (k * 40.0 - off) % 480;
      if (x < 0) x += 480;
      x -= 40;
      _cover(canvas, Rect.fromLTWH(x, kRnGround - 120, 32, 44), k, dim: true);
      _cover(canvas, Rect.fromLTWH(x + 4, kRnGround - 70, 32, 44), k + 3, dim: true);
    }
    canvas.drawRect(Rect.fromLTWH(0, kRnGround - 74, kRnW, 5), Paint()..color = const Color(0xFF4E342E));
    canvas.drawRect(Rect.fromLTWH(0, kRnGround - 24, kRnW, 5), Paint()..color = const Color(0xFF4E342E));
    // sol en bois
    canvas.drawRect(const Rect.fromLTWH(0, kRnGround, kRnW, kRnH - kRnGround), Paint()..color = const Color(0xFF3E2723));
    canvas.drawRect(const Rect.fromLTWH(0, kRnGround, kRnW, 6), Paint()..color = const Color(0xFF6D4C41));
    final plank = Paint()..color = const Color(0xFF2E1B17);
    for (var m = (camX - 5).floorToDouble(); m < camX + 18; m++) {
      if (m % 2 == 0) canvas.drawRect(Rect.fromLTWH(_sx(m), kRnGround + 10, 2, kRnH - kRnGround - 10), plank);
    }
    for (var y = kRnGround + 28; y < kRnH; y += 26) {
      canvas.drawRect(Rect.fromLTWH(0, y, kRnW, 1), plank);
    }
    world.generateUntil(camX + 20);
    for (final o in world.obs) {
      final px = _sx(o.x);
      if (px > kRnW + 30) break;
      if (px + _obsW * kRnPxM < -30) continue;
      _obstacle(canvas, o, px);
    }
    for (final l in lines) {
      final px = _sx(l.$1);
      if (px < -10 || px > kRnW + 200) continue;
      canvas.drawRect(Rect.fromLTWH(px, 0, 2, kRnGround), Paint()..color = l.$3.withOpacity(0.55));
      _text(canvas, l.$2, Offset(px + 4, 6), l.$3, 10);
    }
    for (final r in runners.where((r) => r.ghost)) {
      _runner(canvas, r);
    }
    for (final r in runners.where((r) => !r.ghost)) {
      _runner(canvas, r);
    }
    canvas.restore();
  }

  static const _cols = [Color(0xFFE53935), Color(0xFF1E88E5), Color(0xFFFDD835), Color(0xFF43A047), Color(0xFF8E24AA), Color(0xFFFB8C00)];

  // jaquette : boîtier sombre, bandeau de couleur, illustration dégradée, pastille
  void _cover(Canvas canvas, Rect r, int i, {bool dim = false}) {
    final a = dim ? 0.55 : 1.0;
    final c1 = _cols[i % 6].withOpacity(a), c2 = _cols[(i + 2) % 6].withOpacity(a);
    canvas.drawRect(r.shift(const Offset(2, 2)), Paint()..color = Colors.black.withOpacity(0.5 * a));
    canvas.drawRect(r, Paint()..color = const Color(0xFF15171C));
    canvas.drawRect(Rect.fromLTWH(r.left + 2, r.top + 2, r.width - 4, 9), Paint()..color = c1);
    final art = Rect.fromLTWH(r.left + 2, r.top + 12, r.width - 4, r.height - 16);
    canvas.drawRect(art, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c2, const Color(0xFF222222)]).createShader(art));
    canvas.drawCircle(Offset(r.center.dx, r.top + r.height * 0.5), r.width * 0.2, Paint()..color = Colors.white.withOpacity(0.85 * a));
    canvas.drawRect(r.deflate(0.5), Paint()..style = PaintingStyle.stroke..color = Colors.white.withOpacity(0.55 * a));
  }

  void _obstacle(Canvas canvas, RnObs o, double px) {
    final i = o.x.floor() ~/ 7;
    final w = _obsW * kRnPxM;
    if (!o.air) {
      final h = _gndH * kRnPxM;
      _cover(canvas, Rect.fromLTWH(px, kRnGround - h, w, h), i);
    } else {
      final top = kRnGround - _airHigh * kRnPxM;
      final h = (_airHigh - _airLow) * kRnPxM;
      final cable = Paint()..color = Colors.white38..strokeWidth = 1;
      canvas.drawLine(Offset(px + 4, top), Offset(px + 4, 0), cable);
      canvas.drawLine(Offset(px + w - 4, top), Offset(px + w - 4, 0), cable);
      _cover(canvas, Rect.fromLTWH(px, top, w, h), i);
    }
  }

  // coureur : tête ronde (avatar), pull coloré, jambes qui alternent ; hitbox inchangée
  void _runner(Canvas canvas, RnRunner r) {
    final op = r.ghost ? 0.5 : 1.0;
    final h = (r.sliding ? _slideH : _heroH) * kRnPxM;
    final w = (r.sliding ? 1.0 : 0.7) * kRnPxM;
    final px = _sx(r.x) - w / 2;
    final top = kRnGround - r.y * kRnPxM - h;
    final air = r.y > 0.05;
    final shirt = (r.dead ? Colors.grey : r.color).withOpacity(op);
    final skin = Paint()..color = const Color(0xFFFFCC80).withOpacity(op);
    final white = Paint()..color = Colors.white.withOpacity(op);
    final dark = Paint()..color = Colors.black.withOpacity(op);
    if (air) {
      canvas.drawOval(Rect.fromCenter(center: Offset(px + w / 2, kRnGround + 3), width: w * (1 - r.y / 6).clamp(0.3, 1.0), height: 4), Paint()..color = Colors.black38);
    }
    if (r.sliding) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(px, top + 5, w - 4, h - 5), const Radius.circular(4)), Paint()..color = shirt);
      canvas.drawCircle(Offset(px + w - 5, top + h / 2 + 1), 6, skin);
      canvas.drawRect(Rect.fromLTWH(px + w - 5, top + h / 2 - 2, 3, 3), white);
      canvas.drawRect(Rect.fromLTWH(px + w - 4, top + h / 2 - 1, 2, 2), dark);
    } else {
      final ph = (r.x * 1.6).floor().isEven;
      final leg = Paint()..color = const Color(0xFF283593).withOpacity(op);
      canvas.drawRect(Rect.fromLTWH(px + 2, top + h - 7, 5, air || ph ? 7 : 4), leg);
      canvas.drawRect(Rect.fromLTWH(px + w - 7, top + h - 7, 5, air || !ph ? 7 : 4), leg);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(px, top + 10, w, h - 17), const Radius.circular(4)), Paint()..color = shirt);
      canvas.drawCircle(Offset(px + w / 2, top + 6), 7.5, skin);
      canvas.drawRect(Rect.fromLTWH(px + w / 2 + 1, top + 3, 4, 4), white);
      canvas.drawRect(Rect.fromLTWH(px + w / 2 + 3, top + 4, 2, 2), dark);
    }
    if (!r.dead && !r.ghost) {
      final t = Paint()..color = Colors.white.withOpacity(0.25);
      for (var i = 0; i < 3; i++) {
        canvas.drawRect(Rect.fromLTWH(px - 8 - i * 6, top + 8 + i * 7, 6.0 - i, 2), t);
      }
    }
    if (r.label != null) _text(canvas, r.label!, Offset(px - 10, top - 14), r.color, 10);
  }

  void _text(Canvas canvas, String s, Offset at, Color color, double size) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w800, shadows: const [Shadow(color: Colors.black, blurRadius: 3)])),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 220);
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
