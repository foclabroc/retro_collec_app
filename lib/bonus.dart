import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio.dart';
import 'cards.dart';
import 'catalog.dart';
import 'game.dart';
import 'main.dart';
import 'notifs.dart';
import 'quiz.dart';
import 'retro_theme.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Onglet Bonus : roue de la fortune (un tour gratuit par jour) + quiz rétro
// ═══════════════════════════════════════════════════════════════════════════

/// Cases de la roue, dans le même ordre que le serveur (rc_wheel)
class _Seg {
  final String label;
  final int coins; // 0 = carte
  final bool rare;
  final Color color;
  const _Seg(this.label, this.coins, this.color, {this.rare = false});
}

const _segs = [
  _Seg('20', 20, Color(0xFF3C6FD8)),
  _Seg('50', 50, Color(0xFFE2A21F)),
  _Seg('CARTE', 0, Color(0xFF2FA36B)),
  _Seg('30', 30, Color(0xFFD8453C)),
  _Seg('100', 100, Color(0xFF8E5BD9)),
  _Seg('40', 40, Color(0xFF2A9DB8)),
  _Seg('RARE', 0, Color(0xFFEF6F2E), rare: true),
  _Seg('300', 300, Color(0xFFD4A017)),
];

class BonusScreen extends StatelessWidget {
  const BonusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TabHeader(t('Bonus', 'Bonus')),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: const [
          WheelPanel(),
          SizedBox(height: 18),
          QuizTile(),
        ]),
      ),
    ]);
  }
}

class WheelPanel extends StatefulWidget {
  const WheelPanel({super.key});
  @override
  State<WheelPanel> createState() => _WheelPanelState();
}

