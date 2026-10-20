import 'package:flutter/material.dart';

import 'album.dart';
import 'audio.dart';
import 'bourse.dart';
import 'cards.dart';
import 'catalog.dart';
import 'layout.dart';
import 'game.dart';
import 'main.dart';
import 'notifs.dart';
import 'retro_theme.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Marché (rubrique Bourse) : acheter les cartes des autres joueurs, vendre les
// siennes (le vendeur est payé immédiatement, 12 lots maximum par joueur)
// ═══════════════════════════════════════════════════════════════════════════

/// Mise en vente d'une carte (appelée depuis la fiche de la carte).
Future<void> sellCard(String card, int finish, int price, {bool quiet = false}) async {
  await RcServer.marketAdd(card, finish, price);
  if (quiet) return;
  await Game.i.sync();
  RcAudio.sfx('coin');
  toast(t('Carte mise en vente pour $price pièces', 'Card listed for $price coins'));
  BourseScreenState.current?.reload();
}

const kMaxListings = 12;

/// Achète un lot (avec confirmation). Vrai si acheté.
Future<bool> buyLot(BuildContext context, Map<String, dynamic> row) async {
  final c = Catalog.cards[row['card']];
  if (c == null) return false;
  final f = (row['finish'] as num).toInt();
  final price = (row['price'] as num).toInt();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('Acheter cette carte ?', 'Buy this card?')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 140, child: CardView(card: c, finish: f)),
        const SizedBox(height: 12),
        Text('${finishName(f)} — ${row['seller']}'),
        const SizedBox(height: 6),
        CoinChip(price),
        if (Game.i.has(c.id)) ...[
          const SizedBox(height: 8),
          Text(t('Tu possèdes déjà cette carte', 'You already own this card'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Annuler', 'Cancel'))),
        ElevatedButton(onPressed: Game.i.coins >= price ? () => Navigator.pop(ctx, true) : null, child: Text(t('Acheter', 'Buy'))),
      ],
    ),
  );
  if (ok != true) return false;
  var bought = false;
  try {
    final r = await RcServer.marketBuy((row['id'] as num).toInt());
    if (r == null) {
      toast(t('Trop tard : la carte vient d\'être vendue', 'Too late: the card was just sold'));
    } else {
      bought = true;
      Game.i.addRecent(c.id, f);
      Game.i.emit(r['events']);
      Game.i.playSound(c.rarity);
      toast(r['n'] == true ? t('Nouvelle carte : ${c.title} !', 'New card: ${c.title}!') : t('Carte achetée', 'Card bought'));
    }
    await Game.i.sync();
  } catch (e) {
    toast(errText(e));
  }
  BourseScreenState.current?.reload();
  return bought;
}

/// Les offres d'une carte, de la moins chère à la plus chère (feuille du bas).
/// [finish] : seulement cette finition (null = toutes).
Future<void> showCardOffers(BuildContext context, String cardId, {int? finish}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: kBg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (ctx, scroll) => _CardOffers(cardId: cardId, finish: finish, scroll: scroll, sheet: true),
    ),
  );
}

class _CardOffers extends StatefulWidget {
  final String cardId;
  final int? finish;
  final ScrollController scroll;
  final bool sheet; // dans une feuille du bas (téléphone) ; sinon panneau à droite (mode large)
  const _CardOffers({super.key, required this.cardId, required this.finish, required this.scroll, this.sheet = false});
  @override
  State<_CardOffers> createState() => _CardOffersState();
}

