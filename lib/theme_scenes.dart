import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Fonds animés des thèmes « scène » (Synthwave, Galaxie, Pixel ciel, Salle
// d'arcade, Terminal, Océan, Donjon, Blocs, Aurore, Circuit).
// Tout est dessiné au pinceau, sans image : léger et net à toutes les tailles.
// ═══════════════════════════════════════════════════════════════════════════

class RcScene {
  static const synth = 1, space = 2, sky = 3, arcade = 4, terminal = 5, ocean = 6, dungeon = 7, blocks = 8, aurora = 9, circuit = 10;
}

class _Star {
  final double x, y, z, tw;
  const _Star(this.x, this.y, this.z, this.tw);
}

final List<_Star> _stars = () {
  final r = Random(42);
  return List.generate(140, (_) => _Star(r.nextDouble(), r.nextDouble(), r.nextDouble() * 0.9 + 0.1, r.nextDouble() * 6));
}();

double _mod(double a, double m) => ((a % m) + m) % m;

Paint _fill(Color c) => Paint()..color = c;

void _vGrad(Canvas c, Size s, List<Color> colors, [List<double>? stops]) {
  c.drawRect(Offset.zero & s, Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, s.height), colors, stops));
}

/// Dessine la scène [scene] à l'instant [t] (secondes).
void paintScene(Canvas c, Size s, double t, int scene) {
  switch (scene) {
    case RcScene.synth:
      _synth(c, s, t);
    case RcScene.space:
      _space(c, s, t);
    case RcScene.sky:
      _sky(c, s, t);
    case RcScene.arcade:
      _arcade(c, s, t);
    case RcScene.terminal:
      _terminal(c, s, t);
    case RcScene.ocean:
      _ocean(c, s, t);
    case RcScene.dungeon:
      _dungeon(c, s, t);
    case RcScene.blocks:
      _blocks(c, s, t);
    case RcScene.aurora:
      _aurora(c, s, t);
    case RcScene.circuit:
      _circuit(c, s, t);
  }
}

// ── Synthwave : soleil néon, montagnes, grille qui avance ──────────────────
void _synth(Canvas c, Size s, double t) {
  final w = s.width, h = s.height;
  _vGrad(c, s, const [Color(0xFF12002A), Color(0xFF4A0B5E), Color(0xFFFF5FA2), Color(0xFF1A0230), Color(0xFF07000F)], const [0, 0.45, 0.62, 0.63, 1]);
  for (final st in _stars.take(60)) {
    c.drawRect(Rect.fromLTWH(st.x * w, st.y * h * 0.5, 1.5, 1.5), _fill(Colors.white.withOpacity((0.3 + 0.4 * sin(t * 2 + st.tw)).clamp(0, 1))));
  }
  final hz = h * 0.62, sr = w * 0.32, sy = hz - sr * 0.15;
  c.drawArc(Rect.fromCircle(center: Offset(w / 2, sy), radius: sr), pi, pi, true,
      Paint()..shader = ui.Gradient.linear(Offset(0, sy - sr), Offset(0, sy), const [Color(0xFFFFE66B), Color(0xFFFF3D8B)]));
  for (var i = 0; i < 7; i++) {
    c.drawRect(Rect.fromLTWH(w / 2 - sr, sy - i * i * 2.2 - 4, sr * 2, 2 + i * 0.6), _fill(const Color(0xFF4A0B5E)));
  }
  const m = [[0.0, .78], [.12, .7], [.22, .76], [.32, .66], [.4, .75], [.5, .82], [.62, .7], [.72, .77], [.84, .64], [.94, .74], [1.0, .7]];
  final mp = Path()..moveTo(0, hz);
  for (final p in m) {
    mp.lineTo(p[0] * w, hz - (1 - p[1]) * h * 0.6);
  }
  mp
    ..lineTo(w, hz)
    ..close();
  c.drawPath(mp, _fill(const Color(0xFF1A0236)));
  final glow = Paint()
    ..color = const Color(0xFFFF4FD8)
    ..strokeWidth = 4
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
  final line = Paint()
    ..color = const Color(0xFFFF4FD8)
    ..strokeWidth = 1.5;
  for (var i = -12; i <= 12; i++) {
    final a = Offset(w / 2 + i * 8, hz), b = Offset(w / 2 + i * w * 0.22, h);
    c.drawLine(a, b, glow);
    c.drawLine(a, b, line);
  }
  for (var k = 0; k < 14; k++) {
    final p = _mod(k + t * 0.8, 14) / 14;
    final y = hz + (h - hz) * p * p;
    c.drawLine(Offset(0, y), Offset(w, y), line..color = const Color(0xFFFF4FD8).withOpacity(p));
  }
}

