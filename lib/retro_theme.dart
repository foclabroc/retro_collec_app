import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog.dart';
import 'game.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Thème de l'appli : fond animé épuré (dégradé, lueurs, motif discret),
// couleur d'accent par thème et police pixel pour les titres.
// ═══════════════════════════════════════════════════════════════════════════

// ─── Thèmes d'interface ─────────────────────────────────────────────────────
// Thèmes épurés : un dégradé sombre, deux lueurs de la couleur du thème qui
// dérivent lentement et un motif discret qui défile (étoiles, grille, vagues…).

enum RcMotif { invaders, cards, pads, carts, maze, hearts, coins, title, circuit, bricks, sticks, synth, wall }

/// Motifs animés (les autres sont fixes : le fond n'est redessiné qu'au changement de thème)
/// Visibilité des motifs (0,6 = choisi sur la maquette du 21/10)
const _kMotif = 0.6;

const kAnimatedMotifs = {RcMotif.invaders, RcMotif.cards};

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
      top: Color(0xFF0F5948), bottom: Color(0xFF0A362C), accent: Color(0xFFC6FF5A), accent2: Color(0xFFFFE04A), onAccent: Color(0xFF123000),
      panel: Color(0xCC07261E), panel2: Color(0xFF135846), surface: Color(0xFF093329), line: Color(0xFF2A9A7A)),
  RcThemeData('Menthe', 'Mint', RcMotif.cards, 'Esquisses de cartes', 'Card sketches',
      top: Color(0xFF289564), bottom: Color(0xFF167046), accent: Color(0xFFFFFFFF), accent2: Color(0xFFFFEF7A), onAccent: Color(0xFF0A3A22),
      panel: Color(0xB806301D), panel2: Color(0xFF2B8158), surface: Color(0xFF0C472C), line: Color(0xFF6AE8AA)),
  RcThemeData('Manettes', 'Pads', RcMotif.pads, 'Manettes', 'Pads',
      top: Color(0xFF8A3A30), bottom: Color(0xFF5A2420), accent: Color(0xFFFFD9A0), accent2: Color(0xFFFFFFFF), onAccent: Color(0xFF3A1408),
      panel: Color(0xBD2E0C08), panel2: Color(0xFF904036), surface: Color(0xFF4A1A14), line: Color(0xFFC0705E)),
  RcThemeData('Cartouches', 'Cartridges', RcMotif.carts, 'Cartouches', 'Cartridges',
      top: Color(0xFF4A5670), bottom: Color(0xFF323B50), accent: Color(0xFFFFC94A), accent2: Color(0xFF9FE0FF), onAccent: Color(0xFF2A1C00),
      panel: Color(0xBD161B28), panel2: Color(0xFF525E79), surface: Color(0xFF252B3B), line: Color(0xFF8A98B8)),
  RcThemeData('Pac-gommes', 'Pellets', RcMotif.maze, 'Labyrinthe', 'Maze',
      top: Color(0xFF1B2A6B), bottom: Color(0xFF101A48), accent: Color(0xFFFFE04A), accent2: Color(0xFFFF8AB0), onAccent: Color(0xFF2A2000),
      panel: Color(0xC20A1036), panel2: Color(0xFF213177), surface: Color(0xFF121C4E), line: Color(0xFF4A64D0)),
  RcThemeData('Cœurs', 'Hearts', RcMotif.hearts, 'Cœurs pixel', 'Pixel hearts',
      top: Color(0xFF7A2440), bottom: Color(0xFF4E1428), accent: Color(0xFFFFB0C4), accent2: Color(0xFFFFFFFF), onAccent: Color(0xFF4A0A1C),
      panel: Color(0xBD3A0A1C), panel2: Color(0xFF852C49), surface: Color(0xFF4A1226), line: Color(0xFFD86A8A)),
  RcThemeData('Pièces', 'Coins', RcMotif.coins, 'Pièces d\'or', 'Gold coins',
      top: Color(0xFF7A5A1A), bottom: Color(0xFF4E3A0E), accent: Color(0xFFFFE07A), accent2: Color(0xFFFFFFFF), onAccent: Color(0xFF3A2400),
      panel: Color(0xBD3A2806), panel2: Color(0xFF856422), surface: Color(0xFF4A3410), line: Color(0xFFD8B060)),
  RcThemeData('Nuit rétro', 'Retro night', RcMotif.title, 'Écran titre', 'Title screen',
      top: Color(0xFF161640), bottom: Color(0xFF241038), accent: Color(0xFF3DD9FF), accent2: Color(0xFFFF4FD8), onAccent: Color(0xFF06303D),
      panel: Color(0xC20C0A26), panel2: Color(0xFF242052), surface: Color(0xFF18143A), line: Color(0xFF8A6AD8)),
  RcThemeData('Circuit', 'Circuit', RcMotif.circuit, 'Circuit imprimé', 'Circuit board',
      top: Color(0xFF1A5A3A), bottom: Color(0xFF0E3A24), accent: Color(0xFFB8FF8A), accent2: Color(0xFFFFD86A), onAccent: Color(0xFF0A3000),
      panel: Color(0xC2062A18), panel2: Color(0xFF206442), surface: Color(0xFF0E3A26), line: Color(0xFF4AB07A)),
  RcThemeData('Casse-briques', 'Breakout', RcMotif.bricks, 'Mur de briques', 'Brick wall',
      top: Color(0xFF8A4A2A), bottom: Color(0xFF5A2E18), accent: Color(0xFFFFE2B0), accent2: Color(0xFF7AE0FF), onAccent: Color(0xFF3A1A00),
      panel: Color(0xBD3A1A0A), panel2: Color(0xFF925130), surface: Color(0xFF4E2614), line: Color(0xFFD0885E)),
  RcThemeData('Joysticks', 'Joysticks', RcMotif.sticks, 'Sticks d\'arcade', 'Arcade sticks',
      top: Color(0xFF5A3088), bottom: Color(0xFF3A1C5E), accent: Color(0xFFFFD1F0), accent2: Color(0xFF7AFFD8), onAccent: Color(0xFF3A0A50),
      panel: Color(0xBD220A40), panel2: Color(0xFF623992), surface: Color(0xFF2E1450), line: Color(0xFFA07AD8)),
  RcThemeData('Synthwave', 'Synthwave', RcMotif.synth, 'Grille néon', 'Neon grid',
      top: Color(0xFF4A1A4E), bottom: Color(0xFF2A0E36), accent: Color(0xFFFF7AD0), accent2: Color(0xFFFFC24A), onAccent: Color(0xFF3A0A30),
      panel: Color(0xC21E0824), panel2: Color(0xFF58225C), surface: Color(0xFF2E0E36), line: Color(0xFFC060C0)),
  // fond = mur des jaquettes du joueur (CardWall), le dégradé sert de voile sombre
  RcThemeData('Mur de cartes', 'Card wall', RcMotif.wall, 'Mes jaquettes', 'My box arts',
      top: Color(0xFF2A2440), bottom: Color(0xFF18142A), accent: Color(0xFFFFD23F), accent2: Color(0xFF3DD9FF), onAccent: Color(0xFF2A1C00),
      panel: Color(0xC2120E20), panel2: Color(0xFF3A3458), surface: Color(0xFF1C1830), line: Color(0xFF8A80C0)),
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
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: rcThemeIndex,
        builder: (_, __, ___) => Stack(fit: StackFit.expand, children: [
          RepaintBoundary(child: CustomPaint(painter: _BgPainter(time), child: const SizedBox.expand())),
          if (rcTheme.motif == RcMotif.wall) RepaintBoundary(child: CardWall(rcTheme)),
        ]),
      );
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
            child: RepaintBoundary(
              child: Stack(fit: StackFit.expand, children: [
                CustomPaint(painter: _BgPainter(time, themeIndex: widget.index)),
                if (kThemes[widget.index.clamp(0, kThemes.length - 1)].motif == RcMotif.wall) CardWall(kThemes[widget.index.clamp(0, kThemes.length - 1)]),
              ]),
            ),
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
  static const _pad = ['0111111111110', '1101111110111', '1000111101011', '1101111110111', '1111100111111', '0110000001100'];
  static const _cart = ['111111111', '100000001', '101111101', '101111101', '101111101', '100000001', '111111111', '110101011', '110101011', '011111110'];
  static const _heart = ['0110110', '1111111', '1111111', '0111110', '0011100', '0001000'];
  static const _stick = ['0011100', '0111110', '0111110', '0011100', '0001000', '0001000', '0001000', '1111111', '1111111', '1111111'];

  static void _sprite(Canvas c, List<String> sp, double x, double y, double px, Paint p) {
    for (var yy = 0; yy < sp.length; yy++) {
      for (var xx = 0; xx < sp[yy].length; xx++) {
        if (sp[yy][xx] == '1') c.drawRect(Rect.fromLTWH(x + xx * px, y + yy * px, px, px), p);
      }
    }
  }

  /// Pavage en quinconce (une ligne sur deux décalée de [stagger])
  static void _tile(double w, double h, double cw, double ch, double stagger, void Function(double x, double y) f) {
    for (var j = -1; j * ch < h + ch; j++) {
      for (var i = -1; i * cw < w + cw; i++) {
        f(i * cw + (j.isOdd ? stagger : 0), j * ch);
      }
    }
  }

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
          p.color = (row % 3 == 0 ? th.accent2 : th.accent).withOpacity(0.25 * _kMotif);
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
      case RcMotif.cards:
        // esquisses de cartes qui montent lentement
        final cw = 30 * s, ch = 40 * s, gx = 22 * s, gy = 22 * s, rowH = ch + gy, rise = (t * 6 * s) % rowH;
        final cols = (w / (cw + gx)).ceil() + 1;
        st
          ..strokeWidth = 2 * s
          ..color = white.withOpacity(0.2 * _kMotif);
        p.color = white.withOpacity(0.12 * _kMotif);
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
      case RcMotif.pads:
        p.color = white.withOpacity(0.16 * _kMotif);
        _tile(w, h, 72 * s, 52 * s, 36 * s, (x, y) => _sprite(canvas, _pad, x + 10 * s, y + 12 * s, 3 * s, p));
      case RcMotif.carts:
        p.color = white.withOpacity(0.15 * _kMotif);
        _tile(w, h, 48 * s, 58 * s, 24 * s, (x, y) => _sprite(canvas, _cart, x + 10 * s, y + 10 * s, 3 * s, p));
      case RcMotif.maze:
        // couloirs de labyrinthe + rangées de gommes
        final g = 60 * s;
        st
          ..strokeWidth = 3 * s
          ..color = white.withOpacity(0.2 * _kMotif);
        for (var j = 0; j * g < h + g; j++) {
          for (var i = 0; i * g < w + g; i++) {
            final x = i * g + 8 * s, y = j * g + 8 * s;
            final r = rnd(i * 7 + j * 13, 1) < 0.5 ? Rect.fromLTWH(x, y, g - 16 * s, g / 2 - 10 * s) : Rect.fromLTWH(x, y, g / 2 - 10 * s, g - 16 * s);
            canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(6 * s)), st);
          }
        }
        p.color = white.withOpacity(0.28 * _kMotif);
        for (var j = 0; j * g < h + g; j++) {
          for (var i = 0; i * g < w; i++) {
            final y = j * g + g - 4 * s;
            for (var d = 0; d < 4; d++) {
              final x = i * g + d * g / 4 + 6 * s;
              if ((i + j * 3 + d) % 11 == 0) {
                canvas.drawCircle(Offset(x, y), 4 * s, p);
              } else {
                canvas.drawRect(Rect.fromCenter(center: Offset(x, y), width: 3 * s, height: 3 * s), p);
              }
            }
          }
        }
      case RcMotif.hearts:
        p.color = white.withOpacity(0.17 * _kMotif);
        _tile(w, h, 40 * s, 40 * s, 20 * s, (x, y) => _sprite(canvas, _heart, x + 10 * s, y + 12 * s, 3 * s, p));
      case RcMotif.coins:
        st
          ..strokeWidth = 2.5 * s
          ..color = white.withOpacity(0.2 * _kMotif);
        p.color = white.withOpacity(0.16 * _kMotif);
        _tile(w, h, 44 * s, 44 * s, 22 * s, (x, y) {
          final c = Offset(x + 22 * s, y + 22 * s);
          canvas.drawCircle(c, 11 * s, st);
          canvas.drawRect(Rect.fromCenter(center: c, width: 4 * s, height: 12 * s), p);
        });
      case RcMotif.title:
        // comme l'écran titre : étoiles pixel + sol quadrillé néon (fixe)
        for (var i = 0; i < 70; i++) {
          final z = (rnd(i, 3) < 0.2 ? 2.4 : 1.6) * s;
          p.color = white.withOpacity((0.3 + 0.6 * rnd(i, 4)) * _kMotif);
          canvas.drawRect(Rect.fromLTWH((rnd(i, 1) * w).roundToDouble(), (rnd(i, 2) * h * 0.72).roundToDouble(), z, z), p);
        }
        final top = h * 0.68, fh = h - top, floor = Rect.fromLTWH(0, top, w, fh), pk = th.accent2;
        canvas.drawRect(
            floor,
            Paint()
              ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [pk.withOpacity(0), pk.withOpacity(0.18 * _kMotif)])
                  .createShader(floor));
        st.strokeWidth = 1.2 * s;
        for (var i = 1; i <= 12; i++) {
          final z = i / 12, y = top + fh * pow(z, 2.2);
          st.color = pk.withOpacity(0.45 * z * _kMotif);
          canvas.drawLine(Offset(0, y), Offset(w, y), st);
        }
        st.color = pk.withOpacity(0.33 * _kMotif);
        for (var i = -8; i <= 8; i++) {
          canvas.drawLine(Offset(w / 2 + i * w * 0.04, top), Offset(w / 2 + i * w * 0.32, h), st);
        }
      case RcMotif.circuit:
        final g = 36 * s;
        st
          ..strokeWidth = 2.5 * s
          ..color = white.withOpacity(0.2 * _kMotif);
        p.color = white.withOpacity(0.24 * _kMotif);
        for (var i = 0; i < 26; i++) {
          var x = (rnd(i, 1) * w / g).floor() * g, y = (rnd(i, 2) * h / g).floor() * g;
          final path = Path()..moveTo(x, y);
          final n = 2 + (rnd(i, 3) * 3).floor();
          for (var k = 0; k < n; k++) {
            final d = (rnd(i, 4 + k) * 3).floor();
            if (d == 0) {
              x += g;
            } else if (d == 1) {
              y += g;
            } else {
              x += g * 0.6;
              y += g * 0.6;
            }
            path.lineTo(x, y);
          }
          canvas.drawPath(path, st);
          canvas.drawCircle(Offset(x, y), 4 * s, p);
        }
      case RcMotif.bricks:
        final bw = 44 * s, bh = 20 * s;
        st
          ..strokeWidth = 2 * s
          ..color = white.withOpacity(0.18 * _kMotif);
        _tile(w, h, bw, bh, bw / 2, (x, y) => canvas.drawRect(Rect.fromLTWH(x + 2 * s, y + 2 * s, bw - 4 * s, bh - 4 * s), st));
      case RcMotif.sticks:
        p.color = white.withOpacity(0.16 * _kMotif);
        _tile(w, h, 50 * s, 56 * s, 25 * s, (x, y) => _sprite(canvas, _stick, x + 14 * s, y + 10 * s, 3 * s, p));
      case RcMotif.synth:
        // soleil rayé + grille néon en perspective
        final hz = h * 0.55, cx = w / 2, sr = 70 * s;
        p.color = th.accent2.withOpacity(0.29 * _kMotif);
        for (var b = 0; b < 7; b++) {
          canvas.save();
          canvas.clipRect(Rect.fromLTWH(0, hz - sr + b * sr / 7, w, sr / 7 * 0.62));
          canvas.drawArc(Rect.fromCircle(center: Offset(cx, hz), radius: sr), pi, pi, true, p);
          canvas.restore();
        }
        st
          ..strokeWidth = 2 * s
          ..color = th.accent.withOpacity(0.3 * _kMotif);
        for (var k = 0; k < 12; k++) {
          final y = hz + pow(k / 12, 1.8) * (h - hz);
          canvas.drawLine(Offset(0, y), Offset(w, y), st);
        }
        for (var k = -10; k <= 10; k++) {
          canvas.drawLine(Offset(cx + k * 14 * s, hz), Offset(cx + k * 90 * s, h), st);
        }
      case RcMotif.wall:
        break; // dessiné par CardWall par-dessus le dégradé
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BgPainter old) => false;
}

