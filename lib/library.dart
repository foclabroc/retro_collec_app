import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'album.dart';
import 'cards.dart';
import 'catalog.dart';
import 'filters.dart';
import 'layout.dart';
import 'game.dart';
import 'main.dart';
import 'sagas.dart';

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
  '3ds': Color(0xFFCE181E),
  'sg1000': Color(0xFF1F4FA8),
  'dreamcast': Color(0xFFE8711E),
  'atari7800': Color(0xFFB8242A),
  'amigacd32': Color(0xFF4A4A52),
  'gb': Color(0xFF8B8FA8),
  'amiga1200': Color(0xFF1F6F8B),
  'lynx': Color(0xFFE8A317),
  'supervision': Color(0xFF2FA89A),
  'atari2600': Color(0xFF8B5A2B),
  'colecovision': Color(0xFF2B2B33),
  'saturn': Color(0xFF3B4A9E),
  'wii': Color(0xFF8FA3B8),
  'wiiu': Color(0xFF009AC7),
  'xbox': Color(0xFF107C10),
};

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

// Ordre des consoles (menu déroulant à côté de « Mes consoles », mémorisé)
const _kSysSortKey = 'rc_sys_sort';
List<String> get _sysSortLabels => [
      t('Les plus complètes', 'Most complete'),
      t('Les moins complètes', 'Least complete'),
      t('Les plus anciennes', 'Oldest first'),
      t('Les plus récentes', 'Newest first'),
      t('Nom (A → Z)', 'Name (A → Z)'),
      t('Ordre habituel', 'Default order'),
    ];

class _LibraryScreenState extends State<LibraryScreen> {
  int sysSort = 0;
  int mode = 0; // onglet : 0 Consoles, 1 Sagas, 2 Full art (mémorisé)
  bool get sagas => mode == 1;
  bool dashOpen = false; // tableau de bord déplié (mémorisé, replié par défaut)

  @override
  void initState() {
    super.initState();
    Game.i.loadRecent();
    SharedPreferences.getInstance().then((p) {
      final v = p.getInt(_kSysSortKey);
      if (v != null && mounted) setState(() => sysSort = v.clamp(0, 5));
      final m = p.getInt('rc_coll_mode') ?? (p.getBool('rc_coll_sagas') == true ? 1 : 0);
      if (m != 0 && mounted) setState(() => mode = m.clamp(0, 2));
      if (p.getBool('rc_dash_open') == true && mounted) setState(() => dashOpen = true);
    }).catchError((_) {});
  }

  void _toggleDash() {
    setState(() => dashOpen = !dashOpen);
    SharedPreferences.getInstance().then((p) => p.setBool('rc_dash_open', dashOpen)).catchError((_) => false);
  }

  void _setMode(int v) {
    setState(() => mode = v);
    SharedPreferences.getInstance().then((p) => p.setInt('rc_coll_mode', v)).catchError((_) => false);
  }

