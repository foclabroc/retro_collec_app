import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Thème de l'appli : fond animé épuré (dégradé, lueurs, motif discret),
// couleur d'accent par thème et police pixel pour les titres.
// ═══════════════════════════════════════════════════════════════════════════

// ─── Thèmes d'interface ─────────────────────────────────────────────────────
// Thèmes épurés : un dégradé sombre, deux lueurs de la couleur du thème qui
// dérivent lentement et un motif discret qui défile (étoiles, grille, vagues…).

enum RcMotif { stars, grid, pix, waves, diamonds, lines, fire, hex, bubbles, cross }

class RcThemeData {
  final String fr, en, motifFr, motifEn;
  final RcMotif motif;
  final Color top, bottom; // dégradé du fond
  final Color accent, accent2, onAccent; // couleur du thème, seconde lueur, texte sur bouton
  final Color bg, panel, panel2, surface, line;
  const RcThemeData(this.fr, this.en, this.motif, this.motifFr, this.motifEn,
      {required this.top,
      required this.bottom,
      required this.accent,
      required this.accent2,
      required this.onAccent,
      required this.panel,
      required this.panel2,
      required this.surface,
      required this.line})
      : bg = top;
  String get name => t(fr, en);
  String get motifName => t(motifFr, motifEn);
}

const kThemes = <RcThemeData>[
  RcThemeData('Minuit', 'Midnight', RcMotif.stars, 'Étoiles', 'Stars',
      top: Color(0xFF0B1030), bottom: Color(0xFF141A44), accent: Color(0xFF6EA8FF), accent2: Color(0xFF9A7DFF), onAccent: Color(0xFF08142E),
      panel: Color(0xD1161C40), panel2: Color(0xFF26306B), surface: Color(0xFF161C40), line: Color(0xFF2C3770)),
  RcThemeData('Arcade', 'Arcade', RcMotif.grid, 'Grille pixel', 'Pixel grid',
      top: Color(0xFF120A24), bottom: Color(0xFF1E0F3A), accent: Color(0xFFFF5EC4), accent2: Color(0xFF3EE6FF), onAccent: Color(0xFF2B0420),
      panel: Color(0xD11E123A), panel2: Color(0xFF3A2560), surface: Color(0xFF1E123A), line: Color(0xFF3E2A70)),
  RcThemeData('Game Boy', 'Game Boy', RcMotif.pix, 'Petits pixels', 'Little pixels',
      top: Color(0xFF0E1F12), bottom: Color(0xFF173020), accent: Color(0xFF9BDC5A), accent2: Color(0xFF5AC48A), onAccent: Color(0xFF0E2208),
      panel: Color(0xD6142818), panel2: Color(0xFF2A4A30), surface: Color(0xFF142818), line: Color(0xFF2E5A3A)),
  RcThemeData('Océan', 'Ocean', RcMotif.waves, 'Vagues', 'Waves',
      top: Color(0xFF06202E), bottom: Color(0xFF0B3448), accent: Color(0xFF3EC7E6), accent2: Color(0xFF2F8FD6), onAccent: Color(0xFF05222B),
      panel: Color(0xD10A2838), panel2: Color(0xFF1D4A60), surface: Color(0xFF0A2838), line: Color(0xFF1D5068)),
  RcThemeData('Or', 'Gold', RcMotif.diamonds, 'Losanges', 'Diamonds',
      top: Color(0xFF17120A), bottom: Color(0xFF271D10), accent: Color(0xFFEFB54A), accent2: Color(0xFFD27A2A), onAccent: Color(0xFF2A1800),
      panel: Color(0xD6261E12), panel2: Color(0xFF4A3A22), surface: Color(0xFF261E12), line: Color(0xFF4A3A20)),
  RcThemeData('Couchant', 'Sunset', RcMotif.lines, 'Lignes rétro', 'Retro lines',
      top: Color(0xFF1E0C2A), bottom: Color(0xFF3A1430), accent: Color(0xFFFF8A5B), accent2: Color(0xFFFF5EA8), onAccent: Color(0xFF2B0B06),
      panel: Color(0xD12C122C), panel2: Color(0xFF52244A), surface: Color(0xFF2C122C), line: Color(0xFF5A2A50)),
  RcThemeData('Forêt', 'Forest', RcMotif.fire, 'Lucioles', 'Fireflies',
      top: Color(0xFF0A1A12), bottom: Color(0xFF10281C), accent: Color(0xFF5FD39A), accent2: Color(0xFFD8FF7A), onAccent: Color(0xFF06281B),
      panel: Color(0xD610241A), panel2: Color(0xFF24452F), surface: Color(0xFF10241A), line: Color(0xFF24452F)),
  RcThemeData('Ardoise', 'Slate', RcMotif.hex, 'Hexagones', 'Hexagons',
      top: Color(0xFF14171D), bottom: Color(0xFF1E222B), accent: Color(0xFFE6E9EF), accent2: Color(0xFF8A93A3), onAccent: Color(0xFF14171C),
      panel: Color(0xDB1E222A), panel2: Color(0xFF3A404D), surface: Color(0xFF1E222A), line: Color(0xFF3A404D)),
  RcThemeData('Prune', 'Plum', RcMotif.bubbles, 'Bulles', 'Bubbles',
      top: Color(0xFF1A0F24), bottom: Color(0xFF2A1838), accent: Color(0xFFC08BFF), accent2: Color(0xFFFF7AB8), onAccent: Color(0xFF1F0B33),
      panel: Color(0xD1281834), panel2: Color(0xFF4A3060), surface: Color(0xFF281834), line: Color(0xFF4A3060)),
  RcThemeData('Néon', 'Neon', RcMotif.cross, 'Croix', 'Crosses',
      top: Color(0xFF05060A), bottom: Color(0xFF0E1016), accent: Color(0xFF3EF5C0), accent2: Color(0xFFFF4FD8), onAccent: Color(0xFF032018),
      panel: Color(0xDB12141C), panel2: Color(0xFF2A2E3A), surface: Color(0xFF12141C), line: Color(0xFF2A2E3A)),
];
/// Thème choisi (réglages, mémorisé)
final rcThemeIndex = ValueNotifier<int>(0);
RcThemeData get rcTheme => kThemes[rcThemeIndex.value.clamp(0, kThemes.length - 1)];

