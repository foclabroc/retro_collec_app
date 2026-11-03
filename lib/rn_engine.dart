import 'dart:math';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'retro_theme.dart' show pixelStyle;

import 'rj_engine.dart' show RjRng;

// ═══════════════════════════════════════════════════════════════════════════
// Course de jaquettes (30/10) : runner en mètres, pas fixe 1/120 s (même suite chez tous les joueurs).
//  · Obstacles tirés de la graine du serveur (RjRng, même suite VM / JS / Wasm) : mêmes pour les deux joueurs.
//  · Vitesse v(t) = 10 + 0,1 t jusqu'à 22 m/s (2 min), puis +0,02 m/s par s jusqu'à 36, sans limite de temps (fin à la chute). Le serveur plafonne à 100 + 40 m/s
//    (sql/2026-10-30_course_sans_limite.sql : garder synchronisé).
//  · Toucher en haut = saut, en bas (ou ↓ / S) = glisse ; ↑ / Espace / W = saut.
//  · 1.0.43 : appui gardé 0,15 s (saut au prochain contact du sol), glisse tant que `hold`, ↓ en l'air = plongeon.
//    Rendu « Rayon de jeux » (magasin de jeux de nuit), héros cartouche, zoom 34 → 24 px/m selon la vitesse.
// ═══════════════════════════════════════════════════════════════════════════

const kRnW = 360.0, kRnH = 480.0;
const kRnDuration = 3600; // garde-fou : la course n'a plus de limite de temps
const kRnStep = 1 / 120;
const kRnPxM = 20.0; // pixels par mètre
const kRnHeroX = 80.0; // position du coureur à l'écran
const kRnGround = 380.0;
const _gravity = 30.0, _jumpV = 9.5, _slideT = 0.5;
const _heroHalf = 0.3, _heroH = 1.2, _slideH = 0.6;
const _obsW = 1.2, _gndH = 0.9, _airLow = 0.8, _airHigh = 1.6;
const kRnRed = Color(0xFFE02020), kRnBlue = Color(0xFF2F8CFF);

// +0,1 m/s par seconde jusqu'à 22 m/s (2 min, 1 920 m), puis +0,02 m/s par seconde jusqu'à 36 m/s
double rnSpeed(double t) {
  t = max(t, 0);
  return t <= 120 ? 10 + 0.1 * t : min(22 + 0.02 * (t - 120), 36.0);
}

// vitesse à une distance donnée (v² = v0² + 2·a·d, même courbe que rnSpeed)
double _rnSpeedAt(double d) => d <= 1920 ? sqrt(100 + 0.2 * d) : min(sqrt(484 + 0.04 * (d - 1920)), 36.0);

class RnObs {
  final double x;
  final bool air; // barre en l'air : il faut glisser dessous
  double? mc; // marge la plus petite au passage (frôlement)
  bool done = false;
  RnObs(this.x, this.air);
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
      final v = _rnSpeedAt(_next);
      _next += _obsW + 2 + v * (0.95 + _r.nextDouble() * 0.8);
    }
  }
}

class RnHero {
  final RnWorld world;
  RnHero(this.world);
  double x = 0, y = 0, vy = 0, slide = 0;
  bool dead = false, jumpReq = false, slideReq = false;
  bool hold = false; // glisse tenue (doigt / touche ↓ restés appuyés)
  double _jb = 0, _sb = 0; // appuis gardés 0,15 s
  final RnFx fx = RnFx();
  void Function(String sfx)? onSfx;

  int get score => x.floor();
  bool get sliding => slide > 0 && y == 0;

