import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'audio.dart';
import 'booster_choice.dart';
import 'cards.dart';
import 'catalog.dart';
import 'duel_watch.dart';
import 'events.dart';
import 'game.dart';
import 'library.dart';
import 'main.dart';
import 'notifs.dart';
import 'retro_theme.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Boutique de paquets + ouverture animée (déchirer, révéler, effets par rareté)
// ═══════════════════════════════════════════════════════════════════════════

/// Ouvre un paquet (serveur + choix du booster + animation). [sys] : console, ou numéro du cadeau.
Future<void> openPackFlow(BuildContext context, String kind, [String? sys]) async {
  _packFlows++;
  try {
    final r = await Game.i.openChoice(kind, sys);
    if (!context.mounted) return;
    await showPackOpening(context, r, kind, sys);
  } finally {
    _packFlows--;
  }
  if (_packFlows == 0) _packFlowsDone();
}

/// Ouvertures en cours (achat → choix du booster) : pendant ce temps, le paquet « en attente »
/// vu par le serveur est celui qu'on est en train d'ouvrir, pas un paquet entamé à afficher.
int _packFlows = 0;

/// Un paquet est en cours d'ouverture : pas de fenêtre de défi par-dessus (duel_watch.dart)
bool get packOpening => _packFlows > 0;

/// Fin d'une ouverture : paquet entamé revérifié, défi en attente montré
void _packFlowsDone() {
  PacksScreenState.reloadPending();
  DuelWatch.i.retryShow();
}

/// Écran d'ouverture pour un résultat de [Game.openChoice] (ou un achat resté sans choix).
Future<void> showPackOpening(BuildContext context, Map<String, dynamic> r, String kind, [String? sys]) async {
  _packFlows++;
  try {
    await _showPackOpening(context, r, kind, sys);
  } finally {
    _packFlows--;
  }
  if (_packFlows == 0) _packFlowsDone(); // booster quitté sans déchirer → « Paquet entamé »
}

Future<void> _showPackOpening(BuildContext context, Map<String, dynamic> r, String kind, [String? sys]) async {
  r = await Game.i.autoPickGift(r); // cadeau resté en attente : couleur au hasard
  if (!context.mounted) return;
  final k = (r['kind'] as String?) ?? kind;
  final s = r.containsKey('kind') ? r['sys'] as String? : sys;
  if (r['resumed'] == true) toast(t('Tu n\'avais pas encore choisi ton booster', 'You hadn\'t picked your booster yet'));
  await Navigator.of(context).push(PageRouteBuilder(
    opaque: true,
    pageBuilder: (_, __, ___) => PackOpeningPage(result: r, kind: k, sys: k == 'console' || k == 'sconsole' ? s : null),
    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  ));
  Game.i.sync();
  Notifs.i.refresh();
}

/// Accès depuis le menu : recharge le paquet entamé quand on ouvre l'onglet
class PacksScreenState {
  static void reloadPending() => _PacksScreenState.current?.loadPending();

  /// Clic sur les pièces du bandeau : défile jusqu'à la boutique
  static void showShop() => _PacksScreenState.current?.showShop();

  /// Clic sur les pixels du bandeau : ouvre le sous-menu des boosters spéciaux
  static void openPixels() => _PacksScreenState.current?._openPixels();
}

class PacksScreen extends StatefulWidget {
  const PacksScreen({super.key});
  @override
  State<PacksScreen> createState() => _PacksScreenState();
}

class _PacksScreenState extends State<PacksScreen> {
  static _PacksScreenState? current;
  bool busy = false;
  Map<String, dynamic>? pending; // paquet déjà payé dont le booster n'est pas encore choisi
  final _scroll = ScrollController();
  final _shopKey = GlobalKey();

