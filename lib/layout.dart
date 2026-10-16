import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Mode tablette : décidé sur la taille réelle de l'appareil (plus petit côté
// ≥ 600 dp), pas sur l'orientation. Un téléphone reste toujours en mode
// téléphone (et en portrait) ; une tablette peut tourner.
// Web : selon la largeur de la fenêtre.
// ═══════════════════════════════════════════════════════════════════════════

/// Vrai si l'appareil est une tablette — fixé au lancement par [detectTablet].
bool rcTabletDevice = false;

void detectTablet() {
  if (kIsWeb) return;
  try {
    final v = WidgetsBinding.instance.platformDispatcher.views.first;
    final s = v.physicalSize / v.devicePixelRatio;
    rcTabletDevice = s.shortestSide >= 600;
  } catch (_) {}
}

/// Réglage « Affichage » : 0 automatique, 1 toujours téléphone, 2 toujours tablette
/// (le mode tablette forcé permet aussi d'essayer sur téléphone, en paysage).
final rcLayoutMode = ValueNotifier<int>(0);
const _kLayoutKey = 'rc_layout';

Future<void> loadLayoutMode() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    rcLayoutMode.value = (prefs.getInt(_kLayoutKey) ?? 0).clamp(0, 2);
  } catch (_) {}
}

Future<void> setLayoutMode(int m) async {
  rcLayoutMode.value = m;
  await applyOrientation();
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLayoutKey, m);
  } catch (_) {}
}

/// Téléphone : portrait seulement ; tablette (ou mode tablette forcé) : rotation libre.
Future<void> applyOrientation() async {
  if (kIsWeb) return;
  final free = rcLayoutMode.value == 2 || (rcTabletDevice && rcLayoutMode.value == 0);
  try {
    await SystemChrome.setPreferredOrientations(free ? const [] : const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  } catch (_) {}
}

/// Mise en page tablette (plus de colonnes) : tablette, ou navigateur assez large.
bool isTablet(BuildContext c) => switch (rcLayoutMode.value) {
      1 => false,
      2 => true,
      _ => kIsWeb ? MediaQuery.sizeOf(c).width >= 700 : rcTabletDevice,
    };

/// Mise en page large (menu fixe à gauche, écrans en deux parties) : tablette en paysage, PC.
/// En mode tablette forcé, dès 640 px (téléphone tourné en paysage).
bool isWide(BuildContext c) => isTablet(c) && MediaQuery.sizeOf(c).width >= (rcLayoutMode.value == 2 ? 640 : 900);

/// Nombre de colonnes : [phone] sur téléphone, sinon selon la largeur disponible.
int adaptiveCols(BuildContext c, double width, {required int phone, required double minTile, int max = 10}) =>
    isTablet(c) ? (width / minTile).floor().clamp(phone, max) : phone;

/// Contenu centré et limité en largeur sur grand écran (listes, réglages…).
class MaxWidth extends StatelessWidget {
  final double max;
  final Widget child;
  const MaxWidth({super.key, this.max = 760, required this.child});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        // même structure quelle que soit la largeur : l'état de l'écran est gardé quand on tourne la tablette
        builder: (_, box) => Center(child: SizedBox(width: box.maxWidth < max ? box.maxWidth : max, height: box.maxHeight, child: child)),
      );
}