class _CardOffersState extends State<_CardOffers> {
  List<Map<String, dynamic>>? rows;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await RcServer.marketList(card: widget.cardId);
      r.removeWhere((x) => widget.finish != null && (x['finish'] as num).toInt() != widget.finish);
      r.sort((a, b) => (a['price'] as num).compareTo(b['price'] as num));
      if (mounted) setState(() => rows = r);
    } catch (e) {
      if (mounted) setState(() => error = errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Catalog.cards[widget.cardId];
    if (c == null) return const SizedBox();
    final known = Game.i.has(c.id);
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(16, 10, 16, 24), children: [
      Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
      const SizedBox(height: 12),
      Row(children: [
        // carte en vente : toujours montrée en entier (même si on ne l'a pas), dans la finition de l'offre la moins chère
        // toucher la carte : la voir en grand (on peut la faire tourner au doigt)
        Builder(builder: (context) {
          final f = widget.finish ?? (rows != null && rows!.isNotEmpty ? (rows!.first['finish'] as num).toInt() : 0);
          return GestureDetector(
            onTap: () => showDialog<void>(
              context: context,
              barrierColor: Colors.black.withOpacity(0.8),
              builder: (ctx) => GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Center(child: SizedBox(width: 280, child: SpinCard(card: c, finish: f))),
              ),
            ),
            child: SizedBox(width: 70, child: CardView(card: c, finish: f)),
          );
        }),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 2),
            Text('${Catalog.system(c.sys)?.name ?? c.sys} · ${rarityName(c.rarity)}', style: TextStyle(color: kRarityLight[c.rarity], fontSize: 12)),
            const SizedBox(height: 2),
            Text(
              known ? t('Tu en as ${Game.i.qty(c.id)}', 'You have ${Game.i.qty(c.id)}') : t('Il te manque cette carte', 'You don\'t have this card'),
              style: TextStyle(color: known ? Colors.white54 : const Color(0xFF5DCAA5), fontSize: 12),
            ),
          ]),
        ),
      ]),
      const SizedBox(height: 14),
      Text(t('Offres (moins chères d\'abord)', 'Offers (cheapest first)'), style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      if (error != null)
        _Retry(error!, load)
      else if (rows == null)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: kGold)))
      else if (rows!.isEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(t('Plus aucune offre pour cette carte', 'No more offers for this card'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
        )
      else
        for (var i = 0; i < rows!.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            decoration: BoxDecoration(
              color: kPanel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: i == 0 ? kGold.withOpacity(0.7) : Colors.transparent),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${rows![i]['seller']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    finishName((rows![i]['finish'] as num).toInt()) + (i == 0 ? t(' · le moins cher', ' · cheapest') : ''),
                    style: TextStyle(color: i == 0 ? kGold : Colors.white54, fontSize: 12),
                  ),
                ]),
              ),
              CoinChip((rows![i]['price'] as num).toInt()),
              const SizedBox(width: 6),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800), visualDensity: VisualDensity.compact),
                onPressed: () async {
                  if (await buyLot(context, rows![i])) {
                    // feuille du bas : on la ferme ; panneau du mode large : surtout pas de « pop »
                    // (il fermerait l'écran principal et ne laisserait que le fond)
                    if (widget.sheet && context.mounted) {
                      Navigator.of(context).pop();
                    } else {
                      load();
                      MarketGroupsState.current?.load();
                    }
                  } else {
                    load();
                  }
                },
                child: Text(t('Acheter', 'Buy')),
              ),
            ]),
          ),
    ]);
  }
}

/// Marché groupé : une ligne par carte (et finition) avec le prix le plus bas
/// et le nombre de lots. Toucher une ligne ouvre les offres triées par prix.
/// Acheter : recherche, filtres en pastilles, rubriques (Il te manque, Bonnes affaires,
/// Nouveautés) puis la grille de toutes les cartes en vente (chargée au fil du défilement).
/// Une seule requête (rc_market_browse) ; filtres et tri dans l'appli.
class MarketGroups extends StatefulWidget {
  const MarketGroups({super.key});
  @override
  State<MarketGroups> createState() => MarketGroupsState();
}

class MarketGroupsState extends State<MarketGroups> {
  static MarketGroupsState? current;
  List<Map<String, dynamic>>? rows;
  String? error;
  final search = TextEditingController();
  String query = '';
  String sys = '';
  bool missing = false;
  final rarities = <int>{};
  int? finish; // null : toutes
  int sort = 0; // 0 récents, 1 moins chers, 2 plus rares, 3 bonnes affaires
  (String, int)? sel; // mode large : carte dont les offres sont affichées à droite
  bool picking = false; // achat groupé : sélection de plusieurs cartes
  final picks = <(String, int), Map<String, dynamic>>{};
  final _offersScroll = ScrollController();

  @override
  void dispose() {
    if (current == this) current = null;
    _offersScroll.dispose();
    search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    current = this;
    load();
  }