/// Thème « Mur de cartes » : les jaquettes du joueur (catalogue au hasard s'il
/// en a peu) en mur incliné qui glisse lentement en diagonale, sous un voile
/// sombre aux couleurs du thème.
class CardWall extends StatefulWidget {
  final RcThemeData th;
  const CardWall(this.th, {super.key});
  @override
  State<CardWall> createState() => _CardWallState();
}

class _CardWallState extends State<CardWall> with SingleTickerProviderStateMixin {
  static const _n = 8; // motif de 8 × 8 jaquettes qui se répète
  final _t = ValueNotifier<double>(0);
  final _loaded = ValueNotifier<int>(0);
  late final Ticker _ticker;
  List<RcCard> _cards = [];
  List<ui.Image?> _imgs = [];

  @override
  void initState() {
    super.initState();
    _pick();
    _ticker = createTicker((d) {
      if (_cards.isEmpty && Catalog.loaded) _pick();
      _t.value = d.inMicroseconds / 1e6;
      _flipTick(_t.value);
    })..start();
  }

  // ── cartes qui se retournent au passage ──
  static const _flipDur = 1.1; // durée d'un retournement (s)
  final _rnd = Random();
  final _flips = <(int, int), (double, int)>{}; // case (ligne, colonne) → (début, nouvelle face)
  final _face = <(int, int), int>{}; // faces déjà changées par un retournement
  List<(int, int)> _seen = []; // cases bien visibles à la dernière image
  double _nextFlip = 2;