// ── Galaxie : étoiles en profondeur, planète à anneaux, étoiles filantes ────
void _space(Canvas c, Size s, double t) {
  final w = s.width, h = s.height;
  c.drawRect(Offset.zero & s,
      Paint()..shader = ui.Gradient.radial(Offset(w * 0.7, h * 0.3), h, const [Color(0xFF3A1D6E), Color(0xFF0D1440), Color(0xFF03040F)], const [0, 0.5, 1]));
  c.drawRect(Offset.zero & s,
      Paint()..shader = ui.Gradient.radial(Offset(w * 0.25, h * 0.7), w * 0.6, const [Color(0x593DD9FF), Color(0x003DD9FF)]));
  for (final st in _stars) {
    final y = _mod(st.y * h + t * 12 * st.z, h);
    final a = (0.3 + 0.7 * sin(t * 1.5 + st.tw).abs()) * st.z;
    final z = st.z * 2.4;
    c.drawRect(Rect.fromLTWH(st.x * w, y, z, z), _fill(Colors.white.withOpacity(a.clamp(0, 1))));
  }
  final px = w * 0.72, py = h * 0.28 + sin(t * 0.3) * 6, pr = w * 0.17;
  final ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 5
    ..color = const Color(0xB3FFDCA0);
  void ringHalf(double start) {
    c.save();
    c.translate(px, py);
    c.rotate(-0.35);
    c.drawArc(Rect.fromCenter(center: Offset.zero, width: pr * 3.4, height: pr * 0.9), start, pi, false, ring);
    c.restore();
  }

  ringHalf(pi);
  c.drawCircle(Offset(px, py), pr,
      Paint()..shader = ui.Gradient.linear(Offset(px - pr, py - pr), Offset(px + pr, py + pr), const [Color(0xFFFFB86B), Color(0xFFB0381E)]));
  c.drawCircle(Offset(px + pr * 0.35, py + pr * 0.3), pr * 0.85, _fill(const Color(0x40000000)));
  ringHalf(0);
  for (var i = 0; i < 2; i++) {
    final p = _mod(t * 0.35 + i * 0.5, 1.4);
    if (p >= 1) continue;
    final a = Offset(w * (1.1 - p * 1.3), h * (0.05 + p * 0.4 + i * 0.2));
    final b = a + const Offset(80, -30);
    c.drawLine(a, b, Paint()
      ..strokeWidth = 2
      ..shader = ui.Gradient.linear(a, b, const [Colors.white, Color(0x00FFFFFF)]));
  }
}

