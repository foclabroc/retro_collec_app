import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio.dart';
import 'connect4.dart';
import 'cards.dart';
import 'catalog.dart';
import 'gamedle.dart';
import 'game.dart';
import 'layout.dart';
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

/// Roue en or (tous les 7 jours de connexion d'affilée) : mêmes cases, gains doublés, JACKPOT
const _goldSegs = [
  _Seg('40', 40, Color(0xFFB8860B)),
  _Seg('100', 100, Color(0xFFE6B422)),
  _Seg('CARTE', 0, Color(0xFFC9A227)),
  _Seg('60', 60, Color(0xFFB07A10)),
  _Seg('200', 200, Color(0xFFF2C94C)),
  _Seg('80', 80, Color(0xFFA67C00)),
  _Seg('ÉPIQUE', 0, Color(0xFFD99A00), rare: true),
  _Seg('JACKPOT', 1000, Color(0xFFFF4F79)),
];

/// Vrai le jour de la roue en or (série de connexion multiple de 7)
bool get _goldDay => Game.i.streak > 0 && Game.i.streak % 7 == 0;
List<_Seg> get _wheelSegs => _goldDay ? _goldSegs : _segs;

class BonusScreen extends StatelessWidget {
  const BonusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TabHeader(t('Bonus / Jeux', 'Bonus / Games'), icon: 'bonus'),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: const [
          WheelTile(),
          SizedBox(height: 12),
          GamedleTile(),
          SizedBox(height: 12),
          QuizTile(),
          SizedBox(height: 12),
          Connect4Tile(),
          SizedBox(height: 12),
          BattleTile(),
        ]),
      ),
    ]);
  }
}