  void step(double dt, double t) {
    if (dead) return;
    x += rnSpeed(t) * dt;
    world.generateUntil(x + 40);
    if (jumpReq) _jb = 0.15;
    if (slideReq) _sb = 0.15;
    jumpReq = false;
    slideReq = false;
    final onGround = y == 0 && vy <= 0;
    if (_jb > 0 && onGround) {
      vy = _jumpV;
      slide = 0;
      _jb = 0;
      onSfx?.call('jump');
      fx.puff(x, 6);
    } else if ((_sb > 0 || hold) && onGround) {
      if (slide <= 0) fx.puff(x, 5);
      slide = max(slide, hold ? 0.12 : _slideT);
      _sb = 0;
    } else if ((_sb > 0 || hold) && y > 0) {
      vy -= 160 * dt; // plonge vite si on appuie en l'air
    }
    _jb -= dt;
    _sb -= dt;
    if (slide > 0) slide -= dt;
    if (y > 0 || vy > 0) {
      vy -= _gravity * dt;
      y += vy * dt;
      if (y <= 0) {
        y = 0;
        vy = 0;
        fx.land(x);
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
        fx.burst(o);
        return;
      }
      final c = o.air ? _airLow - (y + h) : y - _gndH;
      if (o.mc == null || c < o.mc!) o.mc = c;
    }
    for (final o in world.obs) {
      if (o.x + _obsW >= x - _heroHalf) break;
      if (o.mc != null && !o.done) {
        o.done = true;
        if (o.mc! < 0.22) fx.near(o);
      }
    }
  }
}

// ── effets du coureur local (poussière, débris, frôlements, traînée, paliers) : décor seulement ──
class _Part {
  double x, y, vx, vy, life;
  final Color c;
  final double s;
  final bool g;
  _Part(this.x, this.y, this.vx, this.vy, this.life, this.c, this.s, this.g);
}

class _Pop {
  final double x;
  double y, life;
  final String txt;
  _Pop(this.x, this.y, this.life, this.txt);
}

class RnFx {
  static final _rnd = Random();
  final List<_Part> parts = [];
  final List<_Pop> pops = [];
  final List<(double, double)> trail = [];
  double sq = 0, mileFx = 0, _last = -1, _tk = 0;
  int mile = 0;

  void puff(double x, int n) {
    for (var i = 0; i < n; i++) {
      parts.add(_Part(x - 0.2, 0.05, -(_rnd.nextDouble() * 3 + 1), _rnd.nextDouble() * 2, 0.4, const Color(0xFFD9D2F5), 2, false));
    }
  }

  void land(double x) {
    puff(x, 10);
    sq = 0.12;
  }

  void burst(RnObs o) {
    for (var i = 0; i < 18; i++) {
      parts.add(_Part(o.x + _obsW / 2, o.air ? 1.2 : 0.5, (_rnd.nextDouble() - 0.3) * 8, _rnd.nextDouble() * 7, 0.9, _kCovers[i % 8], 3, true));
    }
  }

  void near(RnObs o) {
    const t = ['OUF !', 'PILE !', 'TOUT JUSTE !'];
    pops.add(_Pop(o.x + _obsW / 2, o.air ? 2.3 : 1.6, 0.8, t[_rnd.nextInt(3)]));
  }

  /// Avance les effets à l'heure du dessin (continue après la chute)
  void advance(double now, double hx, double hy, double v, bool dead) {
    final dt = _last < 0 ? 0.0 : (now - _last).clamp(0.0, 0.1);
    _last = now;
    for (final p in parts) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      if (p.g) p.vy -= 20 * dt;
      p.life -= dt;
    }
    parts.removeWhere((p) => p.life <= 0);
    for (final p in pops) {
      p.life -= dt;
      p.y += dt * 1.2;
    }
    pops.removeWhere((p) => p.life <= 0);
    sq = max(0, sq - dt);
    mileFx = max(0, mileFx - dt);
    if (dead) {
      trail.clear();
      return;
    }
    if (hy == 0 && _rnd.nextDouble() < 0.25 * dt * 60) parts.add(_Part(hx - 0.25, 0.02, -2, 0.5, 0.25, const Color(0x66FFFFFF), 2, false));
    _tk += dt;
    if (v > 17 && _tk >= 1 / 30) {
      _tk = 0;
      trail.add((hx, hy));
    }
    if (trail.length > 5 || (v <= 17 && trail.isNotEmpty)) trail.removeAt(0);
    final m = (hx / 100).floor();
    if (m > mile) {
      mile = m;
      mileFx = 1.2;
    }
  }
}

