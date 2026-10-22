import 'package:flutter/material.dart';

import 'cards.dart';
import 'catalog.dart';
import 'game.dart';
import 'layout.dart';
import 'main.dart';
import 'server.dart';
import 'trades.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Mes cartes manquantes chez les voisins : les joueurs (vus depuis 30 jours)
// qui ont en double des cartes que je n'ai pas encore (rc_missing_finder).
// Toucher un joueur → échange pré-rempli avec ses 5 cartes les plus rares.
// ═══════════════════════════════════════════════════════════════════════════

class MissingFinderPage extends StatefulWidget {
  const MissingFinderPage({super.key});
  @override
  State<MissingFinderPage> createState() => _MissingFinderPageState();
}

class _MissingFinderPageState extends State<MissingFinderPage> {
  Map<String, dynamic>? _data;
  String? _error;
  String _sys = ''; // filtre console ('' = toutes)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _data = null;
    });
    try {
      final d = await RcServer.missingFinder();
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    }
  }

  /// [(carte, quantité)] d'un joueur, filtrées par console
  List<(RcCard, int)> _cards(Map<String, dynamic> p) => [
        for (final x in (p['cards'] as List? ?? const []))
          if (x is List && x.length >= 2 && Catalog.cards[x[0].toString()] != null)
            if (_sys.isEmpty || Catalog.cards[x[0].toString()]!.sys == _sys)
              (Catalog.cards[x[0].toString()]!, (x[1] as num).toInt()),
      ];

  @override
  Widget build(BuildContext context) {
    return MaxWidth(
      max: 820,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('Mes cartes manquantes', 'My missing cards')),
          actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(child: TextButton(onPressed: _load, child: Text('$_error\n${t('Réessayer', 'Retry')}', textAlign: TextAlign.center)));
    }
    final d = _data;
    if (d == null) return const Center(child: CircularProgressIndicator(color: kGold));
    final players = [for (final p in (d['players'] as List? ?? const [])) Map<String, dynamic>.from(p as Map)];
    final total = (d['cards'] as num? ?? 0).toInt();
    if (players.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t('Aucun voisin n\'a en double une carte qui te manque pour le moment.', 'No neighbor has a spare copy of a card you\'re missing right now.'),
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
        ),
      );
    }
    // consoles présentes dans les résultats (pour le filtre)
    final syss = <String>{
      for (final p in players)
        for (final x in (p['cards'] as List? ?? const []))
          if (x is List && Catalog.cards[x[0].toString()] != null) Catalog.cards[x[0].toString()]!.sys,
    };
    final shown = [
      for (final p in players)
        if (_cards(p).isNotEmpty) p
    ]..sort((a, b) => _cards(b).length.compareTo(_cards(a).length));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        child: Text(
          t('$total carte(s) qui te manquent sont en double chez ${players.length} voisin(s). Touche un voisin pour lui proposer un échange.',
              '$total card(s) you\'re missing are spare copies at ${players.length} neighbor(s). Tap a neighbor to propose a trade.'),
          style: const TextStyle(color: Colors.white70, fontSize: 12.5),
        ),
      ),
      SizedBox(
        height: 40,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
          for (final s in ['', ...Catalog.systems.map((x) => x.id).where(syss.contains), ...Catalog.sagaSystems.map((x) => x.id).where(syss.contains)])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(s.isEmpty ? t('Toutes', 'All') : (Catalog.system(s)?.short ?? s), style: const TextStyle(fontSize: 12)),
                selected: _sys == s,
                onSelected: (_) => setState(() => _sys = s),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
          itemCount: shown.length,
          itemBuilder: (_, i) => _player(shown[i]),
        ),
      ),
    ]);
  }

  Widget _player(Map<String, dynamic> p) {
    final cards = _cards(p);
    final name = p['name']?.toString() ?? '?';
    final online = p['online'] == true;
    void trade() => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TradeBuilderPage(pid: p['pid'].toString(), name: name, wantCards: [for (final c in cards.take(5)) c.$1.id]),
        ));
    return Card(
      color: kPanel,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: trade,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Stack(clipBehavior: Clip.none, children: [
                avatarWidget((p['avatar'] as num? ?? 0).toInt(), size: 36),
                if (online)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF5DCAA5), border: Border.all(color: Colors.black, width: 1.5)),
                    ),
                  ),
              ]),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(t('${cards.length} carte(s) qui te manquent, en double', '${cards.length} missing card(s), spare copies'),
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ]),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800), visualDensity: VisualDensity.compact),
                onPressed: trade,
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: Text(t('Échanger', 'Trade'), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: cards.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => SizedBox(
                  width: 66,
                  child: Stack(children: [
                    CardView(card: cards[i].$1),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
                        child: Text('×${cards[i].$2}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
