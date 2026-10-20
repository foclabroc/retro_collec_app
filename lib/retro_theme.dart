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

enum RcMotif { invaders, blocks, dots, stripes, waves, crosses, checker, cards, bubbles, clouds, diamonds, scanlines }

/// Motifs animés (les autres sont fixes : le fond n'est redessiné qu'au changement de thème)
const kAnimatedMotifs = {RcMotif.invaders, RcMotif.blocks, RcMotif.waves, RcMotif.cards, RcMotif.bubbles, RcMotif.clouds};

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
      : bg = surface;
  String get name => t(fr, en);
  String get motifName => t(motifFr, motifEn);
}

const kThemes = <RcThemeData>[
  RcThemeData('Envahisseurs', 'Invaders', RcMotif.invaders, 'Envahisseurs', 'Invaders',
      top: Color(0xFF0F7A62), bottom: Color(0xFF0A4A3C), accent: Color(0xFFC6FF5A), accent2: Color(0xFFFFE04A), onAccent: Color(0xFF123000),
      panel: Color(0xED062C22), panel2: Color(0xFF135846), surface: Color(0xFF07352A), line: Color(0xFF2A9A7A)),
  RcThemeData('Blocs', 'Blocks', RcMotif.blocks, 'Blocs qui tombent', 'Falling blocks',
      top: Color(0xFF2457E0), bottom: Color(0xFF173AA6), accent: Color(0xFFFFD23F), accent2: Color(0xFFFF7AD0), onAccent: Color(0xFF2A1C00),
      panel: Color(0xED0C1E5A), panel2: Color(0xFF244299), surface: Color(0xFF0F256A), line: Color(0xFF4A78F0)),
  RcThemeData('Cerise', 'Cherry', RcMotif.dots, 'Pois', 'Dots',
      top: Color(0xFFE0306A), bottom: Color(0xFFA81848), accent: Color(0xFFFFE7A0), accent2: Color(0xFFFFFFFF), onAccent: Color(0xFF4A0A1C),
      panel: Color(0xED500820), panel2: Color(0xFF982E50), surface: Color(0xFF610D29), line: Color(0xFFFF6A98)),
  RcThemeData('Mandarine', 'Tangerine', RcMotif.stripes, 'Rayures', 'Stripes',
      top: Color(0xFFFF8A24), bottom: Color(0xFFE0520C), accent: Color(0xFFFFF2C0), accent2: Color(0xFFFFFFFF), onAccent: Color(0xFF4A1C00),
      panel: Color(0xED5A1E00), panel2: Color(0xFFA15A2A), surface: Color(0xFF6E2B04), line: Color(0xFFFFB070)),
  RcThemeData('Lagon', 'Lagoon', RcMotif.waves, 'Vagues', 'Waves',
      top: Color(0xFF16B4C4), bottom: Color(0xFF0A7C8E), accent: Color(0xFFFFF07A), accent2: Color(0xFFFFFFFF), onAccent: Color(0xFF2A2400),
      panel: Color(0xED00323E), panel2: Color(0xFF217682), surface: Color(0xFF03424E), line: Color(0xFF5AD8E4)),
  RcThemeData('Raisin', 'Grape', RcMotif.crosses, 'Croix', 'Crosses',
      top: Color(0xFF8A44E6), bottom: Color(0xFF5A24B0), accent: Color(0xFFFFD1F0), accent2: Color(0xFF7AFFD8), onAccent: Color(0xFF3A0A50),
      panel: Color(0xED280A50), panel2: Color(0xFF5F3699), surface: Color(0xFF341162), line: Color(0xFFB07AFF)),
  RcThemeData('Citron', 'Lemon', RcMotif.checker, 'Damier', 'Checker',
      top: Color(0xFFF6CC22), bottom: Color(0xFFE09A0A), accent: Color(0xFFFFF07A), accent2: Color(0xFFFFFFFF), onAccent: Color(0xFF3A2000),
      panel: Color(0xED462800), panel2: Color(0xFF94752A), surface: Color(0xFF5B3C04), line: Color(0xFFFFE070)),
  RcThemeData('Menthe', 'Mint', RcMotif.cards, 'Esquisses de cartes', 'Card sketches',
      top: Color(0xFF2CCC84), bottom: Color(0xFF169A5C), accent: Color(0xFFFFFFFF), accent2: Color(0xFFFFEF7A), onAccent: Color(0xFF0A3A22),
      panel: Color(0xED043820), panel2: Color(0xFF2B8158), surface: Color(0xFF094A2C), line: Color(0xFF6AE8AA)),
  RcThemeData('Corail', 'Coral', RcMotif.bubbles, 'Bulles', 'Bubbles',
      top: Color(0xFFFF6A5E), bottom: Color(0xFFD8384A), accent: Color(0xFFFFF2B0), accent2: Color(0xFFFFFFFF), onAccent: Color(0xFF4A0A10),
      panel: Color(0xED5A0E18), panel2: Color(0xFFA14647), surface: Color(0xFF6E1920), line: Color(0xFFFF9A90)),
  RcThemeData('Ciel', 'Sky', RcMotif.clouds, 'Nuages pixel', 'Pixel clouds',
      top: Color(0xFF46A8FF), bottom: Color(0xFF2A70E0), accent: Color(0xFFFFE04A), accent2: Color(0xFFFFFFFF), onAccent: Color(0xFF2A2000),
      panel: Color(0xED0A2864), panel2: Color(0xFF3868A7), surface: Color(0xFF113777), line: Color(0xFF80C4FF)),
  RcThemeData('Bonbon', 'Candy', RcMotif.diamonds, 'Losanges', 'Diamonds',
      top: Color(0xFFFF5AB8), bottom: Color(0xFFC42A88), accent: Color(0xFFFFF2A0), accent2: Color(0xFF7AE8FF), onAccent: Color(0xFF4A0A30),
      panel: Color(0xED500834), panel2: Color(0xFF9B3C75), surface: Color(0xFF651244), line: Color(0xFFFF8AD0)),
  RcThemeData('Rétro gris', 'Retro grey', RcMotif.scanlines, 'Lignes d\'écran', 'Scanlines',
      top: Color(0xFF8A8EA0), bottom: Color(0xFF5E6276), accent: Color(0xFFFF4F6A), accent2: Color(0xFFFFFFFF), onAccent: Color(0xFFFFFFFF),
      panel: Color(0xED1E202C), panel2: Color(0xFF5A5C6A), surface: Color(0xFF2B2D3A), line: Color(0xFFB0B4C4)),
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
      backgroundColor: th.bg.withOpacity(0.93),
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
        backgroundColor: navy.withOpacity(0.93),
        side: BorderSide(color: line, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: const Color(0xFF8FD3FF))),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: th.bg.withOpacity(0.93),
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
      backgroundColor: navy.withOpacity(0.93),
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
    _ticker = createTicker((d) {
      if (kAnimatedMotifs.contains(rcTheme.motif)) time.value = d.inMicroseconds / 1e6;
    })..start();
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
    _ticker = createTicker((d) {
      if (kAnimatedMotifs.contains(kThemes[widget.index.clamp(0, kThemes.length - 1)].motif)) time.value = 3 + d.inMicroseconds / 1e6;
    })..start();
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

  // sprites pixel
  static const _inv = ['00100000100', '00010001000', '00111111100', '01101110110', '11111111111', '10111111101', '10100000101', '00011011000'];
  static const _tetro = [
    [[0, 0], [1, 0], [2, 0], [3, 0]], [[0, 0], [1, 0], [0, 1], [1, 1]], [[0, 0], [1, 0], [2, 0], [1, 1]], [[0, 0], [0, 1], [1, 1], [2, 1]],
    [[2, 0], [0, 1], [1, 1], [2, 1]], [[1, 0], [2, 0], [0, 1], [1, 1]], [[0, 0], [1, 0], [1, 1], [2, 1]],
  ];
  static const _blockCols = [Color(0xFFFFD23F), Color(0xFFFF7AD0), Color(0xFF5CE08A), Colors.white, Color(0xFFFF9F43), Color(0xFF4FE0FF), Color(0xFFC9A2FF)];

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final w = size.width, h = size.height, s = w / 360;
    final th = themeIndex == null ? rcTheme : kThemes[themeIndex!.clamp(0, kThemes.length - 1)];
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final p = Paint();

    // dégradé
    p.shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [th.top, th.bottom]).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, p);
    p.shader = null;

    final white = Colors.white;
    final st = Paint()..style = PaintingStyle.stroke;
    double rnd(int k, int salt) => _hash(k * 12.9898 + salt * 78.233);

    switch (th.motif) {
      case RcMotif.invaders:
        final px = 3 * s, sw = 11 * px, gap = 18 * s, rowH = 8 * px + 26 * s;
        final cols = (w / (sw + gap)).floor();
        final off = sin(t * 0.4) * 14 * s, frame = t.floor() % 2, drop = (t * 4 * s) % rowH;
        for (var row = -1; row < h / rowH + 1; row++) {
          p.color = (row % 3 == 0 ? th.accent2 : th.accent).withOpacity(0.25);
          for (var col = 0; col < cols; col++) {
            final x = col * (sw + gap) + gap / 2 + off + (row.isOdd ? 12 * s : 0), y = row * rowH + drop;
            for (var yy = 0; yy < 8; yy++) {
              for (var xx = 0; xx < 11; xx++) {
                final b = (frame == 1 && yy >= 6) ? _inv[yy][10 - xx] : _inv[yy][xx];
                if (b == '1') canvas.drawRect(Rect.fromLTWH(x + xx * px, y + yy * px, px, px), p);
              }
            }
          }
        }
      case RcMotif.blocks:
        final cs = 18 * s;
        for (var i = 0; i < 12; i++) {
          final k = (rnd(i, 1) * 7).floor() % 7, sp = (8 + rnd(i, 2) * 10) * s;
          final x = (rnd(i, 3) * (w / cs)).floor() * cs;
          final y = ((t * sp + rnd(i, 4) * h * 1.4) % (h + 80 * s)) - 60 * s;
          final yy = (y / cs).floor() * cs;
          p.color = _blockCols[k].withOpacity(0.3);
          for (final d in _tetro[k]) {
            canvas.drawRect(Rect.fromLTWH(x + d[0] * cs + 1, yy + d[1] * cs + 1, cs - 2, cs - 2), p);
          }
        }
      case RcMotif.dots:
        final g = 22 * s, z = 4 * s;
        p.color = white.withOpacity(0.18);
        for (var j = 0; j * g < h + g; j++) {
          for (var x = j.isOdd ? g / 2 : 0.0; x < w + g; x += g) {
            canvas.drawRect(Rect.fromCenter(center: Offset(x, j * g), width: z, height: z), p);
          }
        }
      case RcMotif.stripes:
        st
          ..strokeWidth = 10 * s
          ..color = white.withOpacity(0.14);
        for (var x = -h; x < w + h; x += 36 * s) {
          canvas.drawLine(Offset(x, 0), Offset(x + h, h), st);
        }
      case RcMotif.waves:
        st
          ..strokeWidth = 3 * s
          ..color = white.withOpacity(0.16);
        for (var y = 20 * s; y < h; y += 34 * s) {
          final path = Path();
          for (double x = 0; x <= w; x += 6 * s) {
            final yy = y + sin(x / s * 0.04 + t * 0.6 + y) * 6 * s;
            x == 0 ? path.moveTo(x, yy) : path.lineTo(x, yy);
          }
          canvas.drawPath(path, st);
        }
      case RcMotif.crosses:
        final g = 28 * s;
        p.color = white.withOpacity(0.12);
        for (var j = 0; j * g < h + g; j++) {
          for (var x = j.isOdd ? g / 2 : 0.0; x < w + g; x += g) {
            final y = j * g;
            canvas.drawRect(Rect.fromLTWH(x - s, y - 6 * s, 2 * s, 12 * s), p);
            canvas.drawRect(Rect.fromLTWH(x - 6 * s, y - s, 12 * s, 2 * s), p);
          }
        }
      case RcMotif.checker:
        final g = 24 * s;
        p.color = white.withOpacity(0.18);
        for (var j = 0; j * g < h; j++) {
          for (var x = j.isOdd ? g : 0.0; x < w; x += g * 2) {
            canvas.drawRect(Rect.fromLTWH(x, j * g, g, g), p);
          }
        }
      case RcMotif.cards:
        // esquisses de cartes qui montent lentement
        final cw = 30 * s, ch = 40 * s, gx = 22 * s, gy = 22 * s, rowH = ch + gy, rise = (t * 6 * s) % rowH;
        final cols = (w / (cw + gx)).ceil() + 1;
        st
          ..strokeWidth = 2 * s
          ..color = white.withOpacity(0.2);
        p.color = white.withOpacity(0.12);
        for (var row = -1; row < h / rowH + 2; row++) {
          for (var col = -1; col < cols; col++) {
            final cx = col * (cw + gx) + gx / 2 + (row.isOdd ? (cw + gx) / 2 : 0) + cw / 2;
            final cy = row * rowH - rise + ch / 2;
            canvas.save();
            canvas.translate(cx, cy);
            canvas.rotate((((row * 7 + col * 3) % 5) - 2) * 0.06);
            final r = Rect.fromCenter(center: Offset.zero, width: cw, height: ch);
            canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(4 * s)), st);
            canvas.drawRect(Rect.fromLTWH(r.left + 4 * s, r.top + 4 * s, cw - 8 * s, ch * 0.55), p);
            canvas.drawRect(Rect.fromLTWH(r.left + 4 * s, r.top + ch * 0.55 + 8 * s, cw * 0.6, 2.5 * s), p);
            canvas.drawRect(Rect.fromLTWH(r.left + 4 * s, r.top + ch * 0.55 + 13 * s, cw * 0.4, 2.5 * s), p);
            canvas.restore();
          }
        }
      case RcMotif.bubbles:
        st
          ..strokeWidth = 2 * s
          ..color = white.withOpacity(0.22);
        p.color = white.withOpacity(0.25);
        for (var i = 0; i < 18; i++) {
          final r = (8 + rnd(i, 1) * 22) * s, sp = (6 + rnd(i, 2) * 10) * s;
          final x = rnd(i, 3) * w + sin(t * 0.5 + i) * 10 * s;
          final y = h + r - ((t * sp + rnd(i, 4) * h * 1.4) % (h + r * 2));
          canvas.drawCircle(Offset(x, y), r, st);
          canvas.drawRect(Rect.fromLTWH(x - r * 0.45, y - r * 0.5, 4 * s, 4 * s), p);
        }
      case RcMotif.clouds:
        final q = 6 * s;
        p.color = white.withOpacity(0.35);
        for (var i = 0; i < 7; i++) {
          final n = 4 + (rnd(i, 1) * 4).floor();
          final x = ((rnd(i, 2) * w * 1.5 + t * (5 + i * 2) * s) % (w + 160 * s)) - 80 * s;
          final y = 30 * s + rnd(i, 3) * (h - 80 * s);
          final X = (x / q).round() * q, Y = (y / q).round() * q;
          canvas.drawRect(Rect.fromLTWH(X, Y, n * q * 3, q * 3), p);
          canvas.drawRect(Rect.fromLTWH(X + q * 2, Y - q * 2, n * q * 1.6, q * 2), p);
        }
      case RcMotif.diamonds:
        final g = 30 * s, d = 9 * s;
        p.color = white.withOpacity(0.14);
        for (var j = 0; j * g < h + g; j++) {
          for (var x = j.isOdd ? g / 2 : 0.0; x < w + g; x += g) {
            final y = j * g;
            canvas.drawPath(Path()..moveTo(x, y - d)..lineTo(x + d, y)..lineTo(x, y + d)..lineTo(x - d, y)..close(), p);
          }
        }
      case RcMotif.scanlines:
        p.color = Colors.black.withOpacity(0.1);
        for (var y = 0.0; y < h; y += 4 * s) {
          canvas.drawRect(Rect.fromLTWH(0, y, w, 2 * s), p);
        }
        p.color = white.withOpacity(0.12);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.12, w, 6 * s), p);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.12 + 12 * s, w, 3 * s), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BgPainter old) => false;
}
