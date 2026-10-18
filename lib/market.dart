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
      builder: (ctx, scroll) => _CardOffers(cardId: cardId, finish: finish, scroll: scroll),
    ),
  );
}

class _CardOffers extends StatefulWidget {
  final String cardId;
  final int? finish;
  final ScrollController scroll;
  const _CardOffers({super.key, required this.cardId, required this.finish, required this.scroll});
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
        SizedBox(width: 70, child: CardView(card: c, finish: widget.finish ?? 0, owned: known)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(known ? c.title : '#${c.num.toString().padLeft(3, '0')}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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
                    if (context.mounted) Navigator.of(context).pop();
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
class MarketGroups extends StatefulWidget {
  const MarketGroups({super.key});
  @override
  State<MarketGroups> createState() => MarketGroupsState();
}

class MarketGroupsState extends State<MarketGroups> {
  List<Map<String, dynamic>>? rows;
  String? error;
  String sys = '';
  bool missing = false;
  int sort = 0; // 0 récents, 1 moins chers, 2 plus rares
  (String, int)? sel; // mode large : carte dont les offres sont affichées à droite
  final _offersScroll = ScrollController();

  @override
  void dispose() {
    _offersScroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (error != null) setState(() => error = null);
    try {
      final r = await RcServer.marketGroups(sys: sys.isEmpty ? null : sys, missing: missing);
      if (mounted) setState(() => rows = r);
    } catch (e) {
      if (mounted) setState(() => error = errText(e));
    }
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
          color: kBg.withOpacity(0.55),
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

  Widget _list(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
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
      SizedBox(
        height: 40,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          for (final (i, label) in [(0, t('Récents', 'Recent')), (1, t('Moins chers', 'Cheapest')), (2, t('Plus rares', 'Rarest'))])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(label, style: const TextStyle(fontSize: 12)),
                selected: sort == i,
                visualDensity: VisualDensity.compact,
                selectedColor: kPanel2,
                onSelected: (_) => setState(() => sort = i),
              ),
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
    if (sort == 1) list.sort((a, b) => (a['min_price'] as num).compareTo(b['min_price'] as num));
    if (sort == 2) {
      list.sort((a, b) {
        final ra = Catalog.cards[a['card']]!.rarity, rb = Catalog.cards[b['card']]!.rarity;
        return ra != rb ? rb.compareTo(ra) : (b['finish'] as num).compareTo(a['finish'] as num);
      });
    }
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
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final r = list[i];
          final c = Catalog.cards[r['card']]!;
          final f = (r['finish'] as num).toInt();
          final lots = (r['lots'] as num).toInt();
          final known = Game.i.has(c.id);
          final seller = (r['seller'] as String?) ?? '';
          return Material(
            color: sel == (c.id, f) ? kGold.withOpacity(0.18) : kPanel,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                if (isWide(context)) {
                  setState(() => sel = (c.id, f));
                  return;
                }
                await showCardOffers(context, c.id, finish: f);
                load();
              },
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  SizedBox(width: 54, child: CardView(card: c, finish: f)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('${Catalog.system(c.sys)?.short ?? c.sys} · ${rarityName(c.rarity)}${f > 0 ? ' · ${finishName(f)}' : ''}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: kRarityLight[c.rarity], fontSize: 12)),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: t('$lots en vente', '$lots for sale')),
                          // vendeur (le moins cher s'il y en a plusieurs)
                          if (seller.isNotEmpty) ...[
                            TextSpan(text: lots == 1 ? t(' · par ', ' · by ') : t(' · moins cher : ', ' · cheapest: ')),
                            TextSpan(text: seller, style: const TextStyle(color: Color(0xFF8FD3FF), fontWeight: FontWeight.w700)),
                          ],
                          if (!known)
                            TextSpan(text: t('  · manquante', '  · missing'), style: const TextStyle(color: Color(0xFF5DCAA5), fontWeight: FontWeight.w700)),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(t('dès', 'from'), style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    CoinChip((r['min_price'] as num).toInt()),
                  ]),
                  const Icon(Icons.chevron_right, color: Colors.white38),
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
