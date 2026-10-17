import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio.dart';
import 'cards.dart';
import 'catalog.dart';
import 'game.dart';
import 'layout.dart';
import 'main.dart';
import 'retro_theme.dart';
import 'filters.dart';
import 'market.dart';
import 'bourse.dart';
import 'server.dart';

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
  final f = CardFilter.album; // filtres et tri (gardés d'un album à l'autre)

  @override
  Widget build(BuildContext context) {
    final sys = widget.sys;
    return ListenableBuilder(
      listenable: Game.i,
      builder: (context, _) {
        final g = Game.i;
        final all = Catalog.bySys[sys] ?? const <RcCard>[];
        final list = f.apply(all);
        final summary = filterSummary(f);
        final mine = g.ownedIn(sys);
        final total = all.length;
        final next = kMilestoneSteps.firstWhere((s) => !g.milestones.contains('$sys:$s'), orElse: () => 0);
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 64,
            title: ConsoleLogo(sys, height: 40),
            actions: [
              FilterButton(filter: f, source: all, onChanged: () => setState(() {})),
              IconButton(
                tooltip: t('Recycler les doublons', 'Recycle duplicates'),
                icon: Badge(isLabelVisible: g.dupes > 0, label: Text('${g.dupes}'), child: const Icon(Icons.recycling)),
                onPressed: () => recycleAllDupes(context),
              ),
              Padding(padding: const EdgeInsets.only(right: 12), child: Center(child: CoinChip(g.coins))),
            ],
          ),
          body: SplitCardDetail(
           child: Column(children: [
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
                ]),
                if (summary.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      const Icon(Icons.tune, size: 14, color: kGold),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('$summary · ${list.length}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kGold, fontSize: 11)),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => f.reset()),
                        child: Text(t('Effacer', 'Clear'), style: const TextStyle(color: Color(0xFF8FD3FF), fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
              ]),
            ),
            Expanded(
              child: CardGrid(list),
            ),
           ]),
          ),
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

/// [list] : cartes affichées autour (grille de l'album, toutes mes cartes…) ;
/// si fourni, la fiche permet de passer à la carte possédée précédente / suivante.
void openCardDetail(BuildContext context, RcCard c, {Map<String, List<int>>? otherOwned, String? otherName, List<RcCard>? list}) {
  final split = context.getInheritedWidgetOfExactType<_SplitScope>();
  final st = split?.state;
  if (st != null && otherOwned == null) {
    st.select(c, list); // mode large : la fiche s'affiche à droite, sans changer d'écran
    return;
  }
  Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => otherOwned == null && list != null
          ? CardBrowser(list: list, card: c)
          : CardDetailPage(card: c, otherOwned: otherOwned, otherName: otherName)));
}

/// Navigation entre cartes possédées depuis la fiche (flèches, glisser, clavier).
class CardNav {
  final VoidCallback? prev, next;
  final int pos, count; // position parmi les cartes possédées de la liste (0 = carte non possédée)
  const CardNav({this.prev, this.next, required this.pos, required this.count});
}

/// Fiche d'une carte avec passage à la carte possédée précédente / suivante de [list].
class CardBrowser extends StatefulWidget {
  final List<RcCard> list;
  final RcCard card;
  final bool embedded;
  const CardBrowser({super.key, required this.list, required this.card, this.embedded = false});
  @override
  State<CardBrowser> createState() => _CardBrowserState();
}

class _CardBrowserState extends State<CardBrowser> {
  late RcCard cur = widget.card;

  RcCard? _step(int d) {
    final l = widget.list;
    var i = l.indexWhere((x) => x.id == cur.id);
    if (i < 0) return null;
    for (i += d; i >= 0 && i < l.length; i += d) {
      if (Game.i.has(l[i].id)) return l[i];
    }
    return null;
  }