/// Thème « Aléatoire » : un thème différent tiré au hasard à chaque lancement
bool rcThemeRandom = false;

int _randomTheme() {
  if (kThemes.length < 2) return 0;
  final cur = rcThemeIndex.value;
  int i;
  do {
    i = Random().nextInt(kThemes.length);
  } while (i == cur);
  return i;
}

Future<void> loadTheme() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt('rc_theme2') ?? -1; // -1 = aléatoire (par défaut, nouveaux thèmes)
    rcThemeRandom = v < 0;
    if (rcThemeRandom) {
      rcThemeIndex.value = (prefs.getInt('rc_theme_last') ?? 0).clamp(0, kThemes.length - 1);
      rcThemeIndex.value = _randomTheme();
      await prefs.setInt('rc_theme_last', rcThemeIndex.value);
    } else {
      rcThemeIndex.value = v.clamp(0, kThemes.length - 1);
    }
  } catch (_) {}
}

/// [i] = -1 : aléatoire
Future<void> setTheme(int i) async {
  rcThemeRandom = i < 0;
  rcThemeIndex.value = rcThemeRandom ? _randomTheme() : i;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('rc_theme2', i < 0 ? -1 : i);
    await prefs.setInt('rc_theme_last', rcThemeIndex.value);
  } catch (_) {}
}

/// La police pixel n'a pas de majuscules accentuées (« ÉVÉNEMENTS » s'affichait « éVéNEMENTS ») :
/// on les remplace par la lettre simple dans les textes en police pixel.
String px(String s) {
  const from = 'ÉÈÊËÀÂÄÎÏÔÖÙÛÜÇ', to = 'EEEEAAAIIOOUUUC';
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : (ch == 'Œ' ? 'OE' : ch));
  }
  return b.toString();
}

/// Police pixel des titres (Press Start 2P, téléchargée une fois puis gardée en cache).
TextStyle pixelStyle({double size = 14, Color color = kGold, bool shadow = true}) => GoogleFonts.pressStart2p(
      fontSize: size,
      color: color,
      height: 1.3,
      shadows: shadow ? const [Shadow(color: Color(0xFFB0381E), offset: Offset(2, 2))] : null,
    );

