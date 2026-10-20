import 'dart:math';

import 'package:flutter/material.dart';

import 'audio.dart';
import 'game.dart';
import 'main.dart';
import 'notifs.dart';
import 'retro_theme.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Trophées à 3 paliers (bronze, argent, or) : seuils et compteurs côté serveur
// (rc__tpool, rc__tn), textes et icônes ici. Vitrine de 3 trophées au profil
// et sur la borne du Voisinage (« type:palier,,type:palier »).
// ═══════════════════════════════════════════════════════════════════════════

class TrophyDef {
  final String k, icon, fr, en, dfr, den; // # = seuil du palier
  final List<int> s; // seuils bronze, argent, or (les mêmes que rc__tpool)
  const TrophyDef(this.k, this.icon, this.fr, this.en, this.dfr, this.den, this.s);
  String get name => t(fr, en);
  String desc(int n) => t(dfr, den).replaceAll('#', '$n');
}

const kTrophies = [
  TrophyDef('packs', '📦', 'Ouvreur de paquets', 'Pack opener', 'Ouvrir # paquets', 'Open # packs', [25, 100, 500]),
  TrophyDef('cards', '🗂️', 'Collectionneur', 'Collector', 'Avoir # cartes différentes', 'Own # different cards', [100, 400, 1000]),
  TrophyDef('consoles', '🎮', 'Console complète', 'Full system', 'Terminer # console(s) à 100 %', 'Complete # system(s) at 100%', [1, 5, 14]),
  TrophyDef('legend', '👑', 'Légendes', 'Legends', 'Obtenir # carte(s) légendaire(s)', 'Get # legendary card(s)', [1, 10, 50]),
  TrophyDef('fullart', '🖼️', 'Full art', 'Full art', 'Obtenir # carte(s) Full art', 'Get # Full art card(s)', [1, 10, 30]),
  TrophyDef('fuse', '⚗️', 'Alchimiste', 'Alchemist', 'Faire # fusions', 'Make # fusions', [5, 25, 100]),
  TrophyDef('wins', '⚔️', 'Gladiateur', 'Gladiator', 'Gagner # duels', 'Win # duels', [10, 50, 200]),
  TrophyDef('gifts', '🎁', 'Père Noël', 'Santa', 'Envoyer # cadeaux', 'Send # gifts', [10, 50, 200]),
  TrophyDef('sales', '💰', 'Marchand', 'Merchant', 'Vendre # cartes à la Bourse', 'Sell # cards on the market', [5, 25, 100]),
  TrophyDef('trades', '🤝', 'Négociateur', 'Negotiator', 'Réussir # échanges', 'Complete # trades', [5, 25, 100]),
  TrophyDef('gamedle', '🟨', 'Détective', 'Detective', 'Réussir # Gamedle', 'Solve # Gamedles', [10, 50, 200]),
  TrophyDef('chest', '🏆', 'Semaine parfaite', 'Perfect week', 'Ouvrir # fois le coffre des défis', 'Open the challenge chest # times', [1, 5, 20]),
  TrophyDef('sagas', '📖', 'Sagas', 'Sagas', 'Terminer # saga(s) à 100 %', 'Complete # saga(s) at 100%', [1, 3, 6]),
  TrophyDef('days', '📅', 'Fidèle', 'Loyal', 'Se connecter # jours', 'Log in on # days', [7, 30, 100]),
  TrophyDef('epics', '💜', 'Épiques', 'Epics', 'Obtenir # cartes épiques', 'Get # epic cards', [10, 50, 200]),
  TrophyDef('holo', '✨', 'Brillant', 'Shiny', 'Obtenir # cartes brillantes', 'Get # holo cards', [10, 50, 200]),
  TrophyDef('gold', '🥇', 'Doré', 'Golden', 'Obtenir # cartes dorées', 'Get # gold cards', [5, 25, 100]),
  TrophyDef('recycle', '♻️', 'Recycleur', 'Recycler', 'Recycler # doublons', 'Recycle # duplicates', [50, 250, 1000]),
  TrophyDef('quiz', '❓', 'Incollable', 'Know-it-all', 'Donner # bonnes réponses au quiz', 'Give # right quiz answers', [50, 250, 1000]),
  TrophyDef('played', '🕹️', 'Joueur', 'Player', 'Jouer # duels', 'Play # duels', [20, 100, 400]),
  TrophyDef('defis', '📋', 'Relevé !', 'Challenger', 'Réussir # défis de la semaine', 'Complete # weekly challenges', [10, 50, 200]),
  TrophyDef('premium', '⭐', 'Premium', 'Premium', 'Ouvrir # paquets premium', 'Open # premium packs', [5, 25, 100]),
  TrophyDef('buys', '🛒', 'Acheteur', 'Buyer', 'Acheter # cartes à la Bourse', 'Buy # cards on the market', [5, 25, 100]),
  TrophyDef('firsttry', '🎯', 'Du premier coup', 'First try', 'Trouver # Gamedle du premier coup', 'Solve # Gamedles on the first try', [1, 5, 20]),
];

