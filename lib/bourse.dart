import 'package:flutter/material.dart';

import 'album.dart';
import 'cards.dart';
import 'catalog.dart';
import 'game.dart';
import 'main.dart';
import 'market.dart';
import 'notifs.dart';
import 'profile.dart';
import 'server.dart';
import 'trades.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Bourse : tout ce qui se passe entre joueurs, au même endroit.
//   Acheter     marché groupé par carte (prix le plus bas, nombre de lots)
//   Vendre      mes lots en vente (vendre une carte, mes doublons)
//   Échanges    propositions reçues et envoyées
//   Historique  ventes, achats et échanges terminés
// ═══════════════════════════════════════════════════════════════════════════

class BourseScreen extends StatefulWidget {
  const BourseScreen({super.key});
  @override
  State<BourseScreen> createState() => BourseScreenState();
}

class BourseScreenState extends State<BourseScreen> with SingleTickerProviderStateMixin {
  static BourseScreenState? current;
  late final TabController tabs = TabController(length: 4, vsync: this);
  final _buyKey = GlobalKey<MarketGroupsState>();
  final _sellKey = GlobalKey<MyListingsState>();
  final _histKey = GlobalKey<_HistoryListState>();

  @override
  void initState() {
    super.initState();
    current = this;
    tabs.addListener(() {
      if (tabs.indexIsChanging) return;
      if (tabs.index == 1) Notifs.i.salesSeen();
      if (tabs.index == 2) TradesScreenState.current?.load();
      if (tabs.index == 3) _histKey.currentState?.load();
    });
  }

  @override
  void dispose() {
    if (current == this) current = null;
    tabs.dispose();
    super.dispose();
  }

  void reload() {
    _buyKey.currentState?.load();
    _sellKey.currentState?.load();
    TradesScreenState.current?.load();
    _histKey.currentState?.load();
  }

  /// Rubrique ouverte depuis le menu : on va droit à ce qui attend une réponse
  void opened() {
    if (Notifs.i.trades > 0) {
      tabs.animateTo(2);
    } else if (Notifs.i.sales.isNotEmpty) {
      tabs.animateTo(1);
      Notifs.i.salesSeen();
    } else if (tabs.index == 1) {
      Notifs.i.salesSeen();
    }
    reload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TabHeader(t('Bourse', 'Exchange'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: reload),
      ]),
      // 4 onglets en carrés de couleur : Acheter vert, Vendre orange, Échanges bleu, Historique violet
      ListenableBuilder(
        listenable: Listenable.merge([Notifs.i, tabs.animation!]),
        builder: (_, __) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: Row(children: [
            for (final (i, icon, label, color, badge) in [
              (0, Icons.shopping_cart, t('Acheter', 'Buy'), const Color(0xFF5DCAA5), 0),
              (1, Icons.sell, t('Vendre', 'Sell'), const Color(0xFFFFB547), Notifs.i.sales.length),
              (2, Icons.swap_horiz, t('Échanges', 'Trades'), const Color(0xFF3EC7FF), Notifs.i.trades),
              (3, Icons.history, t('Historique', 'History'), const Color(0xFFB48CFF), 0),
            ])
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                  child: _TabTile(
                    icon: icon,
                    label: label,
                    color: color,
                    badge: badge,
                    on: (1 - ((tabs.animation!.value) - i).abs()).clamp(0.0, 1.0),
                    onTap: () => tabs.animateTo(i),
                  ),
                ),
              ),
          ]),
        ),
      ),
      Expanded(
        child: TabBarView(controller: tabs, children: [
          MarketGroups(key: _buyKey),
          MyListings(key: _sellKey),
          const TradesScreen(),
          _HistoryList(key: _histKey),
        ]),
      ),
    ]);
  }
}