  /// Sélecteur « Consoles | Sagas | Full art »
  Widget _seg() {
    Widget b(int v, String label) => Expanded(
          child: GestureDetector(
            onTap: () => _setMode(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(color: mode == v ? kGold : Colors.transparent, borderRadius: BorderRadius.circular(10)),
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: mode == v ? const Color(0xFF2A1800) : Colors.white70)),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), borderRadius: BorderRadius.circular(13)),
      child: Row(children: [b(0, t('🎮 Consoles', '🎮 Systems')), b(1, t('📚 Sagas', '📚 Sagas')), b(2, t('★★ Full art', '★★ Full art'))]),
    );
  }

  void _setSysSort(int v) {
    setState(() => sysSort = v);
    SharedPreferences.getInstance().then((p) => p.setInt(_kSysSortKey, v)).catchError((_) => false);
  }

  List<RcSystem> _sortedSystems(Game g) {
    final base = Catalog.systems;
    final rank = {for (var i = 0; i < base.length; i++) base[i].id: i};
    double pctOf(RcSystem s) => g.ownedIn(s.id) / max(1, s.count);
    int byRank(RcSystem a, RcSystem b) => rank[a.id]!.compareTo(rank[b.id]!);
    int year(RcSystem s) => kConsoleYear[s.id] ?? 9999;
    final list = [...base];
    switch (sysSort) {
      case 0 || 1: // complétion (à égalité : le plus de cartes, puis l'ordre habituel)
        list.sort((a, b) {
          var c = pctOf(b).compareTo(pctOf(a));
          if (c == 0) c = g.ownedIn(b.id).compareTo(g.ownedIn(a.id));
          if (sysSort == 1) c = -c;
          return c != 0 ? c : byRank(a, b);
        });
      case 2 || 3:
        list.sort((a, b) {
          final c = sysSort == 2 ? year(a).compareTo(year(b)) : year(b).compareTo(year(a));
          return c != 0 ? c : byRank(a, b);
        });
      case 4:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      default:
        break;
    }
    return list;
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
        final systems = _sortedSystems(g);
        final sagaList = [for (final s in kSagas) if (Catalog.bySys[s.sys] != null) s];
        final faList = mode == 2 ? fullArtCards() : const <RcCard>[];
        final faMine = [for (final c in faList) if ((g.owned[c.id]?[3] ?? 0) > 0) c.id].length;
        return Column(children: [
          TabHeader(t('Collection', 'Collection'), icon: 'collection', actions: [
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
                  padding: const EdgeInsets.fromLTRB(14, 8, 10, 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Align(alignment: Alignment.centerLeft, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 340), child: _seg())),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                      child: Text(
                          switch (mode) {
                            1 => t('Cartes holo : ${livePct('saga')} de chance par carte de paquet', 'Holo cards: ${livePct('saga')} chance per pack card'),
                            2 => t('$faMine / ${faList.length} · ${livePct('fullart')} par épique ou légendaire', '$faMine / ${faList.length} · ${livePct('fullart')} per epic or legendary'),
                            _ => t('Mes consoles', 'My systems'),
                          },
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: Colors.white60)),
                    ),
                    // menu déroulant : ordre des consoles
                    if (mode == 0)
                    DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: sysSort,
                        isDense: true,
                        borderRadius: BorderRadius.circular(12),
                        dropdownColor: kBg,
                        icon: const Icon(Icons.sort, size: 18, color: Colors.white70),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white70),
                        items: [
                          for (var i = 0; i < _sysSortLabels.length; i++) DropdownMenuItem(value: i, child: Text(_sysSortLabels[i])),
                        ],
                        onChanged: (v) {
                          if (v != null) _setSysSort(v);
                        },
                      ),
                    ),
                  ]),
                  ]),
                ),
              ),
              if (mode == 2)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                  // 3 cartes par ligne sur téléphone, plus sur grand écran
                  sliver: SliverLayoutBuilder(
                    builder: (context, box) => SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: adaptiveCols(context, box.crossAxisExtent, phone: 3, minTile: 130, max: 8),
                        childAspectRatio: 5 / 7,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      delegate: SliverChildBuilderDelegate((_, i) => _FullArtSlot(card: faList[i], list: faList), childCount: faList.length),
                    ),
                  ),
                )
              else
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
                    delegate: sagas
                        ? SliverChildBuilderDelegate((_, i) => SagaPoster(sagaList[i]), childCount: sagaList.length)
                        : SliverChildBuilderDelegate((_, i) => _ConsoleTile(sys: systems[i]), childCount: systems.length),
                  ),
                ),
              ),
            ]),
          ),
        ]);
      },
    );
  }

  /// Une ligne du tableau de bord : nom, barre, x/y
  Widget _bar(String label, int mine, int total, Color color, Color light, VoidCallback? onTap) => InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            SizedBox(
              width: 74,
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: light, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: total == 0 ? 0 : mine / total, minHeight: 6, color: color, backgroundColor: Colors.white10),
              ),
            ),
            SizedBox(width: 52, child: Text('$mine/$total', textAlign: TextAlign.right, style: const TextStyle(fontSize: 10.5, color: Colors.white70))),
            Icon(Icons.chevron_right, size: 14, color: onTap != null ? Colors.white38 : Colors.transparent),
          ]),
        ),
      );

  // ── Tableau de bord : progression, raretés, raccourcis, dernières cartes ──
  Widget _dashboard(Game g) {
    final total = Catalog.total; // full art comptées à part
    final pct = total == 0 ? 0.0 : g.cards / total;
    final totalByR = List<int>.filled(5, 0), ownByR = List<int>.filled(5, 0);
    var sagaTotal = 0, sagaMine = 0, faTotal = 0, faMine = 0;
    for (final c in Catalog.cards.values) {
      if (c.isSaga) {
        // cartes de saga : ligne à part (pas dans les épiques)
        sagaTotal++;
        if (g.has(c.id)) sagaMine++;
        continue;
      }
      totalByR[c.rarity]++;
      if (g.has(c.id)) ownByR[c.rarity]++;
      if (c.rarity >= 3) {
        // full art : possible pour les épiques et légendaires
        faTotal++;
        if ((g.owned[c.id]?[3] ?? 0) > 0) faMine++;
      }
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
              _bar('📚 ${t('Sagas', 'Sagas')}', sagaMine, sagaTotal, const Color(0xFFFF8AD8), const Color(0xFFFFB3E6),
                  sagaTotal > 0 ? () => _setMode(1) : null),
              _bar('★★ ${t('Full art', 'Full art')}', faMine, faTotal, const Color(0xFFFF9FE5), const Color(0xFFFFC6F0),
                  faTotal > 0 ? () => _setMode(2) : null),
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
    final a5 = action('★★', '${g.fullArtCount}', t('full art', 'full art'), const Color(0xFFFF9FE5), () => _setMode(2)); // full art : seulement dans son onglet
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
    // replié : une ligne (anneau, total, petits compteurs) ; toucher pour déplier
    if (!dashOpen) {
      Widget mini(String icon, int v, Color c) => Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text('$icon $v', style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 12.5)),
          );
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        decoration: box,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _toggleDash,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              child: Row(children: [
                SizedBox(
                  width: 46,
                  height: 46,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(value: pct, strokeWidth: 5, color: kGold, backgroundColor: Colors.white12, strokeCap: StrokeCap.round),
                    ),
                    Text('${(pct * 100).floor()}%', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: kGold)),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(t('${g.cards} / $total cartes', '${g.cards} / $total cards'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
                    const SizedBox(height: 3),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        mini('📚', sagaMine, const Color(0xFFFFB3E6)),
                        mini('★★', g.fullArtCount, const Color(0xFFFF9FE5)),
                        mini('★', g.goldCount, const Color(0xFFFFD54F)),
                        mini('✦', g.holoCount, const Color(0xFFB4A9FF)),
                        mini('♻', g.dupes, Colors.white70),
                        if (g.fusable > 0) mini('⚡', g.fusable, kGold),
                      ]),
                    ),
                  ]),
                ),
                // bouton bien visible pour déplier
                Container(
                  width: 32,
                  height: 32,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: kGold,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: kGold.withOpacity(0.45), blurRadius: 8)],
                  ),
                  child: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF2A1800), size: 26),
                ),
              ]),
            ),
          ),
        ),
      );
    }
    // bouton pour replier
    final fold = Align(
      alignment: Alignment.centerRight,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _toggleDash,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(t('Réduire', 'Collapse'), style: const TextStyle(color: Colors.white60, fontSize: 11.5, fontWeight: FontWeight.w700)),
            const SizedBox(width: 5),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(color: kGold.withOpacity(0.9), shape: BoxShape.circle),
              child: const Icon(Icons.keyboard_arrow_up_rounded, color: Color(0xFF2A1800), size: 22),
            ),
          ]),
        ),
      ),
    );
    if (wide) {
      // mode large : tout sur une ligne
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        padding: const EdgeInsets.all(14),
        decoration: box,
        child: SizedBox(
          height: 142,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 5, child: Center(child: summary)),
            const SizedBox(width: 14),
            SizedBox(
              width: 250,
              child: Column(children: [
                Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a1, const SizedBox(width: 6), a2])),
                const SizedBox(height: 6),
                Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a3, const SizedBox(width: 6), a4, const SizedBox(width: 6), a5])),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(flex: 4, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [fold, Expanded(child: latest)])),
          ]),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: box,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        fold,
        summary,
        const SizedBox(height: 12),
        Row(children: [a1, const SizedBox(width: 6), a2, const SizedBox(width: 6), a3, const SizedBox(width: 6), a4, const SizedBox(width: 6), a5]),
        if (recent.isNotEmpty) ...[const SizedBox(height: 12), latest],
      ]),
    );
  }
}