  void showShop() {
    final c = _shopKey.currentContext;
    if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 500), curve: Curves.easeInOutCubic);
  }

  @override
  void initState() {
    super.initState();
    current = this;
    loadPending();
  }

  @override
  void dispose() {
    if (current == this) current = null;
    _scroll.dispose();
    super.dispose();
  }

  /// Paquet entamé (on a quitté le choix des boosters sans déchirer) : il reste dans le stock
  Future<void> loadPending() async {
    // prix et promos en direct (un événement « promo » a pu commencer)
    RcServer.appConfig().then((c) {
      applyLive(c['live']);
      if (mounted) setState(() {});
    }).catchError((_) {});
    final gen = ++_pendingGen;
    final p = await Game.i.pendingChoice();
    // réponse dépassée (une plus récente est partie) ou paquet en cours d'ouverture : pas de « Paquet entamé »
    if (!mounted || gen != _pendingGen) return;
    setState(() => pending = _packFlows > 0 ? null : p);
  }

  int _pendingGen = 0;

  Future<void> _resume() async {
    if (pending == null || busy) return;
    setState(() => busy = true);
    try {
      final p = await Game.i.pendingChoice(strict: true); // toujours en attente ? (il a pu être ouvert ailleurs) ; erreur → vrai message
      if (p == null) {
        toast(t('Ce paquet a déjà été ouvert', 'This pack was already opened'));
      } else if (mounted) {
        await showPackOpening(context, p, (p['kind'] as String?) ?? 'mixte', p['sys'] as String?);
      }
    } catch (e) {
      toast(errText(e));
    }
    if (mounted) setState(() => busy = false);
    await loadPending();
  }

  Future<void> _open(String kind, [String? sys]) async {
    if (busy) return;
    if (kind != 'free' && kind != 'gift' && kind != 'lot' && !kSpecialPrice.containsKey(kind) && !await _confirm(kind, sys)) return;
    setState(() => busy = true);
    try {
      await openPackFlow(context, kind, sys);
    } catch (e) {
      toast(errText(e));
    }
    if (mounted) setState(() => busy = false);
    await loadPending();
  }

  /// Confirmation d'achat : booster, prix, solde avant/après.
  Future<bool> _confirm(String kind, String? sys) async {
    final price = kPackPrice[kind] ?? 0;
    final coins = Game.i.coins;
    final color = _kOfferColor[kind] ?? kPanel2;
    final name = switch (kind) {
      'console' => '${t('Paquet', 'Pack')} ${Catalog.system(sys ?? '')?.name ?? ''}',
      'premium' => t('Paquet premium', 'Premium pack'),
      'mystery' => t('Paquet mystère', 'Mystery pack'),
      _ => t('Paquet mixte', 'Mixed pack'),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: kBg.withOpacity(0.95),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: color, width: 2)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(t('Acheter ce paquet ?', 'Buy this pack?'), textAlign: TextAlign.center, style: pixelStyle(size: 11)),
            const SizedBox(height: 18),
            _MiniBooster(kind: kind, label: _offerLabel(kind), color: color, width: 96),
            const SizedBox(height: 16),
            if (kind == 'console' && sys != null)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: ConsoleLogo(sys, height: 26)),
            Text(name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              CoinChip(coins),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward, color: Colors.white54, size: 18)),
              CoinChip(coins - price),
            ]),
            const SizedBox(height: 6),
            Text('-$price ${t('pièces', 'coins')}', style: const TextStyle(color: Color(0xFFFF8A80), fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Annuler', 'Cancel')))),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(t('Acheter', 'Buy'), style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
    return ok == true;
  }

  /// Lot de 5 paquets mixtes : confirmation, achat, ouverture du 1er paquet ; les autres restent « en stock » si on quitte l'écran
  Future<void> _buyLot() async {
    if (busy) return;
    final free = Notifs.i.lotFree;
    final coins = Game.i.coins;
    const color = Color(0xFF534AB7);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: kBg.withOpacity(0.95),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: color, width: 2)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(free ? t('Lot gratuit aujourd\'hui !', 'Free bundle today!') : t('Acheter ce lot ?', 'Buy this bundle?'),
                textAlign: TextAlign.center, style: pixelStyle(size: 11)),
            const SizedBox(height: 18),
            const _LotArt(width: 120),
            const SizedBox(height: 14),
            Text(t('Lot de 5 paquets mixtes', 'Bundle of 5 mixed packs'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            Text(t('25 cartes, toutes consoles', '25 cards, all systems'), style: const TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 14),
            if (free)
              Text(t('GRATUIT aujourd\'hui', 'FREE today'), style: const TextStyle(color: Color(0xFF5DCAA5), fontWeight: FontWeight.w900, fontSize: 16))
            else ...[
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                CoinChip(coins),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward, color: Colors.white54, size: 18)),
                CoinChip(coins - lotPrice),
              ]),
              const SizedBox(height: 6),
              Text('-$lotPrice ${t('pièces', 'coins')}', style: const TextStyle(color: Color(0xFFFF8A80), fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Annuler', 'Cancel')))),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(free ? t('Récupérer', 'Claim') : t('Acheter', 'Buy'), style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      await RcServer.buyLot();
      RcAudio.sfx('powerup');
      await Game.i.sync();
      await Notifs.i.refresh();
      if (mounted) await openPackFlow(context, 'lot');
    } catch (e) {
      toast(errText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _pickConsole([String kind = 'console']) async {
    final sys = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kBg.withOpacity(0.95),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (ctx, scroll) => SafeArea(
          child: CustomScrollView(controller: scroll, slivers: [
            SliverToBoxAdapter(
              child: Column(children: [
                const SizedBox(height: 10),
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(kind == 'sconsole' ? t('BOOSTER CONSOLE+', 'CONSOLE+ BOOSTER') : t('PAQUET CONSOLE', 'CONSOLE PACK'), style: pixelStyle(size: 13)),
                ),
                Text(t('Choisis la série', 'Choose the set'), style: const TextStyle(color: Colors.white60)),
                const SizedBox(height: 12),
              ]),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.15),
                delegate: SliverChildListDelegate([
                  for (final s in Catalog.systems) _ConsolePick(sys: s, onTap: () => Navigator.pop(ctx, s.id)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
    if (sys != null) _open(kind, sys);
  }

  /// Sous-menu Pixels : jauge et boosters spéciaux
  Future<void> _openPixels() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        // glisser vers le bas (depuis le haut de la liste) ferme le sous-menu
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.88,
          minChildSize: 0.35,
          maxChildSize: 0.95,
          builder: (ctx, scroll) => SafeArea(
            child: SingleChildScrollView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: ListenableBuilder(
                listenable: Game.i,
                builder: (_, __) => _PixelsGauge(Game.i.pixels, offers: _pixelOffers(Game.i)),
              ),
            ),
          ),
        ),
      );

  List<Widget> _pixelOffers(Game g) => [
        for (final (kind, title, sub, color) in [
          ('star', t('Booster Étoile', 'Star booster'), t('5 cartes dont une épique ou mieux', '5 cards, one epic or better'), const Color(0xFF8A3DFF)),
          ('sconsole', t('Booster Console+', 'Console+ booster'),
              t('Console au choix : une rare ou mieux et une brillante garanties', 'System of your choice: one rare or better and one holo guaranteed'), const Color(0xFF2F6BFF)),
          ('gold', t('Booster Rétro d\'or', 'Retro Gold booster'), t('Une légendaire… ou une carte dorée garantie', 'A legendary… or a gold card guaranteed'), const Color(0xFFF0A419)),
        ])
          _PackOffer(
            kind: kind,
            packLabel: t('Spécial', 'Special'),
            title: title,
            subtitle: g.pixels >= kSpecialPrice[kind]!
                ? sub
                : '$sub\n${t('Encore ${kSpecialPrice[kind]! - g.pixels} pixels', '${kSpecialPrice[kind]! - g.pixels} more pixels')}',
            price: 0,
            pixels: kSpecialPrice[kind],
            color: color,
            highlight: g.pixels >= kSpecialPrice[kind]!,
            enabled: !busy && g.pixels >= kSpecialPrice[kind]!,
            onTap: () {
              Navigator.pop(context); // ferme le sous-menu
              kind == 'sconsole' ? _pickConsole('sconsole') : _open(kind);
            },
          ),
      ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Game.i, Notifs.i]),
      builder: (context, _) {
        final g = Game.i, n = Notifs.i;
        final stock = n.gifts + n.lots + (pending != null ? 1 : 0);
        final pk = pending?['kind'];
        Widget shop(String kind, String label, String title, String sub, VoidCallback onTap) {
          final price = kPackPrice[kind]!;
          return _ShopTile(
            kind: kind,
            label: label,
            title: title,
            subtitle: sub,
            price: price,
            color: _kOfferColor[kind]!,
            afford: g.coins >= price,
            enabled: !busy && g.coins >= price,
            onTap: onTap,
          );
        }

        return Column(children: [
          TabHeader(t('Paquets', 'Packs'), icon: 'packs'),
          Expanded(
            child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(14, 4, 14, 24), children: [
              // catégorie Pixels : une ligne compacte, les boosters spéciaux dans un sous-menu
              _PixelsRow(g.pixels, onTap: _openPixels),
              // paquets en stock : déjà payés ou offerts, ouverts seulement quand on les déchire
              if (stock > 0) ...[
                _Section(t('EN STOCK · $stock', 'IN STOCK · $stock')),
                SizedBox(
                  height: 146,
                  child: ListView(scrollDirection: Axis.horizontal, clipBehavior: Clip.none, children: [
                    // paquet entamé : on a ouvert le choix des boosters puis quitté sans déchirer
                    if (pending != null)
                      _StockTile(
                        kind: kPackPrice.containsKey(pk) && pk != 'lot' && pk != 'gift' ? pk as String : 'mixte',
                        label: t('Entamé', 'Started'),
                        title: t('Paquet entamé', 'Started pack'),
                        color: const Color(0xFFB0662A),
                        count: 1,
                        enabled: !busy,
                        onTap: _resume,
                      ),
                    if (n.gifts > 0)
                      _StockTile(
                        kind: 'gift',
                        label: t('Cadeau', 'Gift'),
                        title: n.gifts == 1 ? t('De ${n.giftFrom}', 'From ${n.giftFrom}') : t('De ${n.giftFrom} et d\'autres', 'From ${n.giftFrom} and others'),
                        color: const Color(0xFFD8453C),
                        count: n.gifts,
                        enabled: !busy,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GiftsPage())),
                      ),
                    if (n.lots > 0)
                      _StockTile(
                        kind: 'lot',
                        label: t('Lot', 'Bundle'),
                        title: t('Déjà payés', 'Already paid'),
                        color: const Color(0xFF534AB7),
                        count: n.lots,
                        enabled: !busy,
                        onTap: () => _open('lot'),
                      ),
                  ]),
                ),
              ],
              const SizedBox(height: 14),
              _FreeHero(free: g.free, enabled: g.free && !busy, onTap: () => _open('free')),
              _Section(t('BOUTIQUE', 'SHOP'), key: _shopKey),
              LayoutBuilder(builder: (context, box) {
                final cols = box.maxWidth >= 560 ? 4 : 2;
                return GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 214),
                  children: [
                    shop('mixte', t('Mixte', 'Mixed'), t('Mixte', 'Mixed'), t('5 cartes, toutes consoles', '5 cards, all systems'), () => _open('mixte')),
                    shop('console', 'Console', 'Console', t('5 cartes de la console de ton choix', '5 cards from the system of your choice'), _pickConsole),
                    shop('mystery', t('Mystère', 'Mystery'), t('Mystère', 'Mystery'), t('3, 5 ou… 8 cartes ! Surprise à l\'ouverture', '3, 5 or… 8 cards! Surprise inside'), () => _open('mystery')),
                    shop('premium', 'Premium', 'Premium', t('5 cartes dont une rare ou mieux garantie', '5 cards, one rare or better guaranteed'), () => _open('premium')),
                  ],
                );
              }),
              const SizedBox(height: 10),
              _LotTile(free: n.lotFree, afford: g.coins >= lotPrice, enabled: !busy && (n.lotFree || g.coins >= lotPrice), onTap: _buyLot),
              const SizedBox(height: 14),
              // garantie épique : jauge sur 30 paquets
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(
                    TextSpan(style: const TextStyle(color: Color(0xFFCECBF6), fontSize: 12), children: [
                      TextSpan(text: t('Épique ou mieux garantie dans ', 'Epic or better guaranteed within ')),
                      TextSpan(text: '${max(1, 30 - g.pity)}', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
                      TextSpan(text: t(' paquet(s) au plus', ' pack(s)')),
                    ]),
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: (g.pity / 30).clamp(0.0, 1.0), minHeight: 7, color: const Color(0xFFB04FE0), backgroundColor: Colors.white10),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (r, p) in const [(0, '60 %'), (1, '26 %'), (2, '10 %'), (3, '3,2 %'), (4, '0,8 %')])
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: kRarityDark[r], borderRadius: BorderRadius.circular(8), border: Border.all(color: kRarityColor[r])),
                    child: Text('${rarityName(r)} $p', style: TextStyle(color: kRarityLight[r], fontSize: 11.5, fontWeight: FontWeight.w800)),
                  ),
              ]),
              const SizedBox(height: 8),
              Text(t('Finition brillante : ${livePct('holo')} · dorée : ${livePct('gold')} · full art (épiques et légendaires) : ${livePct('fullart')}', 'Holo finish: ${livePct('holo')} · gold: ${livePct('gold')} · full art (epic and legendary): ${livePct('fullart')}'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          ),
        ]);
      },
    );
  }
}

const _kOfferColor = {
  'free': Color(0xFF1D9E75),
  'mixte': Color(0xFF534AB7),
  'console': Color(0xFF185FA5),
  'premium': Color(0xFF854F0B),
  'mystery': Color(0xFF8E2D8E),
  'gift': Color(0xFFD8453C),
  'lot': Color(0xFF534AB7),
};

String _offerLabel(String kind) => switch (kind) {
      'free' => t('Gratuit', 'Free'),
      'console' => 'Console',
      'premium' => 'Premium',
      'mystery' => t('Mystère', 'Mystery'),
      'gift' => t('Cadeau', 'Gift'),
      'lot' => t('Lot', 'Bundle'),
      _ => t('Mixte', 'Mixed'),
    };

/// Tuile du choix de console : photo, logo, progression.
class _ConsolePick extends StatelessWidget {
  final RcSystem sys;
  final VoidCallback onTap;
  const _ConsolePick({required this.sys, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final owned = Game.i.ownedIn(sys.id);
    final total = max(1, sys.count);
    final brand = owned >= total ? kGold : (kConsoleBrand[sys.id] ?? const Color(0xFF3550B8));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color.lerp(kBg, brand, 0.3)!, kBg],
            ),
            border: Border.all(color: brand.withOpacity(0.8), width: 1.5),
            boxShadow: [BoxShadow(color: brand.withOpacity(0.25), blurRadius: 10)],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(children: [
              SizedBox(height: 24, child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: ConsoleLogo(sys.id, height: 20)))),
              const SizedBox(height: 4),
              Expanded(
                child: Image.asset(
                  'assets/consoles/${sys.id}.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) => Icon(Icons.videogame_asset, size: 40, color: Colors.white.withOpacity(0.4)),
                ),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(value: owned / total, minHeight: 5, color: brand, backgroundColor: Colors.white12),
                  ),
                ),
                const SizedBox(width: 8),
                Text('$owned/${sys.count}', style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w700)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _PackOffer extends StatelessWidget {
  final String title, subtitle;
  final int price;
  final Color color;
  final bool enabled, highlight;
  final VoidCallback onTap;
  final String kind, packLabel;
  final Widget? art, trailing, below;
  final int? pixels; // prix en pixels (booster spécial)
  const _PackOffer({required this.kind, required this.packLabel, required this.title, required this.subtitle, required this.price, required this.color, required this.enabled, required this.onTap, this.highlight = false, this.art, this.trailing, this.below, this.pixels});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: kPanel,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: highlight ? kGold : color.withOpacity(0.6), width: highlight ? 2 : 1),
            ),
            child: Row(children: [
              art ?? _MiniBooster(kind: kind, label: packLabel, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 3),
                  if (subtitle.isNotEmpty) Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  if (below != null) below!,
                ]),
              ),
              Opacity(
                opacity: enabled ? 1 : 0.4,
                child: pixels != null
                    ? PixelChip(pixels!)
                    : price == 0
                        ? Text(t('GRATUIT', 'FREE'), style: const TextStyle(color: Color(0xFF5DCAA5), fontWeight: FontWeight.w900))
                        : CoinChip(price),
              ),
              if (trailing != null) trailing!,
            ]),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Ouverture d'un paquet
// ═══════════════════════════════════════════════════════════════════════════

