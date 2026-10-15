import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog.dart';
import 'game.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Modèle de carte unique (toutes consoles) : cadre de la couleur de la rareté,
// jaquette entière (jamais recadrée) sur fond flouté, reflet holo qui suit
// l'inclinaison du téléphone, silhouette pour les cartes non possédées.
// ═══════════════════════════════════════════════════════════════════════════

/// Inclinaison du téléphone (-1..1 sur chaque axe), lissée. Un seul capteur pour toutes les cartes.
class Tilt {
  Tilt._();
  static final value = ValueNotifier<Offset>(Offset.zero);
  static StreamSubscription<AccelerometerEvent>? _sub;
  static int _users = 0;
  static Offset? _base; // position « à plat » : celle du téléphone à l'ouverture

  /// Gyroscope activé (réglage du profil, mémorisé).
  static bool enabled = false;
  static const _kPref = 'rc_gyro2'; // nouvelle clé : désactivé par défaut pour tous

  static Future<void> loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool(_kPref) ?? false;
    } catch (_) {}
  }

  static Future<void> setEnabled(bool v) async {
    enabled = v;
    if (!v) {
      _stop();
      value.value = Offset.zero;
    } else if (_users > 0) {
      _start();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPref, v);
    } catch (_) {}
  }

  static void acquire() {
    _users++;
    if (enabled && _sub == null) _start();
  }

  static void release() {
    _users = max(0, _users - 1);
    if (_users == 0) _stop();
  }

  static void _start() {
    _base = null;
    value.value = Offset.zero;
    try {
      _sub = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen((e) {
        final raw = Offset(-e.x, e.y);
        // 1re mesure = référence : la carte s'affiche bien à plat, quelle que soit la tenue du téléphone
        final base = _base ??= raw;
        // la référence suit lentement la tenue (si on change de position, la carte se recentre)
        _base = Offset(base.dx + (raw.dx - base.dx) * 0.004, base.dy + (raw.dy - base.dy) * 0.004);
        final target = Offset(((raw.dx - base.dx) / 3.2).clamp(-1.0, 1.0), ((raw.dy - base.dy) / 3.2).clamp(-1.0, 1.0));
        final v = value.value;
        value.value = Offset(v.dx + (target.dx - v.dx) * 0.25, v.dy + (target.dy - v.dy) * 0.25);
      }, onError: (_) {});
    } catch (_) {}
  }

  static void _stop() {
    _sub?.cancel();
    _sub = null;
  }
}

/// Active le capteur d'inclinaison tant que le widget est affiché.
class TiltScope extends StatefulWidget {
  final Widget child;
  const TiltScope({super.key, required this.child});
  @override
  State<TiltScope> createState() => _TiltScopeState();
}

class _TiltScopeState extends State<TiltScope> {
  @override
  void initState() {
    super.initState();
    Tilt.acquire();
  }