/// Année de sortie et couleur d'accent de chaque console (posters)
const Map<String, int> kConsoleYear = {
  'nes': 1985, 'snes': 1990, 'n64': 1996, 'psx': 1994, 'gba': 2001,
  'gbc': 1998, 'megadrive': 1988, 'mastersystem': 1986, 'neogeo': 1990, 'switch': 2017,
  '3ds': 2011, 'sg1000': 1983, 'dreamcast': 1998, 'atari7800': 1986, 'amigacd32': 1993,
  'gb': 1989, 'amiga1200': 1992, 'lynx': 1989, 'supervision': 1992,
  'atari2600': 1977, 'colecovision': 1982, 'saturn': 1995, 'wii': 2006, 'wiiu': 2012, 'xbox': 2002,
};
const Map<String, Color> kConsoleAccent = {
  'nes': Color(0xFFFFD23B), 'snes': Color(0xFFFF5D8F), 'n64': Color(0xFFFFD23B), 'psx': Color(0xFF3DD9FF), 'gba': Color(0xFFFFD23B),
  'gbc': Color(0xFFFFD23B), 'megadrive': Color(0xFFFFD23B), 'mastersystem': Color(0xFF3DD9FF), 'neogeo': Color(0xFFE60012), 'switch': Color(0xFF3DD9FF),
  '3ds': Color(0xFF3DD9FF), 'sg1000': Color(0xFFFFD23B), 'dreamcast': Color(0xFF3DD9FF), 'atari7800': Color(0xFFFFD23B), 'amigacd32': Color(0xFFFF5D8F),
  'gb': Color(0xFF9BBC0F), 'amiga1200': Color(0xFFFF5D8F), 'lynx': Color(0xFFFFD23B), 'supervision': Color(0xFF3DD9FF),
  'atari2600': Color(0xFFFF8C3B), 'colecovision': Color(0xFF3DD9FF), 'saturn': Color(0xFFFFD23B), 'wii': Color(0xFF3DD9FF), 'wiiu': Color(0xFFFFD23B), 'xbox': Color(0xFF9BE15D),
};

