import 'package:flutter/material.dart';

import 'game.dart';
import 'main.dart';
import 'retro_theme.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Maisons du Voisinage : chaque joueur choisit sa maison parmi 12 (sprites
// isométriques assets/houses/house_NN.webp). Certaines se débloquent avec la
// collection (nombre de cartes différentes). Code serveur : 'N' (0 à 11).
// ═══════════════════════════════════════════════════════════════════════════

class HouseType {
  final String fr, en;
  final int need; // cartes différentes nécessaires
  const HouseType(this.fr, this.en, this.need);
  String get name => t(fr, en);
}

/// Même ordre que les images (et que rc_set_house côté serveur)
const kHouses = [
  HouseType('Château de pierre', 'Stone castle', 700),
  HouseType('Manoir classique', 'Classic manor', 500),
  HouseType('Chalet de forêt', 'Forest chalet', 0),
  HouseType('Ryokan de montagne', 'Mountain ryokan', 200),
  HouseType('Maison Nouvelle-Angleterre', 'New England house', 0),
  HouseType('Maison de banlieue', 'Suburban house', 0),
  HouseType('Gîte d\'hiver', 'Winter lodge', 100),
  HouseType('Maison de ville britannique', 'British townhouse', 100),
  HouseType('Villa contemporaine', 'Modern villa', 350),
  HouseType('Casa coloniale espagnole', 'Spanish colonial casa', 200),
  HouseType('Cottage de campagne', 'Country cottage', 0),
  HouseType('Dôme géodésique', 'Geodesic dome', 350),
];

/// Maisons gratuites (maison par défaut des joueurs qui n'ont pas choisi)
const _kFree = [4, 5, 10, 2];

class HouseSpec {
  final int style;
  const HouseSpec(this.style);

  /// Maison par défaut variée selon le joueur, pour que le quartier ne soit pas uniforme
  factory HouseSpec.parse(String? s, {String seed = ''}) {
    final n = int.tryParse(s ?? '');
    if (n != null && n >= 0 && n < kHouses.length) return HouseSpec(n);
    return HouseSpec(_kFree[seed.hashCode.abs() % _kFree.length]);
  }

  HouseType get type => kHouses[style];
  String get asset => 'assets/houses/house_${style.toString().padLeft(2, '0')}.webp';

  @override
  String toString() => '$style';
}

/// Parcelle avec la maison (s'adapte à la taille donnée)
class HouseView extends StatelessWidget {
  final HouseSpec spec;
  final bool highlight; // ma parcelle
  final bool locked; // aperçu d'une maison pas encore débloquée
  const HouseView(this.spec, {super.key, this.highlight = false, this.locked = false});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(w * 0.08),
          gradient: const RadialGradient(
            center: Alignment(0, 0.25),
            radius: 0.9,
            colors: [Color(0xFF3E5BB0), Color(0xFF1A2560)],
          ),
          border: Border.all(color: highlight ? kGold : const Color(0x44FFFFFF), width: highlight ? 2.5 : 1),
          boxShadow: highlight ? [BoxShadow(color: kGold.withOpacity(0.35), blurRadius: 12)] : null,
        ),
        child: Stack(alignment: Alignment.center, children: [
          // ombre sous l'île
          Positioned(
            left: w * 0.12,
            right: w * 0.12,
            bottom: box.maxHeight * 0.06,
            height: box.maxHeight * 0.12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 14, spreadRadius: 2)],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(w * 0.05),
            child: ColorFiltered(
              colorFilter: locked
                  ? const ColorFilter.matrix([0.25, 0.25, 0.25, 0, 0, 0.25, 0.25, 0.25, 0, 0, 0.25, 0.25, 0.25, 0, 0, 0, 0, 0, 1, 0])
                  : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
              child: Image.asset(
                spec.asset,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                cacheWidth: (w * MediaQuery.of(context).devicePixelRatio).round().clamp(64, 400),
                errorBuilder: (_, __, ___) => const Icon(Icons.home, color: Colors.white38, size: 48),
              ),
            ),
          ),
          if (locked) const Icon(Icons.lock, color: Colors.white, size: 28),
        ]),
      );
    });
  }
}

// ─── Choix de ma maison ────────────────────────────────────────────────────
class HouseEditorPage extends StatefulWidget {
  final HouseSpec initial;
  const HouseEditorPage({super.key, required this.initial});
  @override
  State<HouseEditorPage> createState() => _HouseEditorPageState();
}

class _HouseEditorPageState extends State<HouseEditorPage> {
  late HouseSpec spec = widget.initial;
  bool saving = false;

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await RcServer.setHouse(spec.toString());
      Game.i.house = spec.toString();
      toast(t('Bienvenue dans ta nouvelle maison !', 'Welcome to your new house!'));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      toast(errText(e));
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = Game.i.cards;
    // gratuites d'abord, puis par palier de déblocage
    final order = List<int>.generate(kHouses.length, (i) => i)..sort((a, b) => kHouses[a].need.compareTo(kHouses[b].need));
    final sel = spec.type;
    return Scaffold(
      appBar: AppBar(title: Text(t('Ma maison', 'My house'))),
      body: Column(children: [
        // aperçu
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SizedBox(height: 200, child: AspectRatio(aspectRatio: 1.15, child: HouseView(spec, highlight: true))),
        ),
        Text(sel.name, style: pixelStyle(size: 10)),
        const SizedBox(height: 2),
        Text(t('${Game.i.name} · $cards cartes', '${Game.i.name} · $cards cards'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.8, crossAxisSpacing: 8, mainAxisSpacing: 8),
            itemCount: order.length,
            itemBuilder: (_, k) {
              final i = order[k];
              final h = kHouses[i];
              final locked = cards < h.need;
              final chosen = spec.style == i;
              return GestureDetector(
                onTap: () {
                  if (locked) {
                    toast(t('${h.name} : débloquée à ${h.need} cartes différentes (tu en as $cards)',
                        '${h.name}: unlocked at ${h.need} different cards (you have $cards)'));
                  } else {
                    setState(() => spec = HouseSpec(i));
                  }
                },
                child: Column(children: [
                  Expanded(child: HouseView(HouseSpec(i), highlight: chosen, locked: locked)),
                  const SizedBox(height: 3),
                  Text(
                    locked ? t('🔒 ${h.need} cartes', '🔒 ${h.need} cards') : h.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: locked ? Colors.white38 : (chosen ? kGold : Colors.white70), fontWeight: FontWeight.w700),
                  ),
                ]),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800), minimumSize: const Size.fromHeight(50)),
              onPressed: saving || (spec.style == widget.initial.style && Game.i.house.isNotEmpty) ? null : _save,
              icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.home),
              label: Text(t('Emménager', 'Move in'), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ]),
    );
  }
}
