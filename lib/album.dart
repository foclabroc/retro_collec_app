import 'package:flutter/material.dart';

import 'audio.dart';
import 'cards.dart';
import 'catalog.dart';
import 'game.dart';
import 'main.dart';
import 'retro_theme.dart';
import 'market.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Album : une série de 100 cartes par console, fiche détaillée d'une carte
// ═══════════════════════════════════════════════════════════════════════════

const kMilestoneSteps = [25, 50, 75, 100];
const kMilestoneReward = {25: 100, 50: 250, 75: 500, 100: 2000};

/// Album d'une console (ouvert depuis le bâtiment de la ville).
class SystemAlbumPage extends StatefulWidget {
  final String sys;
  const SystemAlbumPage({super.key, required this.sys});
  @override
  State<SystemAlbumPage> createState() => _SystemAlbumPageState();
}

class _SystemAlbumPageState extends State<SystemAlbumPage> {
  int filter = 0; // 0 toutes, 1 possédées, 2 manquantes

  @override
  Widget build(BuildContext context) {
    final sys = widget.sys;
    return ListenableBuilder(
      listenable: Game.i,
      builder: (context, _) {
        final g = Game.i;
        final all = Catalog.bySys[sys] ?? const <RcCard>[];
        final list = switch (filter) {
          1 => all.where((c) => g.has(c.id)).toList(),
          2 => all.where((c) => !g.has(c.id)).toList(),
          _ => all,
        };
        final mine = g.ownedIn(sys);
        final total = all.length;
        final next = kMilestoneSteps.firstWhere((s) => !g.milestones.contains('$sys:$s'), orElse: () => 0);
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 64,
            title: ConsoleLogo(sys, height: 40),
            actions: [
              IconButton(
                tooltip: t('Recycler les doublons', 'Recycle duplicates'),
                icon: Badge(isLabelVisible: g.dupes > 0, label: Text('${g.dupes}'), child: const Icon(Icons.recycling)),
                onPressed: () => recycleAllDupes(context),
              ),
              Padding(padding: const EdgeInsets.only(right: 12), child: Center(child: CoinChip(g.coins))),
            ],
          ),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: Column(children: [
                Row(children: [
                  Expanded(child: Text(Catalog.system(sys)?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700))),
                  Text('$mine / $total', style: const TextStyle(color: Colors.white60)),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: total == 0 ? 0 : mine / total, minHeight: 7, color: kGold, backgroundColor: kPanel2),
                ),
                const SizedBox(height: 5),
                Row(children: [
                  Expanded(
                    child: Text(
                      next == 0
                          ? t('Série complète !', 'Set complete!')
                          : t('Prochain palier : $next % → ${kMilestoneReward[next]} pièces', 'Next milestone: $next% → ${kMilestoneReward[next]} coins'),
                      style: const TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                  ),
                  DropdownButton<int>(
                    value: filter,
                    isDense: true,
                    underline: const SizedBox(),
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                    items: [
                      DropdownMenuItem(value: 0, child: Text(t('Toutes', 'All'))),
                      DropdownMenuItem(value: 1, child: Text(t('Possédées', 'Owned'))),
                      DropdownMenuItem(value: 2, child: Text(t('Manquantes', 'Missing'))),
                    ],
                    onChanged: (v) => setState(() => filter = v ?? 0),
                  ),
                ]),
              ]),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 5 / 7.4, crossAxisSpacing: 8, mainAxisSpacing: 8),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final c = list[i];
                  final q = g.owned[c.id];
                  final best = q == null ? 0 : (q[2] > 0 ? 2 : q[1] > 0 ? 1 : 0);
                  final n = g.qty(c.id);
                  return GestureDetector(
                    onTap: () => openCardDetail(context, c),
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
              ),
            ),
          ]),
        );
      },
    );
  }
}

/// Recycle tous les doublons (après confirmation).
Future<void> recycleAllDupes(BuildContext context) async {
  final g = Game.i;
  if (g.dupes == 0) {
    toast(t('Aucun doublon à recycler', 'No duplicates to recycle'));
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('Recycler les doublons', 'Recycle duplicates')),
      content: Text(t(
        '${g.dupes} doublon(s) → ${g.dupesValue} pièces.\nUn exemplaire de chaque carte et de chaque finition est gardé.\n\nAstuce : les doublons servent aussi pour les échanges.',
        '${g.dupes} duplicate(s) → ${g.dupesValue} coins.\nOne copy of each card and finish is kept.\n\nTip: duplicates are also useful for trades.',
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Annuler', 'Cancel'))),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Recycler', 'Recycle'))),
      ],
    ),
  );
  if (ok != true) return;
  try {
    final (n, gain) = await g.recycleDupes();
    RcAudio.sfx('coin');
    toast(t('$n doublon(s) recyclé(s) : +$gain pièces', '$n duplicate(s) recycled: +$gain coins'));
  } catch (e) {
    toast(errText(e));
  }
}

