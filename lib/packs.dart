import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'audio.dart';
import 'cards.dart';
import 'catalog.dart';
import 'game.dart';
import 'main.dart';
import 'retro_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Boutique de paquets + ouverture animée (déchirer, révéler, effets par rareté)
// ═══════════════════════════════════════════════════════════════════════════

class PacksScreen extends StatefulWidget {
  const PacksScreen({super.key});
  @override
  State<PacksScreen> createState() => _PacksScreenState();
}

class _PacksScreenState extends State<PacksScreen> {
  bool busy = false;

  Future<void> _open(String kind, [String? sys]) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final r = await Game.i.openPack(kind, sys);
      if (!mounted) return;
      await Navigator.of(context).push(PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, __, ___) => PackOpeningPage(result: r, kind: kind, sys: sys),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ));
      Game.i.sync();
    } catch (e) {
      toast(errText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _pickConsole() async {
    final sys = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: kPanel,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(t('Paquet console : choisis la série', 'Console pack: choose the set'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          for (final s in Catalog.systems)
            ListTile(
              title: Align(alignment: Alignment.centerLeft, child: ConsoleLogo(s.id, height: 26)),
              subtitle: LinearProgressIndicator(value: Game.i.ownedIn(s.id) / max(1, s.count), color: kGold, backgroundColor: kPanel2),
              trailing: Text('${Game.i.ownedIn(s.id)}/${s.count}'),
              onTap: () => Navigator.pop(ctx, s.id),
            ),
        ]),
      ),
    );
    if (sys != null) _open('console', sys);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Game.i,
      builder: (context, _) {
        final g = Game.i;
        final now = DateTime.now();
        final midnight = DateTime(now.year, now.month, now.day + 1);
        final left = midnight.difference(now);
        return Column(children: [
          TabHeader(t('Paquets', 'Packs')),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              _PackOffer(
                title: t('Paquet du jour', 'Daily pack'),
                subtitle: g.free
                    ? t('5 cartes offertes, toutes consoles', '5 free cards, all systems')
                    : t('Prochain dans ${left.inHours} h ${left.inMinutes % 60} min', 'Next one in ${left.inHours} h ${left.inMinutes % 60} min'),
                price: 0,
                color: const Color(0xFF1D9E75),
                highlight: g.free,
                enabled: g.free && !busy,
                onTap: () => _open('free'),
              ),
              _PackOffer(
                title: t('Paquet mixte', 'Mixed pack'),
                subtitle: t('5 cartes, toutes consoles', '5 cards, all systems'),
                price: kPackPrice['mixte']!,
                color: const Color(0xFF534AB7),
                enabled: !busy && g.coins >= kPackPrice['mixte']!,
                onTap: () => _open('mixte'),
              ),
              _PackOffer(
                title: t('Paquet console', 'Console pack'),
                subtitle: t('5 cartes de la console de ton choix', '5 cards from the system of your choice'),
                price: kPackPrice['console']!,
                color: const Color(0xFF185FA5),
                enabled: !busy && g.coins >= kPackPrice['console']!,
                onTap: _pickConsole,
              ),
              _PackOffer(
                title: t('Paquet premium', 'Premium pack'),
                subtitle: t('5 cartes dont une rare ou mieux garantie', '5 cards, one rare or better guaranteed'),
                price: kPackPrice['premium']!,
                color: const Color(0xFF854F0B),
                enabled: !busy && g.coins >= kPackPrice['premium']!,
                onTap: () => _open('premium'),
              ),
              const SizedBox(height: 6),
              Text(
                t('Épique ou mieux garantie dans ${max(1, 30 - g.pity)} paquet(s) au plus',
                    'Epic or better guaranteed within ${max(1, 30 - g.pity)} pack(s)'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFCECBF6), fontSize: 12),
              ),
              const SizedBox(height: 18),
              _Missions(g),
              const SizedBox(height: 18),
              Text(t('Chances par carte', 'Odds per card'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (r, p) in const [(0, '60 %'), (1, '26 %'), (2, '10 %'), (3, '3,2 %'), (4, '0,8 %')])
                  Chip(
                    backgroundColor: kRarityDark[r],
                    side: BorderSide(color: kRarityColor[r]),
                    label: Text('${rarityName(r)} $p', style: TextStyle(color: kRarityLight[r], fontSize: 12)),
                  ),
              ]),
              const SizedBox(height: 6),
              Text(t('Finition brillante : 5 % · dorée : 0,5 %', 'Holo finish: 5% · gold: 0.5%'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          ),
        ]);
      },
    );
  }
}