class _Pulled {
  final RcCard card;
  final int f, r;
  final bool isNew;
  const _Pulled(this.card, this.f, this.r, this.isNew);
}

class _Particle {
  Offset p, v;
  double life;
  final double maxLife, size, gravity;
  final Color color;
  _Particle(this.p, this.v, this.life, this.size, this.color, this.gravity) : maxLife = life;
}

class PackOpeningPage extends StatefulWidget {
  final Map<String, dynamic> result;
  final String kind;
  final String? sys;
  const PackOpeningPage({super.key, required this.result, required this.kind, this.sys});
  @override
  State<PackOpeningPage> createState() => _PackOpeningPageState();
}

enum _Phase { choose, pack, reveal, summary }

class _PackOpeningPageState extends State<PackOpeningPage> with TickerProviderStateMixin {
  List<_Pulled> pulled = [];
  _Phase phase = _Phase.pack;
  late Map<String, dynamic> res; // résultat du serveur (cartes du booster choisi)
  int? booster; // couleur du booster choisi (kBoosters)
  Map? missed; // meilleure carte des autres boosters {c,f,r,n,b}

  // déchirure
  double tear = 0;
  double? dragStart;
  bool torn = false;
  int _lastTick = 0;
  late final AnimationController tearCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
  late final AnimationController sheenCtl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  late final AnimationController wiggleCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
  // rotation du paquet avec le doigt (avant / arrière), comme une carte
  double rotY = 0, rotX = 0, _fromY = 0, _toY = 0, _fromX = 0;
  double pw = _kPackW, ph = _kPackH; // taille du paquet à l'écran
  double get pcap => ph * _kCapFrac;
  bool _tearing = false, _keepX = true;
  bool faceUp = false; // paquet ouvert de face : les cartes sortent de face (déjà retournées)
  late final AnimationController spinCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
    ..addListener(() {
      final v = Curves.easeOutCubic.transform(spinCtl.value);
      setState(() {
        rotY = _fromY + (_toY - _fromY) * v;
        rotX = _keepX ? _fromX : _fromX * (1 - v);
      });
    });

  // révélation
  int idx = 0;
  bool flipped = false, busy = false;
  late final AnimationController dealCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController flipCtl = AnimationController(vsync: this);
  late final AnimationController liftCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  late final AnimationController shakeCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..repeat();
  late final AnimationController auraCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
  late final AnimationController outCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  late final AnimationController raysCtl = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
  late final AnimationController flashCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  double dim = 0, rays = 0;
  bool banner = false, tagOn = false;
  Offset? fingerTilt;
  double dragDx = 0; // glissement de la carte vers la droite

  // particules
  final particles = <_Particle>[];
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  Size stage = Size.zero;
  final rnd = Random();

  @override
  void initState() {
    super.initState();
    rcEdgeMenuBlocked++;
    res = widget.result;
    if (res['cards'] == null && res['choose'] != null) {
      phase = _Phase.choose; // 6 boosters tirés : le joueur en choisit un
    } else {
      _load(res);
    }
    _ticker = createTicker(_tick)..start();
    RcAudio.sfx('logo');
  }

  void _load(Map<String, dynamic> r) {
    final list = <_Pulled>[];
    for (final c in (r['cards'] as List? ?? const [])) {
      final card = Catalog.cards[c['c'] as String];
      if (card == null) continue;
      list.add(_Pulled(card, (c['f'] as num).toInt(), (c['r'] as num).toInt(), c['n'] == true));
    }
    // du plus commun au plus rare : le meilleur pour la fin
    list.sort((a, b) => (a.r * 4 + a.f).compareTo(b.r * 4 + b.f));
    pulled = list;
    booster = (r['choice'] as num?)?.toInt();
    // cadeau : pas de choix, donc pas de « tu as raté »
    missed = widget.kind != 'gift' && r['missed'] is Map && Catalog.cards[(r['missed'] as Map)['c']] != null ? r['missed'] as Map : null;
  }

  /// Booster choisi : le serveur donne ses cartes, puis on passe au paquet à déchirer.
  bool _choosing = false;

  Future<void> _choose(int i) async {
    if (_choosing) return; // un seul envoi à la fois
    _choosing = true;
    try {
      final r = await Game.i.pickPack(i);
      if (!mounted) return;
      RcAudio.sfx('coin');
      setState(() {
        res = r;
        _load(r);
        booster = i;
        phase = _Phase.pack;
      });
    } catch (e) {
      if ('$e'.contains('aucun booster')) {
        // ce paquet a déjà été ouvert (autre écran, autre appareil) : on ferme proprement
        toast(t('Ce paquet a déjà été ouvert', 'This pack was already opened'));
        Game.i.sync();
        if (mounted) Navigator.of(context).maybePop();
      } else {
        toast(errText(e));
      }
    } finally {
      _choosing = false;
    }
  }

  @override
  void dispose() {
    rcEdgeMenuBlocked--;
    _ticker.dispose();
    for (final c in [tearCtl, sheenCtl, wiggleCtl, spinCtl, dealCtl, flipCtl, liftCtl, shakeCtl, auraCtl, outCtl, raysCtl, flashCtl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 16666.0).clamp(0.0, 3.0);
    _last = now;
    if (particles.isEmpty) return;
    for (final p in particles) {
      p.p += p.v * dt;
      p.v = Offset(p.v.dx * pow(0.985, dt), p.v.dy + p.gravity * dt);
      p.life -= dt;
    }
    particles.removeWhere((p) => p.life <= 0);
    setState(() {});
  }

  void _burst(Offset at, int n, List<Color> colors, double speed, {double gravity = 0.12}) {
    for (var i = 0; i < n; i++) {
      final a = rnd.nextDouble() * pi * 2;
      final v = speed * (0.3 + rnd.nextDouble());
      particles.add(_Particle(at, Offset(cos(a) * v, sin(a) * v - 1.5), 50 + rnd.nextDouble() * 60,
          2 + rnd.nextInt(4).toDouble(), colors[rnd.nextInt(colors.length)], gravity));
    }
  }

  Offset get _center => Offset(stage.width / 2, stage.height / 2);

  // ── Phase 1 : tourner le paquet, puis le déchirer ─────────────────────
  void _panStart(DragStartDetails d) {
    if (torn) return;
    spinCtl.stop();
    _tearing = d.localPosition.dy < ph * 0.22;
    if (_tearing) {
      // remis bien droit, du côté (recto / verso) le plus proche, pour déchirer
      final target = (rotY / pi).roundToDouble() * pi;
      faceUp = cos(target) > 0;
      _spinTo(target, keepX: false);
      _dragStart(d);
    }
  }

  void _panUpdate(DragUpdateDetails d) {
    if (torn) return;
    if (_tearing) {
      _dragUpdate(d);
    } else {
      setState(() {
        rotY -= d.delta.dx * 0.013;
        rotX = (rotX - d.delta.dy * 0.009).clamp(-0.7, 0.7);
      });
    }
  }

  void _panEnd(DragEndDetails d) {
    if (torn) return;
    if (_tearing) {
      _dragEnd(d);
    } else {
      // continue sur sa lancée puis s'arrête
      final v = -d.velocity.pixelsPerSecond.dx;
      spinCtl.duration = Duration(milliseconds: (300 + v.abs() * 0.5).clamp(300, 1400).round());
      _spinTo(rotY + v * 0.0022, keepX: true);
    }
  }

  void _spinTo(double y, {required bool keepX}) {
    _fromY = rotY;
    _fromX = rotX;
    _toY = y;
    _keepX = keepX;
    spinCtl.forward(from: 0);
  }

  void _dragStart(DragStartDetails d) {
    if (torn) return;
    dragStart = d.localPosition.dx;
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (torn || dragStart == null) return;
    final p = ((d.localPosition.dx - dragStart!) / (pw * 0.7)).clamp(0.0, 1.0);
    setState(() => tear = p);
    final tick = (p * 10).floor();
    if (tick > _lastTick) {
      _lastTick = tick;
      HapticFeedback.selectionClick();
    }
    if (rnd.nextBool()) {
      final c = _center;
      _burst(Offset(c.dx - pw / 2 + pw * p, c.dy - ph / 2 + pcap), 2, const [Color(0xFFFAC775), Colors.white], 1.5, gravity: 0.15);
    }
    if (p >= 0.95) _tear();
  }

  void _dragEnd(DragEndDetails d) {
    if (torn) return;
    if (tear < 0.05) wiggleCtl.forward(from: 0);
    dragStart = null;
    _lastTick = 0;
    setState(() => tear = 0);
  }

  Future<void> _tear() async {
    torn = true;
    final c = _center;
    _burst(Offset(c.dx, c.dy - ph / 2 + pcap / 2), 45, const [Color(0xFFFAC775), Colors.white, Color(0xFFAFA9EC)], 4, gravity: 0.18);
    flashCtl.forward(from: 0.6);
    RcAudio.sfx('break');
    HapticFeedback.mediumImpact();
    tearCtl.forward(from: 0);
    if (faceUp) flipCtl.value = 1; // les cartes arrivent déjà de face
    await Future.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;
    setState(() => phase = _Phase.reveal);
    dealCtl.forward(from: 0);
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) _prepare();
  }

  // ── Phase 2 : révéler ─────────────────────────────────────────────────
  void _prepare() {
    if (pulled.isEmpty) return;
    final p = pulled[idx];
    if (p.r >= 3) HapticFeedback.lightImpact();
    setState(() {
      flipped = false;
      tagOn = false;
      banner = false;
      fingerTilt = null;
    });
    if (faceUp) _reveal(instant: true); // déjà de face : effets de rareté tout de suite
  }

  Future<void> _tap() async {
    if (phase != _Phase.reveal || busy || dealCtl.isAnimating) return;
    if (!flipped) {
      await _reveal();
    } else {
      await _next();
    }
  }

