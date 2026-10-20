import 'dart:math';

import 'package:flutter/material.dart';

import 'album.dart';
import 'catalog.dart';
import 'game.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Sagas (Mario, Sonic, Zelda, Pokémon) : 10 cartes chacune, en version holo.
// Une carte de saga est une copie d'une carte existante (même jaquette) rangée
// UNIQUEMENT dans l'album de sa saga (« console » sg_<saga>, voir catalog.dart).
// Chaque carte tirée a 3,2 % de chance d'être une carte de saga (patch_sagas.sql).
// ═══════════════════════════════════════════════════════════════════════════

const kSagaSteps = [50, 100];
const kSagaReward = {50: 100, 100: 500}; // + 2 pixels à 100 %

const _kRainbow = [
  Color(0xFFFF5EA8),
  Color(0xFFFFD166),
  Color(0xFF5DFFB0),
  Color(0xFF4FC3FF),
  Color(0xFFB07CFF),
  Color(0xFFFF5EA8),
];

/// Logo d'une saga (image fournie, fond transparent)
class SagaLogo extends StatelessWidget {
  final RcSaga saga;
  final double height;
  const SagaLogo(this.saga, {super.key, this.height = 36});
  @override
  Widget build(BuildContext context) => Image.asset(
        saga.logo,
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => Text(saga.name.toUpperCase(),
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: height * 0.5, color: saga.accent)),
      );
}

/// Rayons qui tournent (derrière la jaquette ou sur l'affiche)
class _RaysPainter extends CustomPainter {
  final Color color;
  final double angle;
  final Offset center; // en fraction de la taille
  _RaysPainter(this.color, this.angle, {this.center = const Offset(0.5, 0.52)});
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width * center.dx, size.height * center.dy);
    final r = size.longestSide * 1.3;
    const n = 18;
    final p = Paint()..color = color;
    for (var i = 0; i < n; i++) {
      final a0 = angle + i * 2 * pi / n, a1 = a0 + pi / n * 0.8;
      canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy)
            ..lineTo(c.dx + r * cos(a0), c.dy + r * sin(a0))
            ..lineTo(c.dx + r * cos(a1), c.dy + r * sin(a1))
            ..close(),
          p);
    }
  }

  @override
  bool shouldRepaint(covariant _RaysPainter old) => old.angle != angle || old.color != color;
}

// ── Carte de saga (style holographique avec halo) ─────────────────────────

class SagaFace extends StatefulWidget {
  final RcCard card;
  final double width;
  final ImageProvider cover;
  final bool owned;
  final Offset? manualTilt;
  const SagaFace({super.key, required this.card, required this.width, required this.cover, this.owned = true, this.manualTilt});
  @override
  State<SagaFace> createState() => _SagaFaceState();
}

