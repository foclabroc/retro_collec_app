import 'dart:math';

import 'package:flutter/material.dart';

import 'album.dart';
import 'cards.dart';
import 'catalog.dart';
import 'filters.dart';
import 'layout.dart';
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

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  @override
  void initState() {
    super.initState();
    Game.i.loadRecent();
  }

  void _openCards({int show = 1, int sort = 0, int? rarity}) {
    CardFilter.all
      ..reset(defShow: show)
      ..sort = sort
      ..query = '';
    if (rarity != null) CardFilter.all.rarities.add(rarity);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AllCardsPage()));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Game.i,
      builder: (context, _) {
        final g = Game.i;
        final systems = Catalog.systems;
        return Column(children: [
          TabHeader(t('Collection', 'Collection'), actions: [
            IconButton(
              tooltip: t('Toutes mes cartes : recherche, filtres, tri', 'All my cards: search, filters, sort'),
              icon: const Icon(Icons.search),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AllCardsPage())),
            ),
          ]),
          Expanded(
            child: CustomScrollView(slivers: [
              SliverToBoxAdapter(child: _dashboard(g)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                  child: Text(t('Mes consoles', 'My systems'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                // 2 posters par ligne sur téléphone, 3 à 5 sur tablette / PC
                sliver: SliverLayoutBuilder(
                  builder: (context, box) => SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: adaptiveCols(context, box.crossAxisExtent, phone: 2, minTile: 230, max: 5),
                      childAspectRatio: 0.68,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate((_, i) => _ConsoleTile(sys: systems[i]), childCount: systems.length),
                  ),
                ),
              ),
            ]),
          ),
        ]);
      },
    );
  }

  // ── Tableau de bord : progression, raretés, raccourcis, dernières cartes ──
  Widget _dashboard(Game g) {
    final total = Catalog.cards.length;
    final pct = total == 0 ? 0.0 : g.cards / total;
    final totalByR = List<int>.filled(5, 0), ownByR = List<int>.filled(5, 0);
    for (final c in Catalog.cards.values) {
      totalByR[c.rarity]++;
      if (g.has(c.id)) ownByR[c.rarity]++;
    }
    final recent = [for (final (id, f) in g.recent) if (Catalog.cards[id] != null) (Catalog.cards[id]!, f)];

    Widget action(String icon, String value, String label, Color color, VoidCallback? onTap) => Expanded(
          child: Material(
            color: Colors.black.withOpacity(0.18),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Column(children: [
                  Text(icon, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 2),
                  FittedBox(child: Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: color))),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: Colors.white60)),
                ]),
              ),
            ),
          ),
        );

    final wide = isWide(context);
    // anneau + barres de rareté
    final summary = Row(children: [
          // anneau de progression
          SizedBox(
            width: 92,
            height: 92,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: CircularProgressIndicator(value: pct, strokeWidth: 8, color: kGold, backgroundColor: Colors.white12, strokeCap: StrokeCap.round),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${(pct * 100).floor()} %', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: kGold)),
                Text('${g.cards}/$total', style: const TextStyle(fontSize: 10.5, color: Colors.white60)),
              ]),
            ]),
          ),
          const SizedBox(width: 14),
          // cartes par rareté
          Expanded(
            child: Column(children: [
              // toucher une rareté : mes cartes de cette rareté
              for (var r = 4; r >= 0; r--)
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: ownByR[r] > 0 ? () => _openCards(rarity: r, sort: 1) : null,
                  child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    SizedBox(
                      width: 74,
                      child: Text(rarityName(r), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: kRarityLight[r], fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: totalByR[r] == 0 ? 0 : ownByR[r] / totalByR[r],
                          minHeight: 6,
                          color: kRarityColor[r],
                          backgroundColor: Colors.white10,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 52,
                      child: Text('${ownByR[r]}/${totalByR[r]}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 10.5, color: Colors.white70)),
                    ),
                    Icon(Icons.chevron_right, size: 14, color: ownByR[r] > 0 ? Colors.white38 : Colors.transparent),
                  ]),
                ),
                ),
            ]),
          ),
        ]);
    // raccourcis
    final a1 = action('♻', '${g.dupes}', t('doublons', 'duplicates'), Colors.white, g.dupes > 0 ? () => recycleAllDupes(context) : null);
    final a2 = action('⚡', '${g.fusable}', t('fusions', 'fusions'), g.fusable > 0 ? kGold : Colors.white54, () => _openCards(show: 3, sort: 5));
    final a3 = action('✦', '${g.holoCount}', t('brillantes', 'holo'), const Color(0xFFB4A9FF), () => _openCards(show: 4, sort: 1));
    final a4 = action('★', '${g.goldCount}', t('dorées', 'gold'), const Color(0xFFFFD54F), () => _openCards(show: 5, sort: 1));
    // dernières cartes
    final latest = recent.isEmpty
        ? const SizedBox()
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Text(t('Dernières cartes', 'Latest cards'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            const Spacer(),
            GestureDetector(
              onTap: () => _openCards(),
              child: Text(t('Tout voir', 'See all'), style: const TextStyle(color: Color(0xFF8FD3FF), fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 6),
          SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recent.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final (c, f) = recent[i];
                return GestureDetector(
                  onTap: () => openCardDetail(context, c, list: [for (final (rc, _) in recent) rc]),
                  child: SizedBox(width: 60, child: CardView(card: c, finish: f, owned: g.has(c.id))),
                );
              },
            ),
          ),
        ]);
    final box = BoxDecoration(
      color: kPanel,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: kGold.withOpacity(0.45)),
    );
    if (wide) {
      // mode large : tout sur une ligne
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        padding: const EdgeInsets.all(14),
        decoration: box,
        child: SizedBox(
          height: 116,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 5, child: Center(child: summary)),
            const SizedBox(width: 14),
            SizedBox(
              width: 210,
              child: Column(children: [
                Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a1, const SizedBox(width: 6), a2])),
                const SizedBox(height: 6),
                Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a3, const SizedBox(width: 6), a4])),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(flex: 4, child: latest),
          ]),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: box,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        summary,
        const SizedBox(height: 12),
        Row(children: [a1, const SizedBox(width: 6), a2, const SizedBox(width: 6), a3, const SizedBox(width: 6), a4]),
        if (recent.isNotEmpty) ...[const SizedBox(height: 12), latest],
      ]),
    );
  }
}