  void _go(int d) {
    final n = _step(d);
    if (n == null) return;
    setState(() => cur = n);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Game.i,
      builder: (context, _) {
        final owned = [for (final c in widget.list) if (Game.i.has(c.id)) c.id];
        final nav = CardNav(
          prev: _step(-1) == null ? null : () => _go(-1),
          next: _step(1) == null ? null : () => _go(1),
          pos: owned.indexOf(cur.id) + 1,
          count: owned.length,
        );
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: CardDetailPage(key: ValueKey(cur.id), card: cur, embedded: widget.embedded, nav: nav),
        );
      },
    );
  }
}

// ─── Mode large : liste à gauche, fiche de la carte choisie à droite ───────
class SplitCardDetail extends StatefulWidget {
  final Widget child;
  const SplitCardDetail({super.key, required this.child});
  @override
  State<SplitCardDetail> createState() => _SplitCardDetailState();
}

class _SplitCardDetailState extends State<SplitCardDetail> {
  RcCard? selected;
  List<RcCard>? list;

  void select(RcCard c, [List<RcCard>? l]) => setState(() {
        selected = c;
        list = l;
      });

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final sel = selected;
    return _SplitScope(
      state: wide ? this : null,
      child: Row(children: [
        Expanded(child: widget.child),
        if (wide)
          Container(
            width: 420,
            decoration: BoxDecoration(
              color: kBg.withOpacity(0.55),
              border: const Border(left: BorderSide(color: Colors.white12)),
            ),
            child: sel == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.touch_app, size: 42, color: Colors.white24),
                        const SizedBox(height: 10),
                        Text(t('Touche une carte pour voir sa fiche', 'Tap a card to see its details'),
                            textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
                      ]),
                    ),
                  )
                : list != null
                    ? CardBrowser(key: ValueKey(sel.id), list: list!, card: sel, embedded: true)
                    : CardDetailPage(key: ValueKey(sel.id), card: sel, embedded: true),
          ),
      ]),
    );
  }
}

class _SplitScope extends InheritedWidget {
  final _SplitCardDetailState? state;
  const _SplitScope({required this.state, required super.child});
  @override
  bool updateShouldNotify(_SplitScope old) => old.state != state;
}