const _kPaper = Color(0xFFF3E6C8); // papier d'affiche
const _kInk = Color(0xFF2A1B0E); // encre foncée

/// Console en « poster rétro » : rayons, année, bandeau promo
class _ConsoleTile extends StatefulWidget {
  final RcSystem sys;
  const _ConsoleTile({required this.sys});
  @override
  State<_ConsoleTile> createState() => _ConsoleTileState();
}

class _ConsoleTileState extends State<_ConsoleTile> with SingleTickerProviderStateMixin {
  bool pressed = false;
  // une seule horloge de 40 s ; chaque animation a une période qui divise 40 s
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 40));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (still) {
      _clock.stop();
      _started = false;
    } else if (!_started) {
      _started = true;
      // décalage propre à chaque console pour qu'elles ne bougent pas en même temps
      _clock.value = (widget.sys.id.hashCode % 1000) / 1000;
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  /// phase 0..1 d'une animation de [sec] secondes
  double _ph(double sec) => (_clock.value * 40 / sec) % 1;

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
          // affiche : rayons + console + bandeau
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              // rayons qui tournent lentement
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _clock,
                  builder: (_, __) => CustomPaint(painter: _RaysPainter(brand, _clock.value * 2 * pi)),
                ),
              ),
              // lueur qui respire derrière la console
              AnimatedBuilder(
                animation: _clock,
                builder: (_, __) => Opacity(
                  opacity: 0.675 + 0.325 * cos(_ph(4) * 2 * pi),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(radius: 0.6, colors: [Color(0x59FFFFFF), Color(0x00FFFFFF)]),
                    ),
                  ),
                ),
              ),
              // console qui flotte
              Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 30),
                  child: AnimatedBuilder(
                    animation: _clock,
                    builder: (_, child) {
                      final w = sin(_ph(4) * 2 * pi);
                      return Transform.translate(
                        offset: Offset(0, -3 - 3 * w),
                        child: Transform.rotate(angle: -0.013 * w, child: child),
                      );
                    },
                    child: Image.asset(
                      'assets/consoles/${s.id}.png',
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, __, ___) => Icon(Icons.videogame_asset, size: 56, color: Colors.white.withOpacity(0.6)),
                    ),
                  ),
                ),
              ),
              // étoiles qui scintillent (séries complètes)
              if (complete)
                for (final st in const [[0.12, 0.18, 0.0], [0.82, 0.30, 0.3], [0.70, 0.62, 0.6], [0.18, 0.56, 0.8]])
                  Align(
                    alignment: Alignment(st[0] * 2 - 1, st[1] * 2 - 1),
                    child: AnimatedBuilder(
                      animation: _clock,
                      builder: (_, __) {
                        final k = 0.5 - 0.5 * cos(((_ph(2.5) + st[2]) % 1) * 2 * pi);
                        return Opacity(
                          opacity: k,
                          child: Transform.scale(scale: 0.3 + 0.7 * k, child: const CustomPaint(size: Size(11, 11), painter: _SparkPainter())),
                        );
                      },
                    ),
                  ),
              // bandeau promo penché
              Positioned(
                left: -8,
                right: -8,
                bottom: 6,
                child: AnimatedBuilder(
                  animation: _clock,
                  builder: (_, child) {
                    final w = 0.5 - 0.5 * cos(_ph(4) * 2 * pi);
                    return Transform.translate(
                      offset: Offset(0, -w),
                      child: Transform.rotate(angle: -0.05 - 0.025 * w, child: child),
                    );
                  },
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
              // reflet qui passe de temps en temps
              IgnorePointer(
                child: AnimatedBuilder(
                  animation: _clock,
                  builder: (_, __) {
                    final v = _ph(5);
                    if (v < 0.6) return const SizedBox.shrink();
                    final x = -1.2 + 2.4 * ((v - 0.6) / 0.25).clamp(0.0, 1.0);
                    return FractionalTranslation(
                      translation: Offset(x, 0),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(-1, -0.4),
                            end: Alignment(1, 0.4),
                            colors: [Color(0x00FFFFFF), Color(0x8CFFFFFF), Color(0x00FFFFFF)],
                            stops: [0.35, 0.48, 0.6],
                          ),
                        ),
                      ),
                    );
                  },
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
                  // barre qui se remplit à l'ouverture
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: (owned / total).clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 1400),
                    curve: const Cubic(0.2, 0.8, 0.2, 1),
                    builder: (_, f, __) => FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: f,
                      child: Container(color: complete ? kGold : brand),
                    ),
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