/// Case « Roue de la fortune » (comme Gamedle et Quiz) : ouvre la roue en plein écran
class WheelTile extends StatelessWidget {
  const WheelTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Notifs.i,
      builder: (context, _) {
        final can = Notifs.i.wheel;
        final gold = _goldDay;
        final accent = gold ? const Color(0xFFFFD54F) : kGold;
        final now = DateTime.now();
        final left = DateTime(now.year, now.month, now.day + 1).difference(now);
        final toGold = 7 - Game.i.streak % 7;
        final status = can
            ? (gold ? t('Tour en or disponible : gains doublés !', 'Golden spin ready: double prizes!') : t('Ton tour gratuit est disponible !', 'Your free spin is ready!'))
            : t('Prochain tour dans ${left.inHours} h ${left.inMinutes % 60} min', 'Next spin in ${left.inHours} h ${left.inMinutes % 60} min');
        return Material(
          color: kPanel,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WheelPage())),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withOpacity(gold ? 1 : 0.7), width: gold ? 2 : 1.5),
                gradient: LinearGradient(colors: [accent.withOpacity(0.16), Colors.transparent]),
                boxShadow: gold ? [BoxShadow(color: accent.withOpacity(0.35), blurRadius: 14)] : null,
              ),
              child: Row(children: [
                Container(
                  width: 58,
                  height: 58,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: kBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: accent, width: 2),
                    boxShadow: [BoxShadow(color: accent.withOpacity(can ? 0.6 : 0.2), blurRadius: 12)],
                  ),
                  child: CustomPaint(painter: _WheelPainter(_wheelSegs, gold, mini: true)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
                      Text(gold ? t('Roue en or ✨', 'Golden wheel ✨') : t('Roue de la fortune', 'Wheel of fortune'),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      if (can) PulsePill(t('🎁 Tour gratuit', '🎁 Free spin')),
                    ]),
                    const SizedBox(height: 3),
                    Text(
                        gold
                            ? t('${Game.i.streak} jours d\'affilée : JACKPOT possible', '${Game.i.streak}-day streak: JACKPOT possible')
                            : t('Un tour gratuit par jour · roue en or dans $toGold j', 'One free spin a day · golden wheel in $toGold d'),
                        style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(status, style: TextStyle(color: can ? accent : Colors.white38, fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ),
                Icon(can ? Icons.play_arrow_rounded : Icons.check_circle, color: can ? accent : Colors.white38, size: 32),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// La roue en plein écran
class WheelPage extends StatelessWidget {
  const WheelPage({super.key});
  @override
  Widget build(BuildContext context) => MaxWidth(
        max: 820,
        child: Scaffold(
          appBar: AppBar(title: Text(t('Roue de la fortune', 'Wheel of fortune'))),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: const [WheelPanel()]),
        ),
      );
}

class WheelPanel extends StatefulWidget {
  const WheelPanel({super.key});
  @override
  State<WheelPanel> createState() => _WheelPanelState();
}

class _WheelPanelState extends State<WheelPanel> with TickerProviderStateMixin {
  late final AnimationController spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 4800));
  late final AnimationController shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
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
    shake.dispose();
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
    final segAngle = 2 * pi / _wheelSegs.length;
    final jitter = (Random().nextDouble() - 0.5) * segAngle * 0.6;
    final base = angle % (2 * pi);
    from = angle;
    to = angle - base + 6 * 2 * pi + (2 * pi - (seg + 0.5) * segAngle) + jitter;
    _lastTick = (from / (pi / 4)).floor();
    RcAudio.sfx('continue');
    await spin.forward(from: 0);
    if (!mounted) return;
    // gros lot : la roue tremble avant la fête
    if (_prizeLevel(r) >= 2) {
      HapticFeedback.heavyImpact();
      await shake.forward(from: 0);
    }
    if (!mounted) return;
    Game.i.setCoins((r['coins'] as num? ?? Game.i.coins).toInt());
    Game.i.emit(r['events']);
    await Notifs.i.refresh();
    await _showPrize(r);
    Game.i.sync();
    if (mounted) setState(() => busy = false);
  }

  /// 0 petit gain, 1 joli gain, 2 gros lot (300 et plus, épique / légendaire), 3 JACKPOT
  int _prizeLevel(Map<String, dynamic> r) {
    final gain = (r['gain'] as num? ?? 0).toInt();
    final cr = r['card'] is Map ? ((r['card'] as Map)['r'] as num? ?? 0).toInt() : -1;
    if (r['gold'] == true && (r['seg'] as num?)?.toInt() == 7) return 3;
    if (gain >= 300 || cr >= 3) return 2;
    if (gain >= 100 || cr >= 0) return 1;
    return 0;
  }

  Future<void> _showPrize(Map<String, dynamic> r) async {
    final level = _prizeLevel(r);
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
    if (level >= 2) RcAudio.win();
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: kBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: kGold, width: level >= 2 ? 3 : 2)),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
         // confettis : plus il y en a, plus le lot est gros
         if (level > 0) Positioned.fill(child: IgnorePointer(child: _Confetti(count: const [0, 40, 90, 160][level]))),
         Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
                level == 3
                    ? 'JACKPOT !!!'
                    : level == 2
                        ? t('ÉNORME !', 'HUGE!')
                        : t('GAGNÉ !', 'YOU WIN!'),
                style: pixelStyle(size: level >= 2 ? 22 : 18, color: level == 3 ? const Color(0xFFFF4F79) : kGold)),
            if (r['gold'] == true) ...[
              const SizedBox(height: 6),
              Text(t('✨ Roue en or ✨', '✨ Golden wheel ✨'), style: const TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.w800)),
            ],
            const SizedBox(height: 18),
            if (c != null) ...[
              SizedBox(width: 170, child: CardView(card: c, finish: f)),
              const SizedBox(height: 10),
              if (card?['n'] == true)
                Text(t('Nouvelle carte !', 'New card!'), style: pixelStyle(size: 11, color: const Color(0xFF5DCAA5))),
              if (gain > 0) const SizedBox(height: 10),
            ],
            if (c == null || gain > 0)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('+$gain', style: pixelStyle(size: 30)),
                const SizedBox(width: 10),
                const Icon(Icons.monetization_on, color: kGold, size: 40),
              ]),
            const SizedBox(height: 16),
            Text(t('Reviens demain pour un nouveau tour', 'Come back tomorrow for another spin'), style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
                onPressed: () => Navigator.pop(ctx),
                child: Text(t('SUPER !', 'GREAT!'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              ),
            ),
          ]),
         ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Notifs.i,
      builder: (context, _) {
        final can = Notifs.i.wheel && !busy;
        final gold = _goldDay;
        final now = DateTime.now();
        final left = DateTime(now.year, now.month, now.day + 1).difference(now);
        final toGold = 7 - Game.i.streak % 7;
        return AnimatedBuilder(
          animation: shake,
          builder: (_, child) => Transform.translate(offset: Offset(sin(shake.value * pi * 10) * 9 * (1 - shake.value), 0), child: child),
          child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          decoration: BoxDecoration(
            color: kPanel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: gold ? const Color(0xFFFFD54F) : kGold.withOpacity(0.6), width: gold ? 3 : 1.5),
            boxShadow: gold ? [BoxShadow(color: const Color(0xFFFFD54F).withOpacity(0.45), blurRadius: 22)] : null,
          ),
          child: Column(children: [
            Text(gold ? t('✨ ROUE EN OR ✨', '✨ GOLDEN WHEEL ✨') : t('ROUE DE LA FORTUNE', 'WHEEL OF FORTUNE'),
                style: pixelStyle(size: 12, color: gold ? const Color(0xFFFFD54F) : kGold)),
            const SizedBox(height: 4),
            Text(
                gold
                    ? t('${Game.i.streak} jours d\'affilée : gains doublés et JACKPOT !', '${Game.i.streak}-day streak: double prizes and JACKPOT!')
                    : t('Un tour gratuit par jour · roue en or dans $toGold jour${toGold > 1 ? 's' : ''} de connexion',
                        'One free spin a day · golden wheel in $toGold login day${toGold > 1 ? 's' : ''}'),
                textAlign: TextAlign.center,
                style: TextStyle(color: gold ? const Color(0xFFFFE08A) : Colors.white60, fontSize: 12)),
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
                      builder: (_, __) => Transform.rotate(angle: angle, child: CustomPaint(painter: _WheelPainter(_wheelSegs, gold))),
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
                            color: kBg,
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
          ),
        );
      },
    );
  }
}

