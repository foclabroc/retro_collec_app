import 'package:flutter/material.dart';

import 'album.dart';
import 'cards.dart';
import 'catalog.dart';
import 'game.dart';
import 'layout.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Filtres et tri des cartes : albums des consoles et « Toutes mes cartes ».
// Les choix sont gardés pendant que l'appli est ouverte.
// ═══════════════════════════════════════════════════════════════════════════

class CardFilter {
  int show = 0; // 0 toutes, 1 possédées, 2 manquantes, 3 doublons, 4 brillantes ou dorées, 5 dorées
  final rarities = <int>{}; // vide = toutes
  String? genre; // null = tous
  int sort = 0; // 0 numéro, 1 rareté, 2 année ↑, 3 année ↓, 4 nom, 5 exemplaires
  String query = '';

  static final album = CardFilter(); // albums des consoles
  static final all = CardFilter()..show = 1; // toutes mes cartes

  /// Nombre de réglages actifs (pastille du bouton)
  int get active => (show != 0 ? 1 : 0) + (rarities.isNotEmpty ? 1 : 0) + (genre != null ? 1 : 0) + (sort != 0 ? 1 : 0);

  void reset({int defShow = 0}) {
    show = defShow;
    rarities.clear();
    genre = null;
    sort = 0;
  }

  List<RcCard> apply(Iterable<RcCard> cards) {
    final g = Game.i;
    final q = query.trim().toLowerCase();
    final out = cards.where((c) {
      final own = g.owned[c.id] ?? const [0, 0, 0, 0];
      final n = qSum(own);
      final ok = switch (show) {
        1 => n > 0,
        2 => n == 0,
        3 => n > 1,
        4 => own[1] + own[2] + own[3] > 0,
        5 => own[2] > 0,
        6 => own[3] > 0,
        _ => true,
      };
      if (!ok) return false;
      if (rarities.isNotEmpty && !rarities.contains(c.rarity)) return false;
      if (genre != null && c.genreL != genre) return false;
      // recherche par nom : seulement les cartes connues (on ne dévoile pas les autres)
      if (q.isNotEmpty && (n == 0 || !c.title.toLowerCase().contains(q))) return false;
      return true;
    }).toList();
    int byNum(RcCard a, RcCard b) => a.sys != b.sys ? a.sys.compareTo(b.sys) : a.num.compareTo(b.num);
    switch (sort) {
      case 1:
        out.sort((a, b) => a.rarity != b.rarity ? b.rarity.compareTo(a.rarity) : byNum(a, b));
      case 2:
      case 3:
        out.sort((a, b) {
          final ya = a.year ?? 9999, yb = b.year ?? 9999;
          final c = sort == 2 ? ya.compareTo(yb) : yb.compareTo(ya);
          return c != 0 ? c : byNum(a, b);
        });
      case 4:
        out.sort((a, b) {
          final ka = g.has(a.id), kb = g.has(b.id);
          if (ka != kb) return ka ? -1 : 1; // cartes inconnues à la fin
          return ka ? a.title.toLowerCase().compareTo(b.title.toLowerCase()) : byNum(a, b);
        });
      case 5:
        out.sort((a, b) {
          final c = g.qty(b.id).compareTo(g.qty(a.id));
          return c != 0 ? c : byNum(a, b);
        });
      default:
        out.sort(byNum);
    }
    return out;
  }
}

List<String> get _showLabels => [
      t('Toutes', 'All'),
      t('Possédées', 'Owned'),
      t('Manquantes', 'Missing'),
      t('Doublons', 'Duplicates'),
      t('Brillantes ✦', 'Holo ✦'),
      t('Dorées ★', 'Gold ★'),
      t('Full art ★★', 'Full art ★★'),
    ];

List<String> get _sortLabels => [
      t('Numéro', 'Number'),
      t('Rareté', 'Rarity'),
      t('Année ↑', 'Year ↑'),
      t('Année ↓', 'Year ↓'),
      t('Nom A→Z', 'Name A→Z'),
      t('Exemplaires', 'Copies'),
    ];

/// Petit résumé du filtre actif (ex. « Possédées · Rare · tri Année ↑ »)
String filterSummary(CardFilter f) {
  final parts = <String>[
    if (f.show != 0) _showLabels[f.show],
    if (f.rarities.isNotEmpty) (f.rarities.toList()..sort()).map(rarityName).join(', '),
    if (f.genre != null) f.genre!,
    if (f.sort != 0) '${t('tri', 'sort')} ${_sortLabels[f.sort]}',
  ];
  return parts.join(' · ');
}

/// Bouton « Filtres » avec pastille du nombre de réglages actifs
class FilterButton extends StatelessWidget {
  final CardFilter filter;
  final Iterable<RcCard> source; // pour la liste des genres
  final VoidCallback onChanged;
  final int defShow;
  const FilterButton({super.key, required this.filter, required this.source, required this.onChanged, this.defShow = 0});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: t('Filtres et tri', 'Filters and sort'),
        icon: Badge(
          isLabelVisible: filter.active > 0,
          label: Text('${filter.active}'),
          child: const Icon(Icons.tune),
        ),
        onPressed: () async {
          await showFilterSheet(context, filter, source, defShow: defShow);
          onChanged();
        },
      );
}