/// Onglet de la Bourse : carré de couleur avec son icône ; [on] de 0 à 1 (suit le glissement)
class _TabTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final int badge;
  final double on;
  final VoidCallback onTap;
  const _TabTile({required this.icon, required this.label, required this.color, required this.badge, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Color.lerp(color, Colors.black, 0.45)!;
    final edge = Color.lerp(color, Colors.black, 0.65)!;
    return GestureDetector(
      onTap: onTap,
      child: Transform.translate(
        offset: Offset(0, -2 * on),
        child: SizedBox(
          height: 76, // carré sur téléphone, sans devenir énorme sur tablette
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.72 + 0.28 * on,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color, dark]),
                    border: Border.all(color: Colors.white.withOpacity(0.8 * on), width: 2),
                    boxShadow: [
                      BoxShadow(color: edge, offset: Offset(0, 4 + 2 * on)),
                      if (on > 0) BoxShadow(color: color.withOpacity(0.55 * on), blurRadius: 18),
                    ],
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(icon, color: Colors.white, size: 26, shadows: const [Shadow(color: Colors.black38, offset: Offset(0, 1), blurRadius: 2)]),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(label,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, shadows: [Shadow(color: Colors.black45, offset: Offset(0, 1), blurRadius: 2)])),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            if (badge > 0)
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: const Color(0xFFFF4757), borderRadius: BorderRadius.circular(9), border: Border.all(color: kBg, width: 2)),
                  child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

// ─── Historique ────────────────────────────────────────────────────────────
class _HistoryList extends StatefulWidget {
  const _HistoryList({super.key});
  @override
  State<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<_HistoryList> {
  List<Map<String, dynamic>>? rows;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await RcServer.history();
      if (mounted) {
        setState(() {
          rows = r;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && rows == null) setState(() => error = errText(e));
    }
  }

  String _when(String? s) {
    final d = DateTime.tryParse(s ?? '')?.toLocal();
    if (d == null) return '';
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (days == 0) return hm;
    if (days == 1) return t('hier', 'yesterday');
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(child: TextButton(onPressed: load, child: Text('$error\n${t('Réessayer', 'Retry')}', textAlign: TextAlign.center)));
    }
    if (rows == null) return const Center(child: CircularProgressIndicator(color: kGold));
    if (rows!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t('Rien pour l\'instant : tes ventes, achats et échanges apparaîtront ici', 'Nothing yet: your sales, purchases and trades will show up here'),
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
        ),
      );
    }
    // bilan des pièces sur la période affichée
    var earned = 0, spent = 0;
    for (final r in rows!) {
      final p = (r['price'] as num? ?? 0).toInt();
      if (r['kind'] == 'sold') earned += p;
      if (r['kind'] == 'bought') spent += p;
    }
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        Row(children: [
          _total(t('Gagné en ventes', 'Earned from sales'), '+$earned', const Color(0xFF5DCAA5)),
          const SizedBox(width: 8),
          _total(t('Dépensé en achats', 'Spent on purchases'), '-$spent', const Color(0xFFF09595)),
        ]),
        const SizedBox(height: 10),
        for (final r in rows!) _row(r),
      ]),
    );
  }

  Widget _total(String k, String v, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text(v, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            Text(k, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ]),
        ),
      );

  Widget _row(Map<String, dynamic> r) {
    final kind = r['kind'] as String? ?? '';
    final other = r['other_name'] as String? ?? '?';
    final pid = r['other_pid'] as String?;
    final when = _when(r['at'] as String?);

    if (kind == 'sold' || kind == 'bought') {
      final c = Catalog.cards[r['card']];
      if (c == null) return const SizedBox();
      final f = (r['finish'] as num? ?? 0).toInt();
      final p = (r['price'] as num? ?? 0).toInt();
      final sold = kind == 'sold';
      return _frame(
        icon: sold ? Icons.sell : Icons.shopping_cart,
        color: sold ? const Color(0xFF5DCAA5) : const Color(0xFF85B7EB),
        onTap: () => openCardDetail(context, c),
        child: Row(children: [
          SizedBox(width: 38, child: CardView(card: c, finish: f)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(sold ? t('Vendue à $other · $when', 'Sold to $other · $when') : t('Achetée à $other · $when', 'Bought from $other · $when'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          ),
          Text(sold ? '+$p' : '-$p',
              style: TextStyle(fontWeight: FontWeight.w800, color: sold ? const Color(0xFF5DCAA5) : const Color(0xFFF09595))),
          const SizedBox(width: 4),
          const Icon(Icons.monetization_on, color: kGold, size: 16),
        ]),
      );
    }

    // échange terminé
    final incoming = kind == 'trade_in';
    final give = parseItems(r['give'] as String? ?? '');
    final want = parseItems(r['want'] as String? ?? '');
    final iGet = incoming ? give : want, iGive = incoming ? want : give;
    final (label, color) = switch (r['status']) {
      'accepted' => (t('Échange réussi', 'Trade done'), const Color(0xFF5DCAA5)),
      'refused' => (t('Refusé', 'Declined'), const Color(0xFFF09595)),
      'cancelled' => (t('Annulé', 'Cancelled'), Colors.white38),
      _ => (t('Échoué', 'Failed'), Colors.white38),
    };
    return _frame(
      icon: Icons.swap_horiz,
      color: color,
      onTap: pid == null ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerProfilePage(pid: pid))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(t('$label avec $other', '$label with $other'),
                style: TextStyle(fontWeight: FontWeight.w700, color: color == Colors.white38 ? Colors.white70 : Colors.white)),
          ),
          Text(when, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
        if (r['status'] == 'accepted') ...[
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('Reçu', 'Got'), style: const TextStyle(color: Color(0xFF5DCAA5), fontSize: 11)),
                const SizedBox(height: 2),
                MiniCards(iGet),
              ]),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('Donné', 'Gave'), style: const TextStyle(color: Color(0xFFF09595), fontSize: 11)),
                const SizedBox(height: 2),
                MiniCards(iGive),
              ]),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _frame({required IconData icon, required Color color, required Widget child, VoidCallback? onTap}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: kPanel,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 2, right: 8), child: Icon(icon, color: color, size: 18)),
                Expanded(child: child),
              ]),
            ),
          ),
        ),
      );
}