  int faceOf((int, int) k) => _face[k] ?? (((k.$1 % _n) * _n + k.$2 % _n) % max(1, _imgs.length));

  void _flipTick(double t) {
    _flips.removeWhere((k, v) {
      if (t - v.$1 < _flipDur) return false;
      _face[k] = v.$2;
      return true;
    });
    if (t < _nextFlip || _imgs.length < 2 || _seen.isEmpty) return;
    _nextFlip = t + 2.5 + _rnd.nextDouble() * 2.5; // une ou deux cartes toutes les 2,5 à 5 s
    final seen = _seen.toSet();
    _face.removeWhere((k, _) => !seen.contains(k)); // oublie les cases sorties de l'écran
    final count = _rnd.nextDouble() < 0.35 ? 2 : 1;
    for (var i = 0; i < count; i++) {
      final k = _seen[_rnd.nextInt(_seen.length)];
      if (_flips.containsKey(k)) continue;
      final cur = faceOf(k);
      var nf = _rnd.nextInt(_imgs.length);
      if (nf == cur) nf = (nf + 1) % _imgs.length;
      _flips[k] = (t, nf);
    }
  }

  void _pick() {
    final rnd = Random();
    final mine = <RcCard>[
      for (final id in Game.i.owned.keys)
        if (Catalog.cards[id] case final c?) c
    ]..shuffle(rnd);
    final out = mine.take(_n * _n).toList();
    if (out.length < _n * _n) {
      final ids = {for (final c in out) c.id};
      final rest = Catalog.baseCards.where((c) => !ids.contains(c.id)).toList()..shuffle(rnd);
      out.addAll(rest.take(_n * _n - out.length));
    }
    if (out.isEmpty) return;
    _cards = out;
    _imgs = List<ui.Image?>.filled(out.length, null);
    for (var i = 0; i < out.length; i++) {
      final stream = Catalog.image(out[i]).resolve(ImageConfiguration.empty);
      late final ImageStreamListener l;
      l = ImageStreamListener((info, _) {
        stream.removeListener(l);
        if (!mounted) return info.dispose();
        _imgs[i]?.dispose();
        _imgs[i] = _frame(info.image, out[i].rarity);
        info.dispose();
        _loaded.value++;
      }, onError: (_, __) => stream.removeListener(l));
      stream.addListener(l);
    }
  }