Future<void> showFilterSheet(BuildContext context, CardFilter f, Iterable<RcCard> source, {int defShow = 0}) {
  final genres = {for (final c in source) if (c.genreL.isNotEmpty) c.genreL}.toList()..sort();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: kBg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        Widget title(String s) => Padding(
              padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
              child: Text(s, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            );
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: kHandle, borderRadius: BorderRadius.circular(2)))),
                title(t('Afficher', 'Show')),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (var i = 0; i < _showLabels.length; i++)
                    ChoiceChip(
                      label: Text(_showLabels[i]),
                      selected: f.show == i,
                      selectedColor: const Color(0xFF412402),
                      onSelected: (_) => set(() => f.show = i),
                    ),
                ]),
                title(t('Rareté', 'Rarity')),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (var r = 0; r < 5; r++)
                    FilterChip(
                      label: Text(rarityName(r), style: TextStyle(color: kRarityLight[r], fontWeight: FontWeight.w700)),
                      selected: f.rarities.contains(r),
                      selectedColor: kRarityDark[r],
                      side: BorderSide(color: kRarityColor[r]),
                      onSelected: (v) => set(() => v ? f.rarities.add(r) : f.rarities.remove(r)),
                    ),
                ]),
                if (genres.isNotEmpty) ...[
                  title(t('Genre', 'Genre')),
                  DropdownButton<String?>(
                    value: f.genre,
                    isExpanded: true,
                    hint: Text(t('Tous les genres', 'All genres')),
                    items: [
                      DropdownMenuItem<String?>(value: null, child: Text(t('Tous les genres', 'All genres'))),
                      for (final g in genres) DropdownMenuItem<String?>(value: g, child: Text(g, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => set(() => f.genre = v),
                  ),
                ],
                title(t('Trier par', 'Sort by')),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (var i = 0; i < _sortLabels.length; i++)
                    ChoiceChip(
                      label: Text(_sortLabels[i]),
                      selected: f.sort == i,
                      selectedColor: kPanel2,
                      onSelected: (_) => set(() => f.sort = i),
                    ),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => set(() => f.reset(defShow: defShow)),
                      child: Text(t('Réinitialiser', 'Reset')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(t('Voir les cartes', 'Show cards'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        );
      },
    ),
  );
}

/// Grille de cartes (album, toutes mes cartes) avec le nombre d'exemplaires
class CardGrid extends StatelessWidget {
  final List<RcCard> cards;
  const CardGrid(this.cards, {super.key});

  @override
  Widget build(BuildContext context) {
    final g = Game.i;
    if (cards.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t('Aucune carte avec ces filtres', 'No cards match these filters'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
        ),
      );
    }
    // 3 colonnes sur téléphone, 4 à 8 sur tablette / PC
    return LayoutBuilder(builder: (context, box) => GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: adaptiveCols(context, box.maxWidth, phone: 3, minTile: 120, max: 8),
          childAspectRatio: 5 / 7.4,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8),
      itemCount: cards.length,
      itemBuilder: (_, i) {
        final c = cards[i];
        final q = g.owned[c.id];
        final best = q == null ? 0 : bestFinish(q);
        final n = g.qty(c.id);
        return GestureDetector(
          onTap: () => openCardDetail(context, c, list: cards),
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(child: Align(alignment: Alignment.topCenter, child: CardView(card: c, finish: best, owned: n > 0))),
            if (n > 1)
              Positioned(
                right: 2,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(8)),
                  child: Text('×$n', style: const TextStyle(color: Color(0xFF412402), fontSize: 11, fontWeight: FontWeight.w800)),
                ),
              ),
          ]),
        );
      },
    ));
  }
}

/// Toutes mes cartes, toutes consoles : recherche par nom, filtres et tri
class AllCardsPage extends StatefulWidget {
  const AllCardsPage({super.key});
  @override
  State<AllCardsPage> createState() => _AllCardsPageState();
}

class _AllCardsPageState extends State<AllCardsPage> {
  final f = CardFilter.all;
  late final ctl = TextEditingController(text: f.query);

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Game.i,
      builder: (context, _) {
        final list = f.apply(Catalog.cards.values);
        final summary = filterSummary(f);
        return Scaffold(
          appBar: AppBar(
            title: Text(t('Mes cartes', 'My cards')),
            actions: [
              FilterButton(filter: f, source: Catalog.cards.values, defShow: 1, onChanged: () => setState(() {})),
              const SizedBox(width: 6),
            ],
          ),
          body: SplitCardDetail(child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              child: TextField(
                controller: ctl,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: t('Chercher un jeu', 'Search a game'),
                  isDense: true,
                  filled: true,
                  fillColor: kCell,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  suffixIcon: f.query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            ctl.clear();
                            f.query = '';
                          }),
                        ),
                ),
                onChanged: (v) => setState(() => f.query = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
              child: Row(children: [
                Expanded(
                  child: Text(summary.isEmpty ? t('Toutes les cartes', 'All cards') : summary,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ),
                Text(t('${list.length} carte(s)', '${list.length} card(s)'), style: const TextStyle(color: kGold, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
            Expanded(child: CardGrid(list)),
          ])),
        );
      },
    );
  }
}
