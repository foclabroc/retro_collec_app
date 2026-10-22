import 'package:flutter/material.dart';

import 'album.dart';
import 'audio.dart';
import 'cards.dart';
import 'catalog.dart';
import 'layout.dart';
import 'game.dart';
import 'main.dart';
import 'notifs.dart';
import 'profile.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Échanges entre joueurs (rubrique Bourse) : jusqu'à 5 cartes contre 5. Rien n'est bloqué avant
// l'acceptation ; le serveur vérifie que chacun possède encore ses cartes.
// ═══════════════════════════════════════════════════════════════════════════

class TradesScreen extends StatefulWidget {
  const TradesScreen({super.key});
  @override
  State<TradesScreen> createState() => TradesScreenState();
}

class TradesScreenState extends State<TradesScreen> {
  static TradesScreenState? current;
  List<Map<String, dynamic>>? rows;
  String? error;
  final busy = <int>{};
  int tab = -1; // 0 reçus, 1 envoyés, 2 terminés (-1 : choisi automatiquement)

  @override
  void initState() {
    super.initState();
    current = this;
    load();
  }

  @override
  void dispose() {
    if (current == this) current = null;
    super.dispose();
  }

  Future<void> load() async {
    if (error != null) setState(() => error = null);
    Notifs.i.refresh();
    try {
      final r = await RcServer.trades();
      if (mounted) setState(() => rows = r);
    } catch (e) {
      if (mounted) setState(() => error = errText(e));
    }
  }

  Future<void> _answer(int id, bool accept) async {
    setState(() => busy.add(id));
    try {
      final r = await RcServer.tradeAnswer(id, accept);
      switch (r['status']) {
        case 'accepted':
          RcAudio.sfx('tier');
          toast(t('Échange réussi !', 'Trade completed!'));
          Game.i.emit(r['events']);
        case 'failed':
          toast(t('Échange impossible : l\'un de vous n\'a plus les cartes', 'Trade failed: one of you no longer has the cards'));
        default:
          toast(t('Échange refusé', 'Trade declined'));
      }
      await Game.i.sync();
    } catch (e) {
      toast(errText(e));
    }
    busy.remove(id);
    load();
  }