// ─── Fiche d'une carte ─────────────────────────────────────────────────────
class CardDetailPage extends StatefulWidget {
  final RcCard card;
  final Map<String, List<int>>? otherOwned; // collection d'un autre joueur (lecture seule)
  final String? otherName;
  final bool embedded; // mode large : affichée à droite de l'album (pas de bouton retour)
  final CardNav? nav; // passage à la carte possédée précédente / suivante
  const CardDetailPage({super.key, required this.card, this.otherOwned, this.otherName, this.embedded = false, this.nav});
  @override
  State<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends State<CardDetailPage> {
  int finish = 0;
  bool busy = false;
  final _cardKey = GlobalKey();
  Offset? _down;
  Duration _downT = Duration.zero;

  // glisser l'écran (hors de la carte, qui garde son geste de rotation) = carte suivante / précédente
  bool _onCard(Offset p) {
    final b = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (b == null || !b.hasSize) return false;
    return (b.localToGlobal(Offset.zero) & b.size).contains(p);
  }

  void _swipeEnd(PointerUpEvent e) {
    final d = _down, nav = widget.nav;
    _down = null;
    if (d == null || nav == null) return;
    final dx = e.position.dx - d.dx, dy = e.position.dy - d.dy;
    final ms = (e.timeStamp - _downT).inMilliseconds;
    if (dx.abs() < 60 || dx.abs() < dy.abs() * 1.5 || ms > 700) return;
    (dx < 0 ? nav.next : nav.prev)?.call();
  }

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
          final shot = owned || myTotal > 0 ? Catalog.shot(c) : null;
          final nav = widget.nav;
          final cardW = SizedBox(key: _cardKey, width: 240, child: SpinCard(key: ValueKey('$finish'), card: c, finish: owned ? finish : 0, owned: owned));
          Widget arrow(IconData i, VoidCallback? f, String tip) => IconButton(
                tooltip: tip,
                iconSize: 38,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 38, minHeight: 64),
                color: kGold,
                disabledColor: Colors.white12,
                icon: Icon(i),
                onPressed: f,
              );
          final page = Scaffold(
            backgroundColor: widget.embedded ? Colors.transparent : null,
            appBar: AppBar(
              toolbarHeight: 66,
              automaticallyImplyLeading: !widget.embedded,
              backgroundColor: widget.embedded ? Colors.transparent : null,
              // titre complet : police pixel plus petite, sur 2 lignes si besoin
              title: Text(owned || myTotal > 0 ? c.title : '#${c.num.toString().padLeft(3, '0')}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: pixelStyle(size: 11, color: Colors.white, shadow: false)),
              actions: [if (!readOnly) Padding(padding: const EdgeInsets.only(right: 12), child: Center(child: CoinChip(Game.i.coins)))],
            ),
            body: Listener(
             onPointerDown: (e) {
               _down = _onCard(e.position) ? null : e.position;
               _downT = e.timeStamp;
             },
             onPointerUp: _swipeEnd,
             onPointerCancel: (_) => _down = null,
             child: ListView(padding: const EdgeInsets.all(16), children: [
              if (nav == null)
                Center(child: cardW)
              else
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  arrow(Icons.chevron_left, nav.prev, t('Carte précédente', 'Previous card')),
                  Flexible(child: cardW),
                  arrow(Icons.chevron_right, nav.next, t('Carte suivante', 'Next card')),
                ]),
              const SizedBox(height: 6),
              Text(t('Fais tourner la carte avec ton doigt · double-tap pour la remettre de face', 'Spin the card with your finger · double-tap to reset'),
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              if (nav != null && nav.count > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    nav.pos > 0
                        ? t('${nav.pos} / ${nav.count} · glisse l\'écran pour changer de carte', '${nav.pos} / ${nav.count} · swipe the screen to change card')
                        : t('${nav.count} cartes possédées · glisse l\'écran pour les parcourir', '${nav.count} owned cards · swipe the screen to browse them'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kGold, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
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
                ClipRRect(borderRadius: BorderRadius.circular(10), child: Image(image: shot, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox())),
              if (owned || myTotal > 0) ...[
                const SizedBox(height: 14),
                _info(t('Console', 'System'), Catalog.system(c.sys)?.name ?? c.sys),
                _info(t('Année', 'Year'), '${c.year ?? '?'}'),
                _info(t('Développeur', 'Developer'), c.dev.isEmpty ? '?' : c.dev),
                _info(t('Éditeur', 'Publisher'), c.pub.isEmpty ? '?' : c.pub),
                _info(t('Genre', 'Genre'), c.genreL.isEmpty ? '?' : c.genreL),
                _info(t('Rareté', 'Rarity'), rarityName(c.rarity)),
                if (c.descL.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(c.descL, style: const TextStyle(color: Colors.white70, height: 1.45)),
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
            ),
          );
          if (nav == null) return page;
          // clavier (web / PC) : flèches gauche / droite
          return CallbackShortcuts(
            bindings: {
              if (nav.prev != null) const SingleActivator(LogicalKeyboardKey.arrowLeft): nav.prev!,
              if (nav.next != null) const SingleActivator(LogicalKeyboardKey.arrowRight): nav.next!,
            },
            child: Focus(autofocus: true, child: page),
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
      // Bourse : acheter / vendre / demander en échange, directement depuis la carte
      _BoursePanel(
        key: ValueKey('bourse${c.id}$total'),
        card: c,
        onSell: total > 0 && x[finish] > 0 && !busy ? () => _sell(context, c) : null,
        sellLabel: total > 0 ? t('Vendre (${finishName(finish).toLowerCase()})', 'Sell (${finishName(finish).toLowerCase()})') : null,
      ),
      const SizedBox(height: 14),
      if (total > 0) ...[
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.recycling),
              label: Text(t('Recycler +${recycleValue(c.rarity, finish)}', 'Recycle +${recycleValue(c.rarity, finish)}')),
              onPressed: busy || total <= 1 || x[finish] == 0 ? null : () => _recycle(c),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              icon: Icon(inShowcase ? Icons.star : Icons.star_border, color: kGold),
              label: Text(inShowcase ? t('Hors vitrine', 'Unshowcase') : t('Vitrine', 'Showcase')),
              onPressed: busy ? null : () => _toggleShowcase(c, inShowcase),
            ),
          ),
        ]),
        const SizedBox(height: 8),
      ],
      // fusion : 5 normales → brillante, 3 brillantes → dorée
      if (x[0] >= 5 || x[1] >= 3) ...[
        for (final f in [0, 1])
          if (x[f] >= (f == 0 ? 5 : 3))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: f == 0 ? const Color(0xFF3C3489) : const Color(0xFF7A5A0E),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                  side: BorderSide(color: f == 0 ? const Color(0xFFB4A9FF) : kGold, width: 1.5),
                ),
                icon: Text(f == 0 ? '✦' : '★', style: const TextStyle(fontSize: 18)),
                label: Text(
                  f == 0
                      ? t('Fusionner 5 normales → 1 brillante', 'Fuse 5 normal → 1 holo')
                      : t('Fusionner 3 brillantes → 1 dorée', 'Fuse 3 holo → 1 gold'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                onPressed: busy ? null : () => _fuse(c, f),
              ),
            ),
      ] else if (total > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            t('Fusion : 5 normales → 1 brillante · 3 brillantes → 1 dorée (tu as ${x[0]} normale(s), ${x[1]} brillante(s))',
                'Fusion: 5 normal → 1 holo · 3 holo → 1 gold (you have ${x[0]} normal, ${x[1]} holo)'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: Colors.white38),
          ),
        ),
      ElevatedButton.icon(
        icon: const Icon(Icons.auto_fix_high),
        label: Text(t('Fabriquer (${fmt(cost)} pièces)', 'Craft (${fmt(cost)} coins)')),
        onPressed: busy || g.coins < cost ? null : () => _craft(c, cost),
      ),
      if (total > 1)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            t('Recycler rapporte des pièces (on garde toujours un exemplaire).', 'Recycling gives coins (you always keep one copy).'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: Colors.white38),
          ),
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

  void _fuse(RcCard c, int from) => _run(() async {
        final need = from == 0 ? 5 : 3;
        final to = from + 1;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(t('Fusionner ?', 'Fuse?')),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(width: 70, child: CardView(card: c, finish: from)),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('×$need', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))),
                const Icon(Icons.arrow_forward, color: Colors.white54),
                const SizedBox(width: 8),
                SizedBox(width: 70, child: CardView(card: c, finish: to)),
              ]),
              const SizedBox(height: 12),
              Text(
                t('$need exemplaires ${finishName(from).toLowerCase()}s deviennent 1 exemplaire ${finishName(to).toLowerCase()}.',
                    '$need ${finishName(from).toLowerCase()} copies become 1 ${finishName(to).toLowerCase()} copy.'),
                textAlign: TextAlign.center,
              ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Annuler', 'Cancel'))),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(t('Fusionner', 'Fuse'), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        );
        if (ok != true) return;
        final f = await Game.i.fuse(c.id, from);
        RcAudio.sfx('powerup');
        Game.i.playSound(c.rarity >= 3 ? c.rarity : 3);
        if (!mounted) return;
        setState(() => finish = f);
        await showDialog<void>(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: kBg.withOpacity(0.95),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: f == 2 ? kGold : const Color(0xFFB4A9FF), width: 2)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(f == 2 ? t('Carte dorée !', 'Gold card!') : t('Carte brillante !', 'Holo card!'), style: pixelStyle(size: 12)),
                const SizedBox(height: 16),
                TiltScope(child: SizedBox(width: 200, child: CardView(card: c, finish: f, tilt3d: true))),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Super !', 'Great!'))),
              ]),
            ),
          ),
        );
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
  Map<String, dynamic>? info;
  var loading = true;
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      if (loading && info == null) {
        marketPriceInfo(c.id, finish).then((m) {
          info = m;
          loading = false;
          ctl.text = '${suggestedPrice(c, finish, m)}';
          if (ctx.mounted) setD(() {});
        });
        info = const {}; // évite de relancer la requête
      }
      final rec = recycleValue(c.rarity, finish);
      final avg = (info?['avg'] as num?)?.toInt();
      final min = (info?['min'] as num?)?.toInt();
      Widget chip(String label, int v) => ActionChip(
            label: Text('$label : $v', style: const TextStyle(fontSize: 12)),
            avatar: const Icon(Icons.monetization_on, color: kGold, size: 16),
            onPressed: () => setD(() => ctl.text = '$v'),
          );
      return AlertDialog(
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
          const SizedBox(height: 10),
          if (loading)
            const LinearProgressIndicator(minHeight: 2, color: kGold)
          else
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (avg != null) chip(t('Prix moyen', 'Average price'), avg),
              if (min != null) chip(t('Moins cher en vente', 'Cheapest listed'), min),
              chip(t('Recyclage', 'Recycle'), rec),
            ]),
          const SizedBox(height: 6),
          Text(
            avg != null
                ? t('${info?['sold']} vente(s) ces 30 derniers jours', '${info?['sold']} sale(s) in the last 30 days')
                : t('Pas encore de vente de cette carte : prix conseillé = 2 × recyclage', 'No sales yet for this card: suggested = 2 × recycle'),
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
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
      );
    }),
  );
}