ThemeData retroTheme() {
  final th = rcTheme;
  final navy = th.surface;
  final line = th.line;
  final base = ThemeData(brightness: Brightness.dark);
  return base.copyWith(
    colorScheme: ColorScheme.dark(primary: th.accent, secondary: th.accent2, surface: navy, onSurface: Colors.white),
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: navy,
    appBarTheme: AppBarTheme(
      backgroundColor: th.bg.withOpacity(0.8),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: pixelStyle(size: 13, color: Colors.white, shadow: false),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: th.accent,
        foregroundColor: th.onAccent,
        disabledBackgroundColor: const Color(0xFF3A3F66),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: Color.lerp(th.accent, Colors.black, 0.45)!, width: 2),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: navy.withOpacity(0.4),
        side: BorderSide(color: line, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: const Color(0xFF8FD3FF))),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: th.bg.withOpacity(0.94),
      indicatorColor: th.accent.withOpacity(0.33),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: navy,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: line, width: 2)),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: navy, surfaceTintColor: Colors.transparent),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: navy.withOpacity(0.67),
      side: BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: th.panel2,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: th.accent),
    tabBarTheme: TabBarThemeData(labelColor: th.accent, indicatorColor: th.accent, unselectedLabelColor: Colors.white70),
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

/// Aperçu animé d'un thème (choix du thème dans les réglages) : la scène est
/// dessinée à taille de téléphone puis réduite.
class ThemePreview extends StatefulWidget {
  final int index;
  final double width, height;
  const ThemePreview(this.index, {super.key, this.width = 64, this.height = 44});
  @override
  State<ThemePreview> createState() => _ThemePreviewState();
}

class _ThemePreviewState extends State<ThemePreview> with SingleTickerProviderStateMixin {
  final time = ValueNotifier<double>(3);
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => time.value = 3 + d.inMicroseconds / 1e6)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.width,
        height: widget.height,
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: 220,
            height: 220 * widget.height / widget.width,
            child: RepaintBoundary(child: CustomPaint(painter: _BgPainter(time, themeIndex: widget.index))),
          ),
        ),
      );
}

class _BgPainter extends CustomPainter {
  final ValueNotifier<double> time;
  final int? themeIndex; // aperçu d'un thème précis (réglages)
  _BgPainter(this.time, {this.themeIndex}) : super(repaint: Listenable.merge([time, rcThemeIndex]));

