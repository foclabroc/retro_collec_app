import 'package:flutter/material.dart';

import 'album.dart';
import 'audio.dart';
import 'cards.dart';
import 'catalog.dart';
import 'game.dart';
import 'main.dart';
import 'notifs.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Marché : acheter les cartes des autres joueurs, vendre les siennes
// (le vendeur est payé immédiatement, 12 lots maximum par joueur)
// ═══════════════════════════════════════════════════════════════════════════

/// Mise en vente d'une carte (appelée depuis la fiche de la carte).
Future<void> sellCard(String card, int finish, int price, {bool quiet = false}) async {
  await RcServer.marketAdd(card, finish, price);
  if (quiet) return;
  await Game.i.sync();
  RcAudio.sfx('coin');
  toast(t('Carte mise en vente pour $price pièces', 'Card listed for $price coins'));
  MarketScreenState.current?.reload();
}

const kMaxListings = 12;

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});
  @override
  State<MarketScreen> createState() => MarketScreenState();
}

class MarketScreenState extends State<MarketScreen> with SingleTickerProviderStateMixin {
  static MarketScreenState? current;
  late final TabController tabs = TabController(length: 2, vsync: this);
  final _buyKey = GlobalKey<_MarketListState>();
  final _mineKey = GlobalKey<_MyListingsState>();

  @override
  void initState() {
    super.initState();
    current = this;
  }

  @override
  void dispose() {
    if (current == this) current = null;
    tabs.dispose();
    super.dispose();
  }

  void reload() {
    _buyKey.currentState?.load();
    _mineKey.currentState?.load();
  }

  /// Onglet Marché ouvert : s'il y a eu des ventes, on montre « Mes ventes »
  void opened() {
    if (Notifs.i.sales.isNotEmpty) tabs.animateTo(1);
    Notifs.i.salesSeen();
    reload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TabHeader(t('Marché', 'Market'), actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: reload,
        ),
      ]),
      TabBar(controller: tabs, indicatorColor: kGold, labelColor: kGold, tabs: [
        Tab(text: t('Acheter', 'Buy')),
        Tab(text: t('Mes ventes', 'My sales')),
      ]),
      Expanded(
        child: TabBarView(controller: tabs, children: [
          MarketList(key: _buyKey),
          MyListings(key: _mineKey),
        ]),
      ),
    ]);
  }
}

/// Liste des lots en vente (filtrable).
class MarketList extends StatefulWidget {
  final String? cardId; // recherche d'une carte précise
  const MarketList({super.key, this.cardId});
  @override
  State<MarketList> createState() => _MarketListState();
}

