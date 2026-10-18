import 'package:flutter/material.dart';

import 'cards.dart';
import 'catalog.dart';
import 'game.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Statistiques d'une collection (la mienne ou celle d'un autre joueur)
// ═══════════════════════════════════════════════════════════════════════════

class StatsPanel extends StatelessWidget {
  final Map<String, List<int>> owned;
  final int? packs;
  final DateTime? since;
  final void Function(RcCard c)? onCard;
  const StatsPanel({super.key, required this.owned, this.packs, this.since, this.onCard});

  @override
  Widget build(BuildContext context) {
    // possédées par rareté, copies, finitions, valeur au recyclage
    final totalByR = List<int>.filled(5, 0), ownByR = List<int>.filled(5, 0);
    for (final c in Catalog.cards.values) {
      totalByR[c.rarity]++;
    }
    var copies = 0, holo = 0, gold = 0, value = 0;
    final best = <(RcCard, int)>[];
    owned.forEach((id, q) {
      final c = Catalog.cards[id];
      if (c == null) return;
      final n = qSum(q);
      if (n <= 0) return;
      ownByR[c.rarity]++;
      copies += n;
      holo += q[1];
      gold += q[2];
      for (var f = 0; f < kFinishes; f++) {
        value += recycleValue(c.rarity, f) * q[f];
      }
      best.add((c, bestFinish(q)));
    });
    best.sort((a, b) {
      final va = recycleValue(a.$1.rarity, a.$2), vb = recycleValue(b.$1.rarity, b.$2);
      return vb != va ? vb.compareTo(va) : a.$1.id.compareTo(b.$1.id);
    });
    final distinct = ownByR.fold<int>(0, (a, b) => a + b);
    final total = Catalog.cards.length;
    // console la plus avancée
    String? bestSys;
    var bestPct = -1.0;
    for (final s in Catalog.systems) {
      final list = Catalog.bySys[s.id] ?? const <RcCard>[];
      if (list.isEmpty) continue;
      final n = list.where((c) => (owned[c.id]?.fold<int>(0, (a, b) => a + b) ?? 0) > 0).length;
      final pct = n / list.length;
      if (pct > bestPct) {
        bestPct = pct;
        bestSys = s.name;
      }
    }

    Widget tile(String v, String k, {Color color = Colors.white}) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              FittedBox(child: Text(v, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color))),
              const SizedBox(height: 2),
              Text(k, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ]),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        tile('$distinct', t('cartes /$total', 'cards /$total')),
        tile('${total == 0 ? 0 : (distinct * 100 / total).floor()} %', t('complété', 'complete'), color: kGold),
        tile('$copies', t('exemplaires', 'copies')),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        tile('$holo ✦', t('brillantes', 'holo')),
        tile('$gold ★', t('dorées', 'gold'), color: const Color(0xFFFFD54F)),
        tile('$value', t('valeur (pièces)', 'value (coins)'), color: kGold),
      ]),
      if (packs != null || bestSys != null) ...[
        const SizedBox(height: 6),
        Row(children: [
          if (packs != null) tile('$packs', t('paquets ouverts', 'packs opened')),
          if (bestSys != null) tile('${(bestPct * 100).floor()} %', t('meilleure série :\n$bestSys', 'best set:\n$bestSys')),
          if (since != null) tile('${DateTime.now().difference(since!).inDays + 1} j', t('d\'ancienneté', 'days played')),
        ]),
      ],
      const SizedBox(height: 14),
      Text(t('Par rareté', 'By rarity'), style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      for (var r = 4; r >= 0; r--)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 96, child: Text(rarityName(r), style: TextStyle(color: kRarityLight[r], fontSize: 12, fontWeight: FontWeight.w700))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: totalByR[r] == 0 ? 0 : ownByR[r] / totalByR[r],
                  minHeight: 7,
                  color: kRarityColor[r],
                  backgroundColor: Colors.white10,
                ),
              ),
            ),
            SizedBox(width: 64, child: Text('${ownByR[r]} / ${totalByR[r]}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: Colors.white70))),
          ]),
        ),
      if (best.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(t('Cartes les plus précieuses', 'Most valuable cards'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final (c, f) in best.take(8))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: onCard == null ? null : () => onCard!(c),
                  child: SizedBox(width: 84, child: CardView(card: c, finish: f)),
                ),
              ),
          ]),
        ),
      ],
    ]);
  }
}