  /// Carte dessinée une fois pour toutes (cadre de la rareté + jaquette),
  /// sur le modèle de CardView mais sans texte : le mur ne fait ensuite que la recopier.
  static const _fw = 160.0, _fh = 223.0;
  static ui.Image _frame(ui.Image cover, int rarity) {
    final r = rarity.clamp(0, kRarityColor.length - 1);
    final gem = kRarityColor[r];
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    const w = _fw, h = _fh, rad = w * 0.075, fw = w * 0.045;
    final all = const Rect.fromLTWH(0, 0, w, h);
    c.drawRRect(
        RRect.fromRectAndRadius(all, const Radius.circular(rad)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kRarityLight[r], kRarityColor[r], kRarityDark[r], kRarityColor[r], kRarityLight[r]],
          ).createShader(all));
    final inner = all.deflate(fw);
    c.save();
    c.clipRRect(RRect.fromRectAndRadius(inner, Radius.circular(rad - fw * 0.7)));
    c.drawRect(inner, Paint()..color = const Color(0xFF11131D));
    // bandeau du haut (étiquette de cartouche)
    final band = Rect.fromLTWH(inner.left, inner.top, inner.width, w * 0.11);
    c.drawRect(band, Paint()..shader = LinearGradient(colors: [gem.withOpacity(0.55), gem.withOpacity(0.08)]).createShader(band));
    c.drawRect(Rect.fromLTWH(band.right - w * 0.2, band.top, w * 0.2, band.height), Paint()..color = gem);
    // fenêtre de la jaquette
    final win = Rect.fromLTRB(inner.left + w * 0.03, band.bottom + w * 0.03, inner.right - w * 0.03, inner.bottom - w * 0.16);
    final winR = RRect.fromRectAndRadius(win, const Radius.circular(w * 0.025));
    c.drawRRect(winR, Paint()..color = kRarityDark[r]);
    final iw = cover.width.toDouble(), ih = cover.height.toDouble();
    final box = win.deflate(w * 0.015);
    final k = min(box.width / iw, box.height / ih);
    final dst = Rect.fromCenter(center: box.center, width: iw * k, height: ih * k);
    c.drawImageRect(cover, Rect.fromLTWH(0, 0, iw, ih), dst, Paint()..filterQuality = FilterQuality.medium);
    c.drawRRect(
        winR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.008
          ..color = gem.withOpacity(0.55));
    // titre suggéré (deux traits)
    final tp = Paint()..color = Colors.white.withOpacity(0.35);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(win.left, win.bottom + w * 0.045, inner.width * 0.62, w * 0.035), const Radius.circular(2)), tp);
    tp.color = Colors.white.withOpacity(0.18);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(win.left, win.bottom + w * 0.1, inner.width * 0.4, w * 0.028), const Radius.circular(2)), tp);
    c.restore();
    final pic = rec.endRecording();
    final img = pic.toImageSync(_fw.toInt(), _fh.toInt());
    pic.dispose();
    return img;
  }

  @override
  void dispose() {
    _ticker.dispose();
    for (final im in _imgs) {
      im?.dispose();
    }
    _t.dispose();
    _loaded.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _WallPainter(this), child: const SizedBox.expand());
}