  @override
  void dispose() {
    Tilt.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Carte face visible.
class CardView extends StatelessWidget {
  final RcCard card;
  final int finish;
  final bool owned;
  final bool tilt3d; // la carte entière s'incline avec le téléphone (grande carte)
  final Offset? manualTilt; // inclinaison au doigt (prioritaire sur le capteur)
  const CardView({super.key, required this.card, this.finish = 0, this.owned = true, this.tilt3d = false, this.manualTilt});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 5 / 7,
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final face = _face(context, w);
        if (!tilt3d) return face;
        return ValueListenableBuilder<Offset>(
          valueListenable: Tilt.value,
          builder: (_, tl, child) {
            final o = manualTilt ?? tl;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateY(o.dx * 0.5)
                ..rotateX(-o.dy * 0.5),
              child: child,
            );
          },
          child: face,
        );
      }),
    );
  }

  Widget _face(BuildContext context, double w) {
    final r = card.rarity;
    final sys = Catalog.system(card.sys);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final small = w < 140;
    final img = Catalog.imageFile(card);
    final cacheW = (w * dpr).round().clamp(64, 900);

    Widget picture = Image.file(img,
        fit: BoxFit.contain,
        cacheWidth: cacheW,
        errorBuilder: (_, __, ___) => Icon(Icons.image_not_supported, color: Colors.white24, size: w * 0.2));
    if (!owned) {
      picture = Stack(alignment: Alignment.center, children: [
        Opacity(
          opacity: 0.9,
          child: ColorFiltered(colorFilter: const ColorFilter.mode(Color(0xFF26262C), BlendMode.srcATop), child: picture),
        ),
        Text('?', style: TextStyle(color: Colors.white24, fontSize: w * 0.28, fontWeight: FontWeight.w900)),
      ]);
    }

    final background = owned
        ? (small
            ? Opacity(
                opacity: 0.35,
                child: Image.file(img, fit: BoxFit.cover, cacheWidth: (cacheW / 3).round().clamp(32, 300), errorBuilder: (_, __, ___) => const SizedBox()),
              )
            : ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Opacity(
                  opacity: 0.55,
                  child: Image.file(img, fit: BoxFit.cover, cacheWidth: (cacheW / 3).round().clamp(32, 300), errorBuilder: (_, __, ___) => const SizedBox()),
                ),
              ))
        : const SizedBox();

    final fs = w / 190; // échelle du texte
    final rad = w * 0.075;
    final frameW = max(3.0, w * 0.045);
    // Cadre : dégradé métallique de la rareté ; arc-en-ciel (brillante) ; or (dorée) ; gris (non possédée)
    final List<Color> frame = !owned
        ? const [Color(0xFF5A5A63), Color(0xFF2E2E36), Color(0xFF4A4A52), Color(0xFF26262C), Color(0xFF5A5A63)]
        : finish == 2
            ? const [Color(0xFFFFF3B0), Color(0xFFD4A017), Color(0xFFFFE082), Color(0xFF8C6A0E), Color(0xFFFFF3B0)]
            : finish == 1
                ? const [Color(0xFFFF8A80), Color(0xFFFFD180), Color(0xFFCCFF90), Color(0xFF80D8FF), Color(0xFFB388FF), Color(0xFFFF8A80)]
                : [kRarityLight[r], kRarityColor[r], kRarityDark[r], kRarityColor[r], kRarityLight[r]];
    final gem = !owned ? const Color(0xFF6A6A72) : (finish == 2 ? const Color(0xFFFFD54F) : kRarityColor[r]);
    final gemLight = !owned ? const Color(0xFF8A8A92) : (finish == 2 ? const Color(0xFFFFF3B0) : kRarityLight[r]);
    final Gradient gradient = finish == 1 && owned
        ? SweepGradient(colors: frame)
        : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: frame);

    Widget diamond(double size, Color c) => Transform.rotate(
          angle: pi / 4,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: c, border: Border.all(color: Colors.black54, width: max(0.6, size * 0.12))),
          ),
        );

    final inner = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF11131D),
        borderRadius: BorderRadius.circular(max(2.0, rad - frameW * 0.7)),
        border: Border.all(color: Colors.black.withOpacity(0.7), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // bandeau du haut façon étiquette de cartouche
        Container(
          height: max(9.0, w * 0.11),
          padding: EdgeInsets.only(left: w * 0.035),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [gem.withOpacity(0.55), gem.withOpacity(0.08)]),
          ),
          child: Row(children: [
            Expanded(
              child: Text((sys?.short ?? card.sys).toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 8.5 * fs, fontWeight: FontWeight.w800, letterSpacing: 0.8 * fs)),
            ),
            Container(
              height: double.infinity,
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(horizontal: w * 0.03),
              color: gem,
              child: Text('#${card.num.toString().padLeft(3, '0')}',
                  style: TextStyle(color: const Color(0xFF11131D), fontSize: 9 * fs, fontWeight: FontWeight.w900)),
            ),
          ]),
        ),
        // fenêtre de la jaquette
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(w * 0.03, w * 0.03, w * 0.03, w * 0.02),
            child: Container(
              decoration: BoxDecoration(
                color: owned ? kRarityDark[r] : const Color(0xFF1B1B22),
                borderRadius: BorderRadius.circular(w * 0.025),
                border: Border.all(color: gem.withOpacity(0.55), width: max(1.0, w * 0.008)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(fit: StackFit.expand, children: [
                background,
                Padding(padding: EdgeInsets.all(w * 0.03), child: picture),
              ]),
            ),
          ),
        ),
        // titre
        Container(
          margin: EdgeInsets.symmetric(horizontal: w * 0.03),
          padding: EdgeInsets.symmetric(horizontal: w * 0.025, vertical: w * 0.012),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.35), borderRadius: BorderRadius.circular(w * 0.02)),
          child: Text(owned ? card.title : '???',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white, fontSize: 12.5 * fs, fontWeight: FontWeight.w800)),
        ),
        // pied : année + rareté écrite + gemmes + finition
        Padding(
          padding: EdgeInsets.fromLTRB(w * 0.04, w * 0.018, w * 0.035, w * 0.03),
          child: Row(children: [
            Text(owned ? '${card.year ?? ''}' : '',
                style: TextStyle(color: Colors.white54, fontSize: 9.5 * fs, fontWeight: FontWeight.w600)),
            SizedBox(width: w * 0.03),
            const Spacer(),
            if (owned)
              Flexible(
                flex: 6,
                child: Container(
                  padding: EdgeInsets.fromLTRB(w * 0.03, w * 0.008, w * 0.025, w * 0.008),
                  decoration: BoxDecoration(
                    color: finish == 2 ? const Color(0xFF5A4206) : kRarityDark[r],
                    borderRadius: BorderRadius.circular(w * 0.025),
                    border: Border.all(color: gem.withOpacity(0.7), width: max(0.6, w * 0.005)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                      child: Text(
                        rarityName(r) + (finish == 1 ? ' ✦' : finish == 2 ? ' ★' : ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: gemLight, fontSize: 9 * fs, fontWeight: FontWeight.w800),
                      ),
                    ),
                    SizedBox(width: w * 0.02),
                    for (var i = 0; i <= r; i++)
                      Padding(
                        padding: EdgeInsets.only(left: w * 0.008),
                        child: diamond(max(3.0, w * 0.028), gemLight),
                      ),
                  ]),
                ),
              )
            else
              for (var i = 0; i <= r; i++)
                Padding(
                  padding: EdgeInsets.only(left: w * 0.012),
                  child: diamond(max(3.0, w * 0.03), const Color(0xFF3A3A42)),
                ),
          ]),
        ),
      ]),
    );

    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(rad),
        boxShadow: [
          if (!small) BoxShadow(color: Colors.black.withOpacity(0.55), offset: Offset(0, w * 0.025), blurRadius: w * 0.03),
          if (owned && r >= 3 && !small) BoxShadow(color: gem.withOpacity(0.45), blurRadius: w * 0.09),
        ],
      ),
      child: Stack(children: [
        Padding(padding: EdgeInsets.all(frameW), child: inner),
        // reflet sur le cadre (bord supérieur)
        Positioned(
          left: rad,
          right: rad,
          top: frameW * 0.25,
          height: max(1.0, frameW * 0.3),
          child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(color: Colors.white.withOpacity(owned ? 0.45 : 0.15), borderRadius: BorderRadius.circular(2)))),
        ),
        // ornements en losange aux quatre coins
        if (!small) ...[
          Positioned(left: frameW * 0.2, top: frameW * 0.2, child: diamond(frameW * 1.2, frame.first)),
          Positioned(right: frameW * 0.2, top: frameW * 0.2, child: diamond(frameW * 1.2, frame.first)),
          Positioned(left: frameW * 0.2, bottom: frameW * 0.2, child: diamond(frameW * 1.2, frame.first)),
          Positioned(right: frameW * 0.2, bottom: frameW * 0.2, child: diamond(frameW * 1.2, frame.first)),
        ],
        if (owned && finish > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(borderRadius: BorderRadius.circular(rad), child: HoloSheen(gold: finish == 2, manualTilt: manualTilt)),
            ),
          ),
        // cartes animées : légendaires, dorées, épiques brillantes
        if (owned && (r == 4 || finish == 2 || (r == 3 && finish == 1)))
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(rad),
                child: CardSparkle(
                  color: finish == 2 ? const Color(0xFFFFE9A0) : (r == 4 ? const Color(0xFFFFD27A) : const Color(0xFFE6DDFF)),
                  stars: small ? 4 : 9,
                  seed: card.id.hashCode,
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Animation des cartes rares : un éclat lumineux traverse la carte et des
/// étoiles scintillent.
class CardSparkle extends StatefulWidget {
  final Color color;
  final int stars, seed;
  const CardSparkle({super.key, required this.color, this.stars = 8, this.seed = 0});
  @override
  State<CardSparkle> createState() => _CardSparkleState();
}

class _CardSparkleState extends State<CardSparkle> with SingleTickerProviderStateMixin {
  late final AnimationController ctl = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat();

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(child: CustomPaint(painter: _SparklePainter(ctl, widget.color, widget.stars, widget.seed), child: const SizedBox.expand()));
}

class _SparklePainter extends CustomPainter {
  final Animation<double> anim;
  final Color color;
  final int stars, seed;
  _SparklePainter(this.anim, this.color, this.stars, this.seed) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    final v = anim.value;
    final w = size.width, h = size.height;
    // éclat diagonal pendant le premier tiers du cycle
    if (v < 0.35) {
      final p = v / 0.35;
      final x = -w * 0.6 + p * w * 2.2;
      final band = Path()
        ..moveTo(x, 0)
        ..lineTo(x + w * 0.22, 0)
        ..lineTo(x + w * 0.22 - h * 0.45, h)
        ..lineTo(x - h * 0.45, h)
        ..close();
      final fade = sin(p * pi);
      canvas.drawPath(
        band,
        Paint()
          ..shader = LinearGradient(colors: [
            color.withOpacity(0),
            color.withOpacity(0.38 * fade),
            Colors.white.withOpacity(0.55 * fade),
            color.withOpacity(0.38 * fade),
            color.withOpacity(0),
          ]).createShader(Rect.fromLTWH(x - h * 0.45, 0, w * 0.22 + h * 0.45, h))
          ..blendMode = BlendMode.plus,
      );
    }
    // étoiles qui scintillent
    final rnd = Random(seed);
    final paint = Paint()..blendMode = BlendMode.plus;
    for (var i = 0; i < stars; i++) {
      final px = 0.08 + rnd.nextDouble() * 0.84, py = 0.08 + rnd.nextDouble() * 0.84;
      final phase = rnd.nextDouble();
      final a = pow(max(0.0, sin(2 * pi * (v * 2 + phase))), 4).toDouble();
      if (a < 0.02) continue;
      final c = Offset(px * w, py * h);
      final s = w * (0.035 + rnd.nextDouble() * 0.03) * (0.6 + 0.4 * a);
      paint.color = color.withOpacity(0.9 * a);
      final star = Path()
        ..moveTo(c.dx, c.dy - s)
        ..quadraticBezierTo(c.dx, c.dy, c.dx + s, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + s)
        ..quadraticBezierTo(c.dx, c.dy, c.dx - s, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - s)
        ..close();
      canvas.drawPath(star, paint);
      canvas.drawCircle(c, s * 0.18, Paint()..color = Colors.white.withOpacity(0.9 * a));
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter old) => old.color != color || old.stars != stars || old.seed != seed;
}

/// Reflet arc-en-ciel (brillante) ou doré, qui glisse selon l'inclinaison.
class HoloSheen extends StatelessWidget {
  final bool gold;
  final Offset? manualTilt;
  const HoloSheen({super.key, this.gold = false, this.manualTilt});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Offset>(
      valueListenable: Tilt.value,
      builder: (_, tl, __) {
        final o = manualTilt ?? tl;
        final shift = (o.dx + o.dy) * 0.9;
        // bande de reflet étroite, mélangée en « overlay » : elle avive la
        // jaquette au lieu de poser un voile laiteux sur toute la carte
        final c = 0.5 + shift * 0.7;
        final stops = [for (final d in const [-0.32, -0.16, 0.0, 0.16, 0.32]) (c + d).clamp(0.0, 1.0)];
        final colors = gold
            ? const [Color(0x00FFE082), Color(0x88FFE082), Color(0xBBFFF8E1), Color(0x88FFB300), Color(0x00FFB300)]
            : const [Color(0x0085B7EB), Color(0x8885B7EB), Color(0xAAFFFFFF), Color(0x88ED93B1), Color(0x00FAC775)];
        return DecoratedBox(
          decoration: BoxDecoration(
            backgroundBlendMode: BlendMode.overlay,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
              stops: stops,
            ),
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

/// Dos de carte (ouverture des paquets).
class CardBack extends StatelessWidget {
  final Color? aura; // halo de la couleur de la rareté (suspense)
  final double glow; // 0..1 pulsation
  const CardBack({super.key, this.aura, this.glow = 0});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 5 / 7,
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final r = BorderRadius.circular(w * 0.07);
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D1B4D),
            borderRadius: r,
            boxShadow: aura == null
                ? null
                : [BoxShadow(color: aura!.withOpacity(0.25 + 0.5 * glow), blurRadius: w * (0.06 + 0.12 * glow), spreadRadius: w * 0.01)],
          ),
          // Dos des cartes : illustration « Retrogaming » (assets/card_back.jpg)
          foregroundDecoration: aura == null
              ? null
              : BoxDecoration(borderRadius: r, border: Border.all(color: aura!.withOpacity(0.6 + 0.4 * glow), width: w * 0.03)),
          child: ClipRRect(
            borderRadius: r,
            child: Image.asset(
              'assets/card_back.jpg',
              fit: BoxFit.cover,
              width: w,
              height: w * 7 / 5,
              cacheWidth: (w * MediaQuery.of(context).devicePixelRatio).round().clamp(64, 640),
              errorBuilder: (_, __, ___) => Center(
                child: Text('RC', style: TextStyle(color: const Color(0xFF7F77DD), fontSize: w * 0.22, fontWeight: FontWeight.w900)),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Petite pastille de pièces.
class CoinChip extends StatelessWidget {
  final int coins;
  const CoinChip(this.coins, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xFF412402), borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.monetization_on, color: Color(0xFFFAC775), size: 16),
          const SizedBox(width: 4),
          Text(fmt(coins), style: const TextStyle(color: Color(0xFFFAC775), fontWeight: FontWeight.w700)),
        ]),
      );
}

String fmt(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

/// Ligne de petites cartes (échanges, vitrine).
class MiniCards extends StatelessWidget {
  final List<(String, int)> items;
  final double width;
  const MiniCards(this.items, {super.key, this.width = 54});
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return Text(t('rien', 'nothing'), style: const TextStyle(color: Colors.white38));
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final (id, f) in items)
        if (Catalog.cards[id] != null) SizedBox(width: width, child: CardView(card: Catalog.cards[id]!, finish: f)),
    ]);
  }
}