/// Encadré « Bourse » de la fiche d'une carte : offres au marché (prix le plus
/// bas), vendre la mienne, la demander en échange à un joueur qui l'a en double.
class _BoursePanel extends StatefulWidget {
  final RcCard card;
  final VoidCallback? onSell;
  final String? sellLabel;
  const _BoursePanel({super.key, required this.card, this.onSell, this.sellLabel});
  @override
  State<_BoursePanel> createState() => _BoursePanelState();
}

class _BoursePanelState extends State<_BoursePanel> {
  int? lots, min;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await RcServer.marketList(card: widget.card.id);
      var m = 0;
      for (final x in r) {
        final p = (x['price'] as num).toInt();
        if (m == 0 || p < m) m = p;
      }
      if (mounted) {
        setState(() {
          lots = r.length;
          min = m;
        });
      }
    } catch (_) {
      if (mounted) setState(() => lots = -1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.card;
    final n = lots;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kGold.withOpacity(0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.storefront, color: kGold, size: 18),
          const SizedBox(width: 6),
          Text(t('Bourse', 'Exchange'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const Spacer(),
          if (n == null)
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: kGold))
          else if (n < 0)
            Text(t('hors ligne', 'offline'), style: const TextStyle(color: Colors.white38, fontSize: 12))
          else if (n == 0)
            Text(t('aucune en vente', 'none for sale'), style: const TextStyle(color: Colors.white54, fontSize: 12))
          else
            Text(t('$n en vente · dès $min', '$n for sale · from $min'), style: const TextStyle(color: kGold, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: kGold,
                foregroundColor: const Color(0xFF2A1800),
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              onPressed: (n ?? 0) > 0
                  ? () async {
                      await showCardOffers(context, c.id);
                      _load();
                    }
                  : null,
              icon: const Icon(Icons.shopping_cart, size: 18),
              label: Text(t('Acheter', 'Buy'), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
              onPressed: () => askTradeFor(context, c),
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: Text(t('Échanger', 'Trade')),
            ),
          ),
        ]),
        if (widget.sellLabel != null) ...[
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: widget.onSell == null
                ? null
                : () {
                    widget.onSell!();
                  },
            icon: const Icon(Icons.sell_outlined, size: 18),
            label: Text(widget.sellLabel!),
          ),
        ],
      ]),
    );
  }
}
