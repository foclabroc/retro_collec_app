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
const kRnRed = Color(0xFFE02020), kRnBlue = Color(0xFF2F8CFF), _green = Color(0xFF69F0AE);

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
    canvas.drawRect(rect, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0B1040), Color(0xFF5A1F7A), Color(0xFFFF6F61)], stops: [0.0, 0.6, 1.0]).createShader(rect));
    // étoiles
    final star = Paint()..color = Colors.white.withOpacity(0.8);
    for (var i = 0; i < 40; i++) {
      final sx = (i * 97.0 - camX * kRnPxM * 0.03) % kRnW;
      canvas.drawRect(Rect.fromLTWH(sx < 0 ? sx + kRnW : sx, (i * 53) % 190 + 4.0, i % 3 == 0 ? 2 : 1, i % 3 == 0 ? 2 : 1), star);
    }
    // soleil rétro
    final sun = Paint()..color = const Color(0xFFFFD166).withOpacity(0.9);
    canvas.drawCircle(const Offset(270, 250), 46, sun);
    for (var k = 0; k < 5; k++) {
      canvas.drawRect(Rect.fromLTWH(220, 262 + k * 10.0, 100, 2 + k * 1.2), Paint()..color = const Color(0xFF5A1F7A));
    }
    // villes en parallaxe (deux couches)
    void skyline(double speed, Color col, double hMax, double wBlock) {
      final p = Paint()..color = col;
      final off = (camX * kRnPxM * speed) % (wBlock * 6);
      for (var k = -1; k < 9; k++) {
        final idx = k + (camX * kRnPxM * speed / (wBlock * 6)).floor() * 6;
        final h = 40 + ((idx * 37) % 7) * hMax / 7;
        canvas.drawRect(Rect.fromLTWH(k * wBlock - off, kRnGround - h, wBlock - 3, h), p);
      }
    }
    skyline(0.12, const Color(0xFF2A1450), 120, 46);
    skyline(0.3, const Color(0xFF160A33), 80, 38);
    // sol
    canvas.drawRect(const Rect.fromLTWH(0, kRnGround, kRnW, kRnH - kRnGround), Paint()..color = const Color(0xFF0D0F14));
    canvas.drawRect(const Rect.fromLTWH(0, kRnGround, kRnW, 3), Paint()..color = _green);
    canvas.drawRect(const Rect.fromLTWH(0, kRnGround + 3, kRnW, 6), Paint()..color = _green.withOpacity(0.18));
    final grid = Paint()..color = _green.withOpacity(0.22);
    for (var m = (camX - 5).floorToDouble(); m < camX + 18; m++) {
      canvas.drawRect(Rect.fromLTWH(_sx(m), kRnGround + 10, 1, kRnH - kRnGround - 10), grid);
    }
    for (var y = kRnGround + 24; y < kRnH; y += 22) {
      canvas.drawRect(Rect.fromLTWH(0, y, kRnW, 1), grid);
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

  static const _cols = [Color(0xFF26A69A), Color(0xFFEC407A), Color(0xFF5C6BC0), Color(0xFFFFA726)];

  // boîtier de jeu : tranche colorée, étiquette claire, pastille de couleur
  void _box(Canvas canvas, Rect r, Color c) {
    canvas.drawRRect(RRect.fromRectAndRadius(r.shift(const Offset(2, 2)), const Radius.circular(3)), Paint()..color = Colors.black38);
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), Paint()..color = c);
    canvas.drawRect(Rect.fromLTWH(r.left, r.top, 4, r.height), Paint()..color = Colors.black26);
    canvas.drawRect(Rect.fromLTWH(r.left + 7, r.top + 4, r.width - 11, r.height * 0.5), Paint()..color = Colors.white.withOpacity(0.88));
    canvas.drawRect(Rect.fromLTWH(r.left + 9, r.top + 6, r.width - 15, 3), Paint()..color = c.withOpacity(0.8));
    canvas.drawCircle(Offset(r.left + r.width / 2 + 2, r.bottom - r.height * 0.22), r.height * 0.1, Paint()..color = Colors.white70);
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = Colors.white.withOpacity(0.5));
  }

  void _obstacle(Canvas canvas, RnObs o, double px) {
    final c = _cols[(o.x.floor() ~/ 7) % _cols.length];
    final w = _obsW * kRnPxM;
    if (!o.air) {
      final h = _gndH * kRnPxM;
      _box(canvas, Rect.fromLTWH(px, kRnGround - h, w, h), c);
    } else {
      final top = kRnGround - _airHigh * kRnPxM;
      final h = (_airHigh - _airLow) * kRnPxM;
      // câbles de suspension
      final cable = Paint()..color = Colors.white38..strokeWidth = 1;
      canvas.drawLine(Offset(px + 4, top), Offset(px + 4, 0), cable);
      canvas.drawLine(Offset(px + w - 4, top), Offset(px + w - 4, 0), cable);
      _box(canvas, Rect.fromLTWH(px, top, w, h), c);
    }
  }

  void _runner(Canvas canvas, RnRunner r) {
    final op = r.ghost ? 0.5 : 1.0;
    final col = (r.dead ? Colors.grey : r.color).withOpacity(op);
    final h = (r.sliding ? _slideH : _heroH) * kRnPxM;
    final w = (r.sliding ? 1.0 : 0.7) * kRnPxM;
    final px = _sx(r.x) - w / 2;
    final top = kRnGround - r.y * kRnPxM - h;
    final white = Paint()..color = Colors.white.withOpacity(op);
    final dark = Paint()..color = Colors.black.withOpacity(op);
    final air = r.y > 0.05;
    // jambes qui alternent selon la distance
    if (!r.sliding) {
      final ph = (r.x * 1.6).floor().isEven;
      final leg = Paint()..color = col;
      final lh = air ? 5.0 : 6.0;
      canvas.drawRect(Rect.fromLTWH(px + 2, top + h - lh, 5, lh + (air || ph ? 0 : -2)), leg);
      canvas.drawRect(Rect.fromLTWH(px + w - 7, top + h - lh, 5, lh + (air || !ph ? 0 : -2)), leg);
    }
    // ombre au sol
    if (air) canvas.drawOval(Rect.fromCenter(center: Offset(px + w / 2, kRnGround + 2), width: w * (1 - r.y / 6).clamp(0.3, 1.0), height: 4), Paint()..color = Colors.black38);
    // corps : cartouche
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(px, top, w, h - (r.sliding ? 0 : 5)), const Radius.circular(4));
    canvas.drawRRect(body, Paint()..color = col);
    canvas.drawRect(Rect.fromLTWH(px + 3, top + 3, w - 6, (h - 5) * 0.32), Paint()..color = Colors.black.withOpacity(0.28 * op));
    // visage
    final ex = px + w - (r.sliding ? 10 : 8);
    canvas.drawRect(Rect.fromLTWH(ex, top + (r.sliding ? 5 : 6), 5, 5), white);
    canvas.drawRect(Rect.fromLTWH(ex + 2, top + (r.sliding ? 6 : 7), 2, 3), dark);
    // traînée de vitesse
    if (!r.dead && !r.ghost) {
      final t = Paint()..color = Colors.white.withOpacity(0.25);
      for (var i = 0; i < 3; i++) {
        canvas.drawRect(Rect.fromLTWH(px - 8 - i * 6, top + 6 + i * 7, 6.0 - i, 2), t);
      }
    }
    canvas.drawRRect(body, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = Colors.white.withOpacity(0.7 * op));
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
