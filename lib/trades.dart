import 'package:flutter/material.dart';

import 'audio.dart';
import 'cards.dart';
import 'catalog.dart';
import 'game.dart';
import 'main.dart';
import 'profile.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Échanges entre joueurs : jusqu'à 5 cartes contre 5. Rien n'est bloqué avant
// l'acceptation ; le serveur vérifie que chacun possède encore ses cartes.
// ═══════════════════════════════════════════════════════════════════════════

class TradesScreen extends StatefulWidget {
  const TradesScreen({super.key});
  @override
  State<TradesScreen> createState() => _TradesScreenState();
}

class _TradesScreenState extends State<TradesScreen> {
  List<Map<String, dynamic>>? rows;
  String? error;
  final busy = <int>{};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (error != null) setState(() => error = null);
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
      TabHeader(t('Échanges', 'Trades'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: load)]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
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
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        _section(t('Reçus', 'Received'), incoming.length),
        if (incoming.isEmpty) _empty(t('Aucune proposition reçue', 'No offers received')),
        for (final r in incoming) _tradeTile(r, incoming: true),
        _section(t('Envoyés', 'Sent'), outgoing.length),
        if (outgoing.isEmpty) _empty(t('Aucune proposition en attente', 'No pending offers')),
        for (final r in outgoing) _tradeTile(r, incoming: false),
        if (done.isNotEmpty) _section(t('Historique', 'History'), done.length),
        for (final r in done) _tradeTile(r, incoming: r['incoming'] == true, finished: true),
      ]),
    );
  }

  Widget _section(String title, int n) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Text('$title ($n)', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      );

  Widget _empty(String s) => Padding(padding: const EdgeInsets.all(8), child: Text(s, style: const TextStyle(color: Colors.white38)));

  Widget _tradeTile(Map<String, dynamic> r, {required bool incoming, bool finished = false}) {
    final id = (r['id'] as num).toInt();
    final give = parseItems(r['give'] as String? ?? '');
    final want = parseItems(r['want'] as String? ?? '');
    // Du point de vue du joueur : ce que je reçois / ce que je donne
    final iGet = incoming ? give : want;
    final iGive = incoming ? want : give;
    final status = switch (r['status']) {
      'accepted' => t('Accepté', 'Accepted'),
      'refused' => t('Refusé', 'Declined'),
      'cancelled' => t('Annulé', 'Cancelled'),
      'failed' => t('Échoué', 'Failed'),
      _ => '',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: incoming && !finished ? kGold : Colors.transparent),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              incoming ? t('De ${r['other_name']}', 'From ${r['other_name']}') : t('À ${r['other_name']}', 'To ${r['other_name']}'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (finished) Text(status, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.person_search, size: 20),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerProfilePage(pid: r['other_pid'] as String))),
          ),
        ]),
        const SizedBox(height: 6),
        Text(t('Tu reçois', 'You get'), style: const TextStyle(color: Color(0xFF5DCAA5), fontSize: 12)),
        const SizedBox(height: 4),
        MiniCards(iGet),
        const SizedBox(height: 8),
        Text(t('Tu donnes', 'You give'), style: const TextStyle(color: Color(0xFFF09595), fontSize: 12)),
        const SizedBox(height: 4),
        MiniCards(iGive),
        if (!finished) ...[
          const SizedBox(height: 10),
          if (incoming)
            Row(children: [
              Expanded(
                child: OutlinedButton(onPressed: busy.contains(id) ? null : () => _answer(id, false), child: Text(t('Refuser', 'Decline'))),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(onPressed: busy.contains(id) ? null : () => _answer(id, true), child: Text(t('Accepter', 'Accept'))),
              ),
            ])
          else
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => _cancel(id), child: Text(t('Annuler la proposition', 'Cancel offer'))),
            ),
        ],
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
  const TradeBuilderPage({super.key, required this.pid, required this.name, this.wantCard});
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
        final wc = widget.wantCard;
        if (wc != null) {
          final q = theirs![wc];
          if (q != null) want.add((wc, q[0] > 0 ? 0 : q[1] > 0 ? 1 : 2));
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
    return Scaffold(
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
                        for (final s in Catalog.systems) DropdownMenuItem(value: s.id, child: Text(s.name)),
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
    );
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
      for (var f = 0; f < 3; f++) {
        if (q[f] <= 0) continue;
        if (mine && onlyDupes && q[0] + q[1] + q[2] < 2) continue;
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
