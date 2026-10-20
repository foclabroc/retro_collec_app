import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'audio.dart';
import 'game.dart';
import 'retro_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Choix du booster : 6 boosters de couleurs différentes tournent en cercle,
// le joueur en choisit un (le serveur a tiré 6 paquets, il en garde un).
// ═══════════════════════════════════════════════════════════════════════════

class BoosterColor {
  final String fr, en;
  final double hue, sat, bri; // filtre appliqué à l'image du booster (bleu d'origine)
  final Color glow;
  const BoosterColor(this.fr, this.en, this.hue, this.sat, this.bri, this.glow);
  String get name => t(fr, en);
}

const kBoosters = [
  BoosterColor('bleu', 'blue', 0, 1.15, 1.0, Color(0xFF2F6BFF)),
  BoosterColor('violet', 'purple', 45, 1.25, 1.0, Color(0xFF8A3DFF)),
  BoosterColor('rose', 'pink', 95, 1.3, 1.05, Color(0xFFFF3D9E)),
  BoosterColor('rouge', 'red', 140, 1.45, 0.98, Color(0xFFFF3B2F)),
  BoosterColor('or', 'gold', 180, 1.6, 1.08, Color(0xFFF0A419)),
  BoosterColor('vert', 'green', -95, 1.3, 1.0, Color(0xFF19C46A)),
];

/// Filtre de couleur du booster [i] : teinte, puis saturation, puis luminosité (comme en CSS).
ColorFilter boosterFilter(int i) {
  final b = kBoosters[i % kBoosters.length];
  final a = b.hue * pi / 180, c = cos(a), s = sin(a);
  final h = [
    0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928,
    0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.140, 0.072 - c * 0.072 - s * 0.283,
    0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072,
  ];
  final k = b.sat;
  final sm = [
    0.213 + 0.787 * k, 0.715 - 0.715 * k, 0.072 - 0.072 * k,
    0.213 - 0.213 * k, 0.715 + 0.285 * k, 0.072 - 0.072 * k,
    0.213 - 0.213 * k, 0.715 - 0.715 * k, 0.072 + 0.928 * k,
  ];
  final m = List<double>.filled(9, 0);
  for (var r = 0; r < 3; r++) {
    for (var col = 0; col < 3; col++) {
      var v = 0.0;
      for (var x = 0; x < 3; x++) {
        v += sm[r * 3 + x] * h[x * 3 + col];
      }
      m[r * 3 + col] = v * b.bri;
    }
  }
  return ColorFilter.matrix([
    m[0], m[1], m[2], 0, 0,
    m[3], m[4], m[5], 0, 0,
    m[6], m[7], m[8], 0, 0,
    0, 0, 0, 1, 0,
  ]);
}

/// Anneau de 6 boosters : glisser pour faire tourner, toucher celui du milieu pour le choisir.
class BoosterRing extends StatefulWidget {
  final Widget Function(int i, double w, double h) pack; // image du booster i (déjà colorée)
  final Widget? label; // type de paquet (logo de la console, « Premium »…)
  final Future<void> Function(int i) onChoose;
  const BoosterRing({super.key, required this.pack, required this.onChoose, this.label});
  @override
  State<BoosterRing> createState() => _BoosterRingState();
}