  Future<void> _reveal({bool instant = false}) async {
    busy = true;
    final p = pulled[idx];
    if (p.r >= 3) setState(() => dim = p.r == 4 ? 0.82 : 0.55);
    if (instant) {
      flipCtl.value = 1;
      if (p.r == 4) {
        RcAudio.sfx('alarm');
        HapticFeedback.heavyImpact();
      }
    } else {
      if (p.r == 4) {
        RcAudio.sfx('alarm');
        HapticFeedback.heavyImpact();
        await liftCtl.forward(from: 0);
      }
      final ms = const [420, 480, 620, 950, 1500][p.r];
      flipCtl.duration = Duration(milliseconds: ms);
      RcAudio.sfx('jump');
      await flipCtl.forward(from: 0);
    }
    if (!mounted) return;
    final c = _center;
    final colors = [kRarityColor[p.r], kRarityLight[p.r], Colors.white];
    _burst(c, const [10, 22, 45, 90, 170][p.r], colors, const [2.0, 3.0, 4.0, 5.5, 7.0][p.r]);
    if (p.r >= 2) flashCtl.forward(from: 1 - const <double>[0, 0, 0.25, 0.45, 0.7][p.r]);
    if (p.r >= 3) {
      HapticFeedback.heavyImpact();
      setState(() {
        rays = p.r == 4 ? 0.75 : 0.45;
        banner = true;
      });
    } else if (p.r == 2) {
      HapticFeedback.mediumImpact();
    }
    if (p.r == 4) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _burst(Offset(c.dx, c.dy - 160), 70, const [Color(0xFFFAC775), Color(0xFFEF9F27), Colors.white], 3, gravity: 0.06);
      });
    }
    Game.i.playSound(p.r);
    setState(() {
      flipped = true;
      tagOn = true;
    });
    busy = false;
  }

  Future<void> _next() async {
    busy = true;
    setState(() {
      banner = false;
      dim = 0;
      rays = 0;
      tagOn = false;
    });
    await outCtl.forward(from: 0);
    if (!mounted) return;
    flipCtl.value = faceUp ? 1 : 0;
    liftCtl.value = 0;
    outCtl.value = 0;
    dragDx = 0;
    if (idx + 1 >= pulled.length) {
      setState(() => phase = _Phase.summary);
      RcAudio.sfx('tier');
    } else {
      setState(() => idx++);
      _prepare();
    }
    busy = false;
  }

  /// Retour / croix avant la fin : les cartes sont déjà dans la collection,
  /// on saute directement au récapitulatif pour les montrer.
  void _skipToSummary() {
    if (phase == _Phase.summary || phase == _Phase.choose) {
      Navigator.pop(context);
      return;
    }
    for (final c in [tearCtl, wiggleCtl, spinCtl, dealCtl, flipCtl, liftCtl, outCtl]) {
      c.stop();
    }
    particles.clear();
    setState(() {
      torn = true;
      dim = 0;
      rays = 0;
      banner = false;
      tagOn = false;
      phase = _Phase.summary;
    });
    RcAudio.sfx('tier');
  }

  // ── Construction ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: phase == _Phase.summary || phase == _Phase.choose,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _skipToSummary();
      },
      child: TiltScope(
      child: Scaffold(
        backgroundColor: const Color(0xB3060A1E), // fond animé assombri pendant l'ouverture
        body: SafeArea(
          child: Column(children: [
            Row(children: [
              IconButton(icon: const Icon(Icons.close), onPressed: _skipToSummary),
              Expanded(
                child: Text(
                  switch (widget.kind) {
                    'free' => t('Paquet gratuit', 'Free pack'),
                    'console' => t('Paquet ${Catalog.system(widget.sys ?? '')?.name ?? ''}', '${Catalog.system(widget.sys ?? '')?.name ?? ''} pack'),
                    'sconsole' => t('Booster ${Catalog.system(widget.sys ?? '')?.name ?? ''}+', '${Catalog.system(widget.sys ?? '')?.name ?? ''}+ booster'),
                    'star' => t('Booster Étoile', 'Star booster'),
                    'gold' => t('Booster Rétro d\'or', 'Retro Gold booster'),
                    'premium' => t('Paquet premium', 'Premium pack'),
                    'mystery' => t('Paquet mystère', 'Mystery pack'),
                    'gift' => t('Paquet cadeau', 'Gift pack'),
                    'lot' => t('Paquet du lot', 'Bundle pack'),
                    _ => t('Paquet mixte', 'Mixed pack'),
                  },
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                ),
              ),
              ListenableBuilder(listenable: Game.i, builder: (_, __) => CoinChip(Game.i.coins)),
              const SizedBox(width: 12),
            ]),
            Expanded(
              child: LayoutBuilder(builder: (context, box) {
                stage = Size(box.maxWidth, box.maxHeight);
                return Stack(children: [
                  // assombrissement (épique / légendaire)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedOpacity(opacity: dim, duration: const Duration(milliseconds: 450), child: Container(color: Colors.black)),
                    ),
                  ),
                  // rayons tournants
                  if (phase == _Phase.reveal)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: rays,
                          duration: const Duration(milliseconds: 600),
                          child: RotationTransition(
                            turns: raysCtl,
                            child: CustomPaint(painter: _RaysPainter(kRarityColor[pulled.isEmpty ? 0 : pulled[idx].r])),
                          ),
                        ),
                      ),
                    ),
                  if (phase == _Phase.choose) _chooseStage(),
                  if (phase == _Phase.pack) _packStage(),
                  if (phase == _Phase.reveal) _revealStage(),
                  if (phase == _Phase.summary) _summary(),
                  // bannière
                  if (phase == _Phase.reveal && pulled.isNotEmpty)
                    Positioned(
                      top: 18,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: AnimatedScale(
                          scale: banner ? 1 : 0,
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.elasticOut,
                          child: Text(
                            '${rarityName(pulled[idx].r)} !',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              color: kRarityColor[pulled[idx].r],
                              shadows: [Shadow(color: kRarityColor[pulled[idx].r], blurRadius: 18)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  // particules
                  Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _ParticlesPainter(particles)))),
                  // flash
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: flashCtl,
                        builder: (_, __) => Container(color: Colors.white.withOpacity(flashCtl.isAnimating ? (1 - flashCtl.value) * 0.8 : 0.0)),
                      ),
                    ),
                  ),
                ]);
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
              child: Text(_hint(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 13)),
            ),
          ]),
        ),
      ),
    ),
    );
  }

  String _hint() {
    switch (phase) {
      case _Phase.choose:
        return t('Fais tourner les boosters avec ton doigt · touche celui du milieu pour le choisir',
            'Spin the boosters with your finger · tap the middle one to pick it');
      case _Phase.pack:
        return t('Fais tourner le paquet avec ton doigt · glisse le long du pointillé en haut pour l\'ouvrir\nOuvert de face, les cartes sortent de face · ouvert de dos, elles sortent de dos',
            'Spin the pack with your finger · swipe along the dotted line at the top to open it\nOpened face up, the cards come out face up · opened from the back, face down');
      case _Phase.reveal:
        if (pulled.isEmpty) return '';
        if (flipped) return t('Bouge le doigt sur la carte pour la faire briller · touche ou glisse à droite pour continuer', 'Move your finger over the card to make it shine · tap or swipe right to continue');
        return pulled[idx].r >= 3 ? t('Quelque chose brille dans ce paquet…', 'Something is shining in this pack…') : t('Touche ou glisse à droite pour retourner la carte', 'Tap or swipe right to flip the card');
      case _Phase.summary:
        return '';
    }
  }

  Widget _packStage() {
    return LayoutBuilder(builder: (context, box) {
      // le plus grand possible : 82 % de la largeur, sans dépasser la hauteur (étiquette et bouton compris)
      pw = min(box.maxWidth * 0.82, (box.maxHeight - 150) * _kPackW / _kPackH).clamp(160.0, 420.0);
      ph = pw * _kPackH / _kPackW;
      return _packStageSized(pw, ph, pcap);
    });
  }

  Widget _packStageSized(double w, double h, double capH) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onPanStart: _panStart,
          onPanUpdate: _panUpdate,
          onPanEnd: _panEnd,
          onTap: () => wiggleCtl.forward(from: 0),
          onDoubleTap: torn ? null : () => _spinTo((rotY / (2 * pi)).roundToDouble() * 2 * pi, keepX: false),
          child: AnimatedBuilder(
            animation: Listenable.merge([tearCtl, sheenCtl, wiggleCtl]),
            builder: (_, __) {
              final tt = Curves.easeOut.transform(tearCtl.value);
              final wig = sin(wiggleCtl.value * pi * 4) * 0.08 * (1 - wiggleCtl.value);
              final glow = _packColor();
              // brillance : éclat qui ne touche que le paquet (pas son contour), suit la rotation
              // et balaie le paquet toutes les 3 s
              final tc = sheenCtl.value;
              final sweep = tc < 0.4 ? -0.9 + tc / 0.4 * 1.8 : 9.0;
              final turn = sin(rotY) * 0.9 + rotX * 0.5;
              Widget img(String a) => _boosterImg(a, w, h, booster);
              Widget shiny(String a) => ShaderMask(
                    blendMode: BlendMode.srcATop,
                    shaderCallback: (r) {
                      // deux éclats : celui de la rotation (fixe) et celui qui balaie
                      final c1 = 0.5 + turn * 0.5, c2 = 0.5 + sweep * 0.5;
                      final a1 = (0.45 * min(1.0, sin(rotY).abs() * 2 + rotX.abs() * 1.5)).toDouble(); // seulement quand on le penche
                      final pts = <(double, double)>[(c1, a1), (c2, 0.55)]..sort((x, y) => x.$1.compareTo(y.$1));
                      final cols = <Color>[], stops = <double>[];
                      for (final (c, al) in pts) {
                        for (final (d, k) in const [(-0.16, 0.0), (-0.05, 0.4), (0.0, 1.0), (0.05, 0.4), (0.16, 0.0)]) {
                          cols.add(Colors.white.withOpacity(al * k));
                          stops.add((c + d).clamp(0.0, 1.0));
                        }
                      }
                      // stops croissants obligatoires
                      for (var i = 1; i < stops.length; i++) {
                        if (stops[i] < stops[i - 1]) stops[i] = stops[i - 1];
                      }
                      return LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: cols, stops: stops).createShader(r);
                    },
                    child: img(a),
                  );
              // étoiles qui scintillent sur le paquet
              final twinkle = IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(w * 0.08, h * 0.1, w * 0.08, h * 0.12),
                  child: const CardSparkle(color: Color(0xFFFFF3C4), stars: 7, seed: 7, sweep: false),
                ),
              );
              // une face du paquet, déchirable (recto ou verso)
              Widget tearable(String asset) => SizedBox(
                      width: w,
                      height: h,
                      child: Stack(clipBehavior: Clip.none, children: [
                        // corps du paquet (tombe après la déchirure)
                        Positioned(
                          top: capH,
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Transform.translate(
                            offset: Offset(0, 420 * Curves.easeIn.transform((tearCtl.value - 0.25).clamp(0, 1) / 0.75)),
                            child: Opacity(
                              opacity: (1 - ((tearCtl.value - 0.45).clamp(0, 1) / 0.55)).toDouble(),
                              child: ClipRect(
                                child: OverflowBox(
                                  alignment: Alignment.bottomCenter,
                                  minWidth: w,
                                  maxWidth: w,
                                  minHeight: h,
                                  maxHeight: h,
                                  child: Stack(children: [shiny(asset), Positioned.fill(child: twinkle)]),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // ligne de déchirure (pointillés + progression)
                        if (!torn)
                          Positioned(
                            top: capH - 2,
                            left: 10,
                            right: 10,
                            height: 4,
                            child: Stack(children: [
                              Positioned.fill(child: CustomPaint(painter: _DashPainter())),
                              FractionallySizedBox(
                                widthFactor: tear,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: kGold,
                                    borderRadius: BorderRadius.circular(2),
                                    boxShadow: const [BoxShadow(color: Color(0xAAFFD166), blurRadius: 6)],
                                  ),
                                ),
                              ),
                            ]),
                          ),
                        // haut du paquet (s'arrache et s'envole)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: capH + 1,
                          child: Transform.translate(
                            offset: Offset(160 * tt + tear * 6, -320 * tt),
                            child: Transform.rotate(
                              angle: 0.9 * tt + tear * 0.05,
                              alignment: Alignment.centerLeft,
                              child: Opacity(
                                opacity: 1 - tt,
                                child: ClipRect(
                                  child: OverflowBox(
                                    alignment: Alignment.topCenter,
                                    minWidth: w,
                                    maxWidth: w,
                                    minHeight: h,
                                    maxHeight: h,
                                    child: img(asset),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ]),
                    );
              final Widget frontFace = tearable('assets/booster_front.webp');
              final Widget backFace = tearable('assets/booster_back.webp');
              // ── Paquet : recto ou verso selon la rotation (sans épaisseur) ──
              final base = Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateX(rotX)
                ..rotateY(rotY);
              Widget faceAt(Matrix4 local, Widget child) =>
                  Transform(alignment: Alignment.center, transform: base.clone()..multiply(local), child: child);
              final showBack = cos(rotY) < 0;
              final faces = <Widget>[
                if (showBack)
                  faceAt(Matrix4.rotationY(pi), backFace)
                else
                  faceAt(
                    Matrix4.identity(),
                    Container(
                      decoration: BoxDecoration(boxShadow: [
                        if (!torn) BoxShadow(color: glow.withOpacity(0.55), blurRadius: 30, spreadRadius: -4),
                      ]),
                      child: frontFace,
                    ),
                  ),
              ];
              return Transform.rotate(
                angle: wig + tear * 0.04,
                child: SizedBox(
                  width: w,
                  height: h,
                  child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: faces),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        // type de paquet
        AnimatedOpacity(
          opacity: torn ? 0 : 1,
          duration: const Duration(milliseconds: 250),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _packColor().withOpacity(0.9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kGold, width: 1.5),
            ),
            child: (widget.kind == 'console' || widget.kind == 'sconsole') && widget.sys != null
                ? ConsoleLogo(widget.sys!, height: 18)
                : Text(px(_packLabel().toUpperCase()), style: pixelStyle(size: 9, color: Colors.white, shadow: false)),
          ),
        ),
        const SizedBox(height: 14),
        // raccourci : déchire le paquet et montre toutes les cartes d'un coup (récapitulatif)
        IgnorePointer(
          ignoring: torn,
          child: AnimatedOpacity(
            opacity: torn ? 0 : 1,
            duration: const Duration(milliseconds: 250),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xCC2A1F5E),
                foregroundColor: const Color(0xFFFFD166),
                side: const BorderSide(color: Color(0x66FFD166)),
              ),
              onPressed: _skipToSummary,
              icon: const Icon(Icons.bolt),
              label: Text(t('Déchirer et tout voir', 'Tear and see all'), style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ),
      ]),
    );
  }

  /// Image du paquet, aux couleurs du booster [b] (null : couleurs d'origine)
  Widget _boosterImg(String a, double w, double h, int? b) {
    final Widget im = ColorFiltered(
      colorFilter: _kVivid,
      child: Image.asset(a, width: w, height: h, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
    );
    return b == null ? im : ColorFiltered(colorFilter: boosterFilter(b), child: im);
  }

  Widget _chooseStage() => Positioned.fill(
        child: BoosterRing(
          pack: (i, w, h) => _boosterImg('assets/booster_front.webp', w, h, i),
          label: (widget.kind == 'console' || widget.kind == 'sconsole') && widget.sys != null ? ConsoleLogo(widget.sys!, height: 14) : null,
          onChoose: _choose,
        ),
      );

  Color _packColor() => booster != null ? kBoosters[booster!].glow : switch (widget.kind) {
        'free' => const Color(0xFF0F6E56),
        'console' => const Color(0xFF185FA5),
        'star' => const Color(0xFF8A3DFF),
        'sconsole' => const Color(0xFF2F6BFF),
        'gold' => const Color(0xFFF0A419),
        'premium' => const Color(0xFF854F0B),
        'mystery' => const Color(0xFF8E2D8E),
        'gift' => const Color(0xFFD8453C),
        _ => const Color(0xFF3C3489),
      };

  String _packLabel() => switch (widget.kind) {
        'free' => t('Paquet gratuit', 'Free pack'),
        'console' => Catalog.system(widget.sys ?? '')?.name ?? '',
        'sconsole' => '${Catalog.system(widget.sys ?? '')?.name ?? ''}+',
        'star' => t('Étoile', 'Star'),
        'gold' => t('Rétro d\'or', 'Retro Gold'),
        'premium' => t('Premium', 'Premium'),
        'mystery' => t('Mystère', 'Mystery'),
        'gift' => t('Cadeau', 'Gift'),
        'lot' => t('Lot', 'Bundle'),
        _ => t('Paquet mixte', 'Mixed pack'),
      };

  Widget _revealStage() {
    const cw = 230.0;
    final remaining = pulled.length - idx;
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tap,
        onPanStart: (_) => dragDx = 0,
        onPanUpdate: (d) {
          if (busy) return;
          final c = _center;
          setState(() {
            dragDx = max(0.0, dragDx + d.delta.dx); // la carte suit le doigt vers la droite
            if (flipped) {
              fingerTilt = Offset(((d.localPosition.dx - c.dx) / 130).clamp(-1.0, 1.0), ((d.localPosition.dy - c.dy) / 170).clamp(-1.0, 1.0));
            }
          });
        },
        onPanEnd: (d) {
          final swipe = dragDx > 70 || d.velocity.pixelsPerSecond.dx > 500;
          setState(() {
            fingerTilt = null;
            if (!swipe || !flipped) dragDx = 0;
          });
          // glisser vers la droite : retourne la carte, puis passe à la suivante
          if (swipe) _tap();
        },
        child: Stack(alignment: Alignment.center, children: [
          // cartes restantes (dessous de la pile)
          for (var k = remaining - 1; k >= 1; k--)
            AnimatedBuilder(
              animation: dealCtl,
              builder: (_, child) {
                final d = Curves.easeOutBack.transform(((dealCtl.value * 1.4) - (pulled.length - 1 - (idx + k)) * 0.08).clamp(0.0, 1.0));
                return Transform.translate(
                  offset: Offset(k * 3.0, -k * 3.0 + (1 - d) * 260),
                  child: Opacity(opacity: d.clamp(0, 1).toDouble(), child: child),
                );
              },
              child: SizedBox(width: cw, child: faceUp ? CardView(card: pulled[idx + k].card, finish: pulled[idx + k].f) : const CardBack()),
            ),
          if (remaining > 0) _topCard(cw),
          Positioned(
            bottom: 6,
            child: Text('${idx + 1} / ${pulled.length}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ),
        ]),
      ),
    );
  }

  Widget _topCard(double cw) {
    final p = pulled[idx];
    return AnimatedBuilder(
      animation: Listenable.merge([dealCtl, flipCtl, liftCtl, shakeCtl, auraCtl, outCtl]),
      builder: (_, __) {
        final d = Curves.easeOutBack.transform(((dealCtl.value * 1.4) - (pulled.length - 1 - idx) * 0.08).clamp(0.0, 1.0));
        final angle = Curves.easeInOut.transform(flipCtl.value) * pi;
        final showFront = angle > pi / 2;
        // tremblement avant la révélation (plus fort si plus rare)
        var shake = Offset.zero;
        var rot = 0.0;
        if (!flipped && flipCtl.value == 0 && p.r >= 2) {
          final s = shakeCtl.value * 2 * pi;
          final amp = const [0.0, 0.0, 0.8, 2.0, 3.2][p.r];
          final speed = const [1, 1, 1, 2, 4][p.r];
          if (p.r == 2) {
            rot = shakeCtl.value > 0.8 ? sin(s * 5) * 0.03 : 0.0;
          } else {
            shake = Offset(sin(s * speed) * amp, cos(s * speed * 1.3) * amp * 0.5);
            rot = sin(s * speed) * 0.012 * amp;
          }
        }
        final lift = Curves.easeOut.transform(liftCtl.value);
        final o = Curves.easeIn.transform(outCtl.value);
        final dx = flipped ? dragDx : dragDx * 0.25;
        final m = Matrix4.identity()
          ..setEntry(3, 2, 0.0013)
          ..translate(shake.dx + dx + (340 - dx) * o, shake.dy - 12 * lift - 50 * o + (1 - d) * 260)
          ..rotateZ(rot + dx * 0.0016 + 0.45 * o)
          ..scale(1 + 0.12 * lift)
          ..rotateY(angle);
        Widget face = showFront
            ? CardView(card: p.card, finish: p.f, manualTilt: fingerTilt)
            : CardBack(aura: p.r >= 2 ? kRarityColor[p.r] : null, glow: auraCtl.value);
        // ouvert de face : le halo de rareté pulse autour de la carte, comme sur le dos
        if (showFront && faceUp && p.r >= 2) {
          final g = auraCtl.value, a = kRarityColor[p.r];
          face = DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(cw * 0.07),
              boxShadow: [BoxShadow(color: a.withOpacity(0.35 + 0.5 * g), blurRadius: cw * (0.08 + 0.14 * g), spreadRadius: cw * 0.015)],
            ),
            child: face,
          );
        }
        // Face visible : la carte a tourné de 180°, on la remet à l'endroit (carte + étiquette)
        Widget content = Stack(clipBehavior: Clip.none, children: [
                face,
                Positioned(
                  top: -14,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: AnimatedScale(
                      scale: tagOn ? 1 : 0,
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.elasticOut,
                      child: _tag(p),
                    ),
                  ),
                ),
              ]);
        if (showFront) {
          content = Transform(alignment: Alignment.center, transform: Matrix4.identity()..rotateY(pi), child: content);
        }
        return Opacity(
          opacity: (1 - o).clamp(0.0, 1.0) * d.clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: m,
            child: SizedBox(width: cw, child: content),
          ),
        );
      },
    );
  }

  Widget _tag(_Pulled p) {
    final isNew = p.isNew;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: isNew ? kGold : kPanel2, borderRadius: BorderRadius.circular(10)),
      child: Text(
        isNew ? t('Nouvelle !', 'New!') : t('Doublon', 'Duplicate'),
        style: TextStyle(color: isNew ? const Color(0xFF412402) : Colors.white70, fontWeight: FontWeight.w800, fontSize: 13),
      ),
    );
  }

  /// Paliers de collection gagnés avec ce paquet (25 / 50 / 75 / 100 % d'une console, 50 / 100 % d'une saga) :
  /// montrés dans le récapitulatif, sinon la pièce gagnée passait inaperçue derrière la page du paquet.
  List<Widget> _milestones() {
    final out = <Widget>[];
    for (final e in (res['events'] as List? ?? const [])) {
      if (e is! Map || e['type'] != 'milestone') continue;
      final coins = (e['coins'] as num? ?? 0).toInt();
      final step = (e['step'] as num? ?? 0).toInt();
      final saga = sagaOfSys(e['sys'] as String?);
      final name = saga?.name ?? Catalog.system(e['sys'] as String? ?? '')?.name ?? '${e['sys']}';
      final px = saga != null && step == 100 ? 2 : 0;
      out.add(Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0x332A1F5E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x99FFD166)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(step == 100 ? '🌈' : '🏅', style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              saga != null
                  ? t('Saga $name à $step % : +$coins pièces${px > 0 ? ' et +$px pixels' : ''}',
                      '$name saga at $step%: +$coins coins${px > 0 ? ' and +$px pixels' : ''}')
                  : t('Série $name à $step % : +$coins pièces', '$name set at $step%: +$coins coins'),
              style: const TextStyle(color: Color(0xFFFFD166), fontWeight: FontWeight.w900),
            ),
          ),
        ]),
      ));
    }
    return out;
  }

  Widget _summary() {
    final nw = pulled.where((p) => p.isNew).length;
    final dup = pulled.length - nw;
    final lotsLeft = (res['lots'] as num? ?? 0).toInt();
    final giftsLeft = (res['gifts'] as num? ?? 0).toInt();
    final again = widget.kind == 'lot' && lotsLeft > 0
        ? 'lot'
        : widget.kind == 'gift' && giftsLeft > 0
            ? 'gift'
            : (widget.kind == 'free' || widget.kind == 'gift' || widget.kind == 'lot' || kSpecialPrice.containsKey(widget.kind) ? 'mixte' : widget.kind);
    final price = kPackPrice[again]!;
    final againLabel = switch (again) {
      'lot' => t('Déchirer le suivant ($lotsLeft en stock)', 'Tear the next one ($lotsLeft in stock)'),
      'gift' => t('Cadeau suivant ($giftsLeft)', 'Next gift ($giftsLeft)'),
      _ => t('Ouvrir un autre ($price)', 'Open another ($price)'),
    };
    return Positioned.fill(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text(
            t('$nw nouvelle${nw > 1 ? 's' : ''} · $dup doublon${dup > 1 ? 's' : ''}', '$nw new · $dup duplicate${dup > 1 ? 's' : ''}'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 16, alignment: WrapAlignment.center, children: [
            for (final p in pulled)
              SizedBox(
                width: 100,
                child: Stack(clipBehavior: Clip.none, children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _BigCard(p.card, p.f))),
                    child: CardView(card: p.card, finish: p.f),
                  ),
                  Positioned(bottom: -9, left: 0, right: 0, child: Center(child: Transform.scale(scale: 0.8, child: _tag(p)))),
                ]),
              ),
          ]),
          if (missed != null) ...[const SizedBox(height: 22), _missedLine(missed!)],
          if (_milestones().isNotEmpty) ...[const SizedBox(height: 18), ..._milestones()],
          if (res['pixel_gain'] == 1) ...[
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const PixelIcon(size: 16),
              const SizedBox(width: 8),
              // événement « pixels ×2 » : le serveur multiplie le gain
              Text(
                  Events.i.pixelMult > 1
                      ? t('+${Events.i.pixelMult} pixels (événement ×${Events.i.pixelMult}) · ${Game.i.pixels} pixels',
                          '+${Events.i.pixelMult} pixels (event ×${Events.i.pixelMult}) · ${Game.i.pixels} pixels')
                      : t('+1 pixel · ${Game.i.pixels} pixels', '+1 pixel · ${Game.i.pixels} pixels'),
                  style: const TextStyle(color: Color(0xFFFFD166), fontWeight: FontWeight.w900)),
            ]),
          ],
          const SizedBox(height: 24),
          if (dup > 0)
            Text(t('Les doublons se recyclent (Collection → ♻) ou s\'échangent', 'Duplicates can be recycled (Collection → ♻) or traded'),
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: Game.i,
            builder: (_, __) => Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  HomeShellState.current?.goTo(0);
                },
                child: Text(t('Voir ma collection', 'View my collection')),
              ),
              if (again != 'console' || widget.sys != null)
                ElevatedButton(
                  onPressed: Game.i.coins >= price && !_againBusy ? () => _again(again) : null,
                  child: Text(againLabel),
                ),
            ]),
          ),
          if (again == 'lot' || again == 'gift') ...[
            const SizedBox(height: 8),
            Text(t('Si tu quittes, ${again == 'lot' ? lotsLeft : giftsLeft} restent dans ton stock 📦', 'If you leave, ${again == 'lot' ? lotsLeft : giftsLeft} stay in your stock 📦'),
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ]),
      ),
    );
  }

  /// « Tu as raté : … dans le booster rouge » (meilleure carte des 5 autres boosters)
  Widget _missedLine(Map m) {
    final card = Catalog.cards[m['c'] as String]!;
    final f = (m['f'] as num? ?? 0).toInt(), r = (m['r'] as num? ?? 0).toInt();
    final b = kBoosters[(m['b'] as num? ?? 0).toInt() % kBoosters.length];
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _BigCard(card, f))),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: b.glow.withOpacity(0.8)),
        ),
        child: Row(children: [
          SizedBox(width: 44, child: CardView(card: card, finish: f)),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: t('Tu as raté : ', 'You missed: '), style: const TextStyle(color: Colors.white60)),
                TextSpan(text: card.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                TextSpan(
                  text: ' (${rarityName(r).toLowerCase()}${f > 0 ? ', ${finishName(f).toLowerCase()}' : ''})',
                  style: TextStyle(color: kRarityLight[r], fontWeight: FontWeight.w700),
                ),
                TextSpan(text: t(' dans le booster ', ' in the '), style: const TextStyle(color: Colors.white60)),
                TextSpan(text: t(b.fr, '${b.en} booster'), style: TextStyle(color: b.glow, fontWeight: FontWeight.w800)),
              ]),
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
        ]),
      ),
    );
  }

  bool _againBusy = false; // évite le double appui sur « Cadeau suivant » / « Ouvrir un autre »

  Future<void> _again(String kind) async {
    if (_againBusy) return;
    setState(() => _againBusy = true);
    try {
      final sys = kind == 'console' ? widget.sys : null; // cadeau suivant : le plus ancien
      final r = await Game.i.openChoice(kind, sys);
      Notifs.i.refresh();
      if (!mounted) return;
      final k = (r['kind'] as String?) ?? kind;
      // pushReplacement termine la page d'origine (son await rend la main) : on compte la nouvelle page
      // comme une ouverture en cours, sinon l'onglet Paquets voit ce paquet pas encore choisi comme « entamé »
      _packFlows++;
      Navigator.of(context)
          .pushReplacement(PageRouteBuilder(
            pageBuilder: (_, __, ___) => PackOpeningPage(result: r, kind: k, sys: k == 'console' ? (r.containsKey('kind') ? r['sys'] as String? : sys) : null),
            transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
          ))
          .whenComplete(() {
        _packFlows--;
        Game.i.sync();
        if (_packFlows == 0) _packFlowsDone();
      });
    } catch (e) {
      toast(errText(e));
      if (mounted) setState(() => _againBusy = false);
    }
  }
}