  Future<void> _cancel(int id) async {
    try {
      await RcServer.tradeCancel(id);
      toast(t('Proposition annulée', 'Offer cancelled'));
    } catch (e) {
      toast(errText(e));
    }
    load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: Text(t('Proposer un échange', 'Propose a trade')),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlayerPickerPage()));
              load();
            },
          ),
        ),
      ),
      Expanded(child: _body()),
    ]);
  }

  Widget _body() {
    if (error != null) {
      return Center(child: TextButton(onPressed: load, child: Text('$error\n${t('Réessayer', 'Retry')}', textAlign: TextAlign.center)));
    }
    if (rows == null) return const Center(child: CircularProgressIndicator(color: kGold));
    final incoming = rows!.where((r) => r['status'] == 'pending' && r['incoming'] == true).toList();
    final outgoing = rows!.where((r) => r['status'] == 'pending' && r['incoming'] != true).toList();
    final done = rows!.where((r) => r['status'] != 'pending').toList();
    // par défaut : les reçus s'il y en a, sinon les envoyés, sinon les terminés
    final cur = tab >= 0 ? tab : (incoming.isNotEmpty ? 0 : outgoing.isNotEmpty ? 1 : 2);
    Widget pill(int i, String label) {
      final on = cur == i;
      const blue = Color(0xFF3EC7FF);
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: on ? const Color(0xFF06222B) : const Color(0xFFCFD3FF))),
          selected: on,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          selectedColor: blue,
          backgroundColor: kPanel,
          onSelected: (_) => setState(() => tab = i),
        ),
      );
    }

    final list = [incoming, outgoing, done][cur];
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 16), children: [
        SizedBox(
          height: 38,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            pill(0, t('Reçus · ${incoming.length}', 'Received · ${incoming.length}')),
            pill(1, t('Envoyés · ${outgoing.length}', 'Sent · ${outgoing.length}')),
            pill(2, t('Terminés', 'Finished')),
          ]),
        ),
        const SizedBox(height: 6),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
                [t('Aucune proposition reçue', 'No offers received'), t('Aucune proposition en attente', 'No pending offers'), t('Aucun échange terminé', 'No finished trades')][cur],
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38)),
          ),
        for (final r in list) _tradeTile(r, incoming: r['incoming'] == true, finished: cur == 2),
      ]),
    );
  }

  /// Détail d'un échange : grandes cartes, nouvelles pour moi ou non, valeur, et la décision
  Future<void> _detail(Map<String, dynamic> r, {required bool incoming, required bool finished}) async {
    final id = (r['id'] as num).toInt();
    final choice = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => TradeDetailPage(trade: r, incoming: incoming, finished: finished)));
    if (choice == 'accept') {
      _answer(id, true);
    } else if (choice == 'refuse') {
      _answer(id, false);
    } else if (choice == 'cancel') {
      _cancel(id);
    }
  }

  Widget _tradeTile(Map<String, dynamic> r, {required bool incoming, bool finished = false}) {
    final id = (r['id'] as num).toInt();
    final give = parseItems(r['give'] as String? ?? '');
    final want = parseItems(r['want'] as String? ?? '');
    // Du point de vue du joueur : ce que je reçois / ce que je donne
    final iGet = incoming ? give : want;
    final iGive = incoming ? want : give;
    int value(List<(String, int)> l) => l.fold(0, (a, x) => a + (Catalog.cards[x.$1] == null ? 0 : recycleValue(Catalog.cards[x.$1]!.rarity, x.$2)));
    final diff = value(iGet) - value(iGive);
    final (status, stColor) = switch (r['status']) {
      'accepted' => (t('Accepté', 'Accepted'), const Color(0xFF5DCAA5)),
      'refused' => (t('Refusé', 'Declined'), const Color(0xFFF09595)),
      'cancelled' => (t('Annulé', 'Cancelled'), Colors.white38),
      'failed' => (t('Échoué', 'Failed'), Colors.white38),
      _ => ('', Colors.white38),
    };
    final when = DateTime.tryParse((r['done_at'] ?? r['created_at']) as String? ?? '')?.toLocal();
    String ago() {
      if (when == null) return '';
      final d = DateTime.now().difference(when);
      if (d.inMinutes < 1) return t('à l\'instant', 'just now');
      if (d.inMinutes < 60) return t('il y a ${d.inMinutes} min', '${d.inMinutes} min ago');
      if (d.inHours < 24) return t('il y a ${d.inHours} h', '${d.inHours} h ago');
      return t('il y a ${d.inDays} j', '${d.inDays} d ago');
    }

    final name = r['other_name'] as String? ?? '?';
    Widget btn(String label, Color bg, Color fg, VoidCallback? onTap, {bool outline = false}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: outline
                ? OutlinedButton(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(vertical: 8)),
                    onPressed: onTap,
                    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5)))
                : FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: bg, foregroundColor: fg, visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(vertical: 8)),
                    onPressed: onTap,
                    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5))),
          ),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: incoming && !finished ? kGold.withOpacity(0.7) : Colors.white12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerProfilePage(pid: r['other_pid'] as String))),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w900)),
              TextSpan(
                  text: finished ? '' : (incoming ? t(' te propose', ' offers you') : t(' · en attente', ' · waiting')),
                  style: const TextStyle(color: Colors.white60)),
            ])),
          ),
          const Spacer(),
          if (finished)
            Text(status, style: TextStyle(color: stColor, fontSize: 12, fontWeight: FontWeight.w800))
          else
            Text(ago(), style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
        const SizedBox(height: 8),
        // toucher les cartes : le détail de l'échange
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _detail(r, incoming: incoming, finished: finished),
          child: Row(children: [
            Flexible(child: IgnorePointer(child: MiniCards(iGive, width: 34))),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('⇄', style: TextStyle(fontSize: 18, color: Colors.white54, fontWeight: FontWeight.w900))),
            Flexible(child: IgnorePointer(child: MiniCards(iGet, width: 34))),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(t('tu donnes ${iGive.length} · tu reçois ${iGet.length}', 'you give ${iGive.length} · get ${iGet.length}'),
                  style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
              Text(
                diff == 0 ? t('valeur égale', 'even value') : t('${diff > 0 ? '+' : ''}$diff pièces de valeur', '${diff > 0 ? '+' : ''}$diff coins of value'),
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: diff > 0 ? const Color(0xFF5DCAA5) : diff < 0 ? const Color(0xFFFF8A95) : Colors.white70),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          btn(t('Détail', 'Details'), kPanel2, Colors.white, () => _detail(r, incoming: incoming, finished: finished), outline: true),
          if (!finished && incoming) ...[
            btn(t('Refuser', 'Decline'), const Color(0xFF4A1D2A), const Color(0xFFFFC4CF), busy.contains(id) ? null : () => _answer(id, false)),
            btn(t('Accepter', 'Accept'), const Color(0xFF2FBF8A), const Color(0xFF06281B), busy.contains(id) ? null : () => _answer(id, true)),
          ],
          if (!finished && !incoming) btn(t('Annuler', 'Cancel'), const Color(0xFF4A1D2A), const Color(0xFFFFC4CF), () => _cancel(id)),
        ]),
      ]),
    );
  }
}