  Future<void> load() async {
    if (error != null) setState(() => error = null);
    try {
      final r = await RcServer.marketBrowse();
      if (mounted) {
        setState(() {
          rows = r;
          // garde la sélection à jour (prix, cartes plus en vente)
          final now = {for (final x in r) (x['card'] as String, (x['finish'] as num).toInt()): x};
          picks.removeWhere((k, _) => !now.containsKey(k));
          for (final k in picks.keys.toList()) {
            picks[k] = now[k]!;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = errText(e));
    }
  }

  // ── Achat groupé ───────────────────────────────────────────────────────────
  static const _kMaxPicks = 30;

  int get _picksTotal => picks.values.fold(0, (a, r) => a + _price(r));

  void _toggle(Map<String, dynamic> r) {
    final k = (r['card'] as String, (r['finish'] as num).toInt());
    setState(() {
      picking = true;
      if (picks.remove(k) == null) {
        if (picks.length >= _kMaxPicks) {
          toast(t('$_kMaxPicks cartes maximum par achat', '$_kMaxPicks cards max per purchase'));
        } else {
          picks[k] = r;
        }
      }
    });
  }

  void _stopPicking() => setState(() {
        picking = false;
        picks.clear();
      });

  Future<void> _buyPicks() async {
    final items = picks.values.toList();
    final total = _picksTotal;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Acheter ${items.length} cartes ?', 'Buy ${items.length} cards?')),
        content: SizedBox(
          width: 340,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                child: Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: [
                  for (final r in items)
                    SizedBox(width: 58, child: CardView(card: Catalog.cards[r['card']]!, finish: (r['finish'] as num).toInt())),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            CoinChip(total),
            const SizedBox(height: 8),
            Text(t('L\'offre la moins chère de chaque carte. Si une carte part avant toi ou change de prix, elle est passée.',
                    'The cheapest offer of each card. A card sold meanwhile or repriced is skipped.'),
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Annuler', 'Cancel'))),
          ElevatedButton(onPressed: Game.i.coins >= total ? () => Navigator.pop(ctx, true) : null, child: Text(t('Acheter', 'Buy'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final r = await RcServer.marketBuyMany([for (final x in items) (x['card'] as String, (x['finish'] as num).toInt(), _price(x))]);
      final bought = (r['bought'] as List? ?? const []).cast<Map>();
      final skipped = (r['skipped'] as List? ?? const []).length;
      var best = -1, fresh = 0;
      for (final b in bought) {
        final c = Catalog.cards[b['card']];
        if (c == null) continue;
        Game.i.addRecent(c.id, (b['f'] as num).toInt());
        if (c.rarity > best) best = c.rarity;
        if (b['n'] == true) fresh++;
      }
      Game.i.emit(r['events']);
      if (best >= 0) Game.i.playSound(best);
      final n = bought.length;
      toast([
        n == 0 ? t('Aucune carte achetée', 'No card bought') : t('$n carte${n > 1 ? 's' : ''} achetée${n > 1 ? 's' : ''}', '$n card${n > 1 ? 's' : ''} bought'),
        if (fresh > 0) t('$fresh nouvelle${fresh > 1 ? 's' : ''}', '$fresh new'),
        if (skipped > 0) t('$skipped passée${skipped > 1 ? 's' : ''} (vendue ou prix changé)', '$skipped skipped (sold or repriced)'),
      ].join(' · '));
      if (mounted) _stopPicking();
      await Game.i.sync();
    } catch (e) {
      toast(errText(e));
    }
    BourseScreenState.current?.reload();
    load();
  }

  Widget _pickBar() {
    final total = _picksTotal, n = picks.length;
    final short = total - Game.i.coins;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 10),
      decoration: BoxDecoration(
        color: kPanel,
        border: Border(top: BorderSide(color: kGold.withOpacity(0.6))),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Row(children: [
          IconButton(icon: const Icon(Icons.close), tooltip: t('Annuler la sélection', 'Cancel selection'), onPressed: _stopPicking),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(n == 0 ? t('Touche les cartes à acheter', 'Tap the cards to buy') : '${t('$n carte${n > 1 ? 's' : ''}', '$n card${n > 1 ? 's' : ''}')} · 🪙 $total',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              if (n > 0 && short > 0)
                Text(t('Il te manque $short pièces', 'You need $short more coins'), style: const TextStyle(color: Color(0xFFFF5A5F), fontSize: 12)),
            ]),
          ),
          FilledButton(
            onPressed: n > 0 && short <= 0 ? _buyPicks : null,
            child: Text(t('Acheter', 'Buy'), style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ]),
      ),
    );
  }

  bool get _filtered => query.isNotEmpty || sys.isNotEmpty || missing || rarities.isNotEmpty || finish != null || sort != 0;

  static int _price(Map r) => (r['min_price'] as num).toInt();
  static int? _avg(Map r) => (r['avg'] as num?)?.toInt();
  /// Réduction par rapport au prix moyen payé sur 30 jours (≥ 20 % : bonne affaire)
  static int _discount(Map r) {
    final a = _avg(r);
    if (a == null || a <= 0) return 0;
    return ((1 - _price(r) / a) * 100).round();
  }

  static bool _isNew(Map r) {
    final d = DateTime.tryParse(r['last_at'] as String? ?? '');
    return d != null && DateTime.now().difference(d.toLocal()) < const Duration(hours: 24);
  }

  List<Map<String, dynamic>> _apply(List<Map<String, dynamic>> all) {
    final q = query.trim().toLowerCase();
    final out = all.where((r) {
      final c = Catalog.cards[r['card']];
      if (c == null) return false;
      if (sys.isNotEmpty && c.sys != sys) return false;
      if (missing && Game.i.has(c.id)) return false;
      if (rarities.isNotEmpty && !rarities.contains(c.rarity)) return false;
      if (finish != null && (r['finish'] as num).toInt() != finish) return false;
      if (q.isNotEmpty && !c.title.toLowerCase().contains(q)) return false;
      if (sort == 3 && _discount(r) < 20) return false;
      return true;
    }).toList();
    switch (sort) {
      case 1:
        out.sort((a, b) => _price(a).compareTo(_price(b)));
      case 2:
        out.sort((a, b) {
          final ra = Catalog.cards[a['card']]!.rarity, rb = Catalog.cards[b['card']]!.rarity;
          return ra != rb ? rb.compareTo(ra) : (b['finish'] as num).compareTo(a['finish'] as num);
        });
      case 3:
        out.sort((a, b) => _discount(b).compareTo(_discount(a)));
      default:
        break; // récents : ordre du serveur
    }
    return out;
  }

  Future<void> _open(Map<String, dynamic> r) async {
    if (picking) {
      _toggle(r);
      return;
    }
    final c = r['card'] as String, f = (r['finish'] as num).toInt();
    if (isWide(context)) {
      setState(() => sel = (c, f));
      return;
    }
    await showCardOffers(context, c, finish: f);
    load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _list(context);
    if (!isWide(context)) return list;
    // mode large : la liste à gauche, les offres de la carte choisie à droite
    final s = sel;
    return Row(children: [
      Expanded(child: list),
      Container(
        width: 430,
        decoration: BoxDecoration(
          color: kBg,
          border: const Border(left: BorderSide(color: Colors.white12)),
        ),
        child: s == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(t('Touche une carte pour voir ses offres', 'Tap a card to see its offers'),
                      textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
                ),
              )
            : _CardOffers(key: ValueKey(s), cardId: s.$1, finish: s.$2, scroll: _offersScroll),
      ),
    ]);
  }

  // ── Filtres ────────────────────────────────────────────────────────────────
  List<String> get _sortLabels => [t('Récents', 'Recent'), t('Moins chers', 'Cheapest'), t('Plus rares', 'Rarest'), t('Bonnes affaires', 'Good deals')];

  Widget _pill(String label, bool on, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: on ? const Color(0xFF06281B) : const Color(0xFFCFD3FF))),
          selected: on,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          selectedColor: const Color(0xFF5DCAA5),
          backgroundColor: kPanel,
          onSelected: (_) => onTap(),
        ),
      );

  Future<void> _filters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        void upd(VoidCallback f) {
          setS(f);
          setState(() {});
        }

        Widget opt(String label, bool on, VoidCallback onTap) => ChoiceChip(
              label: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: on ? rcTheme.onAccent : Colors.white70)),
              selected: on,
              showCheckmark: false,
              selectedColor: rcTheme.accent,
              backgroundColor: kPanel,
              onSelected: (_) => upd(onTap),
            );
        Widget title(String s) => Padding(padding: const EdgeInsets.only(top: 12, bottom: 6), child: Text(s, style: const TextStyle(color: Colors.white54, fontSize: 12.5)));
        final n = rows == null ? 0 : _apply(rows!).length;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 8),
              Row(children: [
                Text(t('Filtres', 'Filters'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const Spacer(),
                TextButton(
                  onPressed: () => upd(() {
                    sys = '';
                    missing = false;
                    rarities.clear();
                    finish = null;
                    sort = 0;
                  }),
                  child: Text(t('Tout effacer', 'Clear all')),
                ),
              ]),
              title(t('Console', 'System')),
              Wrap(spacing: 6, runSpacing: 6, children: [
                opt(t('Toutes', 'All'), sys.isEmpty, () => sys = ''),
                for (final s in [...Catalog.systems, ...Catalog.sagaSystems]) opt(s.name, sys == s.id, () => sys = s.id),
              ]),
              title(t('Rareté', 'Rarity')),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (var r = 0; r < 5; r++) opt(rarityName(r), rarities.contains(r), () => rarities.contains(r) ? rarities.remove(r) : rarities.add(r)),
              ]),
              title(t('Finition', 'Finish')),
              Wrap(spacing: 6, runSpacing: 6, children: [
                opt(t('Toutes', 'All'), finish == null, () => finish = null),
                for (var f = 0; f < kFinishes; f++) opt(finishName(f), finish == f, () => finish = f),
              ]),
              title(t('Trier par', 'Sort by')),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (var i = 0; i < 4; i++) opt(_sortLabels[i], sort == i, () => sort = i),
              ]),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(t('Voir $n carte${n > 1 ? 's' : ''}', 'See $n card${n > 1 ? 's' : ''}'), style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }

  Widget _list(BuildContext context) {
    final sysName = sys.isEmpty ? null : Catalog.system(sys)?.name;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: TextField(
          controller: search,
          onChanged: (v) => setState(() => query = v),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: t('Chercher un jeu…', 'Search a game…'),
            prefixIcon: const Icon(Icons.search, color: Colors.white54),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => setState(() {
                      search.clear();
                      query = '';
                    }),
                  ),
            isDense: true,
            filled: true,
            fillColor: const Color(0x33000000),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ),
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 6, 12, 2), children: [
          _pill(t('☑ Plusieurs', '☑ Several'), picking, () => picking ? _stopPicking() : setState(() => picking = true)),
          _pill(t('🎯 Manquantes', '🎯 Missing'), missing, () => setState(() => missing = !missing)),
          _pill('🎮 ${sysName ?? t('Console', 'System')} ▾', sys.isNotEmpty, _filters),
          _pill('💎 ${rarities.isEmpty ? t('Rareté', 'Rarity') : rarities.map(rarityName).join(', ')} ▾', rarities.isNotEmpty, _filters),
          _pill('✦ ${finish == null ? t('Finition', 'Finish') : finishName(finish!)} ▾', finish != null, _filters),
          _pill('↕ ${_sortLabels[sort]} ▾', sort != 0, _filters),
        ]),
      ),
      Expanded(child: _body()),
      if (picking) _pickBar(),
    ]);
  }

  // ── Contenu ────────────────────────────────────────────────────────────────
  Widget _tile(Map<String, dynamic> r, {String? tag, Color tagColor = const Color(0xFF5DCAA5)}) {
    final c = Catalog.cards[r['card']]!;
    final f = (r['finish'] as num).toInt();
    final lots = (r['lots'] as num).toInt();
    final picked = picks.containsKey((c.id, f));
    final selected = picked || (!picking && sel == (c.id, f));
    return GestureDetector(
      onTap: () => _open(r),
      onLongPress: () => _toggle(r),
      child: Padding(
        padding: const EdgeInsets.only(top: 7, right: 3, left: 3),
        child: Stack(clipBehavior: Clip.none, children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: selected ? [BoxShadow(color: kGold.withOpacity(0.8), blurRadius: 10, spreadRadius: 1)] : null,
            ),
            child: CardView(card: c, finish: f),
          ),
          if (lots > 1)
            Positioned(
              left: 5,
              bottom: 30,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.75), borderRadius: BorderRadius.circular(6)),
                child: Text('×$lots', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
              ),
            ),
          Positioned(
            right: -3,
            top: -7,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF2A1800),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kGold, width: 1.5),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2))],
              ),
              child: Text('🪙 ${_price(r)}', style: const TextStyle(color: Color(0xFFFFD166), fontSize: 11, fontWeight: FontWeight.w900)),
            ),
          ),
          if (picking)
            Positioned(
              right: 4,
              bottom: 30,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: picked ? kGold : Colors.black.withOpacity(0.55),
                  border: Border.all(color: picked ? Colors.white : Colors.white70, width: 1.5),
                ),
                child: picked ? const Icon(Icons.check, size: 15, color: Color(0xFF2A1800)) : null,
              ),
            ),
          if (tag != null)
            Positioned(
              left: -3,
              top: -7,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: tagColor, borderRadius: BorderRadius.circular(8)),
                child: Text(tag, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: tagColor == const Color(0xFF5DCAA5) ? const Color(0xFF06281B) : Colors.white)),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _row(String title, String sub, List<Map<String, dynamic>> items, {String? Function(Map<String, dynamic>)? tag, Color tagColor = const Color(0xFF5DCAA5), VoidCallback? all}) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
          const SizedBox(width: 6),
          Expanded(child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12))),
          if (all != null)
            GestureDetector(
              onTap: all,
              child: Text(t('Tout voir', 'See all'), style: const TextStyle(color: Color(0xFF8FD3FF), fontSize: 12, fontWeight: FontWeight.w800)),
            ),
        ]),
      ),
      SizedBox(
        height: 152,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 4),
          itemBuilder: (_, i) => SizedBox(width: 98, child: _tile(items[i], tag: tag?.call(items[i]), tagColor: tagColor)),
        ),
      ),
    ]);
  }

  Widget _body() {
    if (error != null) return _Retry(error!, load);
    if (rows == null) return const Center(child: CircularProgressIndicator(color: kGold));
    final all = rows!.where((r) => Catalog.cards.containsKey(r['card'])).toList();
    final list = _apply(all);
    final sections = <Widget>[];
    if (!_filtered) {
      final miss = all.where((r) => !Game.i.has(r['card'] as String)).toList();
      final deals = all.where((r) => _discount(r) >= 20).toList()..sort((a, b) => _discount(b).compareTo(_discount(a)));
      final fresh = all.where(_isNew).toList();
      sections.addAll([
        _row(t('🎯 Il te manque', '🎯 You\'re missing'), '${miss.length}', miss.take(12).toList(),
            tag: (_) => t('Manque', 'Missing'), all: miss.length > 12 ? () => setState(() => missing = true) : null),
        _row(t('💰 Bonnes affaires', '💰 Good deals'), t('moins chères que d\'habitude', 'cheaper than usual'), deals.take(12).toList(),
            tag: (r) => '-${_discount(r)}%', tagColor: const Color(0xFFFF5A5F), all: deals.length > 12 ? () => setState(() => sort = 3) : null),
        _row(t('🔥 Nouveautés', '🔥 New'), t('mises en vente aujourd\'hui', 'listed today'), fresh.take(12).toList()),
      ]);
    }
    if (all.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t('Aucune carte en vente pour le moment', 'No cards for sale right now'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: load,
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: Column(children: sections)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: _filtered ? t('Résultats', 'Results') : t('Toutes les offres', 'All offers'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
                TextSpan(text: '  ${list.length} ${t('carte', 'card')}${list.length > 1 ? 's' : ''}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ]),
            ),
          ),
        ),
        if (list.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(t('Aucune carte ne correspond', 'No card matches'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 20),
            // grille : construite au fil du défilement (seules les cartes visibles sont dessinées)
            sliver: SliverLayoutBuilder(
              builder: (context, box) => SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: adaptiveCols(context, box.crossAxisExtent, phone: 3, minTile: 120, max: 7),
                  childAspectRatio: 0.66,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                delegate: SliverChildBuilderDelegate((_, i) => _tile(list[i], tag: Game.i.has(list[i]['card'] as String) ? null : t('Manque', 'Missing')), childCount: list.length),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Mes lots en vente et vendus récemment.
class MyListings extends StatefulWidget {
  const MyListings({super.key});
  @override
  State<MyListings> createState() => MyListingsState();
}

class MyListingsState extends State<MyListings> {
  List<Map<String, dynamic>>? rows;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (error != null) setState(() => error = null);
    try {
      final r = await RcServer.marketMine();
      if (mounted) setState(() => rows = r);
    } catch (e) {
      if (mounted) setState(() => error = errText(e));
    }
  }

  Future<void> _openPicker(bool multi, int open) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SellPickerPage(multi: multi, slots: kMaxListings - open)),
    );
    if (changed == true) {
      load();
      BourseScreenState.current?.reload();
    }
  }

  Future<void> _cancel(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Retirer de la vente ?', 'Remove from sale?')),
        content: Text(t('La carte revient dans ta collection.', 'The card goes back to your collection.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Annuler', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Retirer', 'Remove'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (await RcServer.marketCancel(id)) toast(t('Carte retirée de la vente', 'Card removed from sale'));
      await Game.i.sync();
    } catch (e) {
      toast(errText(e));
    }
    load();
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) return _Retry(error!, load);
    if (rows == null) return const Center(child: CircularProgressIndicator(color: kGold));
    final list = rows!.where((r) => Catalog.cards.containsKey(r['card'])).toList();
    final forSale = list.where((r) => r['sold'] != true).toList();
    final sold = list.where((r) => r['sold'] == true).toList()
      // les plus récentes d'abord (les nouvelles ventes en tête)
      ..sort((a, b) => (b['sold_at']?.toString() ?? '').compareTo(a['sold_at']?.toString() ?? ''));
    final fresh = sold.where((r) => Notifs.i.isFreshSale(r['id'])).toList();
    final freshTotal = fresh.fold<int>(0, (a, r) => a + (r['price'] as num).toInt());
    final soldTotal = sold.fold<int>(0, (a, r) => a + (r['price'] as num).toInt());
    final open = forSale.length;
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
              onPressed: open >= kMaxListings ? null : () => _openPicker(false, open),
              icon: const Icon(Icons.sell),
              label: Text(t('Vendre une carte', 'Sell a card'), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: open >= kMaxListings || Game.i.dupes == 0 ? null : () => _openPicker(true, open),
              icon: const Icon(Icons.copy_all),
              label: Text(t('Mes doublons', 'My duplicates')),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: open / kMaxListings, minHeight: 5, color: kGold, backgroundColor: Colors.white12),
            ),
          ),
          const SizedBox(width: 10),
          Text(t('$open / $kMaxListings lots', '$open / $kMaxListings listings'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(t('Rien en vente', 'Nothing for sale'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
          ),
        if (forSale.isNotEmpty) ...[
          _head(t('En vente', 'For sale'), '${forSale.length}'),
          _grid([for (final r in forSale) _listing(r)]),
        ],
        if (fresh.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F6E56).withOpacity(0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF5DCAA5), width: 1.5),
            ),
            child: Row(children: [
              const Text('💰', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    fresh.length == 1
                        ? t('Nouvelle vente : ${Catalog.cards[fresh.first['card']]?.title ?? '?'} à ${fresh.first['buyer'] ?? '?'} (+$freshTotal 🪙)',
                            'New sale: ${Catalog.cards[fresh.first['card']]?.title ?? '?'} to ${fresh.first['buyer'] ?? '?'} (+$freshTotal 🪙)')
                        : t('${fresh.length} nouvelles ventes : +$freshTotal 🪙', '${fresh.length} new sales: +$freshTotal 🪙'),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
              ),
            ]),
          ),
        if (sold.isNotEmpty) ...[
          _head(t('Vendues récemment', 'Recently sold'), t('+$soldTotal 🪙 sur 7 jours', '+$soldTotal 🪙 in 7 days')),
          _grid([for (final r in sold) _listing(r)]),
        ],
      ]),
    );
  }

  Widget _head(String title, String sub) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
          const SizedBox(width: 6),
          Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
      );

  Widget _grid(List<Widget> children) => LayoutBuilder(
        builder: (context, box) => GridView.count(
          crossAxisCount: adaptiveCols(context, box.maxWidth, phone: 3, minTile: 130, max: 7),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.52,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          children: children,
        ),
      );

  /// Une carte en vente (prix, bouton « Retirer de la vente ») ou vendue (tampon VENDUE, acheteur)
  Widget _listing(Map<String, dynamic> r) {
    final c = Catalog.cards[r['card']]!;
    final f = (r['finish'] as num).toInt();
    final isSold = r['sold'] == true;
    final isNew = isSold && Notifs.i.isFreshSale(r['id']);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.only(top: 7, left: 3, right: 3),
        child: Stack(clipBehavior: Clip.none, children: [
          isSold && !isNew
              ? ColorFiltered(
                  colorFilter: const ColorFilter.matrix(<double>[
                    0.45, 0.25, 0.08, 0, 0, //
                    0.2, 0.5, 0.08, 0, 0, //
                    0.2, 0.25, 0.3, 0, 0, //
                    0, 0, 0, 1, 0,
                  ]),
                  child: CardView(card: c, finish: f))
              : GestureDetector(onTap: () => showCardOffers(context, c.id, finish: f), child: CardView(card: c, finish: f)),
          Positioned(
            right: -3,
            top: -7,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: const Color(0xFF2A1800), borderRadius: BorderRadius.circular(10), border: Border.all(color: kGold, width: 1.5)),
              child: Text('🪙 ${(r['price'] as num).toInt()}', style: const TextStyle(color: Color(0xFFFFD166), fontSize: 11, fontWeight: FontWeight.w900)),
            ),
          ),
          if (isNew)
            Positioned(
              left: -3,
              top: -7,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: const Color(0xFFE24B4A), borderRadius: BorderRadius.circular(10)),
                child: Text(t('NOUVEAU', 'NEW'), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
              ),
            ),
          if (isSold)
            Positioned.fill(
              child: Center(
                child: Transform.rotate(
                  angle: -0.2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFF1F6B52), borderRadius: BorderRadius.circular(5), border: Border.all(color: const Color(0xFF5DCAA5), width: 1.5)),
                    child: Text(t('VENDUE', 'SOLD'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                  ),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 4),
      if (isSold)
        Text(t('à ${r['buyer'] ?? '?'}', 'to ${r['buyer'] ?? '?'}'),
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF5DCAA5), fontSize: 11.5, fontWeight: FontWeight.w700))
      else
        // bouton bien visible pour reprendre la carte
        SizedBox(
          width: double.infinity,
          height: 30,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              side: const BorderSide(color: Color(0xFFFF8A95), width: 1.5),
              foregroundColor: const Color(0xFFFFC4CF),
              backgroundColor: const Color(0xFF4A1D2A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => _cancel((r['id'] as num).toInt()),
            icon: const Icon(Icons.undo, size: 15),
            label: Text(t('Retirer', 'Remove'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
          ),
        ),
    ]);
  }
}