/// Un coureur à dessiner (moi, fantôme ou joueur regardé) ; x en mètres, y = hauteur en mètres
class RnRunner {
  final double x, y;
  final bool sliding, dead, ghost;
  final Color color;
  final String? label;
  final RnFx? fx; // effets du coureur local
  const RnRunner(this.x, this.y, this.color, {this.sliding = false, this.dead = false, this.ghost = false, this.label, this.fx});
}

// ═══════════════════════════════════════════════════════════════════════════
// Rendu « Rayon de jeux » (1.0.43, maquette validée le 3/11) : magasin de jeux rétro de nuit,
// étagères en parallaxe (images mises en cache par segment), néons, sol ciré avec reflets,
// héros cartouche en pixel art (images en cache par pose et couleur), zoom selon la vitesse.
// ═══════════════════════════════════════════════════════════════════════════

const _kCovers = [
  Color(0xFFE8262A), Color(0xFF2F6BFF), Color(0xFF19C46A), Color(0xFFFFB321),
  Color(0xFFA23DFF), Color(0xFFFF4FA3), Color(0xFF22C7D6), Color(0xFFF2F2F2),
];
const _kBands = [Color(0xFF111111), Color(0xFFFFFFFF), Color(0xFFD01818), Color(0xFF1B49C9), Color(0xFF222222)];
const _kGold = Color(0xFFFFC23D);

// hachage décoratif (rendu seulement, pas besoin d'être identique d'une plateforme à l'autre)
double _h(int n) {
  var x = (n * 374761393 + 668265263) & 0x7fffffff;
  x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff;
  return (x ^ (x >> 16)) / 0x7fffffff;
}

// zoom : 34 px/m au départ, 24 px/m dès 24 m/s (on voit venir les obstacles quand ça accélère)
double _zoomFor(double v) => 34 - 10 * ((v - 10) / 14).clamp(0.0, 1.0);
const _heroX = 56.0;

// ── héros cartouche (14 colonnes) ──
const _kHead = ['..kkkkkkkkkk..', '.kggggggggggk.', '.kgLLLLLLLLgk.', '.kgLwwLLwwLgk.', '.kgLwkLLwkLgk.', '.kgLLLLLLLLgk.', '.kgLLLmmLLLgk.'];
const _kArms = ['skgLLLLLLLLgk.', '.kgLLLLLLLLgks'];
const _kBody = ['.kggggggggggk.', '.kgGgGgGgGggk.', '.kggggggggggk.', '..kGGGGGGGGk..', '...kyykyyk....'];
const _kLegs = [
  ['..kbbk..kbbk..', '.kbbk....kbbk.', '.kbk......kbk.', 'kOOk......kOOk'],
  ['...kbbkkbbk...', '....kbbbbk....', '....kbkkbk....', '...kOOkOOk....'],
  ['..kbbk.kbbk...', '..kbk...kbk...', '.kbk.....kbk..', 'kOOk.....kOOk.'],
  ['...kbbkkbbk...', '....kbbbbk....', '....kbkkbk....', '...kOOkOOk....'],
];
const _kJump = ['..kbbbbbbk....', '...kbbk.kbbk..', '..kOOk..kOOk..', '..............'];
const _kRows = 7 + 1 + 5 + 4; // 17 lignes

class _Cache {
  static final Map<String, ui.Picture> hero = {};
  static final Map<int, ui.Picture> far = {}, near = {};
  static final Map<String, TextPainter> text = {};
  static ui.Picture? scan;

  static ui.Picture record(void Function(Canvas c) draw) {
    final rec = ui.PictureRecorder();
    draw(Canvas(rec));
    return rec.endRecording();
  }

