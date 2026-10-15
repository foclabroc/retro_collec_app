import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';

import 'game.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Thème « consoles rétro » : fond bleu animé (pixels qui flottent, traînées
// de vitesse, petits envahisseurs pixelisés, lignes de balayage CRT) et
// police pixel pour les titres.
// ═══════════════════════════════════════════════════════════════════════════

/// Police pixel des titres (Press Start 2P, téléchargée une fois puis gardée en cache).
TextStyle pixelStyle({double size = 14, Color color = kGold, bool shadow = true}) => GoogleFonts.pressStart2p(
      fontSize: size,
      color: color,
      height: 1.3,
      shadows: shadow ? const [Shadow(color: Color(0xFFB0381E), offset: Offset(2, 2))] : null,
    );

ThemeData retroTheme() {
  const navy = Color(0xFF141B45);
  const line = Color(0xFF3550B8);
  final base = ThemeData(brightness: Brightness.dark);
  return base.copyWith(
    colorScheme: const ColorScheme.dark(primary: kGold, secondary: Color(0xFF3DD9FF), surface: navy, onSurface: Colors.white),
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: navy,
    appBarTheme: AppBarTheme(
      backgroundColor: const Color(0xCC0A1033),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: pixelStyle(size: 13, color: Colors.white, shadow: false),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kGold,
        foregroundColor: const Color(0xFF412402),
        disabledBackgroundColor: const Color(0xFF3A3F66),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: Color(0xFF7A3E0E), width: 2),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: const Color(0x66141B45),
        side: const BorderSide(color: line, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: const Color(0xFF8FD3FF))),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xF00A0F2E),
      indicatorColor: const Color(0x55EF9F27),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: navy,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: line, width: 2)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: navy, surfaceTintColor: Colors.transparent),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: const Color(0xAA141B45),
      side: const BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Color(0xFF26306B),
      contentTextStyle: TextStyle(color: Colors.white),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: kGold),
    tabBarTheme: const TabBarThemeData(labelColor: kGold, indicatorColor: kGold, unselectedLabelColor: Colors.white70),
  );
}

/// Fond animé, dessiné derrière tous les écrans.
class RetroBackground extends StatefulWidget {
  const RetroBackground({super.key});
  @override
  State<RetroBackground> createState() => _RetroBackgroundState();
}

class _RetroBackgroundState extends State<RetroBackground> with SingleTickerProviderStateMixin {
  final time = ValueNotifier<double>(0);
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => time.value = d.inMicroseconds / 1e6)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: CustomPaint(painter: _BgPainter(time), child: const SizedBox.expand()));
}

class _Pix {
  final double x, y, size, vx, vy, alpha;
  final Color color;
  const _Pix(this.x, this.y, this.size, this.vx, this.vy, this.alpha, this.color);
}

// Envahisseur 11×8 et fantôme 14×14 (1 = pixel allumé)
const _invader = [
  '00100000100',
  '00010001000',
  '00111111100',
  '01101110110',
  '11111111111',
  '10111111101',
  '10100000101',
  '00011011000',
];
const _ghost = [
  '00000111100000',
  '00011111111000',
  '00111111111100',
  '01111111111110',
  '01100111100110',
  '11000011000011',
  '11000011000011',
  '11100111100111',
  '11111111111111',
  '11111111111111',
  '11111111111111',
  '11111111111111',
  '11011100111011',
  '10001100110001',
];

class _BgPainter extends CustomPainter {
  final ValueNotifier<double> time;
  _BgPainter(this.time) : super(repaint: time);

  static final List<_Pix> _pixels = () {
    final r = Random(42);
    const colors = [Color(0xFF6FA8FF), Color(0xFF3DD9FF), Color(0xFF9FC5FF), Color(0xFFFFFFFF), Color(0xFF5B7CFF)];
    return List.generate(46, (_) {
      final s = [3.0, 4.0, 5.0, 6.0, 8.0, 10.0][r.nextInt(6)];
      return _Pix(r.nextDouble(), r.nextDouble(), s, 4 + r.nextDouble() * 10, -(8 + r.nextDouble() * 22), 0.12 + r.nextDouble() * 0.35,
          colors[r.nextInt(colors.length)]);
    });
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final w = size.width, h = size.height;
    final p = Paint();

    // dégradé de fond (bleu des pochettes rétro)
    p.shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF0A1033), Color(0xFF122171), Color(0xFF0B1442)],
      stops: [0, 0.55, 1],
    ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, p);
    p.shader = null;

    // traînées de vitesse en diagonale
    for (var i = 0; i < 7; i++) {
      final speed = 40.0 + i * 9;
      final len = 140.0 + (i % 3) * 90;
      final off = ((t * speed + i * 263) % (w + h + len)) - len;
      final y0 = h - off + (i * 37 % 120);
      final x0 = off - (i * 53 % 150);
      p
        ..color = Color.fromRGBO(120, 180, 255, 0.05 + (i % 3) * 0.025)
        ..strokeWidth = 2.0 + (i % 3) * 2;
      canvas.drawLine(Offset(x0, y0), Offset(x0 + len, y0 - len * 0.55), p);
    }

    // pixels qui flottent vers le haut
    for (final px in _pixels) {
      final x = ((px.x * w + px.vx * t) % (w + 20)) - 10;
      final y = ((px.y * h + px.vy * t) % (h + 20) + (h + 20)) % (h + 20) - 10;
      final twinkle = 0.65 + 0.35 * sin(t * 1.7 + px.x * 20);
      p.color = px.color.withOpacity((px.alpha * twinkle).clamp(0.0, 1.0));
      canvas.drawRect(Rect.fromLTWH(x.roundToDouble(), y.roundToDouble(), px.size, px.size), p);
    }

    // envahisseurs et fantômes qui traversent lentement
    _sprite(canvas, _invader, Offset(((t * 14) % (w + 120)) - 60, h * 0.18 + sin(t * 0.8) * 10), 4, const Color(0x2E7CFF6B));
    _sprite(canvas, _ghost, Offset(w - ((t * 10 + 200) % (w + 120)) + 30, h * 0.62 + sin(t * 0.6 + 1) * 14), 3.5, const Color(0x26FF5DA2));
    _sprite(canvas, _invader, Offset(((t * 8 + w * 0.6) % (w + 120)) - 60, h * 0.86), 3, const Color(0x223DD9FF));

    // lignes de balayage CRT
    p.color = const Color(0x0D000000);
    for (double y = 0; y < h; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, w, 1), p);
    }
    // vignette
    p.shader = RadialGradient(colors: const [Color(0x00000000), Color(0x66000000)], stops: const [0.6, 1])
        .createShader(Rect.fromCircle(center: Offset(w / 2, h / 2), radius: max(w, h) * 0.75));
    canvas.drawRect(Offset.zero & size, p);
    p.shader = null;
  }

  void _sprite(Canvas canvas, List<String> rows, Offset o, double px, Color c) {
    final p = Paint()..color = c;
    for (var y = 0; y < rows.length; y++) {
      for (var x = 0; x < rows[y].length; x++) {
        if (rows[y].codeUnitAt(x) == 49) canvas.drawRect(Rect.fromLTWH(o.dx + x * px, o.dy + y * px, px, px), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BgPainter old) => false;
}