class _Retry extends StatelessWidget {
  final String msg;
  final Future<void> Function() onRetry;
  const _Retry(this.msg, this.onRetry);
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(msg, style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: onRetry, child: Text(t('Réessayer', 'Retry'))),
        ]),
      );
}

// Utilisé par album.dart (ouverture de la fiche depuis le marché)
void openCard(BuildContext context, RcCard c) => openCardDetail(context, c);

// ─── Prix conseillé ─────────────────────────────────────────────────────────
/// Données du marché pour une carte : {avg, sold, min, open} (vide hors ligne)
Future<Map<String, dynamic>> marketPriceInfo(String card, int finish) async {
  try {
    return await RcServer.marketPrice(card, finish);
  } catch (_) {
    return const {};
  }
}

/// Prix conseillé : moyenne des ventes récentes, sinon le moins cher en vente,
/// sinon 2 × la valeur au recyclage. Jamais en dessous du recyclage + 1.
int suggestedPrice(RcCard c, int finish, Map<String, dynamic> info) {
  final rec = recycleValue(c.rarity, finish);
  final avg = (info['avg'] as num?)?.toInt();
  final min = (info['min'] as num?)?.toInt();
  final p = avg ?? min ?? rec * 2;
  return p.clamp(rec + 1, 99999);
}