class _BigCard extends StatelessWidget {
  final RcCard card;
  final int f;
  const _BigCard(this.card, this.f);
  @override
  Widget build(BuildContext context) => TiltScope(
        child: Scaffold(
          appBar: AppBar(title: Text(card.title)),
          body: Center(child: SizedBox(width: 280, child: CardView(card: card, finish: f, tilt3d: true))),
        ),
      );
}

class _ParticlesPainter extends CustomPainter {
  final List<_Particle> ps;
  _ParticlesPainter(this.ps);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in ps) {
      paint.color = p.color.withOpacity((p.life / 30).clamp(0.0, 1.0));
      canvas.drawRect(Rect.fromLTWH(p.p.dx, p.p.dy, p.size, p.size), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _RaysPainter extends CustomPainter {
  final Color color;
  _RaysPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = max(size.width, size.height) * 0.75;
    final paint = Paint()
      ..shader = RadialGradient(colors: [color.withOpacity(0.9), color.withOpacity(0)], stops: const [0.15, 1])
          .createShader(Rect.fromCircle(center: c, radius: r));
    const n = 20;
    for (var i = 0; i < n; i++) {
      final a0 = i * 2 * pi / n;
      final a1 = a0 + pi / n * 0.75;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + cos(a0) * r, c.dy + sin(a0) * r)
        ..lineTo(c.dx + cos(a1) * r, c.dy + sin(a1) * r)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RaysPainter old) => old.color != color;
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFCECBF6)
      ..strokeWidth = 2;
    for (double x = 8; x < size.width - 8; x += 10) {
      canvas.drawLine(Offset(x, size.height - 2), Offset(x + 5, size.height - 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


// ═══════════════════════════════════════════════════════════════════════════
// Booster : sachet métallisé avec l'illustration du dos des cartes, soudures
// crantées en haut et en bas, reflet qui glisse, étiquette du paquet.
// ═══════════════════════════════════════════════════════════════════════════

// Taille du paquet (images assets/booster_front.webp et booster_back.webp, 440 × 856)
const double _kPackW = 200, _kPackH = 389, _kCapFrac = 0.075;

/// Couleurs avivées pour les images du paquet (saturation +35 %, contraste +15 %)
const _kVivid = ColorFilter.matrix([
  1.467, -0.288, -0.029, 0, -11.2,
  -0.086, 1.265, -0.029, 0, -11.2,
  -0.086, -0.288, 1.523, 0, -11.2,
  0, 0, 0, 1, 0,
]);

/// Mini booster pour la liste des offres : le même paquet qu'à l'ouverture, en réduit,
/// avec un bandeau de la couleur du type de paquet.
class _MiniBooster extends StatelessWidget {
  final String kind, label;
  final Color color;
  final double width;
  const _MiniBooster({required this.kind, required this.label, required this.color, this.width = 50});

  @override
  Widget build(BuildContext context) {
    final h = width * _kPackH / _kPackW;
    return SizedBox(
      width: width,
      height: h,
      child: Transform.rotate(
        angle: -0.06,
        child: Container(
          decoration: BoxDecoration(boxShadow: [
            BoxShadow(color: color.withOpacity(0.7), blurRadius: 12, spreadRadius: -2),
            const BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3)),
          ]),
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              child: ColorFiltered(
                colorFilter: _kVivid,
                child: Image.asset(
                'assets/booster_front.webp',
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
                cacheWidth: (width * MediaQuery.of(context).devicePixelRatio).round().clamp(48, 440),
              ),
              ),
            ),
            // bandeau du type de paquet
            Positioned(
              left: -width * 0.04,
              right: -width * 0.04,
              bottom: h * 0.2,
              child: Container(
                padding: EdgeInsets.symmetric(vertical: width * 0.025),
                decoration: BoxDecoration(
                  color: color,
                  border: Border.symmetric(horizontal: BorderSide(color: kGold, width: max(1.0, width * 0.02))),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 3)],
                ),
                child: Text(
                  label.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(color: Colors.white, fontSize: max(6.0, width * 0.115), fontWeight: FontWeight.w900, letterSpacing: 0.3),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Lot : trois boosters en éventail et « ×5 »
class _LotArt extends StatelessWidget {
  final double width;
  const _LotArt({this.width = 74});
  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF534AB7);
    final w = width * 0.62;
    return SizedBox(
      width: width,
      height: w * _kPackH / _kPackW + width * 0.12,
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
        Transform.translate(offset: Offset(-width * 0.2, 0), child: Transform.rotate(angle: -0.22, child: _MiniBooster(kind: 'mixte', label: t('Lot', 'Bundle'), color: color, width: w))),
        Transform.translate(offset: Offset(width * 0.2, 0), child: Transform.rotate(angle: 0.22, child: _MiniBooster(kind: 'mixte', label: t('Lot', 'Bundle'), color: color, width: w))),
        _MiniBooster(kind: 'mixte', label: t('Lot', 'Bundle'), color: color, width: w),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF2A1800), width: 1.5)),
            child: Text('×5', style: TextStyle(color: const Color(0xFF2A1800), fontWeight: FontWeight.w900, fontSize: width * 0.15)),
          ),
        ),
      ]),
    );
  }
}