  static ui.Picture seg(Map<int, ui.Picture> m, int i, void Function(Canvas c) draw) {
    final p = m[i];
    if (p != null) return p;
    if (m.length > 24) m.remove(m.keys.first);
    return m[i] = record(draw);
  }

  static TextPainter label(String s, double size, Color c, {bool pixel = true}) {
    final k = '$s|$size|${c.value}|$pixel';
    final t = text[k];
    if (t != null) return t;
    if (text.length > 80) text.remove(text.keys.first);
    final style = pixel
        ? pixelStyle(size: size, color: c, shadow: false).copyWith(shadows: const [Shadow(color: Colors.black, offset: Offset(2, 2))])
        : TextStyle(color: c, fontSize: size, fontWeight: FontWeight.w800, shadows: const [Shadow(color: Colors.black, blurRadius: 3)]);
    return text[k] = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout(maxWidth: 260);
  }
}

class RnPainter extends CustomPainter {
  final RnWorld world;
  final double camX; // mètre affiché sous le coureur
  final List<RnRunner> runners;
  final List<(double, String, Color)> lines; // repères (mètres, texte, couleur)
  RnPainter({required this.world, required this.camX, required this.runners, this.lines = const []});

  static final Stopwatch _clock = Stopwatch()..start();
  static final Paint _p = Paint();
  late double _pxm, _now;

  double _sx(double m) => _heroX + (m - camX) * _pxm;

  static void _r(Canvas c, double x, double y, double w, double h, Color col) {
    _p
      ..color = col
      ..shader = null
      ..maskFilter = null
      ..style = PaintingStyle.fill;
    c.drawRect(Rect.fromLTWH(x, y, w, h), _p);
  }

  // jaquette en pixels : bandeau, illustration, petites formes
  static void _jaq(Canvas c, double x, double y, double w, double h, int seed) {
    final col = _kCovers[(_h(seed) * 8).floor() % 8], band = _kBands[(_h(seed + 7) * 5).floor() % 5];
    _r(c, x - 1, y - 1, w + 2, h + 2, const Color(0xFF0A0610));
    _r(c, x, y, w, h, col);
    _r(c, x, y, w, max(3, h * 0.18), band);
    final iy = y + h * 0.26, ih = h * 0.56;
    _r(c, x + 2, iy, w - 4, ih / 2, const Color(0x33FFFFFF));
    _r(c, x + 2, iy + ih / 2, w - 4, ih / 2, const Color(0x33000000));
    final n = 3 + (_h(seed + 3) * 3).floor();
    for (var i = 0; i < n; i++) {
      _r(c, x + 2 + _h(seed + i * 11) * max(0, w - 8), iy + _h(seed + i * 13) * max(0, ih - 4), 3 + _h(seed + i) * 4, 3 + _h(seed + i * 5) * 4,
          _kCovers[(_h(seed + i * 17) * 8).floor() % 8]);
    }
    _r(c, x + 2, y + h - 4, w * 0.5, 2, const Color(0xAAFFFFFF));
  }