TrophyDef? trophyDef(String k) {
  for (final d in kTrophies) {
    if (d.k == k) return d;
  }
  return null;
}

const kTrophyRewards = [(100, 0), (300, 0), (800, 3)]; // pièces, pixels par palier
String tierName(int tier) => [t('Bronze', 'Bronze'), t('Argent', 'Silver'), t('Or', 'Gold')][(tier - 1).clamp(0, 2)];

/// Vitrine « wins:3,,cards:2 » → 3 cases (null = vide)
List<(String, int)?> parseTrophyShow(String? s) {
  final out = <(String, int)?>[null, null, null];
  final parts = (s ?? '').split(',');
  for (var i = 0; i < 3 && i < parts.length; i++) {
    final p = parts[i].split(':');
    final tier = p.length == 2 ? int.tryParse(p[1]) ?? 0 : 0;
    if (tier > 0 && trophyDef(p[0]) != null) out[i] = (p[0], tier.clamp(1, 3));
  }
  return out;
}

/// Ma vitrine telle que la borne doit l'afficher (mise à jour dès que je change quelque chose)
final myTrophyShow = ValueNotifier<String?>(null);

// ─── Médaille hexagonale ────────────────────────────────────────────────────

const _tierColors = [
  [Color(0xFF4B6573), Color(0xFF2B414C)], // verrouillé
  [Color(0xFFF2B07A), Color(0xFF8E4E22)], // bronze
  [Color(0xFFF1F5F8), Color(0xFF7F8E9A)], // argent
  [Color(0xFFFFE27A), Color(0xFFD08A12)], // or
];

class TrophyMedal extends StatelessWidget {
  final String kind;
  final int tier; // 0 verrouillé, 1 bronze, 2 argent, 3 or
  final double size;
  final bool glow; // palier prêt à récupérer
  const TrophyMedal(this.kind, this.tier, {super.key, this.size = 48, this.glow = false});

  @override
  Widget build(BuildContext context) {
    final medal = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _HexPainter(tier.clamp(0, 3)),
        child: Center(
          child: Opacity(
            opacity: tier == 0 ? 0.45 : 1,
            child: Text(trophyDef(kind)?.icon ?? '🏆', style: TextStyle(fontSize: size * 0.42, height: 1)),
          ),
        ),
      ),
    );
    return glow ? _Glow(child: medal) : medal;
  }
}

class _HexPainter extends CustomPainter {
  final int tier;
  _HexPainter(this.tier);

  Path _hex(Rect r) {
    final p = Path();
    for (var i = 0; i < 6; i++) {
      final a = -pi / 2 + i * pi / 3;
      final o = Offset(r.center.dx + r.width / 2 * cos(a), r.center.dy + r.height / 2 * sin(a));
      i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size s) {
    final r = Offset.zero & s;
    final c = _tierColors[tier];
    canvas.drawPath(_hex(r), Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c).createShader(r));
    final inner = r.deflate(s.width * 0.08);
    canvas.drawPath(
        _hex(inner),
        Paint()
          ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xAA06202E), Color(0xDD06202E)])
              .createShader(inner));
  }

  @override
  bool shouldRepaint(_HexPainter o) => o.tier != tier;
}

class _Glow extends StatefulWidget {
  final Widget child;
  const _Glow({required this.child});
  @override
  State<_Glow> createState() => _GlowState();
}

class _GlowState extends State<_Glow> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) => DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: kGold.withOpacity(0.15 + 0.45 * _c.value), blurRadius: 6 + 10 * _c.value)],
          ),
          child: child,
        ),
        child: widget.child,
      );
}

// ─── Données ────────────────────────────────────────────────────────────────

class _Tro {
  final String k;
  final int n, got;
  final List<int> t;
  _Tro(this.k, this.n, this.got, this.t);
  int get reached => t.where((x) => n >= x).length;
  bool get ready => got < 3 && reached > got;
}