/// Cadeaux reçus : la liste des donateurs, chacun avec son paquet à ouvrir
class GiftsPage extends StatefulWidget {
  const GiftsPage({super.key});
  @override
  State<GiftsPage> createState() => _GiftsPageState();
}

class _GiftsPageState extends State<GiftsPage> {
  List<Map<String, dynamic>>? rows;
  String? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await RcServer.giftsList();
      if (mounted) {
        setState(() {
          rows = r;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = errText(e));
    }
  }

  Future<void> _open(int id) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await openPackFlow(context, 'gift', '$id');
    } catch (e) {
      toast(errText(e));
    }
    await load();
    if (mounted) {
      setState(() => busy = false);
      // Plus de cadeau : on ferme cette liste. Si « Cadeau suivant » a ouvert un autre paquet
      // par-dessus, on retire la liste en dessous sans toucher à l'ouverture en cours.
      if (rows != null && rows!.isEmpty) {
        final route = ModalRoute.of(context);
        if (route == null || route.isCurrent) {
          Navigator.pop(context);
        } else {
          Navigator.of(context).removeRoute(route);
        }
      }
    }
  }

  String _when(String? s) {
    final d = DateTime.tryParse(s ?? '')?.toLocal();
    if (d == null) return '';
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (days == 0) return t('aujourd\'hui à $hm', 'today at $hm');
    if (days == 1) return t('hier à $hm', 'yesterday at $hm');
    return t('le ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}', 'on ${d.month}/${d.day}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Cadeaux reçus', 'Gifts received'))),
      body: error != null
          ? Center(child: TextButton(onPressed: load, child: Text('$error\n${t('Réessayer', 'Retry')}', textAlign: TextAlign.center)))
          : rows == null
              ? const Center(child: CircularProgressIndicator(color: kGold))
              : rows!.isEmpty
                  ? Center(child: Text(t('Aucun cadeau à ouvrir', 'No gifts to open'), style: const TextStyle(color: Colors.white54)))
                  : ListView(padding: const EdgeInsets.all(14), children: [
                      Text(t('${rows!.length} paquet(s) de 5 cartes offert(s) par tes voisins', '${rows!.length} 5-card pack(s) from your neighbors'),
                          style: const TextStyle(color: Colors.white60)),
                      const SizedBox(height: 10),
                      for (final g in rows!)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                          decoration: BoxDecoration(
                            color: kPanel,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFD8453C).withOpacity(0.7)),
                          ),
                          child: Row(children: [
                            const _MiniBooster(kind: 'gift', label: 'Cadeau', color: Color(0xFFD8453C), width: 40),
                            const SizedBox(width: 12),
                            avatarWidget((g['avatar'] as num? ?? 0).toInt(), size: 30),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(t('De ${g['name']}', 'From ${g['name']}'), style: const TextStyle(fontWeight: FontWeight.w800)),
                                Text(_when(g['at'] as String?), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                              ]),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
                              onPressed: busy ? null : () => _open((g['id'] as num).toInt()),
                              child: Text(t('Ouvrir', 'Open'), style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                          ]),
                        ),
                    ]),
    );
  }
}