class _WheelPanelState extends State<WheelPanel> with SingleTickerProviderStateMixin {
  late final AnimationController spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 4800));
  double from = 0, to = 0; // angles (radians)
  bool busy = false;
  int _lastTick = 0;

  double get angle => from + (to - from) * Curves.easeOutCubic.transform(spin.value);

  @override
  void initState() {
    super.initState();
    spin.addListener(() {
      // petit « clic » à chaque case franchie
      final tick = (angle / (pi / 4)).floor();
      if (tick != _lastTick) {
        _lastTick = tick;
        HapticFeedback.selectionClick();
      }
    });
  }

  @override
  void dispose() {
    spin.dispose();
    super.dispose();
  }

  Future<void> _spin() async {
    if (busy) return;
    setState(() => busy = true);
    Map<String, dynamic> r;
    try {
      r = await RcServer.wheel();
    } catch (e) {
      toast(errText(e));
      if (mounted) setState(() => busy = false);
      Notifs.i.refresh();
      return;
    }
    final seg = (r['seg'] as num).toInt();
    // case gagnante en haut, sous le pointeur, après 6 tours
    final segAngle = 2 * pi / _segs.length;
    final jitter = (Random().nextDouble() - 0.5) * segAngle * 0.6;
    final base = angle % (2 * pi);
    from = angle;
    to = angle - base + 6 * 2 * pi + (2 * pi - (seg + 0.5) * segAngle) + jitter;
    _lastTick = (from / (pi / 4)).floor();
    RcAudio.sfx('continue');
    await spin.forward(from: 0);
    if (!mounted) return;
    Game.i.setCoins((r['coins'] as num? ?? Game.i.coins).toInt());
    Game.i.emit(r['events']);
    await Notifs.i.refresh();
    await _showPrize(r);
    Game.i.sync();
    if (mounted) setState(() => busy = false);
  }

  Future<void> _showPrize(Map<String, dynamic> r) async {
    final gain = (r['gain'] as num? ?? 0).toInt();
    final card = r['card'] is Map ? Map<String, dynamic>.from(r['card'] as Map) : null;
    final c = card == null ? null : Catalog.cards[card['c']];
    final f = (card?['f'] as num? ?? 0).toInt();
    if (c != null) {
      Game.i.playSound(c.rarity);
    } else {
      RcAudio.sfx(gain >= 100 ? 'powerup' : 'coin');
    }
    HapticFeedback.mediumImpact();
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xF20A1033),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: kGold, width: 2)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(t('GAGNÉ !', 'YOU WIN!'), style: pixelStyle(size: 18)),
            const SizedBox(height: 18),
            if (c != null) ...[
              SizedBox(width: 170, child: CardView(card: c, finish: f)),
              const SizedBox(height: 10),
              if (card?['n'] == true)
                Text(t('Nouvelle carte !', 'New card!'), style: pixelStyle(size: 11, color: const Color(0xFF5DCAA5))),
            ] else
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('+$gain', style: pixelStyle(size: 30)),
                const SizedBox(width: 10),
                const Icon(Icons.monetization_on, color: kGold, size: 40),
              ]),
            const SizedBox(height: 16),
            Text(t('Reviens demain pour un nouveau tour', 'Come back tomorrow for another spin'), style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Notifs.i,
      builder: (context, _) {
        final can = Notifs.i.wheel && !busy;
        final now = DateTime.now();
        final left = DateTime(now.year, now.month, now.day + 1).difference(now);
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          decoration: BoxDecoration(
            color: kPanel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kGold.withOpacity(0.6), width: 1.5),
          ),
          child: Column(children: [
            Text(t('ROUE DE LA FORTUNE', 'WHEEL OF FORTUNE'), style: pixelStyle(size: 12)),
            const SizedBox(height: 4),
            Text(t('Un tour gratuit par jour : pièces ou carte !', 'One free spin a day: coins or a card!'),
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 14),
            LayoutBuilder(builder: (context, box) {
              final size = min(box.maxWidth, 300.0);
              return SizedBox(
                width: size,
                height: size,
                child: Stack(alignment: Alignment.topCenter, children: [
                  Positioned.fill(
                    top: 14,
                    child: AnimatedBuilder(
                      animation: spin,
                      builder: (_, __) => Transform.rotate(angle: angle, child: CustomPaint(painter: _WheelPainter())),
                    ),
                  ),
                  // pointeur
                  CustomPaint(size: const Size(34, 36), painter: _PointerPainter()),
                  // moyeu
                  Positioned.fill(
                    top: 14,
                    child: Center(
                      child: GestureDetector(
                        onTap: can ? _spin : null,
                        child: Container(
                          width: size * 0.24,
                          height: size * 0.24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF0A1033),
                            border: Border.all(color: kGold, width: 4),
                            boxShadow: [BoxShadow(color: kGold.withOpacity(can ? 0.6 : 0.1), blurRadius: 14)],
                          ),
                          child: Center(child: Text(can ? 'GO' : '•', style: pixelStyle(size: size * 0.06, color: can ? kGold : Colors.white38))),
                        ),
                      ),
                    ),
                  ),
                ]),
              );
            }),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
                onPressed: can ? _spin : null,
                child: Text(
                  busy
                      ? t('Ça tourne…', 'Spinning…')
                      : Notifs.i.wheel
                          ? t('TOURNER !', 'SPIN!')
                          : t('Prochain tour dans ${left.inHours} h ${left.inMinutes % 60} min', 'Next spin in ${left.inHours} h ${left.inMinutes % 60} min'),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _WheelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r - 6);
    final n = _segs.length;
    final sweep = 2 * pi / n;
    // contour
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF10142E));
    for (var i = 0; i < n; i++) {
      final start = -pi / 2 + i * sweep;
      final s = _segs[i];
      canvas.drawArc(
        rect,
        start,
        sweep,
        true,
        Paint()
          ..shader = RadialGradient(colors: [Color.lerp(s.color, Colors.white, 0.25)!, s.color, Color.lerp(s.color, Colors.black, 0.25)!], stops: const [0, 0.6, 1])
              .createShader(rect),
      );
      canvas.drawLine(c, c + Offset(cos(start), sin(start)) * (r - 6), Paint()
        ..color = Colors.white.withOpacity(0.7)
        ..strokeWidth = 2);
      // texte (orienté vers l'extérieur)
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(start + sweep / 2 + pi / 2);
      final isCoins = s.coins > 0;
      final tp = TextPainter(
        text: TextSpan(
          text: isCoins ? s.label : (s.rare ? t('RARE', 'RARE') : t('CARTE', 'CARD')),
          style: TextStyle(
            color: Colors.white,
            fontSize: r * (isCoins ? 0.13 : 0.085),
            fontWeight: FontWeight.w900,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -r * 0.78));
      // petite icône sous le texte
      final icon = isCoins ? Icons.monetization_on : (s.rare ? Icons.auto_awesome : Icons.style);
      final ip = TextPainter(
        text: TextSpan(text: String.fromCharCode(icon.codePoint), style: TextStyle(fontSize: r * 0.12, fontFamily: icon.fontFamily, color: Colors.white.withOpacity(0.85))),
        textDirection: TextDirection.ltr,
      )..layout();
      ip.paint(canvas, Offset(-ip.width / 2, -r * 0.78 + tp.height + 2));
      canvas.restore();
    }
    // cercle doré + ampoules
    canvas.drawCircle(c, r - 6, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = kGold);
    for (var i = 0; i < 24; i++) {
      final a = i * 2 * pi / 24;
      canvas.drawCircle(c + Offset(cos(a), sin(a)) * (r - 6), 3.2, Paint()..color = i.isEven ? const Color(0xFFFFF6D5) : const Color(0xFFFFC94D));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawShadow(p, Colors.black, 4, false);
    canvas.drawPath(p, Paint()..color = Colors.white);
    canvas.drawPath(p, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFF10142E));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
