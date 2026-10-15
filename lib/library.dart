import 'dart:math';

import 'package:flutter/material.dart';

import 'album.dart';
import 'cards.dart';
import 'catalog.dart';
import 'game.dart';
import 'main.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Collection : une vitrine par console (couleur de la marque, spot lumineux,
// console posée sur un socle, logo, progression). Console grisée tant qu'on
// n'a aucune carte ; vitrine dorée quand la série est complète.
// Toucher une vitrine ouvre l'album de la console.
// ═══════════════════════════════════════════════════════════════════════════

const Map<String, Color> kConsoleBrand = {
  'nes': Color(0xFFE60012),
  'snes': Color(0xFF7B68C8),
  'n64': Color(0xFF2CA44A),
  'psx': Color(0xFF3069B8),
  'gba': Color(0xFF6A4FC0),
  'gbc': Color(0xFF2A9D8F),
  'megadrive': Color(0xFF4F7BD8),
  'mastersystem': Color(0xFFD62828),
  'neogeo': Color(0xFFE0B13A),
  'switch': Color(0xFFE60012),
};

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Game.i,
      builder: (context, _) {
        final g = Game.i;
        final systems = Catalog.systems;
        return Column(children: [
          TabHeader(t('Ma collection', 'My collection'), actions: [
            IconButton(
              tooltip: t('Recycler les doublons', 'Recycle duplicates'),
              icon: Badge(isLabelVisible: g.dupes > 0, label: Text('${g.dupes}'), child: const Icon(Icons.recycling)),
              onPressed: () => recycleAllDupes(context),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: Catalog.cards.isEmpty ? 0 : g.cards / Catalog.cards.length,
                    minHeight: 6,
                    color: kGold,
                    backgroundColor: const Color(0xFF26306B),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('${g.cards} / ${Catalog.cards.length}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.82,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: systems.length,
              itemBuilder: (_, i) => _ConsoleTile(sys: systems[i]),
            ),
          ),
        ]);
      },
    );
  }
}

class _ConsoleTile extends StatefulWidget {
  final RcSystem sys;
  const _ConsoleTile({required this.sys});
  @override
  State<_ConsoleTile> createState() => _ConsoleTileState();
}

class _ConsoleTileState extends State<_ConsoleTile> {
  bool pressed = false;

  static const _grey = ColorFilter.matrix(<double>[
    0.25, 0.55, 0.12, 0, 0, //
    0.25, 0.55, 0.12, 0, 0, //
    0.25, 0.55, 0.12, 0, 0, //
    0, 0, 0, 0.7, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final s = widget.sys;
    final owned = Game.i.ownedIn(s.id);
    final total = max(1, s.count);
    final complete = owned >= total;
    final none = owned == 0;
    final brand = complete ? kGold : (kConsoleBrand[s.id] ?? const Color(0xFF3550B8));

    Widget img = Image.asset(
      'assets/consoles/${s.id}.png',
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => Icon(Icons.videogame_asset, size: 56, color: Colors.white.withOpacity(0.4)),
    );
    if (none) img = ColorFiltered(colorFilter: _grey, child: img);

    return GestureDetector(
      onTapDown: (_) => setState(() => pressed = true),
      onTapCancel: () => setState(() => pressed = false),
      onTapUp: (_) => setState(() => pressed = false),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SystemAlbumPage(sys: s.id))),
      child: AnimatedScale(
        scale: pressed ? 0.96 : 1,
        duration: const Duration(milliseconds: 110),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(const Color(0xFF0A1033), brand, none ? 0.12 : 0.32)!,
                const Color(0xEE0A1033),
              ],
            ),
            border: Border.all(color: brand.withOpacity(none ? 0.35 : 0.85), width: 2),
            boxShadow: [
              if (!none) BoxShadow(color: brand.withOpacity(complete ? 0.6 : 0.35), blurRadius: complete ? 18 : 12),
              const BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 4)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(children: [
              // spot lumineux derrière la console
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.05),
                      radius: 0.75,
                      colors: [brand.withOpacity(none ? 0.10 : 0.35), brand.withOpacity(0)],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                child: Column(children: [
                  // logo
                  SizedBox(
                    height: 30,
                    child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: ConsoleLogo(s.id, height: 22))),
                  ),
                  // console sur son socle
                  Expanded(
                    child: Stack(alignment: Alignment.bottomCenter, children: [
                      // socle lumineux
                      Positioned(
                        bottom: 2,
                        left: 14,
                        right: 14,
                        height: 14,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.all(Radius.elliptical(100, 14)),
                            gradient: RadialGradient(colors: [brand.withOpacity(none ? 0.18 : 0.55), brand.withOpacity(0)]),
                          ),
                        ),
                      ),
                      Padding(padding: const EdgeInsets.fromLTRB(4, 6, 4, 8), child: Center(child: img)),
                    ]),
                  ),
                  // progression
                  Row(children: [
                    if (complete) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.emoji_events, color: kGold, size: 14)),
                    Text('$owned / ${s.count}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: complete ? kGold : Colors.white)),
                    const Spacer(),
                    Text('${(owned * 100 / total).floor()} %', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.6))),
                  ]),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: owned / total,
                      minHeight: 5,
                      color: complete ? kGold : Color.lerp(brand, Colors.white, 0.25),
                      backgroundColor: const Color(0x66000000),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