/// Pluie de confettis (fenêtre de gain)
class _Confetti extends StatefulWidget {
  final int count;
  const _Confetti({required this.count});
  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward();
  late final List<List<double>> parts = () {
    final rnd = Random();
    // x, vitesse, taille, dérive, couleur, rotation, départ
    return [for (var i = 0; i < widget.count; i++) [rnd.nextDouble(), 0.5 + rnd.nextDouble(), 4 + rnd.nextDouble() * 5, rnd.nextDouble() * 2 - 1, rnd.nextInt(6).toDouble(), rnd.nextDouble() * 6, -rnd.nextDouble() * 0.4]];
  }();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: c, builder: (_, __) => CustomPaint(painter: _ConfettiPainter(parts, c.value)));
}

class _ConfettiPainter extends CustomPainter {
  final List<List<double>> parts;
  final double t;
  _ConfettiPainter(this.parts, this.t);
  static const _colors = [Color(0xFFFFD54F), Color(0xFFFF4F79), Color(0xFF3DD9FF), Color(0xFF5DCAA5), Color(0xFFB18CFF), Colors.white];

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in parts) {
      final y = (p[6] + t * p[1] * 1.4) * size.height;
      if (y < -10 || y > size.height + 10) continue;
      final x = p[0] * size.width + sin(t * 8 + p[5]) * 14 * p[3];
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p[5] + t * 10 * p[3]);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p[2], height: p[2] * 0.55),
          Paint()..color = _colors[p[4].toInt()].withOpacity(t > 0.85 ? (1 - t) / 0.15 : 1));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

class _WheelPainter extends CustomPainter {
  final List<_Seg> segs;
  final bool gold;
  final bool mini; // petite roue de la case Bonus : sans texte, ampoules plus fines
  _WheelPainter(this.segs, this.gold, {this.mini = false});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final e = mini ? r * 0.1 : 6.0; // épaisseur du bord
    final rect = Rect.fromCircle(center: c, radius: r - e);
    final n = segs.length;
    final sweep = 2 * pi / n;
    // contour
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF10142E));
    for (var i = 0; i < n; i++) {
      final start = -pi / 2 + i * sweep;
      final s = segs[i];
      canvas.drawArc(
        rect,
        start,
        sweep,
        true,
        Paint()
          ..shader = RadialGradient(colors: [Color.lerp(s.color, Colors.white, 0.25)!, s.color, Color.lerp(s.color, Colors.black, 0.25)!], stops: const [0, 0.6, 1])
              .createShader(rect),
      );
      canvas.drawLine(c, c + Offset(cos(start), sin(start)) * (r - e), Paint()
        ..color = Colors.white.withOpacity(0.7)
        ..strokeWidth = mini ? 1 : 2);
      if (mini) continue;
      // texte (orienté vers l'extérieur)
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(start + sweep / 2 + pi / 2);
      final isCoins = s.coins > 0;
      final tp = TextPainter(
        text: TextSpan(
          text: s.label == 'JACKPOT' ? 'JACKPOT' : isCoins ? s.label : (s.rare ? (gold ? t('ÉPIQUE', 'EPIC') : t('RARE', 'RARE')) : t('CARTE', 'CARD')),
          style: TextStyle(
            color: Colors.white,
            fontSize: r * (s.label == 'JACKPOT' ? 0.075 : isCoins ? 0.13 : 0.085),
            fontWeight: FontWeight.w900,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -r * 0.78));
      // petite icône sous le texte
      final icon = s.label == 'JACKPOT' ? Icons.emoji_events : isCoins ? Icons.monetization_on : (s.rare ? Icons.auto_awesome : Icons.style);
      final ip = TextPainter(
        text: TextSpan(text: String.fromCharCode(icon.codePoint), style: TextStyle(fontSize: r * 0.12, fontFamily: icon.fontFamily, color: Colors.white.withOpacity(0.85))),
        textDirection: TextDirection.ltr,
      )..layout();
      ip.paint(canvas, Offset(-ip.width / 2, -r * 0.78 + tp.height + 2));
      canvas.restore();
    }
    // cercle doré + ampoules
    canvas.drawCircle(c, r - e, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = mini ? e : (gold ? 8 : 6)
      ..color = gold ? const Color(0xFFFFE082) : kGold);
    for (var i = 0; i < 24; i++) {
      final a = i * 2 * pi / 24;
      if (mini && i.isOdd) continue;
      canvas.drawCircle(c + Offset(cos(a), sin(a)) * (r - e), mini ? r * 0.045 : 3.2, Paint()..color = i.isEven ? const Color(0xFFFFF6D5) : const Color(0xFFFFC94D));
    }
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.gold != gold || old.mini != mini;
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