class _SagaFaceState extends State<SagaFace> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!widget.owned || still) {
      c.stop();
    } else if (!c.isAnimating) {
      c.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant SagaFace old) {
    super.didUpdateWidget(old);
    if (widget.owned && !c.isAnimating && !(MediaQuery.maybeOf(context)?.disableAnimations ?? false)) c.repeat();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final saga = sagaById(widget.card.saga) ?? kSagas.first;
    final owned = widget.owned;
    final radius = BorderRadius.circular(w * 0.08);
    final innerR = BorderRadius.circular(w * 0.055);
    final small = w < 120;

    Widget cover = Image(
      image: widget.cover,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(Icons.image_not_supported, color: Colors.white24, size: w * 0.2),
    );
    if (!owned) {
      cover = Stack(alignment: Alignment.center, children: [
        ColorFiltered(colorFilter: const ColorFilter.mode(Color(0xFF26262C), BlendMode.srcATop), child: cover),
        Text('?', style: TextStyle(color: Colors.white24, fontSize: w * 0.28, fontWeight: FontWeight.w900)),
      ]);
    }

    // intérieur (construit une fois ; seuls le cadre, le halo, les rayons et le reflet bougent)
    final inner = ClipRRect(
      borderRadius: innerR,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: owned ? [Color.lerp(saga.color, Colors.black, 0.45)!, saga.dark] : const [Color(0xFF24242C), Color(0xFF111116)],
          ),
        ),
        child: Stack(fit: StackFit.expand, children: [
          if (owned && !small)
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: c,
                builder: (_, __) => CustomPaint(painter: _RaysPainter(saga.color.withOpacity(0.28), c.value * 2 * pi / 3)),
              ),
            ),
          Column(children: [
            SizedBox(height: w * 0.05),
            Opacity(opacity: owned ? 1 : 0.35, child: SagaLogo(saga, height: w * 0.17)),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: w * 0.07, vertical: w * 0.03),
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.55), blurRadius: w * 0.06, offset: Offset(0, w * 0.03))]),
                    child: cover,
                  ),
                ),
              ),
            ),
            Container(
              margin: EdgeInsets.fromLTRB(w * 0.06, 0, w * 0.06, w * 0.06),
              padding: EdgeInsets.symmetric(horizontal: w * 0.04, vertical: w * 0.022),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(w * 0.1),
                border: Border.all(color: Colors.white.withOpacity(owned ? 0.6 : 0.2), width: max(1.0, w * 0.008)),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  owned ? widget.card.title : '???',
                  // nom long : passe sur 2 lignes, police un peu réduite
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: max(7.0, w * (widget.card.title.length > 18 ? 0.05 : 0.058)),
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                      color: owned ? Colors.white : Colors.white38),
                ),
                if (!small)
                  Text(t('CARTE SAGA', 'SAGA CARD'),
                      style: TextStyle(fontSize: w * 0.034, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: owned ? saga.accent : Colors.white24)),
              ]),
            ),
          ]),
          // numéro de la carte dans sa saga
          Positioned(
            left: w * 0.035,
            top: w * 0.035,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: w * 0.025, vertical: w * 0.008),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(w * 0.05),
                border: Border.all(color: (owned ? saga.accent : Colors.white24).withOpacity(0.8), width: max(0.8, w * 0.006)),
              ),
              child: Text('#${widget.card.num.toString().padLeft(2, '0')}',
                  style: TextStyle(
                      fontSize: max(6.5, w * 0.042),
                      fontWeight: FontWeight.w900,
                      color: owned ? saga.accent : Colors.white38,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ),
          // reflet holographique : suit l'inclinaison, sinon glisse tout seul
          if (owned)
            IgnorePointer(
              child: AnimatedBuilder(
                animation: c,
                builder: (_, __) {
                  final tl = widget.manualTilt;
                  final p = tl != null ? (0.5 + tl.dx * 0.8).clamp(0.0, 1.0) : 0.5 - 0.5 * cos(c.value * 2 * pi);
                  final x = -1.6 + 3.2 * p;
                  return Opacity(
                    opacity: 0.32,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(x - 1.2, -1),
                          end: Alignment(x + 1.2, 1),
                          colors: const [
                            Color(0x00FFFFFF),
                            Color(0xFFFF5EA8),
                            Color(0xFFFFD166),
                            Color(0xFF5DFFB0),
                            Color(0xFF4FC3FF),
                            Color(0xFFB07CFF),
                            Color(0x00FFFFFF),
                          ],
                          stops: const [0.2, 0.32, 0.4, 0.48, 0.56, 0.64, 0.78],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ]),
      ),
    );

    // cadre arc-en-ciel qui tourne + halo qui respire
    return AnimatedBuilder(
      animation: c,
      child: inner,
      builder: (_, child) {
        final v = c.value;
        final breath = 0.5 + 0.5 * sin(v * 4 * pi);
        return Container(
          padding: EdgeInsets.all(max(2.0, w * 0.03)),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: owned
                ? SweepGradient(colors: _kRainbow, transform: GradientRotation(v * 2 * pi))
                : const LinearGradient(colors: [Color(0xFF5A5A66), Color(0xFF34343C)]),
            boxShadow: owned
                ? [
                    BoxShadow(color: saga.color.withOpacity(0.35 + 0.35 * breath), blurRadius: w * 0.14, spreadRadius: w * 0.005),
                    BoxShadow(
                      color: HSVColor.fromAHSV(1, (v * 360) % 360, 0.55, 1).toColor().withOpacity(0.25 + 0.3 * (1 - breath)),
                      blurRadius: w * 0.2,
                      spreadRadius: w * 0.01,
                    ),
                  ]
                : [const BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3))],
          ),
          child: child,
        );
      },
    );
  }
}

// ── Affiche d'une saga dans la Collection ─────────────────────────────────

class SagaPoster extends StatefulWidget {
  final RcSaga saga;
  const SagaPoster(this.saga, {super.key});
  @override
  State<SagaPoster> createState() => _SagaPosterState();
}