// ── Pixel ciel : nuages, collines, sol en briques, pièces ──────────────────
void _sky(Canvas c, Size s, double t) {
  final w = s.width, h = s.height;
  _vGrad(c, s, const [Color(0xFF3A8CFF), Color(0xFF9FD8FF)]);
  const P = 6.0;
  void cloud(double x, double y, double k) {
    final white = _fill(Colors.white);
    for (final r in const [[1, 0, 3], [0, 1, 5], [0, 2, 5]]) {
      c.drawRect(Rect.fromLTWH(x + r[0] * P * k, y + r[1] * P * k, r[2] * P * k, P * k), white);
    }
    c.drawRect(Rect.fromLTWH(x, y + 3 * P * k, 5 * P * k, P * k * 0.6), _fill(const Color(0xFFD6ECFF)));
  }

  for (var i = 0; i < 5; i++) {
    cloud(_mod(i * 170 - t * (10 + i * 3), w + 200) - 100, 40.0 + (i * 70) % 260, 1.6 - i * 0.15);
  }
  void hill(double base, double amp, Color col, double spd, double ph) {
    final p = Path()..moveTo(0, h);
    for (double x = 0; x <= w; x += P) {
      final y = base + (sin((x + t * spd) / 90 + ph) * amp / P).round() * P;
      p
        ..lineTo(x, y)
        ..lineTo(x + P, y);
    }
    p
      ..lineTo(w, h)
      ..close();
    c.drawPath(p, _fill(col));
  }

  hill(h * 0.68, 40, const Color(0xFF5FBF5F), 8, 0);
  hill(h * 0.78, 30, const Color(0xFF3E9B4F), 18, 2);
  final off = _mod(t * 30, 32);
  for (double x = -32; x < w + 32; x += 32) {
    final X = x - off;
    c.drawRect(Rect.fromLTWH(X, h - 56, 32, 56), _fill(const Color(0xFFC8692E)));
    c.drawRect(Rect.fromLTWH(X + 2, h - 54, 28, 10), _fill(const Color(0xFFE8954E)));
    final d = _fill(const Color(0xFF8A3F16));
    c.drawRect(Rect.fromLTWH(X, h - 42, 32, 2), d);
    c.drawRect(Rect.fromLTWH(X + 15, h - 42, 2, 14), d);
    c.drawRect(Rect.fromLTWH(X, h - 26, 32, 2), d);
  }
  c.drawRect(Rect.fromLTWH(0, h - 60, w, 6), _fill(const Color(0xFF5FBF5F)));
  for (var i = 0; i < 3; i++) {
    final x = _mod(i * 140 - t * 30, w + 60) - 30, y = h * 0.52 - i * 30 - sin(t * 3 + i).abs() * 10;
    c.drawRect(Rect.fromLTWH(x, y, 14, 18), _fill(const Color(0xFFFFD23B)));
    c.drawRect(Rect.fromLTWH(x + 3, y + 3, 3, 12), _fill(const Color(0xFFFFF7B0)));
  }
}

// ── Salle d'arcade : sol néon en perspective, bornes qui avancent ──────────
const _neon = [Color(0xFF3DD9FF), Color(0xFFFF8C1A), Color(0xFF7DFF3D), Color(0xFFFFD23B), Color(0xFFFF3D8B), Color(0xFF2A7BFF)];