class _MarketListState extends State<MarketList> {
  List<Map<String, dynamic>>? rows;
  String? error;
  String sys = '';
  bool missing = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (error != null) setState(() => error = null);
    try {
      final r = await RcServer.marketList(sys: sys.isEmpty ? null : sys, card: widget.cardId, missing: missing);
      if (mounted) setState(() => rows = r);
    } catch (e) {
      if (mounted) setState(() => error = errText(e));
    }
  }

  Future<void> _buy(Map<String, dynamic> row) async {
    final c = Catalog.cards[row['card']];
    if (c == null) return;
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
    if (ok != true) return;
    try {
      final r = await RcServer.marketBuy((row['id'] as num).toInt());
      if (r == null) {
        toast(t('Trop tard : la carte vient d\'être vendue', 'Too late: the card was just sold'));
      } else {
        Game.i.emit(r['events']);
        Game.i.playSound(c.rarity);
        toast(r['n'] == true ? t('Nouvelle carte : ${c.title} !', 'New card: ${c.title}!') : t('Carte achetée', 'Card bought'));
      }
      await Game.i.sync();
    } catch (e) {
      toast(errText(e));
    }
    load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      if (widget.cardId == null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            Expanded(
              child: DropdownButton<String>(
                value: sys,
                isExpanded: true,
                underline: const SizedBox(),
                items: [
                  DropdownMenuItem(value: '', child: Text(t('Toutes les consoles', 'All systems'))),
                  for (final s in Catalog.systems) DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) {
                  setState(() => sys = v ?? '');
                  load();
                },
              ),
            ),
            FilterChip(
              label: Text(t('Mes manquantes', 'Missing only')),
              selected: missing,
              selectedColor: const Color(0xFF412402),
              onSelected: (v) {
                setState(() => missing = v);
                load();
              },
            ),
          ]),
        ),
      Expanded(child: _body()),
    ]);
  }

  Widget _body() {
    if (error != null) return _Retry(error!, load);
    if (rows == null) return const Center(child: CircularProgressIndicator(color: kGold));
    final list = rows!.where((r) => Catalog.cards.containsKey(r['card'])).toList();
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t('Aucune carte en vente pour le moment', 'No cards for sale right now'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final r = list[i];
          final c = Catalog.cards[r['card']]!;
          final f = (r['finish'] as num).toInt();
          final price = (r['price'] as num).toInt();
          final mine = Game.i.has(c.id);
          return Material(
            color: kPanel,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _buy(r),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  SizedBox(width: 62, child: CardView(card: c, finish: f)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('${Catalog.system(c.sys)?.name ?? c.sys} · ${rarityName(c.rarity)}${f > 0 ? ' · ${finishName(f)}' : ''}',
                          style: TextStyle(color: kRarityLight[c.rarity], fontSize: 12)),
                      const SizedBox(height: 2),
                      Text('${t('Vendeur', 'Seller')} : ${r['seller']}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      if (!mine)
                        Text(t('Il te manque cette carte', 'You don\'t have this card'), style: const TextStyle(color: Color(0xFF5DCAA5), fontSize: 11)),
                    ]),
                  ),
                  CoinChip(price),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Mes lots en vente et vendus récemment.
class MyListings extends StatefulWidget {
  const MyListings({super.key});
  @override
  State<MyListings> createState() => _MyListingsState();
}

class _MyListingsState extends State<MyListings> {
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
      MarketScreenState.current?._buyKey.currentState?.load();
    }
  }

  Future<void> _cancel(int id) async {
    try {
      if (await RcServer.marketCancel(id)) toast(t('Carte reprise', 'Card taken back'));
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
    final open = list.where((r) => r['sold'] != true).length;
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
        const SizedBox(height: 12),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(t('Rien en vente', 'Nothing for sale'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
          ),
        for (final r in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                SizedBox(width: 56, child: CardView(card: Catalog.cards[r['card']]!, finish: (r['finish'] as num).toInt())),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(Catalog.cards[r['card']]!.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    if (r['sold'] == true)
                      Text(t('Vendue à ${r['buyer'] ?? '?'}', 'Sold to ${r['buyer'] ?? '?'}'), style: const TextStyle(color: Color(0xFF5DCAA5), fontSize: 12))
                    else
                      Text(t('En vente', 'For sale'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ]),
                ),
                CoinChip((r['price'] as num).toInt()),
                if (r['sold'] != true)
                  IconButton(
                    tooltip: t('Reprendre', 'Take back'),
                    icon: const Icon(Icons.undo),
                    onPressed: () => _cancel((r['id'] as num).toInt()),
                  ),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Recherche d'une carte précise au marché (depuis sa fiche).
class MarketSearchPage extends StatelessWidget {
  final String cardId;
  const MarketSearchPage({super.key, required this.cardId});
  @override
  Widget build(BuildContext context) {
    final c = Catalog.cards[cardId];
    return Scaffold(
      appBar: AppBar(
        title: Text(c != null && Game.i.has(c.id) ? c.title : t('Carte #${c?.num ?? ''}', 'Card #${c?.num ?? ''}')),
        actions: [Padding(padding: const EdgeInsets.only(right: 12), child: Center(child: ListenableBuilder(listenable: Game.i, builder: (_, __) => CoinChip(Game.i.coins))))],
      ),
      body: MarketList(cardId: cardId),
    );
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
  late bool onlyDupes = widget.multi || Game.i.dupes > 0;
  final selected = <(String, int)>[];
  bool busy = false;

  List<(RcCard, int, int)> _items() {
    final out = <(RcCard, int, int)>[];
    Game.i.owned.forEach((id, q) {
      final c = Catalog.cards[id];
      if (c == null || (sys.isNotEmpty && c.sys != sys)) return;
      final total = q[0] + q[1] + q[2];
      if (onlyDupes && total < 2) return;
      for (var f = 0; f < 3; f++) {
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
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(children: [
            Expanded(
              child: DropdownButton<String>(
                value: sys,
                isExpanded: true,
                underline: const SizedBox(),
                items: [
                  DropdownMenuItem(value: '', child: Text(t('Toutes les consoles', 'All systems'))),
                  for (final s in Catalog.systems) DropdownMenuItem(value: s.id, child: Text(s.name)),
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
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 5 / 7.6, crossAxisSpacing: 8, mainAxisSpacing: 8),
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