List<_Tro> _parse(Map<String, dynamic>? r) => [
      for (final e in (r?['list'] as List? ?? const []))
        if (e is Map && trophyDef('${e['k']}') != null)
          _Tro('${e['k']}', (e['n'] as num? ?? 0).toInt(), (e['got'] as num? ?? 0).toInt(),
              [for (final x in (e['t'] as List? ?? const [1, 1, 1])) (x as num).toInt()]),
    ];

String _showWithTiers(String show, List<_Tro> list) {
  final parts = show.split(',');
  return [
    for (var i = 0; i < 3; i++)
      () {
        final k = i < parts.length ? parts[i] : '';
        final g = list.where((x) => x.k == k).map((x) => x.got).firstOrNull ?? 0;
        return g > 0 ? '$k:$g' : '';
      }()
  ].join(',');
}

// ─── Mon profil : vitrine + grille ──────────────────────────────────────────

class MyTrophies extends StatefulWidget {
  const MyTrophies({super.key});
  @override
  State<MyTrophies> createState() => _MyTrophiesState();
}

class _MyTrophiesState extends State<MyTrophies> {
  bool open = false; // liste complète des trophées dépliée
  List<_Tro> list = [];
  String show = '';
  bool loaded = false, failed = false, busy = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  void _apply(Map<String, dynamic> r) {
    list = _parse(r);
    show = r['show'] as String? ?? '';
    myTrophyShow.value = _showWithTiers(show, list);
  }