// ─── Choix du joueur ──────────────────────────────────────────────────────
class PlayerPickerPage extends StatefulWidget {
  const PlayerPickerPage({super.key});
  @override
  State<PlayerPickerPage> createState() => _PlayerPickerPageState();
}

class _PlayerPickerPageState extends State<PlayerPickerPage> {
  List<Map<String, dynamic>>? rows;
  final ctl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String q) async {
    try {
      final r = q.trim().isEmpty ? await RcServer.board() : await RcServer.find(q.trim());
      if (mounted) setState(() => rows = r.where((x) => x['pid'] != Game.i.pid).toList());
    } catch (e) {
      toast(errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Avec qui échanger ?', 'Trade with whom?'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: ctl,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t('Pseudo du joueur', 'Player name')),
            onChanged: _load,
          ),
        ),
        Expanded(
          child: rows == null
              ? const Center(child: CircularProgressIndicator(color: kGold))
              : ListView(children: [
                  for (final p in rows!)
                    ListTile(
                      leading: avatarWidget((p['avatar'] as num? ?? 0).toInt()),
                      title: Text(p['name'] as String? ?? '?'),
                      subtitle: Text(t('${p['cards']} cartes · score ${p['score']}', '${p['cards']} cards · score ${p['score']}')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
                        builder: (_) => TradeBuilderPage(pid: p['pid'] as String, name: p['name'] as String? ?? '?'),
                      )),
                    ),
                ]),
        ),
      ]),
    );
  }
}

// ─── Composition d'un échange ─────────────────────────────────────────────
class TradeBuilderPage extends StatefulWidget {
  final String pid, name;
  final String? wantCard; // carte demandée d'avance (depuis le profil)
  final String? giveCard; // carte proposée d'avance (depuis le profil)
  final List<String> wantCards; // plusieurs cartes demandées d'avance (cartes manquantes, 5 max)
  const TradeBuilderPage({super.key, required this.pid, required this.name, this.wantCard, this.giveCard, this.wantCards = const []});
  @override
  State<TradeBuilderPage> createState() => _TradeBuilderPageState();
}

class _TradeBuilderPageState extends State<TradeBuilderPage> with SingleTickerProviderStateMixin {
  late final TabController tabs = TabController(length: 2, vsync: this);
  Map<String, List<int>>? theirs;
  final want = <(String, int)>[];
  final give = <(String, int)>[];
  String sys = '';
  bool onlyMissing = true, onlyDupes = false, sending = false;