// ─── Demander une carte en échange ─────────────────────────────────────────
/// Liste des joueurs qui ont cette carte en double → échange pré-rempli.
Future<void> askTradeFor(BuildContext context, RcCard c) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: kBg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => SafeArea(
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: RcServer.cardOwners(c.id),
        builder: (ctx, snap) {
          final known = Game.i.has(c.id);
          final head = Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('Demander en échange', 'Ask in a trade'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 2),
              Text(
                t('Joueurs qui ont ${known ? c.title : 'cette carte'} en double', 'Players with a spare ${known ? c.title : 'copy of this card'}'),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ]),
          );
          if (snap.hasError) {
            return Column(mainAxisSize: MainAxisSize.min, children: [head, Padding(padding: const EdgeInsets.all(20), child: Text(errText(snap.error!)))]);
          }
          if (!snap.hasData) {
            return Column(mainAxisSize: MainAxisSize.min, children: [head, const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: kGold))]);
          }
          final rows = snap.data!;
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            head,
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(t('Personne n\'a cette carte en double pour le moment', 'Nobody has a spare copy right now'),
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
              )
            else
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final p in rows)
                    ListTile(
                      leading: avatarWidget((p['avatar'] as num? ?? 0).toInt()),
                      title: Text(p['name'] as String? ?? '?', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(t('en a ${p['qty']}', 'has ${p['qty']}'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      trailing: const Icon(Icons.swap_horiz, color: kGold),
                      onTap: () {
                        final nav = Navigator.of(ctx);
                        nav.pop();
                        nav.push(MaterialPageRoute(
                          builder: (_) => TradeBuilderPage(pid: p['pid'] as String, name: p['name'] as String? ?? '?', wantCard: c.id),
                        ));
                      },
                    ),
                ]),
              ),
            const SizedBox(height: 8),
          ]);
        },
      ),
    ),
  );
}