void _arcade(Canvas c, Size s, double t) {
  final w = s.width, h = s.height;
  _vGrad(c, s, const [Color(0xFF050A2A), Color(0xFF0C1A5C), Color(0xFF050A2A)], const [0, 0.4, 1]);
  final vx = w / 2, vy = h * 0.32;
  c.drawRect(Offset.zero & s,
      Paint()..shader = ui.Gradient.radial(Offset(vx, vy), w * 0.6, const [Color(0xE6FFFFFF), Color(0x8078C8FF), Color(0x0078C8FF)], const [0, 0.15, 1]));
  for (var i = 0; i < 24; i++) {
    final a = -pi / 2 + i / 24 * pi * 2;
    c.drawLine(Offset(vx, vy), Offset(vx + cos(a) * h, vy + sin(a) * h), Paint()
      ..color = _neon[i % 6].withOpacity(0.18)
      ..strokeWidth = 3.0 + (i % 3) * 3);
  }
  for (var i = -5; i <= 5; i++) {
    if (i == 0) continue;
    final col = _neon[(i + 6) % 6];
    final a = Offset(vx + i * 6, vy + 20), b = Offset(vx + i * w * 0.2, h);
    c.drawLine(a, b, Paint()
      ..color = col
      ..strokeWidth = i.abs() * 2.2 + 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    c.drawLine(a, b, Paint()
      ..color = col
      ..strokeWidth = i.abs() * 2.2);
  }
  for (var k = 0; k < 10; k++) {
    final p = _mod(k + t * 0.9, 10) / 10;
    final y = vy + 20 + (h - vy - 20) * p * p;
    c.drawLine(Offset(vx - (y - vy) * 1.1, y), Offset(vx + (y - vy) * 1.1, y), Paint()
      ..color = const Color(0xFF3DD9FF).withOpacity(p * 0.8)
      ..strokeWidth = 1 + p * 3);
  }
  for (final side in const [-1, 1]) {
    for (var k = 0; k < 5; k++) {
      final p = _mod(k + t * 0.5, 5) / 5;
      final sc = 0.25 + p * 1.6;
      final x = vx + side * (30 + p * w * 0.55), y = vy + 10 + p * p * h * 0.35;
      final bw = 26 * sc, bh = 60 * sc;
      final o = min(1.0, p * 2);
      c.drawRect(Rect.fromLTWH(x - bw / 2, y - bh, bw, bh), _fill(const Color(0xFF141A3A).withOpacity(o)));
      c.drawRect(Rect.fromLTWH(x - bw * 0.38, y - bh * 0.85, bw * 0.76, bh * 0.32), _fill(_neon[k % 6].withOpacity(o)));
      c.drawRect(Rect.fromLTWH(x - bw / 2, y - bh, bw, bh), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _neon[(k + 2) % 6].withOpacity(o));
    }
  }
  for (final st in _stars.take(50)) {
    final y = _mod(st.y * h * 0.6 - t * 15 * st.z, h * 0.6);
    c.drawRect(Rect.fromLTWH(st.x * w, y, 3, 3), _fill(_neon[st.tw.floor() % 6].withOpacity(0.6)));
  }
}

// ── Terminal : pluie de caractères verts et balayage CRT ───────────────────
List<TextPainter>? _glyphs;
List<TextPainter> get _gl => _glyphs ??= [
      for (var i = 0; i < 48; i++)
        TextPainter(
          text: TextSpan(
              text: String.fromCharCode(0x30A0 + (i * 7) % 90),
              style: const TextStyle(color: Color(0xFF33FF66), fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];
TextPainter? _head;

void _terminal(Canvas c, Size s, double t) {
  final w = s.width, h = s.height;
  const bg = Color(0xFF010D05);
  c.drawRect(Offset.zero & s, _fill(bg));
  _head ??= TextPainter(
    text: const TextSpan(text: 'ア', style: TextStyle(color: Color(0xFFD8FFE0), fontSize: 14, fontWeight: FontWeight.bold)),
    textDirection: TextDirection.ltr,
  )..layout();
  const cw = 14.0, lh = 16.0;
  final cols = (w / cw).ceil();
  final g = _gl;
  for (var i = 0; i < cols; i++) {
    final sp = 40 + (i * 37) % 60, len = 8 + (i * 13) % 14;
    final head = _mod(t * sp + i * 97, h + len * lh);
    for (var j = 1; j < len; j++) {
      final y = head - j * lh;
      if (y < -lh || y > h) continue;
      g[(i * 7 + j * 13 + (t * 8).floor()) % g.length].paint(c, Offset(i * cw, y - 14));
    }
    // la traînée s'efface vers le haut
    final top = head - len * lh;
    c.drawRect(Rect.fromLTWH(i * cw, top, cw, len * lh), Paint()..shader = ui.Gradient.linear(Offset(0, top), Offset(0, head), [bg, bg.withOpacity(0)]));
    if (head < h) _head!.paint(c, Offset(i * cw, head - 14));
  }
  final scan = _fill(const Color(0x40000000));
  for (double y = 0; y < h; y += 3) {
    c.drawRect(Rect.fromLTWH(0, y, w, 1), scan);
  }
  final by = _mod(t * 120, h + 80) - 40;
  c.drawRect(Rect.fromLTWH(0, by - 40, w, 80),
      Paint()..shader = ui.Gradient.linear(Offset(0, by - 40), Offset(0, by + 40), const [Color(0x0033FF66), Color(0x1F33FF66), Color(0x0033FF66)], const [0, 0.5, 1]));
}

// ── Océan : rayons, poissons pixel, bulles, algues ─────────────────────────
void _ocean(Canvas c, Size s, double t) {
  final w = s.width, h = s.height;
  _vGrad(c, s, const [Color(0xFF1AA0D8), Color(0xFF0B4F8A), Color(0xFF041A3A)], const [0, 0.5, 1]);
  for (var i = 0; i < 6; i++) {
    final x = w * (i / 6) + sin(t * 0.4 + i) * 30;
    c.drawPath(Path()
      ..moveTo(x, 0)
      ..lineTo(x + 40, 0)
      ..lineTo(x + 140, h)
      ..lineTo(x + 60, h)
      ..close(), _fill(const Color(0x12FFFFFF)));
  }
  const fishCols = [Color(0xFFFFB347), Color(0xFFFF6B9A), Color(0xFFFFD23B), Color(0xFF7DFFB0)];
  for (var i = 0; i < 7; i++) {
    final dir = i.isOdd ? 1.0 : -1.0, sp = 15.0 + i * 6;
    final x = dir > 0 ? _mod(t * sp + i * 90, w + 80) - 40 : w - _mod(t * sp + i * 90, w + 80) + 40;
    final y = h * (0.15 + i * 0.11) + sin(t * 2 + i) * 6;
    final P = 3 * (1 + (i % 3) * 0.4);
    final f = _fill(fishCols[i % 4]);
    for (final r in const [[1, 0, 3], [0, 1, 5], [1, 2, 3]]) {
      c.drawRect(Rect.fromLTRB(min(x + dir * r[0] * P, x + dir * (r[0] + r[2]) * P), y + r[1] * P, max(x + dir * r[0] * P, x + dir * (r[0] + r[2]) * P), y + (r[1] + 1) * P), f);
    }
    c.drawRect(Rect.fromLTRB(min(x + dir * 5 * P, x + dir * 6 * P), y, max(x + dir * 5 * P, x + dir * 6 * P), y + 3 * P), f);
    c.drawRect(Rect.fromLTWH(x + dir * 1.2 * P - (dir < 0 ? P * 0.8 : 0), y + P, P * 0.8, P * 0.8), _fill(Colors.white));
  }
  final bub = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = const Color(0x99DCF5FF);
  for (final st in _stars.take(40)) {
    final y = h - _mod(t * 25 * st.z + st.y * h, h);
    c.drawCircle(Offset(st.x * w + sin(t * 2 + st.tw) * 4, y), 1 + st.z * 3, bub);
  }
  for (var i = 0; i < 14; i++) {
    final x = i * w / 13;
    final p = Path()..moveTo(x, h);
    for (var k = 1; k <= 6; k++) {
      p.lineTo(x + sin(t * 1.5 + i + k * 0.6) * 8, h - k * 14 - (i % 3) * 10);
    }
    c.drawPath(p, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeJoin = StrokeJoin.round
      ..color = i.isOdd ? const Color(0xFF2E9B4F) : const Color(0xFF1F7A3A));
  }
  c.drawRect(Rect.fromLTWH(0, h - 10, w, 10), _fill(const Color(0xFFC9A86A)));
}

// ── Donjon : mur de pierre, torches, braises ───────────────────────────────
void _dungeon(Canvas c, Size s, double t) {
  final w = s.width, h = s.height;
  c.drawRect(Offset.zero & s, _fill(const Color(0xFF1A1214)));
  final a = _fill(const Color(0xFF2A1E22)), b = _fill(const Color(0xFF33252A));
  for (double y = 0; y < h; y += 24) {
    final row = (y / 24).round();
    for (double x = -(row % 2) * 24.0; x < w; x += 48) {
      c.drawRect(Rect.fromLTWH(x + 1, y + 1, 46, 22), ((x * 7 + y * 3).round() % 5) != 0 ? a : b);
    }
  }
  for (final tp in [Offset(w * 0.12, h * 0.3), Offset(w * 0.88, h * 0.3), Offset(w * 0.12, h * 0.75), Offset(w * 0.88, h * 0.75)]) {
    final fl = 0.8 + 0.2 * sin(t * 13 + tp.dx) + 0.1 * sin(t * 31);
    c.drawCircle(tp.translate(0, -10), 130 * fl,
        Paint()..shader = ui.Gradient.radial(tp.translate(0, -10), 130 * fl, const [Color(0x8CFFAA3C), Color(0x00FF781E)]));
    c.drawRect(Rect.fromLTWH(tp.dx - 3, tp.dy, 6, 22), _fill(const Color(0xFF5A3A1E)));
    c.drawOval(Rect.fromCenter(center: tp.translate(0, -6), width: 12 * fl, height: 24 * fl), _fill(const Color(0xFFFFB347)));
    c.drawOval(Rect.fromCenter(center: tp.translate(0, -3), width: 6, height: 12 * fl), _fill(const Color(0xFFFFF3B0)));
  }
  for (final st in _stars.take(50)) {
    final y = h - _mod(t * 30 * st.z + st.y * h, h);
    final z = 2 + st.z * 2;
    c.drawRect(Rect.fromLTWH(st.x * w + sin(t + st.tw) * 10, y, z, z),
        _fill(Color.fromARGB(((0.8 - (h - y) / h * 0.7).clamp(0.0, 1.0) * 255).round(), 255, (120 + st.z * 100).round(), 40)));
  }
}

// ── Blocs : pièces de puzzle qui tombent et s'empilent ─────────────────────
const _blockCols = [Color(0xFFFF4F4F), Color(0xFFFFB347), Color(0xFFFFE14F), Color(0xFF4FFF7A), Color(0xFF3DD9FF), Color(0xFF4F6BFF), Color(0xFFC84FFF)];
const _shapes = [
  [[0, 0], [1, 0], [2, 0], [3, 0]],
  [[0, 0], [1, 0], [0, 1], [1, 1]],
  [[0, 0], [1, 0], [2, 0], [1, 1]],
  [[0, 0], [0, 1], [1, 1], [2, 1]],
  [[1, 0], [2, 0], [0, 1], [1, 1]],
];

void _blocks(Canvas c, Size s, double t) {
  final w = s.width, h = s.height;
  const S = 22.0;
  c.drawRect(Offset.zero & s, _fill(const Color(0xFF0B0B24)));
  final grid = Paint()..color = const Color(0x0AFFFFFF);
  for (double x = 0; x < w; x += S) {
    c.drawLine(Offset(x, 0), Offset(x, h), grid);
  }
  final hi = _fill(const Color(0x59FFFFFF)), lo = _fill(const Color(0x40000000));
  void cell(double x, double y, Color col) {
    c.drawRect(Rect.fromLTWH(x + 1, y + 1, S - 2, S - 2), _fill(col));
    c.drawRect(Rect.fromLTWH(x + 1, y + 1, S - 2, 4), hi);
    c.drawRect(Rect.fromLTWH(x + 1, y + S - 5, S - 2, 4), lo);
  }

  final cols = (w / S).ceil();
  for (var i = 0; i < cols; i++) {
    final hh = 2 + (i * 7) % 4;
    for (var j = 0; j < hh; j++) {
      cell(i * S, h - (j + 1) * S, _blockCols[(i + j * 3) % 7]);
    }
  }
  for (var k = 0; k < 6; k++) {
    final sp = 40.0 + k * 12;
    final y = _mod(t * sp + k * 170, h + 80) - 80;
    final x = ((k * 5 + 3) % max(1, cols - 3)) * S;
    for (final p in _shapes[k % 5]) {
      cell(x + p[0] * S, (y / S).floor() * S + p[1] * S, _blockCols[k % 7]);
    }
  }
}

// ── Aurore : aurore boréale, sapins, neige ─────────────────────────────────
void _aurora(Canvas c, Size s, double t) {
  final w = s.width, h = s.height;
  _vGrad(c, s, const [Color(0xFF020617), Color(0xFF0D2A4A)]);
  for (final st in _stars.take(70)) {
    c.drawRect(Rect.fromLTWH(st.x * w, st.y * h * 0.6, 1.5, 1.5), _fill(Colors.white.withOpacity(0.3 + 0.5 * sin(t + st.tw).abs())));
  }
  const bands = [Color(0x597DFFB0), Color(0x403DD9FF), Color(0x38C878FF)];
  for (var b = 0; b < 3; b++) {
    double yAt(double x) => h * (0.2 + b * 0.08) + sin(x / 70 + t * 0.7 + b) * 30 + sin(x / 31 + t * 1.3) * 10;
    final p = Path()..moveTo(0, yAt(0));
    for (double x = 8; x <= w; x += 8) {
      p.lineTo(x, yAt(x));
    }
    for (double x = w; x >= 0; x -= 8) {
      p.lineTo(x, yAt(x) + 90);
    }
    p.close();
    c.drawPath(p, Paint()..shader = ui.Gradient.linear(Offset(0, h * 0.1), Offset(0, h * 0.5), [bands[b].withOpacity(0), bands[b], const Color(0x00000000)], const [0, 0.5, 1]));
  }
  final snow = Path()..moveTo(0, h);
  for (double x = 0; x <= w; x += 10) {
    snow.lineTo(x, h * 0.86 + sin(x / 60) * 10);
  }
  snow
    ..lineTo(w, h)
    ..close();
  c.drawPath(snow, _fill(const Color(0xFFE8F4FF)));
  for (var i = 0; i < 9; i++) {
    final x = i * w / 8 + (i * 37) % 20, y = h * 0.88, sz = 30.0 + (i * 13) % 30;
    c.drawPath(Path()
      ..moveTo(x, y - sz * 1.6)
      ..lineTo(x + sz * 0.5, y)
      ..lineTo(x - sz * 0.5, y)
      ..close(), _fill(const Color(0xFF0A2A2A)));
  }
  final flake = _fill(const Color(0xCCFFFFFF));
  for (final st in _stars) {
    c.drawCircle(Offset(st.x * w + sin(t + st.tw) * 8, _mod(st.y * h + t * 30 * st.z, h)), st.z * 2.2, flake);
  }
}

// ── Circuit : pistes lumineuses parcourues par des signaux ─────────────────
void _circuit(Canvas c, Size s, double t) {
  final w = s.width, h = s.height;
  const S = 36.0;
  c.drawRect(Offset.zero & s, _fill(const Color(0xFF04201A)));
  int rr(int a, int b) => ((a * 73856093) ^ (b * 19349663)) & 0x7fffffff;
  final paths = <List<double>>[];
  for (var gy = 0; gy < h / S; gy++) {
    for (var gx = 0; gx < w / S; gx++) {
      final hv = rr(gx, gy);
      if (hv % 3 != 0) continue;
      final x = gx * S, y = gy * S;
      final dx = (hv >> 3) % 2 == 1 ? S * 2 : 0.0;
      final dy = dx != 0 ? ((hv >> 5) % 2 == 1 ? S : -S) : S * 2;
      paths.add([x, y, x + dx, y, x + dx, y + dy]);
    }
  }
  final track = Paint()
    ..color = const Color(0xFF0D5A46)
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  final pad = _fill(const Color(0xFF1D8A6A));
  for (final p in paths) {
    c.drawPath(Path()
      ..moveTo(p[0], p[1])
      ..lineTo(p[2], p[3])
      ..lineTo(p[4], p[5]), track);
    c.drawCircle(Offset(p[0], p[1]), 4, pad);
    c.drawCircle(Offset(p[4], p[5]), 4, pad);
  }
  final glow = Paint()
    ..color = const Color(0xFF3DFFD0)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
  final dot = _fill(const Color(0xFFBFFFEF));
  for (var i = 0; i < paths.length; i++) {
    final p = paths[i];
    final k = _mod(t * 0.6 + i * 0.137, 1.6);
    if (k > 1) continue;
    final l1 = (Offset(p[2], p[3]) - Offset(p[0], p[1])).distance, l2 = (Offset(p[4], p[5]) - Offset(p[2], p[3])).distance;
    var d = k * (l1 + l2);
    Offset o;
    if (d < l1) {
      o = Offset(p[0] + (p[2] - p[0]) * d / l1, p[1] + (p[3] - p[1]) * d / l1);
    } else {
      d -= l1;
      o = Offset(p[2] + (p[4] - p[2]) * d / l2, p[3] + (p[5] - p[3]) * d / l2);
    }
    c.drawCircle(o, 6, glow);
    c.drawCircle(o, 3, dot);
  }
  final chip = _fill(const Color(0xFF111111)), pin = _fill(const Color(0xFFCCCCCC));
  for (var i = 0; i < 4; i++) {
    final x = w * (0.15 + i * 0.22), y = h * (0.25 + (i % 2) * 0.4);
    c.drawRect(Rect.fromLTWH(x - 22, y - 14, 44, 28), chip);
    for (var k = 0; k < 5; k++) {
      c.drawRect(Rect.fromLTWH(x - 20 + k * 9, y - 18, 4, 4), pin);
      c.drawRect(Rect.fromLTWH(x - 20 + k * 9, y + 14, 4, 4), pin);
    }
  }
}
