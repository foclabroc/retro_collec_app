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
    canvas.drawRect(rect, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1B2A6B), Color(0xFF3B1F6E), Color(0xFF07051A)]).createShader(rect));
    // collines lointaines (défilement lent)
    final far = Paint()..color = Colors.white.withOpacity(0.06);
    for (var k = -1; k < 8; k++) {
      final bx = k * 90.0 - (camX * kRnPxM * 0.25) % 90;
      canvas.drawRect(Rect.fromLTWH(bx, kRnGround - 70 - (k % 3) * 24, 60, 70 + (k % 3) * 24), far);
    }
    // sol
    canvas.drawRect(const Rect.fromLTWH(0, kRnGround, kRnW, kRnH - kRnGround), Paint()..color = const Color(0xFF0D0F14));
    canvas.drawRect(const Rect.fromLTWH(0, kRnGround, kRnW, 3), Paint()..color = _green.withOpacity(0.7));
    final tick = Paint()..color = Colors.white24;
    for (var m = (camX - 5).floorToDouble(); m < camX + 16; m++) {
      if (m % 5 == 0) canvas.drawRect(Rect.fromLTWH(_sx(m), kRnGround + 8, 2, 8), tick);
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

  void _obstacle(Canvas canvas, RnObs o, double px) {
    final c = _cols[(o.x.floor() ~/ 7) % _cols.length];
    final w = _obsW * kRnPxM;
    if (!o.air) {
      final h = _gndH * kRnPxM;
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(px, kRnGround - h, w, h), const Radius.circular(3));
      canvas.drawRRect(r, Paint()..color = c);
      canvas.drawRect(Rect.fromLTWH(px + 4, kRnGround - h + 4, w - 8, 5), Paint()..color = Colors.white.withOpacity(0.3));
      canvas.drawRect(Rect.fromLTWH(px + 4, kRnGround - 6, w - 8, 3), Paint()..color = Colors.black26);
    } else {
      final top = kRnGround - _airHigh * kRnPxM;
      final h = (_airHigh - _airLow) * kRnPxM;
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(px, top, w, h), const Radius.circular(3));
      canvas.drawRRect(r, Paint()..color = c);
      canvas.drawRect(Rect.fromLTWH(px + 3, top + 3, w - 6, 3), Paint()..color = Colors.white.withOpacity(0.3));
      // poteaux
      canvas.drawRect(Rect.fromLTWH(px + 2, top + h, 2, 4), Paint()..color = Colors.white30);
      canvas.drawRect(Rect.fromLTWH(px + w - 4, top + h, 2, 4), Paint()..color = Colors.white30);
    }
  }

  void _runner(Canvas canvas, RnRunner r) {
    final op = r.ghost ? 0.5 : 1.0;
    final h = (r.sliding ? _slideH : _heroH) * kRnPxM;
    final w = (r.sliding ? 1.0 : 0.7) * kRnPxM;
    final px = _sx(r.x) - w / 2;
    final top = kRnGround - r.y * kRnPxM - h;
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(px, top, w, h), const Radius.circular(4));
    canvas.drawRRect(body, Paint()..color = (r.dead ? Colors.grey : r.color).withOpacity(op));
    canvas.drawRect(Rect.fromLTWH(px + w - 8, top + 4, 4, 4), Paint()..color = Colors.white.withOpacity(op));
    canvas.drawRect(Rect.fromLTWH(px + w - 7, top + 5, 2, 2), Paint()..color = Colors.black.withOpacity(op));
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
