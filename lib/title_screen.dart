import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'cards.dart';
import 'game.dart';
import 'retro_theme.dart';

// Décor de l'écran titre : ciel étoilé + sol quadrillé néon, éventail de 3 dos de carte,
// logo PIXEL TRADE avec reflet.

/// Étoiles qui scintillent et sol quadrillé qui défile (par-dessus le fond du thème)
class TitleSky extends StatefulWidget {
  const TitleSky({super.key});
  @override
  State<TitleSky> createState() => _TitleSkyState();
}

class _TitleSkyState extends State<TitleSky> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
  final _stars = List.generate(70, (i) {
    final r = math.Random(i * 7919 + 3);
    return (r.nextDouble(), r.nextDouble() * 0.72, r.nextDouble() < 0.2 ? 2.4 : 1.6, r.nextDouble() * 6);
  });

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(child: CustomPaint(painter: _SkyPainter(c, _stars), size: Size.infinite));
}

class _SkyPainter extends CustomPainter {
  final Animation<double> a;
  final List<(double, double, double, double)> stars;
  _SkyPainter(this.a, this.stars) : super(repaint: a);

  @override
  void paint(Canvas canvas, Size s) {
    final t = a.value * 20;
    final p = Paint()..color = Colors.white;
    for (final (x, y, sz, ph) in stars) {
      p.color = Colors.white.withOpacity(0.3 + 0.6 * (math.sin(t * 1.3 + ph)).abs());
      canvas.drawRect(Rect.fromLTWH((x * s.width).roundToDouble(), (y * s.height).roundToDouble(), sz, sz), p);
    }
    // sol quadrillé (tiers bas)
    final top = s.height * 0.68, h = s.height - top;
    final floor = Rect.fromLTWH(0, top, s.width, h);
    canvas.drawRect(
      floor,
      Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00FF4FD8), Color(0x2EFF4FD8)]).createShader(floor),
    );
    final line = Paint()
      ..color = const Color(0xFFFF4FD8)
      ..strokeWidth = 1;
    for (var i = 0; i < 12; i++) {
      final z = (i + (t * 0.6) % 1) / 12;
      final y = top + h * math.pow(z, 2.2);
      line.color = const Color(0xFFFF4FD8).withOpacity(0.45 * z);
      canvas.drawLine(Offset(0, y), Offset(s.width, y), line);
    }
    line.color = const Color(0x55FF4FD8);
    for (var i = -8; i <= 8; i++) {
      canvas.drawLine(Offset(s.width / 2 + i * s.width * 0.04, top), Offset(s.width / 2 + i * s.width * 0.32, s.height), line);
    }
  }

  @override
  bool shouldRepaint(_SkyPainter o) => false;
}

/// Trois dos de carte en éventail : épique à gauche, rare à droite (halos qui pulsent
/// l'un après l'autre), doré au milieu (il flotte)
class TitleFan extends StatefulWidget {
  final double width;
  const TitleFan({super.key, this.width = 118});
  @override
  State<TitleFan> createState() => _TitleFanState();
}

class _TitleFanState extends State<TitleFan> with TickerProviderStateMixin {
  late final AnimationController halo = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  late final AnimationController float = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);

  @override
  void dispose() {
    halo.dispose();
    float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width, h = w * 7 / 5;
    Widget side(int rarity, double angle, double dx, double phase) => AnimatedBuilder(
          animation: halo,
          builder: (_, __) {
            final g = 0.5 + 0.5 * math.sin(2 * math.pi * (halo.value + phase));
            return Transform.translate(
              offset: Offset(dx, h * 0.1),
              child: Transform.rotate(
                angle: angle,
                alignment: const Alignment(0, 1.4),
                child: SizedBox(width: w, child: CardBack(aura: kRarityColor[rarity], glow: g)),
              ),
            );
          },
        );
    return SizedBox(
      width: w * 2.1,
      height: h * 1.25,
      child: Stack(alignment: Alignment.topCenter, clipBehavior: Clip.none, children: [
        side(3, -0.3, -w * 0.22, 0), // épique
        side(2, 0.3, w * 0.22, 0.5), // rare
        AnimatedBuilder(
          animation: float,
          builder: (_, child) {
            final v = Curves.easeInOut.transform(float.value);
            return Transform.translate(offset: Offset(0, -9 * v), child: Transform.rotate(angle: 0.035 * v, child: child));
          },
          child: SizedBox(width: w, child: const CardBack(aura: kGold, glow: 0.7)),
        ),
      ]),
    );
  }
}

/// Logo PIXEL / TRADE avec un reflet qui passe toutes les 4 secondes
class TitleLogo extends StatefulWidget {
  const TitleLogo({super.key});
  @override
  State<TitleLogo> createState() => _TitleLogoState();
}

class _TitleLogoState extends State<TitleLogo> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF3DD9FF);
    final logo = Column(mainAxisSize: MainAxisSize.min, children: [
      Text('PIXEL', style: pixelStyle(size: 31).copyWith(letterSpacing: 2, shadows: const [Shadow(color: Color(0xFF8A4E00), offset: Offset(0, 3)), Shadow(color: Color(0x88EF9F27), blurRadius: 18)])),
      const SizedBox(height: 8),
      Text('TRADE', style: pixelStyle(size: 31, color: cyan).copyWith(letterSpacing: 2, shadows: const [Shadow(color: Color(0xFF0B5C78), offset: Offset(0, 3)), Shadow(color: Color(0x883DD9FF), blurRadius: 18)])),
    ]);
    return AnimatedBuilder(
      animation: c,
      child: logo,
      builder: (_, child) {
        // reflet : 0 → 0,6 au repos, puis passe de gauche à droite
        final p = c.value < 0.6 ? -1.0 : -1 + (c.value - 0.6) / 0.4 * 3;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (r) => LinearGradient(
            begin: Alignment(p - 0.5, -0.3),
            end: Alignment(p + 0.5, 0.3),
            colors: const [Color(0x00FFFFFF), Color(0x99FFFFFF), Color(0x00FFFFFF)],
          ).createShader(r),
          child: child,
        );
      },
    );
  }
}