void openCardDetail(BuildContext context, RcCard c, {Map<String, List<int>>? otherOwned, String? otherName}) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => CardDetailPage(card: c, otherOwned: otherOwned, otherName: otherName)));
}

// ─── Fiche d'une carte ─────────────────────────────────────────────────────
class CardDetailPage extends StatefulWidget {
  final RcCard card;
  final Map<String, List<int>>? otherOwned; // collection d'un autre joueur (lecture seule)
  final String? otherName;
  const CardDetailPage({super.key, required this.card, this.otherOwned, this.otherName});
  @override
  State<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends State<CardDetailPage> {
  int finish = 0;
  bool busy = false;

  List<int> get q => widget.otherOwned != null ? (widget.otherOwned![widget.card.id] ?? const [0, 0, 0]) : (Game.i.owned[widget.card.id] ?? const [0, 0, 0]);

  @override
  void initState() {
    super.initState();
    final x = q;
    finish = x[2] > 0 ? 2 : x[1] > 0 ? 1 : 0;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.card;
    final readOnly = widget.otherOwned != null;
    return TiltScope(
      child: ListenableBuilder(
        listenable: Game.i,
        builder: (context, _) {
          final x = q;
          final total = x[0] + x[1] + x[2];
          final owned = total > 0;
          final myTotal = Game.i.qty(c.id);
          final shot = owned || myTotal > 0 ? Catalog.shotFile(c) : null;
          return Scaffold(
            appBar: AppBar(
              toolbarHeight: 66,
              // titre complet : police pixel plus petite, sur 2 lignes si besoin
              title: Text(owned || myTotal > 0 ? c.title : '#${c.num.toString().padLeft(3, '0')}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: pixelStyle(size: 11, color: Colors.white, shadow: false)),
              actions: [if (!readOnly) Padding(padding: const EdgeInsets.only(right: 12), child: Center(child: CoinChip(Game.i.coins)))],
            ),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              Center(child: SizedBox(width: 240, child: SpinCard(key: ValueKey('$finish'), card: c, finish: owned ? finish : 0, owned: owned))),
              const SizedBox(height: 6),
              Text(t('Fais tourner la carte avec ton doigt · double-tap pour la remettre de face', 'Spin the card with your finger · double-tap to reset'),
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              if (owned) ...[
                const SizedBox(height: 12),
                Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
                  for (var f = 0; f < 3; f++)
                    if (x[f] > 0)
                      ChoiceChip(
                        label: Text('${finishName(f)} ×${x[f]}'),
                        selected: finish == f,
                        selectedColor: f == 2 ? const Color(0xFF633806) : f == 1 ? const Color(0xFF26215C) : kPanel2,
                        onSelected: (_) => setState(() => finish = f),
                      ),
                ]),
              ],
              if (readOnly)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    owned
                        ? t('${widget.otherName} possède cette carte', '${widget.otherName} owns this card')
                        : t('${widget.otherName} n\'a pas cette carte', '${widget.otherName} doesn\'t have this card'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
              const SizedBox(height: 16),
              if (shot != null)
                ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(shot, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox())),
              if (owned || myTotal > 0) ...[
                const SizedBox(height: 14),
                _info(t('Console', 'System'), Catalog.system(c.sys)?.name ?? c.sys),
                _info(t('Année', 'Year'), '${c.year ?? '?'}'),
                _info(t('Développeur', 'Developer'), c.dev.isEmpty ? '?' : c.dev),
                _info(t('Éditeur', 'Publisher'), c.pub.isEmpty ? '?' : c.pub),
                _info(t('Genre', 'Genre'), c.genre.isEmpty ? '?' : c.genre),
                _info(t('Rareté', 'Rarity'), rarityName(c.rarity)),
                if (c.desc.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(c.desc, style: const TextStyle(color: Colors.white70, height: 1.45)),
                ],
              ] else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    t('Carte ${rarityName(c.rarity).toLowerCase()} pas encore débloquée.\nOuvre des paquets, échange avec d\'autres joueurs ou fabrique-la.',
                        '${rarityName(c.rarity)} card not unlocked yet.\nOpen packs, trade with other players or craft it.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60, height: 1.4),
                  ),
                ),
              if (!readOnly) ...[const SizedBox(height: 20), ..._actions(context, c, x, total)],
            ]),
          );
        },
      ),
    );
  }

  Widget _info(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(color: Colors.white54))),
          Expanded(child: Text(v)),
        ]),
      );

  List<Widget> _actions(BuildContext context, RcCard c, List<int> x, int total) {
    final g = Game.i;
    final cost = craftCost(c.rarity);
    final inShowcase = g.showcaseItems.any((e) => e.$1 == c.id);
    return [
      if (total > 0) ...[
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.sell_outlined),
              label: Text(t('Vendre', 'Sell')),
              onPressed: busy ? null : () => _sell(context, c),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.recycling),
              label: Text('+${recycleValue(c.rarity, finish)}'),
              onPressed: busy || total <= 1 || x[finish] == 0 ? null : () => _recycle(c),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: Icon(inShowcase ? Icons.star : Icons.star_border, color: kGold),
          label: Text(inShowcase ? t('Retirer de la vitrine', 'Remove from showcase') : t('Mettre en vitrine', 'Add to showcase')),
          onPressed: busy ? null : () => _toggleShowcase(c, inShowcase),
        ),
        const SizedBox(height: 8),
      ],
      ElevatedButton.icon(
        icon: const Icon(Icons.auto_fix_high),
        label: Text(t('Fabriquer (${fmt(cost)} pièces)', 'Craft (${fmt(cost)} coins)')),
        onPressed: busy || g.coins < cost ? null : () => _craft(c, cost),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        icon: const Icon(Icons.storefront),
        label: Text(t('Chercher au marché', 'Find on the market')),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MarketSearchPage(cardId: c.id))),
      ),
      if (total > 1)
        Text(
          t('Recycler rapporte des pièces (on garde toujours un exemplaire).', 'Recycling gives coins (you always keep one copy).'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: Colors.white38),
        ),
    ];
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => busy = true);
    try {
      await f();
    } catch (e) {
      toast(errText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  void _recycle(RcCard c) => _run(() async {
        final gain = await Game.i.recycle(c.id, finish, 1);
        RcAudio.sfx('coin');
        toast(t('+$gain pièces', '+$gain coins'));
        final x = q;
        if (x[finish] == 0) setState(() => finish = x[2] > 0 ? 2 : x[1] > 0 ? 1 : 0);
      });

  void _craft(RcCard c, int cost) => _run(() async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(t('Fabriquer cette carte ?', 'Craft this card?')),
            content: Text(t('Coût : ${fmt(cost)} pièces (finition normale).', 'Cost: ${fmt(cost)} coins (normal finish).')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Annuler', 'Cancel'))),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Fabriquer', 'Craft'))),
            ],
          ),
        );
        if (ok != true) return;
        await Game.i.craft(c.id);
        Game.i.playSound(c.rarity);
        toast(t('Carte fabriquée !', 'Card crafted!'));
      });

  void _toggleShowcase(RcCard c, bool inShowcase) => _run(() async {
        final items = Game.i.showcaseItems.where((e) => e.$1 != c.id).toList();
        if (!inShowcase) {
          if (items.length >= 6) {
            toast(t('Vitrine pleine (6 cartes) : retires-en une d\'abord', 'Showcase full (6 cards): remove one first'));
            return;
          }
          items.add((c.id, finish));
        }
        await Game.i.setProfile(newShowcase: itemsToString(items));
      });

  void _sell(BuildContext context, RcCard c) => _run(() async {
        final total = Game.i.qty(c.id);
        if (total == 1) {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(t('Dernier exemplaire', 'Last copy')),
              content: Text(t('C\'est ton seul exemplaire : la carte quittera ton album. Continuer ?', 'This is your only copy: the card will leave your album. Continue?')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Annuler', 'Cancel'))),
                ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Continuer', 'Continue'))),
              ],
            ),
          );
          if (ok != true) return;
        }
        if (!context.mounted) return;
        final price = await askPrice(context, c, finish);
        if (price == null) return;
        await sellCard(c.id, finish, price);
        final x = q;
        if (x[finish] == 0 && x[0] + x[1] + x[2] > 0) setState(() => finish = x[2] > 0 ? 2 : x[1] > 0 ? 1 : 0);
      });
}

/// Demande un prix de vente (suggestion : 2 × la valeur de recyclage).
Future<int?> askPrice(BuildContext context, RcCard c, int finish) async {
  final ctl = TextEditingController(text: '${recycleValue(c.rarity, finish) * 2}');
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('Mettre en vente', 'Put up for sale')),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${c.title} — ${finishName(finish)}'),
        const SizedBox(height: 12),
        TextField(
          controller: ctl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(labelText: t('Prix (pièces)', 'Price (coins)'), prefixIcon: const Icon(Icons.monetization_on, color: kGold)),
        ),
        const SizedBox(height: 8),
        Text(t('Valeur au recyclage : ${recycleValue(c.rarity, finish)}', 'Recycle value: ${recycleValue(c.rarity, finish)}'),
            style: const TextStyle(fontSize: 12, color: Colors.white54)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Annuler', 'Cancel'))),
        ElevatedButton(
          onPressed: () {
            final p = int.tryParse(ctl.text.trim());
            if (p == null || p < 1 || p > 99999) return;
            Navigator.pop(ctx, p);
          },
          child: Text(t('Vendre', 'Sell')),
        ),
      ],
    ),
  );
}