class _SagaPosterState extends State<SagaPoster> with SingleTickerProviderStateMixin {
  bool pressed = false;
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 40));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (still) {
      _clock.stop();
      _started = false;
    } else if (!_started) {
      _started = true;
      _clock.value = (widget.saga.id.hashCode % 1000) / 1000;
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  double _ph(double sec) => (_clock.value * 40 / sec) % 1;

  Widget _cover(String id) {
    final c = Catalog.cards[id];
    if (c == null) return const SizedBox();
    return DecoratedBox(
      decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 6))]),
      child: Image(image: Catalog.image(c), fit: BoxFit.contain, filterQuality: FilterQuality.medium, errorBuilder: (_, __, ___) => const SizedBox()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.saga;
    final g = Game.i;
    final total = max(1, (Catalog.bySys[s.sys] ?? const []).length);
    final mine = g.ownedIn(s.sys);
    final complete = mine >= total;
    final f = (mine / total).clamp(0.0, 1.0);

    final poster = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: s.accent, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 14, offset: Offset(0, 7))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight;
          // éventail : la carte du centre a toujours la plus grande case (les côtés : 46 % × 32 %)
          final fanTop = h * 0.30, fanH = h * 0.52;
          final sideW = w * 0.46, sideH = h * 0.32, midW = w * 0.80, midH = fanH;
          return Stack(fit: StackFit.expand, children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(center: const Alignment(0, 0.25), radius: 0.95, colors: [s.color, s.dark]),
              ),
            ),
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _clock,
                builder: (_, __) => CustomPaint(
                  painter: _RaysPainter(Colors.white.withOpacity(0.10), _clock.value * 2 * pi, center: const Offset(0.5, 0.6)),
                ),
              ),
            ),
            // logo qui flotte
            Positioned(
              left: w * 0.08,
              right: w * 0.08,
              top: h * 0.04,
              height: h * 0.23,
              child: AnimatedBuilder(
                animation: _clock,
                builder: (_, child) => Transform.translate(offset: Offset(0, -3 - 3 * sin(_ph(4) * 2 * pi)), child: child),
                child: SagaLogo(s, height: h * 0.23),
              ),
            ),
            // les 3 meilleures cartes en éventail
            AnimatedBuilder(
              animation: _clock,
              builder: (_, __) {
                final k = sin(_ph(4.444) * 2 * pi);
                Widget side(String id, bool left) => Positioned(
                      left: left ? w * 0.04 : null,
                      right: left ? null : w * 0.04,
                      top: fanTop + fanH - sideH - h * 0.02,
                      width: sideW,
                      height: sideH,
                      child: Transform.rotate(
                        angle: (left ? -1 : 1) * (0.24 + 0.04 * k),
                        alignment: Alignment.bottomCenter,
                        child: Align(alignment: Alignment.bottomCenter, child: _cover(id)),
                      ),
                    );
                return Stack(fit: StackFit.expand, children: [
                  if (s.best.length > 2) side(s.best[0], true),
                  if (s.best.length > 2) side(s.best[1], false),
                  Positioned(
                    left: (w - midW) / 2,
                    top: fanTop - 4 * k,
                    width: midW,
                    height: midH,
                    child: Align(alignment: Alignment.bottomCenter, child: _cover(s.best.last)),
                  ),
                ]);
              },
            ),
            // pied : progression
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(9, 14, 9, 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xC0000000)], stops: [0, 0.35]),
                ),
                child: Row(children: [
                  Expanded(
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(5)),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: f),
                        duration: const Duration(milliseconds: 1400),
                        curve: const Cubic(0.2, 0.8, 0.2, 1),
                        builder: (_, v, __) => FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: v,
                          child: DecoratedBox(
                            decoration: BoxDecoration(gradient: LinearGradient(colors: [s.accent, Colors.white]), borderRadius: BorderRadius.circular(5)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    complete ? t('★ COMPLÈTE', '★ COMPLETE') : '$mine/$total',
                    style: TextStyle(color: complete ? s.accent : Colors.white, fontWeight: FontWeight.w900, fontSize: 12, fontFamily: 'monospace'),
                  ),
                ]),
              ),
            ),
            // reflet qui passe
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _clock,
                builder: (_, __) {
                  final v = _ph(5);
                  if (v < 0.6) return const SizedBox.shrink();
                  final x = -1.2 + 2.4 * ((v - 0.6) / 0.25).clamp(0.0, 1.0);
                  return FractionalTranslation(
                    translation: Offset(x, 0),
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(-1, -0.4),
                          end: Alignment(1, 0.4),
                          colors: [Color(0x00FFFFFF), Color(0x70FFFFFF), Color(0x00FFFFFF)],
                          stops: [0.35, 0.48, 0.6],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ]);
        }),
      ),
    );

    return GestureDetector(
      onTapDown: (_) => setState(() => pressed = true),
      onTapCancel: () => setState(() => pressed = false),
      onTapUp: (_) => setState(() => pressed = false),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SystemAlbumPage(sys: s.sys))),
      child: AnimatedScale(scale: pressed ? 0.96 : 1, duration: const Duration(milliseconds: 110), child: poster),
    );
  }
}