/// Compte à rebours du prochain paquet gratuit (toutes les 6 h), mis à jour chaque seconde.
class _FreeCountdown extends StatefulWidget {
  const _FreeCountdown();
  @override
  State<_FreeCountdown> createState() => _FreeCountdownState();
}

class _FreeCountdownState extends State<_FreeCountdown> {
  Timer? _tm;
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    _tm = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // l'heure est passée : on redemande au serveur (une fois)
      if (!_asked && !DateTime.now().isBefore(_target())) {
        _asked = true;
        Game.i.sync();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tm?.cancel();
    super.dispose();
  }

  DateTime _target() {
    final now = DateTime.now();
    return Game.i.freeAt ?? DateTime(now.year, now.month, now.day + 1); // ancien serveur : minuit
  }

  @override
  Widget build(BuildContext context) {
    final left = _target().difference(DateTime.now());
    if (left.isNegative) {
      return Text(t('Bientôt disponible…', 'Almost ready…'), style: const TextStyle(color: Color(0xFF5DCAA5), fontSize: 12, fontWeight: FontWeight.w700));
    }
    String two(int n) => n.toString().padLeft(2, '0');
    final h = left.inHours, m = left.inMinutes % 60, sec = left.inSeconds % 60;
    return Row(children: [
      const Icon(Icons.timer_outlined, size: 14, color: kGold),
      const SizedBox(width: 4),
      Text(t('Prochain dans ', 'Next one in '), style: const TextStyle(color: Colors.white60, fontSize: 12)),
      Text('$h:${two(m)}:${two(sec)}',
          style: const TextStyle(color: kGold, fontSize: 13, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
    ]);
  }
}



// ─── Vue en mosaïque ───────────────────────────────────────────────────────
/// Titre de rubrique en pixels, suivi d'un filet
class _Section extends StatelessWidget {
  final String label;
  const _Section(this.label, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
        child: Row(children: [
          Text(label, style: pixelStyle(size: 9, color: const Color(0xFFFFD166), shadow: false)),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: const Color(0x40FFD166))),
        ]),
      );
}

/// Pastille du nombre (paquets en stock)
Widget _countBadge(int n) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(color: const Color(0xFFD8453C), borderRadius: BorderRadius.circular(10), border: Border.all(color: kBg, width: 2)),
      child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
    );

/// Prix en pièces : rouge si on n'a pas assez
class _PriceChip extends StatelessWidget {
  final int price;
  final bool ok;
  final int? base; // prix avant promo (barré)
  const _PriceChip(this.price, {required this.ok, this.base});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: ok ? const Color(0xFF412402) : const Color(0xFF3A1616),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ok ? const Color(0xFF6B4A10) : const Color(0xFF5A2A2A)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.monetization_on, color: ok ? const Color(0xFFFAC775) : const Color(0xFFFF8A80), size: 15),
          const SizedBox(width: 4),
          if (base != null && base! > price) ...[
            Text(fmt(base!), style: const TextStyle(color: Colors.white54, fontSize: 11.5, decoration: TextDecoration.lineThrough)),
            const SizedBox(width: 4),
          ],
          Text(fmt(price), style: TextStyle(color: ok ? const Color(0xFFFAC775) : const Color(0xFFFF8A80), fontWeight: FontWeight.w800)),
        ]),
      );
}