/// Année de sortie et couleur d'accent de chaque console (posters)
const Map<String, int> kConsoleYear = {
  'nes': 1985, 'snes': 1990, 'n64': 1996, 'psx': 1994, 'gba': 2001,
  'gbc': 1998, 'megadrive': 1988, 'mastersystem': 1986, 'neogeo': 1990, 'switch': 2017,
};
const Map<String, Color> kConsoleAccent = {
  'nes': Color(0xFFFFD23B), 'snes': Color(0xFFFF5D8F), 'n64': Color(0xFFFFD23B), 'psx': Color(0xFF3DD9FF), 'gba': Color(0xFFFFD23B),
  'gbc': Color(0xFFFFD23B), 'megadrive': Color(0xFFFFD23B), 'mastersystem': Color(0xFF3DD9FF), 'neogeo': Color(0xFFE60012), 'switch': Color(0xFF3DD9FF),
};

const _kPaper = Color(0xFFF3E6C8); // papier d'affiche
const _kInk = Color(0xFF2A1B0E); // encre foncée

/// Console en « poster rétro » : rayons, trame de points, année, bandeau promo
class _ConsoleTile extends StatefulWidget {
  final RcSystem sys;
  const _ConsoleTile({required this.sys});
  @override
  State<_ConsoleTile> createState() => _ConsoleTileState();
}

class _ConsoleTileState extends State<_ConsoleTile> {
  bool pressed = false;

