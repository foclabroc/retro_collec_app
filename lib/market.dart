import 'package:flutter/material.dart';

import 'album.dart';
import 'audio.dart';
import 'cards.dart';
import 'catalog.dart';
import 'game.dart';
import 'main.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Marché : acheter les cartes des autres joueurs, vendre les siennes
// (le vendeur est payé immédiatement, 8 lots maximum par joueur)
// ═══════════════════════════════════════════════════════════════════════════

/// Mise en vente d'une carte (appelée depuis la fiche de la carte).
Future<void> sellCard(String card, int finish, int price) async {
  await RcServer.marketAdd(card, finish, price);
  await Game.i.sync();
  RcAudio.sfx('coin');
  toast(t('Carte mise en vente pour $price pièces', 'Card listed for $price coins'));
}

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});
  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> with SingleTickerProviderStateMixin {
  late final TabController tabs = TabController(length: 2, vsync: this);
  final _buyKey = GlobalKey<_MarketListState>();
  final _mineKey = GlobalKey<_MyListingsState>();

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TabHeader(t('Marché', 'Market'), actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () {
            _buyKey.currentState?.load();
            _mineKey.currentState?.load();
          },
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
        Text(
          t('$open / 8 lots en vente. Pour vendre : Collection → une console → une carte → Vendre.', '$open / 8 listings. To sell: Collection → a system → a card → Sell.'),
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 10),
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