class _BoosterRingState extends State<BoosterRing> with SingleTickerProviderStateMixin {
  static const n = 6, step = 360.0 / n;
  double ang = 0; // rotation de l'anneau (degrés)
  double? target; // angle visé (aimantation)
  bool auto = true, busy = false;
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 16666.0).clamp(0.0, 3.0);
    _last = now;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (auto && !reduce) {
      setState(() => ang -= 0.18 * dt);
    } else if (target != null) {
      final d = target! - ang;
      setState(() {
        ang += d * min(1.0, 0.14 * dt);
        if (d.abs() < 0.05) {
          ang = target!;
          target = null;
        }
      });
    }
  }

  int get front => ((-ang / step).round() % n + n) % n;

  double _nearest(int i) {
    final base = -i * step;
    return base + ((ang - base) / 360).round() * 360;
  }

  void _spinTo(int i) {
    if (busy) return;
    setState(() {
      auto = false;
      target = _nearest(i);
    });
    RcAudio.sfx('jump');
  }

  Future<void> _choose() async {
    if (busy) return;
    final i = front;
    HapticFeedback.mediumImpact();
    setState(() {
      busy = true;
      auto = false;
      target = _nearest(i); // bien de face
    });
    await widget.onChoose(i);
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final fi = front;
    final col = kBoosters[fi];
    return Column(children: [
      Expanded(
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight;
          final pw = min(w * 0.31, (h - 60) / (856 / 440) * 0.82).clamp(70.0, 170.0);
          final ph = pw * 856 / 440;
          final rad = (w * 0.36).clamp(pw * 1.1, pw * 1.5);
          final cx = w / 2, cy = h / 2 - 14;
          final items = <(double, Widget)>[];
          for (var i = 0; i < n; i++) {
            final a = (i * step + ang) * pi / 180;
            final z = cos(a);
            final s = 1100 / (1100 - z * rad); // perspective
            final x = sin(a) * rad * s;
            final y = z * rad * 0.12; // anneau vu un peu du dessus : l'avant plus bas
            final bw = pw * s, bh = ph * s;
            final isFront = i == fi && target == null;
            final lift = isFront && busy ? 1.1 : 1.0;
            final dark = 1 - (0.45 + 0.55 * (z + 1) / 2);
            items.add((
              z,
              Positioned(
                left: cx + x - bw * lift / 2,
                top: cy + y - bh * lift / 2,
                width: bw * lift,
                height: bh * lift,
                child: GestureDetector(
                  onTap: () => i == fi ? _choose() : _spinTo(i),
                  child: Opacity(
                    opacity: busy && !isFront ? 0.35 : 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(boxShadow: [
                        BoxShadow(color: kBoosters[i].glow.withOpacity(isFront ? 0.75 : 0.4), blurRadius: 30 * s, spreadRadius: -6),
                      ]),
                      child: ColorFiltered(
                        colorFilter: ColorFilter.mode(Colors.black.withOpacity(dark.clamp(0.0, 0.6)), BlendMode.srcATop),
                        child: widget.pack(i, bw * lift, bh * lift),
                      ),
                    ),
                  ),
                ),
              ),
            ));
          }
          items.sort((p, q) => p.$1.compareTo(q.$1)); // du fond vers l'avant
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) {
              if (busy) return;
              setState(() {
                auto = false;
                target = null;
              });
            },
            onHorizontalDragUpdate: (d) {
              if (busy) return;
              setState(() => ang += d.delta.dx * 0.35);
            },
            onHorizontalDragEnd: (d) {
              if (busy) return;
              final proj = ang + d.velocity.pixelsPerSecond.dx * 0.08;
              setState(() => target = (proj / step).round() * step);
            },
            child: Stack(clipBehavior: Clip.none, children: [
              for (final it in items) it.$2,
              // nom du booster du milieu
              Positioned(
                left: 0,
                right: 0,
                top: cy + rad * 0.12 + ph / 2 + 12,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: target == null ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: opq(col.glow.withOpacity(0.9)),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kGold, width: 1.5),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(px('BOOSTER ${col.name.toUpperCase()}'), style: pixelStyle(size: 9, color: Colors.white, shadow: false)),
                        if (widget.label != null) ...[const SizedBox(width: 8), widget.label!],
                      ]),
                    ),
                  ),
                ),
              ),
            ]),
          );
        }),
      ),
      // pastilles : amènent un booster au milieu
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < n; i++)
          GestureDetector(
            onTap: () => _spinTo(i),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: i == fi ? 15 : 11,
                height: i == fi ? 15 : 11,
                decoration: BoxDecoration(
                  color: kBoosters[i].glow.withOpacity(i == fi ? 1 : 0.4),
                  shape: BoxShape.circle,
                  boxShadow: [if (i == fi) BoxShadow(color: kBoosters[i].glow, blurRadius: 10)],
                ),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: kGold,
            foregroundColor: const Color(0xFF2A1800),
            minimumSize: const Size.fromHeight(50),
            textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          onPressed: busy ? null : _choose,
          child: busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF2A1800)))
              : Text(t('Choisir le booster ${col.fr}', 'Pick the ${col.en} booster')),
        ),
      ),
      const SizedBox(height: 6),
    ]);
  }
}