class _PackOffer extends StatelessWidget {
  final String title, subtitle;
  final int price;
  final Color color;
  final bool enabled, highlight;
  final VoidCallback onTap;
  const _PackOffer({required this.title, required this.subtitle, required this.price, required this.color, required this.enabled, required this.onTap, this.highlight = false});

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
              Container(
                width: 46,
                height: 64,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white24, width: 2)),
                child: const Center(child: Text('RC', style: TextStyle(color: Color(0xFFFAC775), fontWeight: FontWeight.w900))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                ]),
              ),
              Opacity(
                opacity: enabled ? 1 : 0.4,
                child: price == 0 ? Text(t('GRATUIT', 'FREE'), style: const TextStyle(color: Color(0xFF5DCAA5), fontWeight: FontWeight.w900)) : CoinChip(price),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Missions extends StatelessWidget {
  final Game g;
  const _Missions(this.g);
  @override
  Widget build(BuildContext context) {
    final m = g.missions;
    final done = (m['done'] as num? ?? 0).toInt();
    Widget row(String label, int cur, int goal, int bit, int reward) {
      final ok = done & bit != 0;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, color: ok ? const Color(0xFF5DCAA5) : Colors.white38, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(color: ok ? Colors.white54 : Colors.white))),
          Text('${min(cur, goal)}/$goal', style: const TextStyle(color: Colors.white54)),
          const SizedBox(width: 10),
          Text('+$reward', style: const TextStyle(color: Color(0xFFFAC775), fontWeight: FontWeight.w700)),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t('Missions du jour', 'Daily missions'), style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        row(t('Ouvrir 2 paquets', 'Open 2 packs'), (m['open'] as num? ?? 0).toInt(), 2, 1, 30),
        row(t('Recycler 5 doublons', 'Recycle 5 duplicates'), (m['recycle'] as num? ?? 0).toInt(), 5, 2, 30),
        row(t('1 échange, achat ou vente', '1 trade, purchase or sale'), (m['trade'] as num? ?? 0).toInt(), 1, 4, 50),
        const SizedBox(height: 4),
        Text(t('Connexion : 50 pièces par jour, 200 tous les 7 jours d\'affilée (série : ${g.streak})',
                'Login: 50 coins a day, 200 every 7 days in a row (streak: ${g.streak})'),
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
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

enum _Phase { pack, reveal, summary }

class _PackOpeningPageState extends State<PackOpeningPage> with TickerProviderStateMixin {
  late List<_Pulled> pulled;
  _Phase phase = _Phase.pack;

  // déchirure
  double tear = 0;
  double? dragStart;
  bool torn = false;
  int _lastTick = 0;
  late final AnimationController tearCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
  late final AnimationController sheenCtl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  late final AnimationController wiggleCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));

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
    final list = <_Pulled>[];
    for (final c in (widget.result['cards'] as List? ?? const [])) {
      final card = Catalog.cards[c['c'] as String];
      if (card == null) continue;
      list.add(_Pulled(card, (c['f'] as num).toInt(), (c['r'] as num).toInt(), c['n'] == true));
    }
    // du plus commun au plus rare : le meilleur pour la fin
    list.sort((a, b) => (a.r * 3 + a.f).compareTo(b.r * 3 + b.f));
    pulled = list;
    _ticker = createTicker(_tick)..start();
    RcAudio.sfx('logo');
  }

  @override
  void dispose() {
    _ticker.dispose();
    for (final c in [tearCtl, sheenCtl, wiggleCtl, dealCtl, flipCtl, liftCtl, shakeCtl, auraCtl, outCtl, raysCtl, flashCtl]) {
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

  // ── Phase 1 : déchirer ────────────────────────────────────────────────
  void _dragStart(DragStartDetails d) {
    if (torn) return;
    dragStart = d.localPosition.dx;
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (torn || dragStart == null) return;
    final p = ((d.localPosition.dx - dragStart!) / 170).clamp(0.0, 1.0);
    setState(() => tear = p);
    final tick = (p * 10).floor();
    if (tick > _lastTick) {
      _lastTick = tick;
      HapticFeedback.selectionClick();
    }
    if (rnd.nextBool()) {
      final c = _center;
      _burst(Offset(c.dx - _kPackW / 2 + _kPackW * p, c.dy - _kPackH / 2 + _kCapH), 2, const [Color(0xFFFAC775), Colors.white], 1.5, gravity: 0.15);
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
    _burst(Offset(c.dx, c.dy - _kPackH / 2 + _kCapH / 2), 45, const [Color(0xFFFAC775), Colors.white, Color(0xFFAFA9EC)], 4, gravity: 0.18);
    flashCtl.forward(from: 0.6);
    RcAudio.sfx('break');
    HapticFeedback.mediumImpact();
    tearCtl.forward(from: 0);
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
  }

  Future<void> _tap() async {
    if (phase != _Phase.reveal || busy || dealCtl.isAnimating) return;
    if (!flipped) {
      await _reveal();
    } else {
      await _next();
    }
  }

  Future<void> _reveal() async {
    busy = true;
    final p = pulled[idx];
    if (p.r >= 3) setState(() => dim = p.r == 4 ? 0.82 : 0.55);
    if (p.r == 4) {
      RcAudio.sfx('alarm');
      HapticFeedback.heavyImpact();
      await liftCtl.forward(from: 0);
    }
    final ms = const [420, 480, 620, 950, 1500][p.r];
    flipCtl.duration = Duration(milliseconds: ms);
    RcAudio.sfx('jump');
    await flipCtl.forward(from: 0);
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
    flipCtl.value = 0;
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

  // ── Construction ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return TiltScope(
      child: Scaffold(
        backgroundColor: const Color(0xB3060A1E), // fond animé assombri pendant l'ouverture
        body: SafeArea(
          child: Column(children: [
            Row(children: [
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              Expanded(
                child: Text(
                  switch (widget.kind) {
                    'free' => t('Paquet du jour', 'Daily pack'),
                    'console' => t('Paquet ${Catalog.system(widget.sys ?? '')?.name ?? ''}', '${Catalog.system(widget.sys ?? '')?.name ?? ''} pack'),
                    'premium' => t('Paquet premium', 'Premium pack'),
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
    );
  }

  String _hint() {
    switch (phase) {
      case _Phase.pack:
        return t('Glisse ton doigt le long du pointillé pour déchirer le paquet', 'Swipe along the dotted line to tear the pack open');
      case _Phase.reveal:
        if (pulled.isEmpty) return '';
        if (flipped) return t('Bouge le doigt sur la carte pour la faire briller · touche ou glisse à droite pour continuer', 'Move your finger over the card to make it shine · tap or swipe right to continue');
        return pulled[idx].r >= 3 ? t('Quelque chose brille dans ce paquet…', 'Something is shining in this pack…') : t('Touche ou glisse à droite pour retourner la carte', 'Tap or swipe right to flip the card');
      case _Phase.summary:
        return '';
    }
  }

  Widget _packStage() {
    const w = _kPackW, h = _kPackH, capH = _kCapH;
    return Center(
      child: GestureDetector(
        onHorizontalDragStart: _dragStart,
        onHorizontalDragUpdate: _dragUpdate,
        onHorizontalDragEnd: _dragEnd,
        onTap: () => wiggleCtl.forward(from: 0),
        child: AnimatedBuilder(
          animation: Listenable.merge([tearCtl, sheenCtl, wiggleCtl]),
          builder: (_, __) {
            final tt = Curves.easeOut.transform(tearCtl.value);
            final wig = sin(wiggleCtl.value * pi * 4) * 0.08 * (1 - wiggleCtl.value);
            final sheen = sheenCtl.value;
            final glow = _packColor();
            return Transform.rotate(
              angle: wig + tear * 0.04,
              child: SizedBox(
                width: w,
                height: h,
                child: Stack(clipBehavior: Clip.none, children: [
                  // corps du booster (tombe après la déchirure)
                  Positioned(
                    top: capH,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Transform.translate(
                      offset: Offset(0, 420 * Curves.easeIn.transform((tearCtl.value - 0.25).clamp(0, 1) / 0.75)),
                      child: Opacity(
                        opacity: (1 - ((tearCtl.value - 0.45).clamp(0, 1) / 0.55)).toDouble(),
                        child: Container(
                          decoration: BoxDecoration(boxShadow: [
                            BoxShadow(color: glow.withOpacity(0.55), blurRadius: 26, spreadRadius: 1),
                            const BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 8)),
                          ]),
                          child: ClipPath(
                            clipper: const _CrimpClipper(top: false),
                            child: _BoosterBody(kind: widget.kind, sys: widget.sys, label: _packLabel(), sheen: sheen, color: glow),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // ligne de déchirure (pointillés + progression)
                  if (!torn)
                    Positioned(
                      top: capH - 2,
                      left: 6,
                      right: 6,
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
                  // soudure du haut (s'arrache et s'envole)
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
                          child: ClipPath(
                            clipper: const _CrimpClipper(top: true),
                            child: CustomPaint(painter: _CrimpPainter(sheen: sheen, top: true), child: const SizedBox.expand()),
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }

  Color _packColor() => switch (widget.kind) {
        'free' => const Color(0xFF0F6E56),
        'console' => const Color(0xFF185FA5),
        'premium' => const Color(0xFF854F0B),
        _ => const Color(0xFF3C3489),
      };

  String _packLabel() => switch (widget.kind) {
        'free' => t('Paquet du jour', 'Daily pack'),
        'console' => Catalog.system(widget.sys ?? '')?.name ?? '',
        'premium' => t('Premium', 'Premium'),
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
              child: const SizedBox(width: cw, child: CardBack()),
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
        final Widget face = showFront
            ? CardView(card: p.card, finish: p.f, manualTilt: fingerTilt)
            : CardBack(aura: p.r >= 2 ? kRarityColor[p.r] : null, glow: auraCtl.value);
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

  Widget _summary() {
    final nw = pulled.where((p) => p.isNew).length;
    final dup = pulled.length - nw;
    final again = widget.kind == 'free' ? 'mixte' : widget.kind;
    final price = kPackPrice[again]!;
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
                  onPressed: Game.i.coins >= price ? () => _again(again) : null,
                  child: Text(t('Ouvrir un autre ($price)', 'Open another ($price)')),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  Future<void> _again(String kind) async {
    try {
      final r = await Game.i.openPack(kind, widget.sys);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        pageBuilder: (_, __, ___) => PackOpeningPage(result: r, kind: kind, sys: widget.sys),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ));
    } catch (e) {
      toast(errText(e));
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

const double _kPackW = 214, _kPackH = 330, _kCapH = 36, _kCrimp = 30;

/// Découpe crantée (dents de scie) du bord haut (soudure du haut) ou bas (corps).
class _CrimpClipper extends CustomClipper<Path> {
  final bool top;
  const _CrimpClipper({required this.top});

  @override
  Path getClip(Size size) {
    const tooth = 7.0, depth = 5.0;
    final p = Path();
    if (top) {
      p.moveTo(0, depth);
      for (double x = 0; x < size.width; x += tooth) {
        p.lineTo(x + tooth / 2, 0);
        p.lineTo(min(x + tooth, size.width), depth);
      }
      p
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
    } else {
      p
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height - depth);
      for (double x = size.width; x > 0; x -= tooth) {
        p.lineTo(x - tooth / 2, size.height);
        p.lineTo(max(x - tooth, 0), size.height - depth);
      }
      p.close();
    }
    return p;
  }

  @override
  bool shouldReclip(covariant _CrimpClipper old) => old.top != top;
}

/// Soudure métallisée : bande argentée striée verticalement.
class _CrimpPainter extends CustomPainter {
  final double sheen;
  final bool top;
  _CrimpPainter({required this.sheen, required this.top});

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final p = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFE8ECF5), Color(0xFF9AA4BE), Color(0xFFD5DBEA), Color(0xFF7D88A6)],
      ).createShader(r);
    canvas.drawRect(r, p);
    p.shader = null;
    // stries de la soudure
    for (double x = 1; x < size.width; x += 3) {
      p.color = (x ~/ 3).isEven ? const Color(0x33000000) : const Color(0x55FFFFFF);
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), p);
    }
    // reflet qui glisse
    final sx = -0.5 + sheen * 2;
    p.shader = LinearGradient(
      begin: Alignment(-1 + sx * 2, 0),
      end: Alignment(-0.6 + sx * 2, 0),
      colors: const [Color(0x00FFFFFF), Color(0xAAFFFFFF), Color(0x00FFFFFF)],
    ).createShader(r);
    canvas.drawRect(r, p);
    p.shader = null;
    // liseré côté sachet
    p.color = const Color(0x66000000);
    canvas.drawRect(Rect.fromLTWH(0, top ? size.height - 2 : 0, size.width, 2), p);
  }

  @override
  bool shouldRepaint(covariant _CrimpPainter old) => old.sheen != sheen;
}

/// Corps du booster : illustration, bombé du sachet, reflet, étiquette, soudure du bas.
class _BoosterBody extends StatelessWidget {
  final String kind, label;
  final String? sys;
  final double sheen;
  final Color color;
  const _BoosterBody({required this.kind, required this.sys, required this.label, required this.sheen, required this.color});

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      // illustration du dos des cartes
      Image.asset('assets/card_back.jpg', fit: BoxFit.cover, alignment: const Alignment(0, -0.1)),
      // teinte selon le type de paquet
      DecoratedBox(decoration: BoxDecoration(color: color.withOpacity(0.18))),
      // bombé : bords plus sombres, centre plus clair
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0x99000000), Color(0x00000000), Color(0x22FFFFFF), Color(0x00000000), Color(0x99000000)],
            stops: [0, 0.14, 0.5, 0.86, 1],
          ),
        ),
      ),
      // plis du sachet près des soudures
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x88000000), Color(0x00000000), Color(0x00000000), Color(0x88000000)],
            stops: [0, 0.07, 0.86, 0.93],
          ),
        ),
      ),
      // reflet métallisé qui glisse
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-2.6 + sheen * 5, -1),
            end: Alignment(-1.6 + sheen * 5, 1),
            colors: const [Color(0x00FFFFFF), Color(0x55FFFFFF), Color(0x33B5D4F4), Color(0x33ED93B1), Color(0x00FFFFFF)],
          ),
        ),
      ),
      // étiquette du paquet
      Positioned(
        left: 18,
        right: 18,
        bottom: _kCrimp + 16,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xE60A1033),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: kGold, width: 2),
            boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 10)],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (kind == 'console' && sys != null)
              Padding(padding: const EdgeInsets.only(bottom: 6), child: ConsoleLogo(sys!, height: 20))
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(label.toUpperCase(), textAlign: TextAlign.center, style: pixelStyle(size: 9, color: Colors.white, shadow: false)),
              ),
            Text('RÉTRO COLLEC', style: pixelStyle(size: 11)),
            const SizedBox(height: 4),
            Text(t('5 CARTES', '5 CARDS'), style: pixelStyle(size: 7, color: const Color(0xFF8FD3FF), shadow: false)),
          ]),
        ),
      ),
      // soudure du bas
      Positioned(left: 0, right: 0, bottom: 0, height: _kCrimp, child: CustomPaint(painter: _CrimpPainter(sheen: sheen, top: false))),
      // contour brillant
      DecoratedBox(decoration: BoxDecoration(border: Border.all(color: Colors.white.withOpacity(0.18), width: 1.5))),
    ]);
  }
}