/// Logo officiel d'une console (assets/logos/<id>.png) sur un panneau clair ou sombre
/// selon les couleurs du logo. Si le logo manque : le nom de la console.
const _kDarkBoardLogos = {'n64', 'neogeo', 'nes', 'psx', 'gba'};

class ConsoleLogo extends StatelessWidget {
  final String sys;
  final double height;
  final bool board; // panneau autour du logo
  const ConsoleLogo(this.sys, {super.key, this.height = 36, this.board = true});

  @override
  Widget build(BuildContext context) {
    final dark = _kDarkBoardLogos.contains(sys);
    final img = Image.asset(
      'assets/logos/$sys.png',
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => Text(Catalog.system(sys)?.name ?? sys,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: height * 0.45, color: dark || !board ? Colors.white : Colors.black87)),
    );
    if (!board) return img;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: height * 0.25, vertical: height * 0.12),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF15151C) : const Color(0xFFF4F2EA),
        borderRadius: BorderRadius.circular(height * 0.2),
        border: Border.all(color: dark ? const Color(0xFF3A3A44) : const Color(0xFFBDB9AD), width: 1.5),
      ),
      child: img,
    );
  }
}


/// Grande carte de la fiche : suit l'inclinaison du téléphone et se tourne
/// entièrement au doigt (on voit le dos) ; elle reste dans la position où on la lâche.
/// Double-tap : remise de face.
class SpinCard extends StatefulWidget {
  final RcCard card;
  final int finish;
  final bool owned;
  const SpinCard({super.key, required this.card, this.finish = 0, this.owned = true});
  @override
  State<SpinCard> createState() => _SpinCardState();
}