  @override
  void initState() {
    super.initState();
    RcServer.profile(widget.pid).then((p) {
      if (!mounted) return;
      setState(() {
        theirs = parseOwned(p?['owned']);
        for (final wc in [if (widget.wantCard != null) widget.wantCard!, ...widget.wantCards]) {
          if (want.length >= 5 || want.any((x) => x.$1 == wc)) continue;
          final q = theirs![wc];
          if (q != null) want.add((wc, q[0] > 0 ? 0 : q[1] > 0 ? 1 : 2));
        }
        final gc = widget.giveCard;
        if (gc != null) {
          for (var f = 0; f < kFinishes; f++) {
            if (Game.i.qty(gc, f) > 0) {
              give.add((gc, f));
              break;
            }
          }
        }
      });
    }).catchError((e) {
      toast(errText(e));
    });
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  int _count(List<(String, int)> l, String c, int f) => l.where((e) => e.$1 == c && e.$2 == f).length;

  Future<void> _send() async {
    if (want.isEmpty && give.isEmpty) return;
    setState(() => sending = true);
    try {
      await RcServer.tradeOffer(widget.pid, itemsToString(give), itemsToString(want));
      RcAudio.sfx('coin');
      toast(t('Proposition envoyée à ${widget.name}', 'Offer sent to ${widget.name}'));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      toast(errText(e));
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaxWidth(max: 820, child: Scaffold(
      appBar: AppBar(
        title: Text(t('Échange avec ${widget.name}', 'Trade with ${widget.name}')),
        bottom: TabBar(controller: tabs, indicatorColor: kGold, labelColor: kGold, tabs: [
          Tab(text: t('Je demande (${want.length}/5)', 'I want (${want.length}/5)')),
          Tab(text: t('Je donne (${give.length}/5)', 'I give (${give.length}/5)')),
        ]),
      ),
      body: theirs == null
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : Column(children: [
              Container(
                color: kPanel,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: _selected(t('Tu reçois', 'You get'), want, const Color(0xFF5DCAA5))),
                  const Icon(Icons.swap_horiz, color: Colors.white38),
                  Expanded(child: _selected(t('Tu donnes', 'You give'), give, const Color(0xFFF09595))),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
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
                  AnimatedBuilder(
                    animation: tabs,
                    builder: (_, __) => tabs.index == 0
                        ? FilterChip(
                            label: Text(t('Mes manquantes', 'I\'m missing')),
                            selected: onlyMissing,
                            selectedColor: const Color(0xFF412402),
                            onSelected: (v) => setState(() => onlyMissing = v),
                          )
                        : FilterChip(
                            label: Text(t('Doublons', 'Duplicates')),
                            selected: onlyDupes,
                            selectedColor: const Color(0xFF412402),
                            onSelected: (v) => setState(() => onlyDupes = v),
                          ),
                  ),
                ]),
              ),
              Expanded(
                child: TabBarView(controller: tabs, children: [
                  _picker(theirs!, want, mine: false),
                  _picker(Game.i.owned, give, mine: true),
                ]),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: sending || (want.isEmpty && give.isEmpty) ? null : _send,
                      child: Text(t('Envoyer la proposition', 'Send the offer')),
                    ),
                  ),
                ),
              ),
            ]),
    ));
  }

  Widget _selected(String title, List<(String, int)> l, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: color, fontSize: 12)),
        const SizedBox(height: 4),
        SizedBox(
          height: 62,
          child: l.isEmpty
              ? Text(t('touche des cartes ci-dessous', 'tap cards below'), style: const TextStyle(color: Colors.white38, fontSize: 11))
              : ListView(scrollDirection: Axis.horizontal, children: [
                  for (var i = 0; i < l.length; i++)
                    GestureDetector(
                      onTap: () => setState(() => l.removeAt(i)),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: SizedBox(width: 42, child: CardView(card: Catalog.cards[l[i].$1]!, finish: l[i].$2)),
                      ),
                    ),
                ]),
        ),
      ]);

  Widget _picker(Map<String, List<int>> owned, List<(String, int)> target, {required bool mine}) {
    final items = <(RcCard, int, int)>[];
    owned.forEach((id, q) {
      final c = Catalog.cards[id];
      if (c == null || (sys.isNotEmpty && c.sys != sys)) return;
      if (!mine && onlyMissing && Game.i.has(id)) return;
      for (var f = 0; f < kFinishes; f++) {
        if (q[f] <= 0) continue;
        if (mine && onlyDupes && qSum(q) < 2) continue;
        items.add((c, f, q[f]));
      }
    });
    items.sort((a, b) => b.$1.rarity != a.$1.rarity ? b.$1.rarity.compareTo(a.$1.rarity) : a.$1.id.compareTo(b.$1.id));
    if (items.isEmpty) {
      return Center(
        child: Text(mine ? t('Aucune carte', 'No cards') : t('Aucune carte à demander', 'No cards to ask for'), style: const TextStyle(color: Colors.white38)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: 5 / 7.6, crossAxisSpacing: 6, mainAxisSpacing: 6),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final (c, f, n) = items[i];
        final used = _count(target, c.id, f);
        final left = n - used;
        return GestureDetector(
          onTap: () {
            if (left <= 0) return;
            if (target.length >= 5) {
              toast(t('5 cartes maximum de chaque côté', '5 cards maximum on each side'));
              return;
            }
            if (mine && Game.i.qty(c.id) - _count(give, c.id, 0) - _count(give, c.id, 1) - _count(give, c.id, 2) <= 1) {
              toast(t('Attention : c\'est ton dernier exemplaire de cette carte', 'Careful: this is your last copy of this card'));
            }
            setState(() => target.add((c.id, f)));
          },
          child: Opacity(
            opacity: left > 0 ? 1 : 0.35,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(child: Align(alignment: Alignment.topCenter, child: CardView(card: c, finish: f))),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(color: used > 0 ? kGold : kPanel2, borderRadius: BorderRadius.circular(6)),
                  child: Text(used > 0 ? '$used/$n' : '×$n',
                      style: TextStyle(fontSize: 10, color: used > 0 ? const Color(0xFF412402) : Colors.white70, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// Détail d'un échange proposé
class TradeDetailPage extends StatelessWidget {
  final Map<String, dynamic> trade;
  final bool incoming, finished;
  const TradeDetailPage({super.key, required this.trade, required this.incoming, required this.finished});

  @override
  Widget build(BuildContext context) {
    final give = parseItems(trade['give'] as String? ?? '');
    final want = parseItems(trade['want'] as String? ?? '');
    final iGet = incoming ? give : want, iGive = incoming ? want : give;
    final name = trade['other_name'] as String? ?? '?';
    int value(List<(String, int)> l) => l.fold(0, (a, x) => a + (Catalog.cards[x.$1] == null ? 0 : recycleValue(Catalog.cards[x.$1]!.rarity, x.$2)));
    final vGet = value(iGet), vGive = value(iGive);
    final fresh = iGet.where((x) => Game.i.qty(x.$1) == 0).length;

    Widget row((String, int) it, {required bool mine}) {
      final c = Catalog.cards[it.$1];
      if (c == null) return const SizedBox();
      final have = Game.i.qty(c.id), haveF = Game.i.qty(c.id, it.$2);
      final sameInTrade = iGive.where((x) => x.$1 == c.id).length;
      final note = mine
          ? (have - sameInTrade <= 0 ? t('⚠ Ta dernière : tu ne l\'auras plus', '⚠ Your last one: you won\'t have it anymore') : t('Il t\'en restera ${have - sameInTrade}', 'You\'ll keep ${have - sameInTrade}'))
          : (have == 0 ? t('✨ Nouvelle pour toi', '✨ New for you') : t('Tu en as déjà $have${haveF > 0 ? ' (dont $haveF ${finishName(it.$2).toLowerCase()})' : ''}', 'You already have $have'));
      final noteColor = mine ? (have - sameInTrade <= 0 ? const Color(0xFFFFB547) : Colors.white54) : (have == 0 ? const Color(0xFF5DCAA5) : Colors.white54);
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openCardDetail(context, c),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(width: 84, child: CardView(card: c, finish: it.$2)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                const SizedBox(height: 2),
                Text('${Catalog.system(c.sys)?.short ?? c.sys}${c.year == null ? '' : ' · ${c.year}'}', style: const TextStyle(fontSize: 12, color: Colors.white60)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  _pill(rarityName(c.rarity), kRarityColor[c.rarity]),
                  if (it.$2 > 0) _pill(finishName(it.$2), it.$2 == 3 ? const Color(0xFFFF9FE5) : it.$2 == 2 ? const Color(0xFFFFD54F) : const Color(0xFF9C8CFF)),
                ]),
                const SizedBox(height: 4),
                Text(note, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: noteColor)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ]),
        ),
      );
    }

    Widget section(String title, Color color, List<(String, int)> l, int v, {required bool mine}) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.6))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 15)),
              const Spacer(),
              Text(t('${l.length} carte${l.length > 1 ? 's' : ''} · valeur $v', '${l.length} card${l.length > 1 ? 's' : ''} · value $v'),
                  style: const TextStyle(fontSize: 12, color: Colors.white54)),
            ]),
            if (l.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(t('rien', 'nothing'), style: const TextStyle(color: Colors.white38))),
            for (final it in l) row(it, mine: mine),
          ]),
        );

    return MaxWidth(
      max: 640,
      child: Scaffold(
        appBar: AppBar(
          title: Text(incoming ? t('Échange proposé par $name', 'Trade from $name') : t('Ton échange avec $name', 'Your trade with $name')),
          actions: [
            IconButton(
              tooltip: t('Profil', 'Profile'),
              icon: const Icon(Icons.person_search),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerProfilePage(pid: trade['other_pid'] as String))),
            ),
          ],
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 24), children: [
          // résumé
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: t('Valeur : tu reçois ', 'Value: you get ')),
                TextSpan(text: '$vGet', style: const TextStyle(color: Color(0xFF5DCAA5), fontWeight: FontWeight.w900)),
                TextSpan(text: t(', tu donnes ', ', you give ')),
                TextSpan(text: '$vGive', style: const TextStyle(color: Color(0xFFF09595), fontWeight: FontWeight.w900)),
                if (fresh > 0) TextSpan(text: t(' · $fresh carte${fresh > 1 ? 's' : ''} nouvelle${fresh > 1 ? 's' : ''} pour toi ✨', ' · $fresh new card${fresh > 1 ? 's' : ''} for you ✨')),
              ]),
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
          section(t('Tu reçois', 'You get'), const Color(0xFF5DCAA5), iGet, vGet, mine: false),
          section(t('Tu donnes', 'You give'), const Color(0xFFF09595), iGive, vGive, mine: true),
          Text(t('Valeur = pièces données par le recyclage. Touche une carte pour voir sa fiche.', 'Value = coins given by recycling. Tap a card to see it.'),
              style: const TextStyle(fontSize: 11.5, color: Colors.white38)),
        ]),
        bottomNavigationBar: finished
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                  child: incoming
                      ? Row(children: [
                          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, 'refuse'), child: Text(t('Refuser', 'Decline')))),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2FBF8A), foregroundColor: const Color(0xFF06281B)),
                              onPressed: () => Navigator.pop(context, 'accept'),
                              child: Text(t('Accepter l\'échange', 'Accept the trade'), style: const TextStyle(fontWeight: FontWeight.w900)),
                            ),
                          ),
                        ])
                      : OutlinedButton(onPressed: () => Navigator.pop(context, 'cancel'), child: Text(t('Annuler la proposition', 'Cancel offer'))),
                ),
              ),
      ),
    );
  }

  Widget _pill(String s, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: c.withOpacity(0.2), borderRadius: BorderRadius.circular(6), border: Border.all(color: c.withOpacity(0.7))),
        child: Text(s, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color.lerp(c, Colors.white, 0.35))),
      );
}