  Future<void> load() async {
    try {
      final r = await RcServer.trophies();
      if (mounted) {
        setState(() {
          _apply(r);
          loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => failed = true); // serveur pas encore à jour : on masque
    }
  }

  Future<void> _claim(_Tro x) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final r = await RcServer.trophyClaim(x.k);
      Game.i.setWallet(r);
      final tier = (r['tier'] as num? ?? 1).toInt(), gain = (r['gain'] as num? ?? 0).toInt(), px = (r['px'] as num? ?? 0).toInt();
      RcAudio.sfx(tier == 3 ? 'powerup' : 'coin');
      toast(px > 0
          ? t('🏆 ${trophyDef(x.k)!.name} ${tierName(tier)} : +$gain pièces et +$px pixels !', '🏆 ${trophyDef(x.k)!.name} ${tierName(tier)}: +$gain coins and +$px pixels!')
          : t('🏆 ${trophyDef(x.k)!.name} ${tierName(tier)} : +$gain pièces !', '🏆 ${trophyDef(x.k)!.name} ${tierName(tier)}: +$gain coins!'));
      if (mounted) setState(() => _apply(r));
      Notifs.i.refresh(); // pastille du profil
    } catch (_) {
      toast(t('Impossible de récupérer pour l\'instant', 'Could not claim right now'));
      load();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _setShow(List<String> slots) async {
    try {
      final r = await RcServer.trophyShow(slots.join(','));
      if (mounted) setState(() => _apply(r));
    } catch (_) {
      toast(t('Impossible de changer la vitrine pour l\'instant', 'Could not change the showcase right now'));
    }
  }

  List<String> get _slots {
    final p = show.split(',');
    return [for (var i = 0; i < 3; i++) i < p.length ? p[i] : ''];
  }

  _Tro? _of(String k) => list.where((x) => x.k == k).firstOrNull;

  @override
  Widget build(BuildContext context) {
    if (failed || !loaded) return const SizedBox.shrink();
    final total = list.fold<int>(0, (a, x) => a + x.got);
    final ready = list.fold<int>(0, (a, x) => a + max(0, x.reached - x.got));
    final slots = _slots;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: Text(t('Mes trophées', 'My trophies'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        Text(
          ready > 0 ? t('$total / ${list.length * 3} paliers · $ready à récupérer', '$total / ${list.length * 3} tiers · $ready to claim') : t('$total / ${list.length * 3} paliers', '$total / ${list.length * 3} tiers'),
          style: TextStyle(color: ready > 0 ? kGold : Colors.white38, fontSize: 12, fontWeight: ready > 0 ? FontWeight.w800 : null),
        ),
      ]),
      const SizedBox(height: 4),
      Text(t('Tes 3 meilleurs s\'affichent sur ton profil et ta borne · touche une case pour en choisir un autre', 'Your 3 best show on your profile and cabinet · tap a slot to pick another'),
          style: const TextStyle(color: Colors.white38, fontSize: 12)),
      const SizedBox(height: 8),
      Row(children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Flexible(child: SizedBox(width: 112, child: _slot(context, i, slots))),
        ],
      ]),
      const SizedBox(height: 10),
      // tous les trophées : dans un déroulant (fermé par défaut)
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => open = !open),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: opq(ready > 0 ? kGold.withOpacity(0.10) : Colors.black.withOpacity(0.18)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ready > 0 ? kGold : Colors.white12),
          ),
          child: Row(children: [
            const Text('🏆', style: TextStyle(fontSize: 15)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ready > 0
                    ? t('Tous les trophées · $ready à récupérer', 'All trophies · $ready to claim')
                    : t('Tous les trophées (${list.length})', 'All trophies (${list.length})'),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: ready > 0 ? kGold : Colors.white),
              ),
            ),
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.expand_more, color: ready > 0 ? kGold : Colors.white70),
            ),
          ]),
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: !open
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: 10),
                child: LayoutBuilder(builder: (ctx, c) {
                  final cols = max(3, ((c.maxWidth + 8) / 104).floor());
                  final w = (c.maxWidth - (cols - 1) * 8) / cols;
                  return Wrap(spacing: 8, runSpacing: 8, children: [for (final x in list) SizedBox(width: w, child: _cell(context, x))]);
                }),
              ),
      ),
    ]);
  }

  Widget _slot(BuildContext context, int i, List<String> slots) {
    final x = _of(slots[i]);
    final has = x != null && x.got > 0;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _choose(context, i),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: opq(Colors.black.withOpacity(0.2)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(children: [
          if (has)
            TrophyMedal(x.k, x.got, size: 48)
          else
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: 2)),
              child: const Icon(Icons.add, color: Colors.white38),
            ),
          const SizedBox(height: 6),
          Text(has ? trophyDef(x.k)!.name : t('Choisir', 'Pick'),
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: has ? Colors.white : Colors.white38)),
        ]),
      ),
    );
  }

  Widget _cell(BuildContext context, _Tro x) {
    final d = trophyDef(x.k)!;
    final base = x.got == 0 ? 0 : x.t[x.got - 1];
    final next = x.t[min(x.got, 2)];
    final pct = x.got >= 3 ? 1.0 : ((x.n - base) / max(1, next - base)).clamp(0.0, 1.0);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _detail(context, x.k),
      child: Container(
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 7),
        decoration: BoxDecoration(
          color: opq(x.ready ? kGold.withOpacity(0.08) : Colors.black.withOpacity(0.18)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: x.ready ? kGold : Colors.transparent),
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          Column(children: [
            TrophyMedal(x.k, x.got, size: 46, glow: x.ready),
            const SizedBox(height: 5),
            SizedBox(
              height: 26,
              child: Text(d.name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, height: 1.15, color: x.got > 0 || x.ready ? Colors.white : Colors.white54)),
            ),
            const SizedBox(height: 4),
            if (x.got < 3)
              FractionallySizedBox(
                widthFactor: 0.8,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: pct, minHeight: 4, backgroundColor: opq(Colors.white12), color: rcTheme.accent),
                ),
              ),
            const SizedBox(height: 5),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var k = 1; k <= 3; k++)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: opq(k <= x.got ? _tierColors[k][0] : Colors.white12)),
                ),
            ]),
          ]),
          if (x.ready)
            Positioned(
              top: -12,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(8)),
                child: const Text('!', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 10)),
              ),
            ),
        ]),
      ),
    );
  }

  /// Détail d'un trophée : ses 3 paliers, récupérer le palier prêt, le mettre en vitrine
  void _detail(BuildContext context, String k) {
    showModalBottomSheet(
      context: context,
      backgroundColor: kBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final x = _of(k)!;
        final d = trophyDef(k)!;
        final inShow = _slots.contains(k);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TrophyMedal(k, x.got, size: 84, glow: x.ready),
              const SizedBox(height: 10),
              Text(d.name.toUpperCase(), textAlign: TextAlign.center, style: pixelStyle(size: 12, color: kGold)),
              const SizedBox(height: 6),
              Text(t('Progression : ${x.n}', 'Progress: ${x.n}'), style: const TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 12),
              for (var i = 0; i < 3; i++) _tierRow(ctx, x, d, i, () => _claim(x).then((_) => setSheet(() {}))),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Fermer', 'Close')))),
                if (x.got > 0) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: inShow
                          ? null
                          : () {
                              final s = _slots;
                              final free = s.indexOf('');
                              s[free < 0 ? 2 : free] = k;
                              _setShow(s);
                              Navigator.pop(ctx);
                            },
                      child: Text(inShow ? t('En vitrine', 'In showcase') : t('Mettre en vitrine', 'Showcase it')),
                    ),
                  ),
                ],
              ]),
            ]),
          ),
        );
      }),
    );
  }

  Widget _tierRow(BuildContext ctx, _Tro x, TrophyDef d, int i, VoidCallback claim) {
    final (coins, px) = kTrophyRewards[i];
    final Widget right = i < x.got
        ? const Icon(Icons.check_circle, color: Color(0xFF5FD39A), size: 22)
        : i < x.reached && i == x.got
            ? FilledButton(
                onPressed: busy ? null : claim,
                style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 12)),
                child: Text(t('Récupérer', 'Claim'), style: const TextStyle(fontWeight: FontWeight.w900)),
              )
            : Text('${min(x.n, x.t[i])} / ${x.t[i]}', style: const TextStyle(color: Colors.white54, fontFeatures: [FontFeature.tabularFigures()]));
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: opq(Colors.black.withOpacity(0.2)), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        TrophyMedal(x.k, i < x.got ? i + 1 : 0, size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tierName(i + 1), style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(px > 0 ? '${d.desc(x.t[i])} · +$coins 🪙 +$px 👾' : '${d.desc(x.t[i])} · +$coins 🪙',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ),
        const SizedBox(width: 8),
        right,
      ]),
    );
  }

  /// Choisir le trophée d'une case de la vitrine
  void _choose(BuildContext context, int slot) {
    final unlocked = list.where((x) => x.got > 0).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: kBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('Case ${slot + 1} de la vitrine', 'Showcase slot ${slot + 1}'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
                unlocked.isEmpty
                    ? t('Aucun trophée débloqué pour l\'instant : récupère un premier palier bronze.', 'No trophy unlocked yet: claim a first bronze tier.')
                    : t('Le trophée s\'affiche à son meilleur palier', 'The trophy shows at its best tier'),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final x in unlocked)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    final s = _slots.map((e) => e == x.k ? '' : e).toList();
                    s[slot] = x.k;
                    _setShow(s);
                    Navigator.pop(ctx);
                  },
                  child: SizedBox(
                    width: 74,
                    child: Column(children: [
                      TrophyMedal(x.k, x.got, size: 48),
                      const SizedBox(height: 4),
                      Text(trophyDef(x.k)!.name, maxLines: 2, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _slots[slot].isEmpty
                      ? null
                      : () {
                          final s = _slots;
                          s[slot] = '';
                          _setShow(s);
                          Navigator.pop(ctx);
                        },
                  child: Text(t('Automatique', 'Automatic')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Fermer', 'Close')))),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ─── Profil d'un autre joueur : sa vitrine de trophées ───────────────────────

class OtherTrophies extends StatelessWidget {
  final String? show;
  final int total;
  const OtherTrophies({super.key, this.show, this.total = 0});

  @override
  Widget build(BuildContext context) {
    final items = parseTrophyShow(show).whereType<(String, int)>().toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: Text(t('Trophées', 'Trophies'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        Text(t('$total / ${kTrophies.length * 3} paliers', '$total / ${kTrophies.length * 3} tiers'), style: const TextStyle(color: Colors.white38, fontSize: 12)),
      ]),
      const SizedBox(height: 8),
      if (items.isEmpty)
        Text(t('Aucun trophée en vitrine', 'No trophy in the showcase'), style: const TextStyle(color: Colors.white38, fontSize: 13))
      else
        Row(children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: i >= items.length
                  ? const SizedBox.shrink()
                  : InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _info(context, items[i].$1, items[i].$2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                        decoration: BoxDecoration(color: opq(Colors.black.withOpacity(0.2)), borderRadius: BorderRadius.circular(14)),
                        child: Column(children: [
                          TrophyMedal(items[i].$1, items[i].$2, size: 52),
                          const SizedBox(height: 6),
                          Text(trophyDef(items[i].$1)!.name,
                              maxLines: 2, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                          Text(tierName(items[i].$2), style: const TextStyle(fontSize: 11, color: Colors.white54)),
                        ]),
                      ),
                    ),
            ),
          ],
        ]),
    ]);
  }

  void _info(BuildContext context, String k, int tier) {
    final d = trophyDef(k)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBg,
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TrophyMedal(k, tier, size: 80),
          const SizedBox(height: 10),
          Text(d.name.toUpperCase(), textAlign: TextAlign.center, style: pixelStyle(size: 11, color: kGold)),
          const SizedBox(height: 8),
          Text('${tierName(tier)} : ${d.desc(d.s[tier - 1])}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Fermer', 'Close')))],
      ),
    );
  }
}