/// Rayons de soleil façon publicité rétro
class _RaysPainter extends CustomPainter {
  final Color color;
  final double angle;
  _RaysPainter(this.color, [this.angle = 0]);

  @override
  void paint(Canvas canvas, Size size) {
    final dark = Color.lerp(color, Colors.black, 0.3)!;
    canvas.drawRect(Offset.zero & size, Paint()..color = dark);
    final c = Offset(size.width / 2, size.height * 0.55);
    final r = size.longestSide * 1.2;
    const n = 22; // rayons
    final p = Paint()..color = color;
    for (var i = 0; i < n; i++) {
      final a0 = angle + i * 2 * pi / n, a1 = a0 + pi / n;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + r * cos(a0), c.dy + r * sin(a0))
        ..lineTo(c.dx + r * cos(a1), c.dy + r * sin(a1))
        ..close();
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _RaysPainter old) => old.color != color || old.angle != angle;
}

/// Petite étoile à 4 branches
class _SparkPainter extends CustomPainter {
  const _SparkPainter();
  @override
  void paint(Canvas canvas, Size z) {
    final w = z.width, h = z.height;
    final path = Path()
      ..moveTo(w * .5, 0)
      ..lineTo(w * .61, h * .39)
      ..lineTo(w, h * .5)
      ..lineTo(w * .61, h * .61)
      ..lineTo(w * .5, h)
      ..lineTo(w * .39, h * .61)
      ..lineTo(0, h * .5)
      ..lineTo(w * .39, h * .39)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => false;
}

/// Toutes les cartes qui peuvent sortir en full art (épiques et légendaires des consoles),
/// dans l'ordre des consoles, puis légendaires d'abord, puis numéro.
List<RcCard> fullArtCards() => [
      for (final sys in Catalog.systems)
        ...([for (final c in Catalog.bySys[sys.id] ?? const <RcCard>[]) if (!c.isSaga && c.rarity >= 3) c]
          ..sort((a, b) => a.rarity != b.rarity ? b.rarity - a.rarity : a.num - b.num)),
    ];

/// Case de la page Full art : la carte en full art si je l'ai, sinon une case vide.
class _FullArtSlot extends StatelessWidget {
  final RcCard card;
  final List<RcCard> list;
  const _FullArtSlot({required this.card, required this.list});

  @override
  Widget build(BuildContext context) {
    final has = (Game.i.owned[card.id]?[3] ?? 0) > 0;
    if (has) {
      return GestureDetector(
        onTap: () => openCardDetail(context, card, list: [for (final c in list) if ((Game.i.owned[c.id]?[3] ?? 0) > 0) c]),
        child: CardView(card: card, finish: 3),
      );
    }
    final sys = Catalog.system(card.sys);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.28),
          borderRadius: BorderRadius.circular(w * 0.075),
          border: Border.all(color: kRarityColor[card.rarity].withOpacity(0.35), width: 1.5),
        ),
        child: Stack(alignment: Alignment.center, children: [
          Text('★★', style: TextStyle(color: Colors.white.withOpacity(0.12), fontSize: w * 0.22, fontWeight: FontWeight.w900)),
          Positioned(
            left: 4,
            right: 4,
            bottom: w * 0.06,
            child: Text('${sys?.short ?? card.sys} #${card.num}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white38, fontSize: max(9, w * 0.085), fontWeight: FontWeight.w700)),
          ),
        ]),
      );
    });
  }
}