// ─── Choix des cartes à vendre ─────────────────────────────────────────────
/// [multi] : sélection de plusieurs doublons d'un coup (un exemplaire de chacun),
/// sinon une seule carte (avec choix du prix). [slots] : lots encore disponibles.
class SellPickerPage extends StatefulWidget {
  final bool multi;
  final int slots;
  const SellPickerPage({super.key, required this.multi, required this.slots});
  @override
  State<SellPickerPage> createState() => _SellPickerPageState();
}

class _SellPickerPageState extends State<SellPickerPage> {
  String sys = '';
  String q = ''; // recherche par nom
  late bool onlyDupes = widget.multi || Game.i.dupes > 0;
  final selected = <(String, int)>[];
  bool busy = false;

  List<(RcCard, int, int)> _items() {
    final out = <(RcCard, int, int)>[];
    Game.i.owned.forEach((id, q) {
      final c = Catalog.cards[id];
      if (c == null || (sys.isNotEmpty && c.sys != sys)) return;
      if (this.q.isNotEmpty && !c.title.toLowerCase().contains(this.q.toLowerCase())) return;
      final total = qSum(q);
      if (onlyDupes && total < 2) return;
      for (var f = 0; f < kFinishes; f++) {
        if (q[f] > 0) out.add((c, f, q[f]));
      }
    });
    out.sort((a, b) => b.$1.rarity != a.$1.rarity
        ? b.$1.rarity.compareTo(a.$1.rarity)
        : (b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$1.id.compareTo(b.$1.id)));
    return out;
  }