  // parallaxe : segments de taille fixe ; les plans du fond défilent à 24 px/m × facteur
  void _seg(double factor, double size, void Function(int i, double x) fn) {
    final c = camX * (factor >= 1 ? _pxm : 24) * factor;
    final i0 = (c / size).floor();
    for (var i = i0; i <= i0 + (kRnW / size).ceil() + 1; i++) {
      fn(i, i * size - c);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    _now = _clock.elapsedMicroseconds / 1e6;
    final v = _rnSpeedAt(max(camX, 0));
    _pxm = _zoomFor(v);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / kRnW, size.height / kRnH);
    final me = runners.where((r) => r.fx != null).firstOrNull;
    me?.fx!.advance(_now, me.x, me.y, v, me.dead);
    _back(canvas);
    _floor(canvas);
    world.generateUntil(camX + 20);
    // reflet sur le sol ciré
    canvas.saveLayer(const Rect.fromLTWH(0, kRnGround + 6, kRnW, kRnH - kRnGround), Paint()..color = const Color(0x29000000));
    canvas.translate(0, 2 * kRnGround + 6);
    canvas.scale(1, -1);
    _objects(canvas, labels: false);
    canvas.restore();
    const fade = Rect.fromLTWH(0, kRnGround + 6, kRnW, kRnH - kRnGround);
    canvas.drawRect(fade, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x000D0A18), Color(0xEE0D0A18)]).createShader(fade));
    _recordLines(canvas);
    if (me != null) _trail(canvas, me);
    _objects(canvas, labels: true, fx: me?.fx);
    _front(canvas);
    if (me != null) _alert(canvas, me, v);
    if (me?.fx != null) _pops(canvas, me!.fx!);
    if (v > 15 && me != null && !me.dead) {
      for (var i = 0; i < 6; i++) {
        final k = (_now * 20).floor();
        _r(canvas, _h(i * 7 + k) * kRnW, 80 + _h(i + k) * 280, 30 + v, 1, Color.fromRGBO(255, 255, 255, min(0.5, (v - 15) / 20)));
      }
    }
    // assombrissement des bords + lignes d'écran
    const all = Rect.fromLTWH(0, 0, kRnW, kRnH);
    canvas.drawRect(all, Paint()..shader = ui.Gradient.radial(const Offset(kRnW / 2, kRnH * 0.45), kRnH * 0.8, const [Color(0x00000000), Color(0x00000000), Color(0xAA000000)], const [0, 0.37, 1]));
    canvas.drawPicture(_Cache.scan ??= _Cache.record((c) {
      final pp = Paint()..color = const Color(0x12000000);
      for (var y = 0.0; y < kRnH; y += 3) {
        c.drawRect(Rect.fromLTWH(0, y, kRnW, 1), pp);
      }
    }));
    canvas.restore();
  }

  // ── fond : mur, néons du plafond, étagères, enseignes ──
  void _back(Canvas c) {
    const sky = Rect.fromLTWH(0, 0, kRnW, kRnGround);
    c.drawRect(sky, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF120C26), Color(0xFF2A1C4F)]).createShader(sky));
    _seg(0.15, 240, (i, x) {
      final on = _h(i * 31 + (_now * 8).floor()) >= 0.04;
      c.drawRect(Rect.fromLTWH(x + 40, 12, 120, 8), Paint()
        ..color = Color.fromRGBO(201, 242, 255, on ? 0.5 : 0.1)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      _r(c, x + 40, 14, 120, 4, on ? const Color(0xFFE9FBFF) : const Color(0x55E9FBFF));
      _r(c, x + 40, 18, 120, 2, const Color(0xFF5A6B8A));
    });
    _seg(0.25, 180, (i, x) {
      c.save();
      c.translate(x, 0);
      c.drawPicture(_Cache.seg(_Cache.far, i, (cc) {
        for (var r = 0; r < 3; r++) {
          final y = 70.0 + r * 62;
          _r(cc, 0, y + 44, 180, 5, const Color(0xFF3B2A1C));
          for (var k = 0; k < 14; k++) {
            final hh = 26 + _h(i * 97 + r * 13 + k) * 14;
            _jaq(cc, 4 + k * 12.6, y + 44 - hh, 10, hh, i * 997 + r * 61 + k);
          }
        }
        _r(cc, 0, 60, 6, 260, const Color(0xFF24183F));
        _r(cc, 0, 60, 180, 260, const Color(0x73120C26)); // plan lointain voilé
      }));
      c.restore();
    });
    _seg(0.35, 420, (i, x) {
      const txts = ['RETRO', 'PROMO', 'NEW', 'TOP 10'];
      const cols = [Color(0xFFFF3BA7), Color(0xFF3DFFD8), _kGold, Color(0xFF8A7BFF)];
      final col = cols[(_h(i * 9) * 4).floor() % 4];
      final on = _h(i * 3 + (_now * 6).floor()) > 0.05;
      final r = Rect.fromLTWH(x + 120, 36, 110, 30);
      if (on) {
        c.drawRect(r, Paint()
          ..color = col.withOpacity(0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
      }
      c.drawRect(r, Paint()
        ..color = col.withOpacity(on ? 1 : 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
      final tp = _Cache.label(txts[(_h(i * 7) * 4).floor() % 4], 12, col.withOpacity(on ? 1 : 0.35));
      tp.paint(c, Offset(x + 175 - tp.width / 2, 51 - tp.height / 2));
    });
    _seg(0.6, 260, (i, x) {
      c.save();
      c.translate(x, 0);
      c.drawPicture(_Cache.seg(_Cache.near, i, (cc) {
        _r(cc, 0, 286, 260, 8, const Color(0xFF5B3A22));
        _r(cc, 0, 294, 260, 3, const Color(0xFF2B1A0E));
        for (var k = 0; k < 12; k++) {
          final hh = 40 + _h(i * 53 + k) * 22;
          _jaq(cc, 6 + k * 21, 286 - hh, 18, hh, i * 3001 + k);
        }
        _r(cc, 252, 210, 8, kRnGround - 210, const Color(0xFF3B2716));
      }));
      c.restore();
    });
    // décor assombri : le jeu ressort
    c.drawRect(sky, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x400D0A18), Color(0x800D0A18)]).createShader(sky));
  }

  // ── sol : carrelage en damier qui défile avec le coureur, liseré doré ──
  void _floor(Canvas c) {
    _r(c, 0, kRnGround, kRnW, kRnH - kRnGround, const Color(0xFF1D1436));
    _seg(1, 40, (i, x) {
      for (var r = 0; r < 4; r++) {
        if ((i + r).isEven) _r(c, x + r * 4, kRnGround + 6 + r * 24, 40, 24, const Color(0xFF2A1F4D));
      }
    });
    _r(c, 0, kRnGround, kRnW, 6, _kGold);
    _r(c, 0, kRnGround + 6, kRnW, 2, const Color(0xFF7A5A12));
  }

  // ── obstacles + coureurs (aussi dessinés en reflet) ──
  void _objects(Canvas c, {required bool labels, RnFx? fx}) {
    for (final o in world.obs) {
      final px = _sx(o.x);
      if (px > kRnW + 30) break;
      if (px < -40) continue;
      o.air ? _sign(c, o, px) : _stack(c, o, px);
    }
    if (fx != null) {
      for (final p in fx.parts) {
        _r(c, _sx(p.x), kRnGround - p.y * _pxm, p.s, p.s, p.c);
      }
    }
    for (final r in runners.where((r) => r.ghost)) {
      _runner(c, r, labels);
    }
    for (final r in runners.where((r) => !r.ghost)) {
      _runner(c, r, labels);
    }
  }

  // au sol : 1 ou 2 jaquettes debout (on saute)
  void _stack(Canvas c, RnObs o, double x) {
    final bw = _obsW * _pxm, bh = _gndH * _pxm, seed = (o.x * 10).floor();
    final n = 1 + (_h(seed) * 2).floor();
    for (var k = 0; k < n; k++) {
      final f = 1 - k * 0.08;
      _jaq(c, x + k * bw * 0.18, kRnGround - bh * f, bw * 0.82, bh * f, seed + k);
    }
    _r(c, x - 2, kRnGround - 2, bw + 4, 2, const Color(0x88000000));
  }

  // en l'air : enseigne « -50% » pendue au plafond (on glisse dessous), qui se balance un peu
  void _sign(Canvas c, RnObs o, double x) {
    final top = kRnGround - _airHigh * _pxm - 2, bot = kRnGround - _airLow * _pxm, w = _obsW * _pxm + 14, cx = x - 7 + w / 2;
    c.save();
    c.translate(cx, 0);
    c.rotate(sin(_now * 2.6 + o.x) * 0.012);
    c.translate(-cx, 0);
    _r(c, x - 3, 0, 2, top, const Color(0xFF8B8FA8));
    _r(c, x + w - 13, 0, 2, top, const Color(0xFF8B8FA8));
    final r = Rect.fromLTWH(x - 7, top, w, bot - top);
    c.drawRect(r.inflate(2), Paint()
      ..color = const Color(0x88FF3BA7)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
    _r(c, r.left, r.top, r.width, r.height, const Color(0xFF2A0A24));
    c.drawRect(r.deflate(1), Paint()
      ..color = const Color(0xFFFF3BA7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    final tp = _Cache.label('-50%', (_pxm * 0.3).roundToDouble(), const Color(0xFFFFE1F3));
    tp.paint(c, Offset(cx - tp.width / 2, (top + bot) / 2 - tp.height / 2));
    c.restore();
  }

  // héros cartouche : image en cache par pose et couleur, dessinée à 0,075 × px/m par pixel
  ui.Picture _heroPic(int f, bool air, Color main, bool ghost) {
    final k = '$f|$air|${main.value}|$ghost';
    final pic = _Cache.hero[k];
    if (pic != null) return pic;
    final a = ghost ? 0.5 : 1.0;
    final pal = <String, Color>{
      'k': const Color(0xFF120E18),
      'g': ghost ? const Color(0xFF8FA7D6) : const Color(0xFF9A9AA8),
      'G': ghost ? const Color(0xFF5D75A8) : const Color(0xFF6A6A78),
      'L': main,
      'w': Colors.white,
      'm': const Color(0xFF140C1C),
      's': const Color(0xFFF2F2F2),
      'y': _kGold,
      'b': const Color(0xFF3A3A46),
      'O': const Color(0xFF1B1B22),
    };
    final rows = [..._kHead, _kArms[air ? 0 : f % 2], ..._kBody, ...(air ? _kJump : _kLegs[f])];
    return _Cache.hero[k] = _Cache.record((c) {
      final pp = Paint();
      for (var j = 0; j < rows.length; j++) {
        for (var i = 0; i < rows[j].length; i++) {
          final col = pal[rows[j][i]];
          if (col == null) continue;
          pp.color = col.withOpacity(a);
          c.drawRect(Rect.fromLTWH(i.toDouble(), j.toDouble(), 1.04, 1.04), pp);
        }
      }
    });
  }

  void _runner(Canvas c, RnRunner r, bool labels) {
    final s = _pxm * 0.075, w2 = 7 * s, h2 = _kRows * s;
    final sx = _sx(r.x), by = kRnGround - r.y * _pxm, air = r.y > 0.05 && !r.dead;
    final f = (r.x * 2.2).floor() % 4;
    final col = r.dead ? Colors.grey : r.color;
    final sw = w2 * 1.3 - min(w2, r.y * 8);
    c.drawOval(Rect.fromCenter(center: Offset(sx, kRnGround + 2), width: sw * 2, height: s * 3), Paint()..color = Color.fromRGBO(0, 0, 0, r.ghost ? 0.18 : 0.35));
    final pic = _heroPic(r.dead ? 1 : f, air, col, r.ghost);
    c.save();
    if (r.dead) {
      c.translate(sx, by - s * 4);
      c.rotate(-1.45);
      c.translate(-w2, -h2);
    } else if (r.sliding) {
      c.translate(sx, by);
      c.rotate(-1.3);
      c.translate(-w2, -h2 * 0.95);
    } else {
      final sq = r.fx?.sq ?? 0;
      if (sq > 0) {
        final k = sq * 1.4;
        c.translate(sx, by);
        c.scale(1 + k, 1 - k);
        c.translate(-sx, -by);
      }
      c.translate(sx - w2, by - h2 - (air ? 0 : (f % 2) * s * 0.6));
    }
    c.scale(s, s);
    c.drawPicture(pic);
    c.restore();
    if (labels && r.label != null) {
      final tp = _Cache.label(r.label!, 10, r.color, pixel: false);
      tp.paint(c, Offset(sx - tp.width / 2, by - h2 - 16));
    }
  }

  void _trail(Canvas c, RnRunner r) {
    final fx = r.fx!;
    if (fx.trail.isEmpty) return;
    final s = _pxm * 0.075, w2 = 7 * s, h2 = _kRows * s;
    final pic = _heroPic(0, false, r.color, true);
    for (var i = 0; i < fx.trail.length; i++) {
      final (x, y) = fx.trail[i];
      c.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, 0.12 * (i + 1)));
      c.translate(_sx(x) - w2, kRnGround - y * _pxm - h2);
      c.scale(s, s);
      c.drawPicture(pic);
      c.restore();
    }
  }

  // repères (record, adversaire tombé) en pointillés
  void _recordLines(Canvas c) {
    for (final l in lines) {
      final px = _sx(l.$1);
      if (px < -10 || px > kRnW + 200) continue;
      final pp = Paint()..color = l.$3.withOpacity(0.7);
      for (var y = 60.0; y < kRnGround; y += 8) {
        c.drawRect(Rect.fromLTWH(px, y, 2, 4), pp);
      }
      final tp = _Cache.label(l.$2, 10, l.$3, pixel: false);
      tp.paint(c, Offset(px + 4, 44));
    }
  }

  // premier plan : bouts de rayons sombres qui passent en bas
  void _front(Canvas c) {
    _seg(1.6, 560, (i, x) {
      if (_h(i * 41) < 0.35) return;
      final h = 46 + _h(i) * 20;
      _r(c, x, kRnH - h, 70, h, const Color(0xFF07040F));
      _r(c, x, kRnH - h, 70, 4, const Color(0xFF2A1F4D));
      for (var k = 0; k < 4; k++) {
        _jaq(c, x + 6 + k * 16, kRnH - h + 8, 12, 18, i * 77 + k);
      }
      _r(c, x, kRnH - h + 4, 70, h - 4, const Color(0x9907040F));
    });
  }

  // alerte : obstacle qui arrive hors de l'écran (▲ sauter, ▼ glisser)
  void _alert(Canvas c, RnRunner me, double v) {
    if (me.dead || (_now * 10).floor().isEven) return;
    for (final o in world.obs) {
      if (_sx(o.x) < kRnW) continue;
      if ((o.x - me.x) / v > 0.9) break;
      final y = o.air ? kRnGround - 1.2 * _pxm : kRnGround - 0.45 * _pxm;
      c.drawPath(
          Path()
            ..moveTo(kRnW - 4, y)
            ..lineTo(kRnW - 22, y - 11)
            ..lineTo(kRnW - 22, y + 11)
            ..close(),
          Paint()..color = o.air ? const Color(0xFF3D8BFF) : const Color(0xFFFF3B3B));
      final tp = _Cache.label(o.air ? '▼' : '▲', 9, Colors.white);
      tp.paint(c, Offset(kRnW - 34 - tp.width / 2, y - tp.height / 2));
      break;
    }
  }

  void _pops(Canvas c, RnFx fx) {
    for (final p in fx.pops) {
      final tp = _Cache.label(p.txt, 8, const Color(0xFF3DFFD8));
      c.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, min(1, p.life * 2)));
      tp.paint(c, Offset(_sx(p.x) - tp.width / 2, kRnGround - p.y * _pxm - tp.height));
      c.restore();
    }
    if (fx.mileFx > 0) {
      final tp = _Cache.label('${fx.mile * 100} m', 20, _kGold);
      c.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, min(1, fx.mileFx)));
      c.translate(kRnW / 2, 130);
      c.scale(1 + (1.2 - fx.mileFx) * 0.3);
      tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
      c.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