  static const _grey = ColorFilter.matrix(<double>[
    0.25, 0.55, 0.12, 0, -10, //
    0.25, 0.55, 0.12, 0, -10, //
    0.25, 0.55, 0.12, 0, -10, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final s = widget.sys;
    final owned = Game.i.ownedIn(s.id);
    final total = max(1, s.count);
    final complete = owned >= total;
    final none = owned == 0;
    final brand = kConsoleBrand[s.id] ?? const Color(0xFF3550B8);
    final accent = kConsoleAccent[s.id] ?? kGold;
    final pct = (owned * 100 / total).floor();

    Widget poster = Container(
      decoration: BoxDecoration(
        color: _kPaper,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kPaper, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 6))],
      ),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: _kInk, width: 2), borderRadius: BorderRadius.circular(3)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          // en-tête : année + logo
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: const BoxDecoration(color: _kPaper, border: Border(bottom: BorderSide(color: _kInk, width: 3))),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(color: accent, border: Border.all(color: _kInk, width: 2)),
                child: Text('${kConsoleYear[s.id] ?? ''}', style: const TextStyle(color: _kInk, fontWeight: FontWeight.w900, fontSize: 10.5, fontFamily: 'monospace')),
              ),
              const SizedBox(width: 4),
              Expanded(child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: ConsoleLogo(s.id, height: 18)))),
            ]),
          ),
          // affiche : rayons + trame + console + bandeau
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              CustomPaint(painter: _RaysPainter(brand)),
              Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 30),
                  child: Image.asset(
                    'assets/consoles/${s.id}.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, __, ___) => Icon(Icons.videogame_asset, size: 56, color: Colors.white.withOpacity(0.6)),
                  ),
                ),
              ),
              // bandeau promo penché
              Positioned(
                left: -8,
                right: -8,
                bottom: 6,
                child: Transform.rotate(
                  angle: -0.05,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: none ? const Color(0xFF3A2A1E) : accent,
                      border: const Border.symmetric(horizontal: BorderSide(color: _kInk, width: 2)),
                    ),
                    child: Text(
                      complete
                          ? t('★ SÉRIE COMPLÈTE ★', '★ SET COMPLETE ★')
                          : none
                              ? t('À DÉCOUVRIR', 'TO DISCOVER')
                              : t('$owned / ${s.count} JEUX', '$owned / ${s.count} GAMES'),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: TextStyle(
                        color: none ? Colors.white54 : _kInk,
                        fontWeight: FontWeight.w900,
                        fontSize: 10.5,
                        letterSpacing: 1,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ),
              // tampon « 100% »
              if (complete)
                Positioned(
                  right: 6,
                  top: 8,
                  child: Transform.rotate(
                    angle: 0.25,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: kGold, width: 2.5),
                      ),
                      child: const Text('100%', style: TextStyle(color: kGold, fontWeight: FontWeight.w900, fontSize: 12, fontFamily: 'monospace')),
                    ),
                  ),
                ),
            ]),
          ),
          // pied : barre de progression
          Container(
            padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
            decoration: const BoxDecoration(color: _kPaper, border: Border(top: BorderSide(color: _kInk, width: 3))),
            child: Row(children: [
              Expanded(
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(color: _kInk.withOpacity(0.2), border: Border.all(color: _kInk, width: 1.5)),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (owned / total).clamp(0.0, 1.0),
                    child: Container(color: complete ? kGold : brand),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text('$pct%', style: const TextStyle(color: _kInk, fontWeight: FontWeight.w900, fontSize: 12, fontFamily: 'monospace')),
            ]),
          ),
        ]),
      ),
    );
    if (none) poster = ColorFiltered(colorFilter: _grey, child: poster);

    return GestureDetector(
      onTapDown: (_) => setState(() => pressed = true),
      onTapCancel: () => setState(() => pressed = false),
      onTapUp: (_) => setState(() => pressed = false),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SystemAlbumPage(sys: s.id))),
      child: AnimatedScale(scale: pressed ? 0.96 : 1, duration: const Duration(milliseconds: 110), child: poster),
    );
  }
}

/// Rayons de soleil façon publicité rétro + trame de points d'imprimerie
class _RaysPainter extends CustomPainter {
  final Color color;
  _RaysPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final dark = Color.lerp(color, Colors.black, 0.3)!;
    canvas.drawRect(Offset.zero & size, Paint()..color = dark);
    final c = Offset(size.width / 2, size.height * 0.55);
    final r = size.longestSide * 1.2;
    const n = 22; // rayons
    final p = Paint()..color = color;
    for (var i = 0; i < n; i++) {
      final a0 = i * 2 * pi / n, a1 = a0 + pi / n;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + r * cos(a0), c.dy + r * sin(a0))
        ..lineTo(c.dx + r * cos(a1), c.dy + r * sin(a1))
        ..close();
      canvas.drawPath(path, p);
    }
    // trame de points
    final dot = Paint()..color = const Color(0x26000000);
    for (double y = 2; y < size.height; y += 6) {
      for (double x = (y ~/ 6).isEven ? 2 : 5; x < size.width; x += 6) {
        canvas.drawCircle(Offset(x, y), 1.1, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RaysPainter old) => old.color != color;
}