/// Paquet en stock (bandeau horizontal) : booster, titre, pastille du nombre
class _StockTile extends StatelessWidget {
  final String kind, label, title;
  final Color color;
  final int count;
  final bool enabled;
  final VoidCallback onTap;
  const _StockTile({required this.kind, required this.label, required this.title, required this.color, required this.count, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 10, top: 8),
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: GestureDetector(
            onTap: enabled ? onTap : null,
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 100,
                padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kGold, width: 2),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color.lerp(color, Colors.black, 0.45)!, Color.lerp(color, Colors.black, 0.8)!],
                  ),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _MiniBooster(kind: kind, label: label, color: color, width: 40),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 28,
                    child: Center(
                      child: Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, height: 1.15)),
                    ),
                  ),
                ]),
              ),
              Positioned(top: -7, right: -5, child: _countBadge(count)),
            ]),
          ),
        ),
      );
}

/// Paquet gratuit en grand : bouton « Ouvrir » ou compte à rebours
class _FreeHero extends StatelessWidget {
  final bool free, enabled;
  final VoidCallback onTap;
  const _FreeHero({required this.free, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF1D9E75);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: free ? kGold : green.withOpacity(0.7), width: free ? 2 : 1.5),
          gradient: const RadialGradient(center: Alignment(-0.7, 0), radius: 1.3, colors: [Color(0xFF1C6A54), Color(0xFF0E3A34), Color(0xFF0B2A30)]),
          boxShadow: [if (free) BoxShadow(color: green.withOpacity(0.45), blurRadius: 16)],
        ),
        child: Row(children: [
          const SizedBox(width: 4),
          _MiniBooster(kind: 'free', label: t('Gratuit', 'Free'), color: green, width: 64),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('TOUTES LES 6 H', 'EVERY 6 H'), style: pixelStyle(size: 7.5, color: const Color(0xFF9FE0C4), shadow: false)),
              const SizedBox(height: 6),
              Text(t('Paquet gratuit', 'Free pack'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(t('5 cartes offertes, toutes consoles', '5 free cards, all systems'), style: const TextStyle(fontSize: 12, color: Color(0xFFCFE9DF))),
              const SizedBox(height: 10),
              if (free)
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800), visualDensity: VisualDensity.compact),
                  onPressed: enabled ? onTap : null,
                  child: Text(t('Ouvrir', 'Open'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                )
              else
                const _FreeCountdown(),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Tuile de la boutique : gros booster sur un halo de sa couleur, nom, description, prix
class _ShopTile extends StatelessWidget {
  final String kind, label, title, subtitle;
  final int price;
  final Color color;
  final bool afford, enabled;
  final VoidCallback onTap;
  const _ShopTile({
    required this.kind,
    required this.label,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.color,
    required this.afford,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: afford ? 1 : 0.6,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? onTap : null,
            child: Ink(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withOpacity(0.9), width: 1.5),
                gradient: RadialGradient(
                  center: const Alignment(0, -0.35),
                  radius: 0.95,
                  colors: [color.withOpacity(0.6), Color.lerp(color, kBg, 0.8)!],
                ),
              ),
              child: Column(children: [
                if ((kPackPromo[kind] ?? 0) > 0)
                  Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: const Color(0xFFE24B4A), borderRadius: BorderRadius.circular(6)),
                      child: Text('-${kPackPromo[kind]} %', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Colors.white)),
                    ),
                  ),
                _MiniBooster(kind: kind, label: label, color: color, width: (kPackPromo[kind] ?? 0) > 0 ? 50 : 58),
                const SizedBox(height: 8),
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
                const SizedBox(height: 2),
                Expanded(
                  child: Text(subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFC5C9E6), fontSize: 11, height: 1.25)),
                ),
                _PriceChip(price, ok: afford, base: (kPackPromo[kind] ?? 0) > 0 ? kPackBase[kind] : null),
              ]),
            ),
          ),
        ),
      );
}

/// Lot de 5 paquets : tuile pleine largeur, gratuit le samedi
class _LotTile extends StatelessWidget {
  final bool free, afford, enabled;
  final VoidCallback onTap;
  const _LotTile({required this.free, required this.afford, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF534AB7);
    return Opacity(
      opacity: free || afford ? 1 : 0.6,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Ink(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: free ? kGold : color.withOpacity(0.9), width: free ? 2 : 1.5),
              gradient: RadialGradient(center: const Alignment(-0.7, 0), radius: 1.4, colors: [color.withOpacity(0.6), Color.lerp(color, kBg, 0.8)!]),
            ),
            child: Row(children: [
              const _LotArt(width: 86),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('Lot de 5 paquets mixtes', '5 mixed packs bundle'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(
                    free ? t('🎉 GRATUIT aujourd\'hui ! 25 cartes', '🎉 FREE today! 25 cards') : t('25 cartes · gratuit chaque samedi', '25 cards · free every Saturday'),
                    style: TextStyle(color: free ? const Color(0xFF9FE0C4) : const Color(0xFFC5C9E6), fontSize: 12, fontWeight: free ? FontWeight.w800 : FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  free
                      ? Text(t('GRATUIT', 'FREE'), style: const TextStyle(color: Color(0xFF5DCAA5), fontWeight: FontWeight.w900))
                      : _PriceChip(lotPrice, ok: afford, base: (kPackPromo['lot'] ?? 0) > 0 ? kLotPrice : null),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── Pixels : 1 par booster ouvert, échangeables contre des boosters spéciaux ─
/// Petit pixel doré (icône de la monnaie des boosters spéciaux)
class PixelIcon extends StatelessWidget {
  final double size;
  const PixelIcon({super.key, this.size = 18});
  @override
  Widget build(BuildContext context) {
    final c = size / 2;
    Widget px(Color col) => Container(width: c, height: c, color: col);
    return Container(
      decoration: BoxDecoration(boxShadow: [BoxShadow(color: const Color(0xFFFFD166).withOpacity(0.5), blurRadius: size * 0.5)]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [px(const Color(0xFFFFF3C4)), px(const Color(0xFFFFD166))]),
        Row(mainAxisSize: MainAxisSize.min, children: [px(const Color(0xFFFFD166)), px(const Color(0xFFEF9F27))]),
      ]),
    );
  }
}

class PixelChip extends StatelessWidget {
  final int n;
  const PixelChip(this.n, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const PixelIcon(size: 13),
          const SizedBox(width: 6),
          Text('$n', style: const TextStyle(color: Color(0xFFFFD166), fontWeight: FontWeight.w900)),
        ]),
      );
}

/// Jauge des pixels (en haut de la boutique), repères aux prix des boosters spéciaux
class _PixelsGauge extends StatelessWidget {
  final int pixels;
  final List<Widget> offers; // boosters spéciaux, sous la jauge
  const _PixelsGauge(this.pixels, {this.offers = const []});

  @override
  Widget build(BuildContext context) {
    final top = kSpecialPrice.values.reduce(max);
    final next = (kSpecialPrice.entries.toList()..sort((a, b) => a.value.compareTo(b.value))).where((e) => e.value > pixels).firstOrNull;
    final nextName = switch (next?.key) {
      'star' => t('Booster Étoile', 'Star booster'),
      'sconsole' => t('Booster Console+', 'Console+ booster'),
      _ => t('Booster Rétro d\'or', 'Retro Gold booster'),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF2A1F6B), Color(0xFF1B2358)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kGold, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (offers.isNotEmpty)
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        Row(children: [
          const PixelIcon(size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('Pixels', 'Pixels'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              Text(t('+1 à chaque booster ouvert', '+1 for every booster opened'), style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ]),
          ),
          Text('$pixels', style: pixelStyle(size: 16, color: const Color(0xFFFFD166))),
        ]),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth;
          return SizedBox(
            height: 30,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: 0,
                right: 0,
                top: 4,
                height: 10,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(value: (pixels / top).clamp(0.0, 1.0), color: const Color(0xFFFFD166), backgroundColor: Colors.white10),
                ),
              ),
              for (final p in kSpecialPrice.values) ...[
                Positioned(left: w * p / top - 1.5, top: 0, width: 3, height: 18, child: Container(color: Colors.white70)),
                Positioned(
                  left: w * p / top - 20,
                  width: 40,
                  top: 18,
                  child: Text('$p', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
              ],
            ]),
          );
        }),
        const SizedBox(height: 4),
        Text(
          next == null
              ? t('Tous les boosters spéciaux sont disponibles !', 'All special boosters are available!')
              : t('Plus que ${next.value - pixels} booster${next.value - pixels > 1 ? 's' : ''} pour le $nextName',
                  '${next.value - pixels} more booster${next.value - pixels > 1 ? 's' : ''} for the $nextName'),
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        if (offers.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...offers,
        ],
      ]),
    );
  }
}


/// Ligne compacte « Boosters Pixels » de la boutique (ouvre le sous-menu)
class _PixelsRow extends StatelessWidget {
  final int pixels;
  final VoidCallback onTap;
  const _PixelsRow(this.pixels, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final top = kSpecialPrice.values.reduce(max);
    final ready = kSpecialPrice.values.where((p) => p <= pixels).length;
    final next = kSpecialPrice.values.where((p) => p > pixels).fold<int>(top, min);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF2A1F6B), Color(0xFF1B2358)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kGold, width: 1.5),
          ),
          child: Row(children: [
            const PixelIcon(size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(t('Boosters Pixels', 'Pixel boosters'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  const SizedBox(width: 8),
                  Text('$pixels', style: pixelStyle(size: 10, color: const Color(0xFFFFD166), shadow: false)),
                ]),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: (pixels / top).clamp(0.0, 1.0), minHeight: 6, color: const Color(0xFFFFD166), backgroundColor: Colors.white10),
                ),
                const SizedBox(height: 4),
                Text(
                  ready > 0
                      ? t('$ready booster${ready > 1 ? 's' : ''} spécial disponible !', '$ready special booster${ready > 1 ? 's' : ''} available!')
                      : t('Plus que ${next - pixels} booster${next - pixels > 1 ? 's' : ''} pour le prochain', '${next - pixels} more booster${next - pixels > 1 ? 's' : ''} for the next one'),
                  style: TextStyle(color: ready > 0 ? const Color(0xFFFFD166) : Colors.white60, fontSize: 11.5, fontWeight: ready > 0 ? FontWeight.w800 : FontWeight.w500),
                ),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFFFD166), size: 28),
          ]),
        ),
      ),
    );
  }
}