class _WallPainter extends CustomPainter {
  final _CardWallState st;
  _WallPainter(this.st) : super(repaint: Listenable.merge([st._t, st._loaded]));

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, s = w / 360, th = st.widget.th;
    final imgs = st._imgs, n = _CardWallState._n;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (imgs.isNotEmpty) {
      final cw = 44 * s, ch = 44 * s * _CardWallState._fh / _CardWallState._fw, sx = cw + 8 * s, sy = ch + 8 * s;
      final t = st._t.value, ox = t * 9 * s, oy = t * 6 * s; // décalage continu : les cases gardent leur identité
      final r = sqrt(w * w + h * h) / 2 + sy;
      canvas.translate(w / 2, h / 2);
      canvas.rotate(-0.18);
      final p = Paint()..filterQuality = FilterQuality.low;
      final empty = Paint()..color = th.panel2.withOpacity(0.6);
      final seen = <(int, int)>[];
      for (var row = ((oy - r) / sy).floor() - 1; row <= ((oy + r) / sy).ceil(); row++) {
        final y = row * sy - oy, shift = row.isOdd ? sx / 2 : 0.0;
        for (var col = ((ox - shift - r) / sx).floor() - 1; col <= ((ox - shift + r) / sx).ceil(); col++) {
          final dst = Rect.fromLTWH(col * sx + shift - ox, y, cw, ch);
          final key = (row, col);
          if (dst.center.dx.abs() < w * 0.38 && dst.center.dy.abs() < h * 0.38) seen.add(key);
          final flip = st._flips[key];
          var idx = st.faceOf(key);
          var flipping = false;
          if (flip != null) {
            final pr = ((t - flip.$1) / _CardWallState._flipDur).clamp(0.0, 1.0);
            if (pr >= 0.5) idx = flip.$2;
            final lift = 1 + 0.1 * sin(pi * pr);
            canvas.save();
            canvas.translate(dst.center.dx, dst.center.dy);
            canvas.scale(max(0.02, cos(pi * pr).abs()) * lift, lift);
            canvas.translate(-dst.center.dx, -dst.center.dy);
            flipping = true;
          }
          final im = imgs[idx % imgs.length];
          if (im == null) {
            canvas.drawRRect(RRect.fromRectAndRadius(dst, Radius.circular(cw * 0.075)), empty);
            if (flipping) canvas.restore();
            continue;
          }
          final src = Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble());
          canvas.drawImageRect(im, src, dst, p);
          if (flipping) canvas.restore();
        }
      }
      st._seen = seen;
    }
    canvas.restore();
    // voile sombre aux couleurs du thème
    final all = Offset.zero & size;
    canvas.drawRect(
        all,
        Paint()
          ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [th.top.withOpacity(0.74), th.bottom.withOpacity(0.84)])
              .createShader(all));
  }

  @override
  bool shouldRepaint(covariant _WallPainter old) => false;
}