class _SpinCardState extends State<SpinCard> with SingleTickerProviderStateMixin {
  double rotY = 0, rotX = 0;
  late final AnimationController ctl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
    ..addListener(() {
      final v = Curves.easeOutCubic.transform(ctl.value);
      setState(() {
        rotY = _fromY + (_toY - _fromY) * v;
        rotX = _keepX ? _fromX : _fromX * (1 - v);
      });
    });
  double _fromY = 0, _toY = 0, _fromX = 0;
  bool _keepX = false;

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  /// Fin du geste : la carte continue sur sa lancée puis s'arrête là où elle est (de face, de dos ou de biais).
  void _glide(double velocity) {
    _fromY = rotY;
    _fromX = rotX;
    _keepX = true;
    _toY = rotY + velocity * 0.0022;
    ctl.duration = Duration(milliseconds: (300 + velocity.abs() * 0.5).clamp(300, 1400).round());
    ctl.forward(from: 0);
  }

  /// Double-tap : remise de face, à plat.
  void _reset() {
    _fromY = rotY;
    _fromX = rotX;
    _keepX = false;
    _toY = (rotY / (2 * pi)).roundToDouble() * 2 * pi;
    ctl.duration = const Duration(milliseconds: 600);
    ctl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (_) => ctl.stop(),
      onPanUpdate: (d) => setState(() {
        rotY -= d.delta.dx * 0.013; // signe inversé : glisser à droite fait tourner la carte vers la droite
        rotX = (rotX - d.delta.dy * 0.009).clamp(-0.8, 0.8);
      }),
      onPanEnd: (d) => _glide(-d.velocity.pixelsPerSecond.dx),
      onDoubleTap: _reset,
      child: ValueListenableBuilder<Offset>(
        valueListenable: Tilt.value,
        builder: (_, tl, __) {
          final ay = rotY + tl.dx * 0.5;
          final ax = rotX - tl.dy * 0.5;
          final back = cos(ay) < 0;
          final sheen = Offset((sin(ay) * 1.6).clamp(-1.0, 1.0), (-sin(ax) * 1.6).clamp(-1.0, 1.0));
          final face = back
              ? Transform(alignment: Alignment.center, transform: Matrix4.identity()..rotateY(pi), child: const CardBack())
              : CardView(card: widget.card, finish: widget.finish, owned: widget.owned, manualTilt: sheen);
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateX(ax)
              ..rotateY(ay),
            child: face,
          );
        },
      ),
    );
  }
}