  static double _hash(double v) {
    final q = sin(v) * 43758.5453;
    return q - q.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final w = size.width, h = size.height, s = w / 340;
    final th = themeIndex == null ? rcTheme : kThemes[themeIndex!.clamp(0, kThemes.length - 1)];
    final acc = th.accent, acc2 = th.accent2;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final p = Paint();

    // dégradé
    p.shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [th.top, th.bottom]).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, p);

    // deux lueurs qui dérivent lentement
    void glow(Color c, double x, double y) {
      final o = Offset(w * x, h * y);
      p.shader = RadialGradient(colors: [c.withOpacity(0.22), c.withOpacity(0)]).createShader(Rect.fromCircle(center: o, radius: w * 0.8));
      canvas.drawRect(Offset.zero & size, p);
    }

    glow(acc, 0.25 + 0.15 * sin(t * 0.15), 0.15 + 0.1 * cos(t * 0.12));
    glow(acc2, 0.8 + 0.1 * cos(t * 0.1), 0.85 + 0.08 * sin(t * 0.13));
    p.shader = null;

    // motif
    Color a([double k = 1]) => acc.withOpacity((0.13 * k).clamp(0.0, 1.0));
    final st = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.0, s)
      ..color = a();
    final off = t * 8 * s;
    switch (th.motif) {
      case RcMotif.stars:
        for (var k = 0; k < 70; k++) {
          final x = _hash(k * 12.9898) * w;
          final y = ((_hash(k * 78.233) + t * 0.004 * (1 + k % 3)) % 1) * h;
          final al = 0.25 + 0.75 * sin(t * 0.8 + k * 2.7).abs();
          p.color = (k % 7 != 0 ? Colors.white : acc).withOpacity(al);
          final z = (k % 3 == 0 ? 2 : 1) * s * 1.3;
          canvas.drawRect(Rect.fromLTWH(x, y, z, z), p);
        }
      case RcMotif.grid:
        final g = 26 * s, o = off % g;
        for (var x = o - g; x < w; x += g) {
          canvas.drawLine(Offset(x, 0), Offset(x, h), st);
        }
        for (var y = o - g; y < h; y += g) {
          canvas.drawLine(Offset(0, y), Offset(w, y), st);
        }
        p.color = acc.withOpacity(0.22);
        final f = (t * 0.7).floor();
        for (var k = 0; k < 6; k++) {
          final i = ((k * 7 + f) * 13) % 12, j = ((k * 5 + f) * 7) % 26;
          canvas.drawRect(Rect.fromLTWH(i * g + o + 1, j * g + o + 1, g - 2, g - 2), p);
        }
      case RcMotif.pix:
        final g = 22 * s, o = (off * 0.6) % g;
        for (var i = 0; i < w / g + 1; i++) {
          for (var j = -1; j < h / g + 1; j++) {
            final v = sin(i * 1.7 + j * 2.3 + t * 0.6);
            if (v <= 0.6) continue;
            p.color = a((v - 0.6) * 1.6);
            canvas.drawRect(Rect.fromLTWH(i * g, j * g + o, g * 0.42, g * 0.42), p);
          }
        }
      case RcMotif.waves:
        for (var k = 0; k < 12; k++) {
          final y0 = k * h / 11;
          final path = Path()..moveTo(0, y0 + 7 * s * sin(t * 0.6 + k));
          for (double x = 4 * s; x <= w + 4 * s; x += 4 * s) {
            path.lineTo(x, y0 + 7 * s * sin(x / (40 * s) + t * 0.6 + k));
          }
          canvas.drawPath(path, st);
        }
      case RcMotif.diamonds:
        final g = 34 * s, o = (off * 0.5) % g, d = 6 * s;
        for (var i = -1; i < w / g + 1; i++) {
          for (var j = -1; j < h / g + 1; j++) {
            final x = i * g + (j.isOdd ? g / 2 : 0), y = j * g + o;
            st.color = a(0.5 + 0.5 * sin(t * 0.8 + i + j * 1.3));
            canvas.drawPath(
                Path()
                  ..moveTo(x, y - d)
                  ..lineTo(x + d, y)
                  ..lineTo(x, y + d)
                  ..lineTo(x - d, y)
                  ..close(),
                st);
          }
        }
      case RcMotif.lines:
        final g = 18 * s;
        for (var y = (off * 0.7) % g; y < h; y += g) {
          p.color = a(y / h * 0.9 + 0.1);
          canvas.drawRect(Rect.fromLTWH(0, y, w, max(1.0, 2 * s)), p);
        }
      case RcMotif.fire:
        for (var k = 0; k < 26; k++) {
          final c = Offset((sin(t * 0.25 + k * 2.1) * 0.5 + 0.5) * w, (cos(t * 0.2 + k * 1.7) * 0.5 + 0.5) * h);
          final al = 0.25 + 0.75 * sin(t * 1.4 + k).abs();
          p.shader = RadialGradient(colors: [acc2.withOpacity(0.9 * al), acc2.withOpacity(0)]).createShader(Rect.fromCircle(center: c, radius: 6 * s));
          canvas.drawCircle(c, 6 * s, p);
        }
        p.shader = null;
      case RcMotif.hex:
        final r = 16 * s, hh = r * sqrt(3), o = (off * 0.4) % hh;
        for (var i = -1; i < w / (r * 1.5) + 1; i++) {
          for (var j = -1; j < h / hh + 1; j++) {
            final x = i * r * 1.5, y = j * hh + (i.isOdd ? hh / 2 : 0) + o;
            st.color = a(0.45 + 0.55 * max(0.0, sin(t * 0.5 - i * 0.4 - j * 0.3)));
            final path = Path();
            for (var q = 0; q < 6; q++) {
              final an = q * pi / 3;
              final pt = Offset(x + r * 0.85 * cos(an), y + r * 0.85 * sin(an));
              if (q == 0) {
                path.moveTo(pt.dx, pt.dy);
              } else {
                path.lineTo(pt.dx, pt.dy);
              }
            }
            canvas.drawPath(path..close(), st);
          }
        }
      case RcMotif.bubbles:
        for (var k = 0; k < 20; k++) {
          final r = (4 + k % 5 * 4) * s;
          final x = ((k * 0.618) % 1) * w + sin(t * 0.5 + k) * 8 * s;
          final y = h + r - ((t * (6 + k % 4 * 3) * s + k * 61 * s) % (h + 2 * r));
          canvas.drawCircle(Offset(x, y), r, st);
        }
      case RcMotif.cross:
        final g = 30 * s, o = (off * 0.5) % g, d = 4 * s;
        for (var i = 0; i < w / g + 1; i++) {
          for (var j = -1; j < h / g + 1; j++) {
            final x = i * g, y = j * g + o;
            final on = sin(t * 0.9 + i * 1.9 + j * 1.1) > 0.75;
            st.color = on ? (j.isOdd ? acc2 : acc).withOpacity(0.55) : a();
            canvas.drawLine(Offset(x - d, y), Offset(x + d, y), st);
            canvas.drawLine(Offset(x, y - d), Offset(x, y + d), st);
          }
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BgPainter old) => false;
}