  Future<void> _sellOne(RcCard c, int f) async {
    if (Game.i.qty(c.id) <= 1) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('Dernier exemplaire', 'Last copy')),
          content: Text(t('C\'est ta seule ${c.title}. Si elle est vendue, elle quittera ta collection.',
              'This is your only ${c.title}. If it sells, it will leave your collection.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Annuler', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Vendre quand même', 'Sell anyway'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final price = await askPrice(context, c, f);
    if (price == null || !mounted) return;
    setState(() => busy = true);
    try {
      await sellCard(c.id, f, price);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      toast(errText(e));
      if (mounted) setState(() => busy = false);
    }
  }

  void _toggle(RcCard c, int f) {
    final k = (c.id, f);
    setState(() {
      if (selected.contains(k)) {
        selected.remove(k);
      } else if (selected.length >= widget.slots) {
        toast(t('Plus que ${widget.slots} lot(s) disponible(s)', 'Only ${widget.slots} listing slot(s) left'));
      } else {
        selected.add(k);
      }
    });
  }

  Future<void> _sellSelected() async {
    if (selected.isEmpty) return;
    setState(() => busy = true);
    // prix conseillés en parallèle
    final infos = await Future.wait([for (final (id, f) in selected) marketPriceInfo(id, f)]);
    if (!mounted) return;
    final ctls = [
      for (var i = 0; i < selected.length; i++)
        TextEditingController(text: '${suggestedPrice(Catalog.cards[selected[i].$1]!, selected[i].$2, infos[i])}'),
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Mettre en vente ${selected.length} carte(s)', 'List ${selected.length} card(s)')),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(shrinkWrap: true, children: [
            Text(t('Prix conseillés d\'après le marché (modifiables) :', 'Suggested prices from the market (editable):'),
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 8),
            for (var i = 0; i < selected.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  SizedBox(width: 34, child: CardView(card: Catalog.cards[selected[i].$1]!, finish: selected[i].$2)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(Catalog.cards[selected[i].$1]!.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  ),
                  SizedBox(
                    width: 84,
                    child: TextField(
                      controller: ctls[i],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(isDense: true, suffixIcon: Icon(Icons.monetization_on, color: kGold, size: 16)),
                    ),
                  ),
                ]),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Annuler', 'Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Mettre en vente', 'List them'), style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true) {
      if (mounted) setState(() => busy = false);
      return;
    }
    var done = 0;
    String? err;
    for (var i = 0; i < selected.length; i++) {
      final p = int.tryParse(ctls[i].text.trim());
      if (p == null || p < 1 || p > 99999) continue;
      try {
        await sellCard(selected[i].$1, selected[i].$2, p, quiet: true);
        done++;
      } catch (e) {
        err = errText(e);
        break;
      }
    }
    await Game.i.sync();
    if (done > 0) RcAudio.sfx('coin');
    toast(err ?? t('$done carte(s) mise(s) en vente', '$done card(s) listed'));
    if (mounted) Navigator.pop(context, done > 0);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.multi ? t('Vendre mes doublons', 'Sell my duplicates') : t('Vendre une carte', 'Sell a card')),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            onChanged: (v) => setState(() => q = v.trim()),
            decoration: InputDecoration(
              hintText: t('Chercher un jeu…', 'Search a game…'),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              isDense: true,
              filled: true,
              fillColor: const Color(0x33000000),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(children: [
            Expanded(
              child: DropdownButton<String>(
                value: sys,
                isExpanded: true,
                underline: const SizedBox(),
                items: [
                  DropdownMenuItem(value: '', child: Text(t('Toutes les consoles', 'All systems'))),
                  for (final s in [...Catalog.systems, ...Catalog.sagaSystems]) DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() => sys = v ?? ''),
              ),
            ),
            if (!widget.multi)
              FilterChip(
                label: Text(t('Doublons', 'Duplicates')),
                selected: onlyDupes,
                selectedColor: const Color(0xFF412402),
                onSelected: (v) => setState(() => onlyDupes = v),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            widget.multi
                ? t('Touche les cartes à vendre (un exemplaire de chaque, tu gardes les autres)', 'Tap the cards to sell (one copy each, you keep the rest)')
                : t('Touche la carte à vendre', 'Tap the card to sell'),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(child: Text(t('Aucune carte', 'No cards'), style: const TextStyle(color: Colors.white38)))
              : GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: adaptiveCols(context, MediaQuery.sizeOf(context).width, phone: 3, minTile: 130, max: 8),
                      childAspectRatio: 5 / 7.6,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final (c, f, n) = items[i];
                    final sel = selected.contains((c.id, f));
                    return GestureDetector(
                      onTap: busy ? null : () => widget.multi ? _toggle(c, f) : _sellOne(c, f),
                      child: Stack(clipBehavior: Clip.none, children: [
                        Positioned.fill(child: Align(alignment: Alignment.topCenter, child: CardView(card: c, finish: f))),
                        if (sel)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: kGold, width: 3),
                                color: kGold.withOpacity(0.18),
                              ),
                              child: const Center(child: Icon(Icons.check_circle, color: kGold, size: 36)),
                            ),
                          ),
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: kPanel2, borderRadius: BorderRadius.circular(6)),
                            child: Text('×$n', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ]),
                    );
                  },
                ),
        ),
        if (widget.multi)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
                  onPressed: busy || selected.isEmpty ? null : _sellSelected,
                  icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sell),
                  label: Text(t('Mettre en vente (${selected.length}/${widget.slots})', 'List them (${selected.length}/${widget.slots})'),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
