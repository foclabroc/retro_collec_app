import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio.dart';
import 'cards.dart';
import 'packs.dart';
import 'game.dart';
import 'layout.dart';
import 'main.dart';
import 'retro_theme.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Événements : la liste vient du serveur (table rc_events), on peut donc en
// ajouter, modifier ou arrêter sans mettre à jour l'appli. 3 sortes :
//   info   : annonce, cadeau à récupérer (pièces, pixels), bouton « Y aller »
//   effect : règle changée pendant l'événement (pixels ×2, paquet gratuit plus fréquent)
//   goal   : défi suivi par le serveur, avec des paliers de récompenses
// Les événements à venir arrivent sans nom ni contenu (surprise).
// ═══════════════════════════════════════════════════════════════════════════

class Events extends ChangeNotifier {
  static final i = Events();
  List<Map<String, dynamic>> list = [];
  int _seen = 0; // plus grand numéro d'événement déjà vu (pastille « nouveau »)
  static const _kSeen = 'rc_events_seen';

  /// Événements en cours pas encore vus, ou avec une récompense pas encore récupérée
  int get unseen => list.where((e) => e['live'] == true && (_id(e) > _seen || _claimable(e))).length;

  static int _id(Map e) => (e['id'] as num? ?? 0).toInt();
  static bool _claimable(Map e) {
    if (e['live'] != true) return false;
    if (e['kind'] == 'goal') return _reachable(e) > 0;
    return e['got'] != true && ((e['coins'] as num? ?? 0) > 0 || (e['pixels'] as num? ?? 0) > 0);
  }

  /// Défi : nombre de paliers atteints pas encore récupérés
  static int _reachable(Map e) {
    final prog = (e['progress'] as num? ?? 0).toInt(), claimed = (e['claimed'] as num? ?? 0).toInt();
    final steps = (e['steps'] as List? ?? const []);
    var n = 0;
    for (var i = claimed; i < steps.length; i++) {
      if (prog >= ((steps[i] as Map)['n'] as num? ?? 0)) n++;
    }
    return n;
  }

  /// Multiplicateur de pixels d'un événement « pixels ×2 » en cours (1 sinon)
  int get pixelMult {
    var m = 1;
    for (final e in list) {
      if (e['live'] == true && e['kind'] == 'effect' && e['effect'] == 'pixels_x2') {
        final v = (e['effect_value'] as num? ?? 2).toInt();
        if (v > m) m = v;
      }
    }
    return m;
  }

  Future<void> refresh() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _seen = prefs.getInt(_kSeen) ?? 0;
      list = await RcServer.events();
      notifyListeners();
    } catch (_) {
      // hors ligne ou serveur pas encore à jour : on garde la liste actuelle
    }
  }

  Future<void> markSeen() async {
    // seulement les événements commencés : un mystère à venir redeviendra « nouveau » à son lancement
    final top = list.where((e) => e['hidden'] != true && e['upcoming'] != true).fold<int>(_seen, (m, e) => _id(e) > m ? _id(e) : m);
    if (top == _seen) return;
    _seen = top;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kSeen, top);
    } catch (_) {}
  }
}

const _kTabs = {'collection': 0, 'packs': 1, 'bonus': 2, 'market': 3, 'messages': 4, 'neighbors': 5, 'news': 6};

class EventsPage extends StatefulWidget {
  const EventsPage({super.key});
  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> with TickerProviderStateMixin {
  bool loading = true;
  int? busy;
  Timer? _tick;
  late final AnimationController anim = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {}); // compte à rebours
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    anim.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await Events.i.refresh();
    if (!mounted) return;
    setState(() => loading = false);
    Events.i.markSeen();
  }

  Future<void> _claim(Map<String, dynamic> e) async {
    final id = Events._id(e);
    setState(() => busy = id);
    try {
      final r = await RcServer.eventClaim(id);
      Game.i.sync(); // pièces et pixels à jour partout
      RcAudio.sfx('coin');
      RcAudio.sfx('powerup');
      final c = (r['gain_coins'] as num? ?? 0).toInt(), p = (r['gain_pixels'] as num? ?? 0).toInt();
      toast(t('Récompense : ${[if (c > 0) '+$c pièces', if (p > 0) '+$p pixels'].join(' · ')}',
          'Reward: ${[if (c > 0) '+$c coins', if (p > 0) '+$p pixels'].join(' · ')}'));
      await Events.i.refresh();
    } catch (err) {
      toast(errText(err));
    }
    if (mounted) setState(() => busy = null);
  }

  void _go(int tab) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    HomeShellState.current?.goTo(tab);
  }

  // ── utilitaires ──
  Color _color(String? hex) {
    final h = (hex ?? '').replaceAll('#', '');
    final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
    return v == null ? kGold : Color(v);
  }

  DateTime? _date(Map e, String k) => DateTime.tryParse(e[k] as String? ?? '');
  // écart avec l'heure du serveur (heure du téléphone - heure du serveur), pour les comptes à rebours
  Duration get _skew => Duration.zero;

  String _span(Duration d) {
    if (d.isNegative) d = Duration.zero;
    if (d.inDays >= 1) return t('${d.inDays} j ${d.inHours % 24} h', '${d.inDays} d ${d.inHours % 24} h');
    if (d.inHours >= 1) return t('${d.inHours} h ${d.inMinutes % 60} min', '${d.inHours} h ${d.inMinutes % 60} min');
    return t('${max(1, d.inMinutes)} min', '${max(1, d.inMinutes)} min');
  }

  /// « Encore 3 j 4 h », « dans 2 j », « Terminé »
  String _when(Map<String, dynamic> e) {
    final now = DateTime.now().add(_skew);
    final start = _date(e, 'starts_at'), end = _date(e, 'ends_at');
    if (e['ended'] == true) return t('Terminé', 'Ended');
    if (start != null && start.isAfter(now)) return t('dans ${_span(start.difference(now))}', 'in ${_span(start.difference(now))}');
    if (end == null) return t('En cours', 'Ongoing');
    return t('Encore ${_span(end.difference(now))}', '${_span(end.difference(now))} left');
  }

  String _title(Map e) => ((rcFrench ? e['title'] : (e['title_en'] ?? e['title'])) as String?) ?? '';
  String _body(Map e) => ((rcFrench ? e['body'] : (e['body_en'] ?? e['body'])) as String?) ?? '';
  int _n(Map e, String k) => (e[k] as num? ?? 0).toInt();

  bool _hasGift(Map e) => (e['kind'] ?? 'info') == 'info' && (_n(e, 'coins') > 0 || _n(e, 'pixels') > 0);

  /// L'événement phare : en cours, cadeau pas encore récupéré d'abord, puis celui qui se termine le plus tôt
  Map<String, dynamic>? _hero(List<Map<String, dynamic>> live) {
    if (live.isEmpty) return null;
    final l = [...live];
    int score(Map e) => Events._claimable(e) ? 0 : (_hasGift(e) ? 1 : 2);
    l.sort((a, b) {
      final s = score(a).compareTo(score(b));
      if (s != 0) return s;
      final ea = _date(a, 'ends_at') ?? DateTime(2100), eb = _date(b, 'ends_at') ?? DateTime(2100);
      return ea.compareTo(eb);
    });
    return l.first;
  }

  String _reward(int coins, int pixels) => [
        if (coins > 0) t('$coins pièces', '$coins coins'),
        if (pixels > 0) t('$pixels pixels', '$pixels pixels'),
      ].join(' + ');

  // ── écran ──
  @override
  Widget build(BuildContext context) {
    return MaxWidth(
      max: 760,
      child: Scaffold(
        appBar: AppBar(
          title: Text(px(t('ÉVÉNEMENTS', 'EVENTS')), style: pixelStyle(size: 13)),
          actions: [
            ListenableBuilder(
              listenable: Game.i,
              builder: (_, __) => Row(children: [PixelChip(Game.i.pixels), const SizedBox(width: 6), CoinChip(Game.i.coins)]),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: ListenableBuilder(
          listenable: Events.i,
          builder: (context, _) {
            final list = Events.i.list;
            if (loading && list.isEmpty) return const Center(child: CircularProgressIndicator(color: kGold));
            final live = list.where((e) => e['live'] == true).toList();
            // à venir : le plus proche d'abord
            final soon = list.where((e) => e['live'] != true && e['ended'] != true).toList()
              ..sort((a, b) => (_date(a, 'starts_at') ?? DateTime(2100)).compareTo(_date(b, 'starts_at') ?? DateTime(2100)));
            final ended = list.where((e) => e['ended'] == true).toList();
            final hero = _hero(live);
            final others = live.where((e) => e != hero).toList();
            Widget sec(String s) => Padding(
                  padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                  child: Text(px(s), style: pixelStyle(size: 8, color: Colors.white38, shadow: false).copyWith(letterSpacing: 1)),
                );
            return RefreshIndicator(
              onRefresh: Events.i.refresh,
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 28), children: [
                if (hero != null) _heroCard(hero) else _emptyHero(soon),
                if (list.isNotEmpty) ...[sec(t('CALENDRIER', 'CALENDAR')), _calendar(list)],
                if (others.isNotEmpty) ...[
                  sec(t('EN COURS', 'NOW')),
                  for (final e in others) Padding(padding: const EdgeInsets.only(bottom: 12), child: _card(e)),
                ],
                if (soon.isNotEmpty) ...[
                  sec(t('BIENTÔT', 'COMING SOON')),
                  // visibles en entier, mais rien n'est utilisable avant leur début
                  for (final e in soon) Padding(padding: const EdgeInsets.only(bottom: 12), child: e['hidden'] == true ? _mystery(e) : _card(e)),
                ],
                if (ended.isNotEmpty) ...[
                  sec(t('TERMINÉS', 'ENDED')),
                  for (final e in ended) _ended(e),
                ],
              ]),
            );
          },
        ),
      ),
    );
  }

  Widget _emptyHero(List<Map<String, dynamic>> soon) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(colors: [Color(0xFF2A1360), Color(0xFF141A4C)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(children: [
          const Text('📅', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 8),
          Text(t('Pas d\'événement en ce moment', 'No event right now'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
              soon.isEmpty
                  ? t('Reviens bientôt !', 'Come back soon!')
                  : t('Le prochain commence ${_when(soon.first)}', 'The next one starts ${_when(soon.first)}'),
              style: const TextStyle(color: Colors.white60)),
        ]),
      );

  /// Grande affiche de l'événement phare
  Widget _heroCard(Map<String, dynamic> e) {
    final c = _color(e['color'] as String?);
    final icon = e['icon'] as String? ?? '🎉';
    final end = _date(e, 'ends_at');
    final left = end?.difference(DateTime.now().add(_skew));
    // décor qui traverse l'affiche : colonne « decor » de l'événement, sinon d'après son émoji
    final custom = (e['decor'] as String?)?.trim() ?? '';
    final decor = custom.isNotEmpty ? custom : switch (icon) {
      '🎃' || '👻' || '🦇' => '🦇',
      '🎄' || '❄️' || '⛄' || '🎅' => '❄️',
      '💘' || '❤️' || '💝' => '💗',
      '🎉' || '🥳' || '🎂' => '🎊',
      '⚡' => '⚡',
      '🏁' || '🃏' => '🃏',
      '⚔️' || '⚔' => '🔴',
      '🚢' => '💥',
      '✨' => '▦',
      _ => '✨',
    };
    final action = _kTabs[e['action']];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(colors: [c, Color.lerp(c, const Color(0xFF2A0F45), 0.7)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: Border.all(color: Color.lerp(c, Colors.white, 0.3)!, width: 2),
        boxShadow: [BoxShadow(color: c.withOpacity(0.45), blurRadius: 30, spreadRadius: -8)],
      ),
      child: Stack(children: [
        // décor animé (mouvement : colonne « decor_fx », sinon d'après le décor)
        Positioned.fill(child: IgnorePointer(child: _Decor(decor: decor, fx: _decorFx(e, decor), anim: anim))),
        // grand émoji qui flotte
        Positioned(
          right: -6,
          top: 18,
          child: AnimatedBuilder(
            animation: anim,
            builder: (_, child) => Transform.translate(offset: Offset(0, -6 * sin(anim.value * 2 * pi * 2)), child: child),
            child: Text(icon, style: const TextStyle(fontSize: 86, shadows: [Shadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 6))])),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _liveTag(),
            const SizedBox(height: 10),
            FractionallySizedBox(
              widthFactor: 0.72,
              child: Text(px(_title(e).toUpperCase()), style: pixelStyle(size: 14, color: Colors.white).copyWith(height: 1.5)),
            ),
            const SizedBox(height: 6),
            FractionallySizedBox(
              widthFactor: 0.7,
              child: Text(_body(e), style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xE6FFFFFF))),
            ),
            if (left != null) ...[
              const SizedBox(height: 12),
              Row(children: [
                for (final (v, l) in [
                  (left.inDays, t('jours', 'days')),
                  (left.inHours % 24, t('heures', 'hours')),
                  (left.inMinutes % 60, 'min'),
                  (left.inSeconds % 60, 's'),
                ])
                  Container(
                    width: 50,
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(8)),
                    child: Column(children: [
                      Text(l == t('jours', 'days') ? '${max(0, v)}' : max(0, v).toString().padLeft(2, '0'), style: pixelStyle(size: 11, color: Colors.white, shadow: false)),
                      const SizedBox(height: 2),
                      Text(l, style: const TextStyle(fontSize: 9, color: Colors.white60, fontWeight: FontWeight.w800)),
                    ]),
                  ),
              ]),
            ],
            if (e['kind'] == 'effect') ...[const SizedBox(height: 12), _effectBox(e, c)],
            if (e['kind'] == 'goal') ...[const SizedBox(height: 12), _goalBox(e, c)],
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (_hasGift(e)) _claimButton(e),
              if (e['kind'] == 'goal' && Events._reachable(e) > 0) _claimButton(e),
              if (action != null)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(backgroundColor: Colors.black26, side: const BorderSide(color: Colors.white54)),
                  onPressed: () => _go(action),
                  child: Text(t('Y aller ›', 'Go ›'), style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
                ),
            ]),
          ]),
        ),
      ]),
    );
  }

  /// Mouvement du décor : traverse, fall (chute), rise (montée), rain (pluie), fireworks (feu d'artifice)
  String _decorFx(Map e, String decor) {
    final fx = (e['decor_fx'] as String?)?.trim() ?? '';
    if (const ['traverse', 'fall', 'rise', 'rain', 'fireworks'].contains(fx)) return fx;
    return switch (decor) {
      '❄️' || '🌸' || '🍂' || '🎊' || '🍁' || '🌨️' => 'fall',
      '🫧' || '🎈' || '✨' || '💗' || '🐟' => 'rise',
      '🪙' || '▦' || '💧' || '🟩' || '🃏' => 'rain',
      '🎇' || '🎆' || '💥' || '🔥' => 'fireworks',
      _ => 'traverse',
    };
  }

  Widget _liveTag() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xFFFF4757), borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AnimatedBuilder(
            animation: anim,
            builder: (_, __) => Opacity(opacity: (anim.value * 8) % 1 < 0.5 ? 1 : 0.25, child: Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white))),
          ),
          const SizedBox(width: 5),
          Text(t('EN COURS', 'LIVE'), style: pixelStyle(size: 7, color: Colors.white, shadow: false)),
        ]),
      );

  /// Bouton « Récupérer » qui brille (cadeau ou paliers d'un défi)
  Widget _claimButton(Map<String, dynamic> e) {
    final goal = e['kind'] == 'goal';
    final got = !goal && e['got'] == true;
    final label = got
        ? t('✓ Récupéré (${_reward(_n(e, 'coins'), _n(e, 'pixels'))})', '✓ Claimed (${_reward(_n(e, 'coins'), _n(e, 'pixels'))})')
        : goal
            ? (Events._reachable(e) > 1 ? t('Récupérer ${Events._reachable(e)} paliers', 'Claim ${Events._reachable(e)} steps') : t('Récupérer le palier', 'Claim the step'))
            : t('Récupérer ${_reward(_n(e, 'coins'), _n(e, 'pixels'))}', 'Claim ${_reward(_n(e, 'coins'), _n(e, 'pixels'))}');
    if (got) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: const Color(0x335DCAA5), borderRadius: BorderRadius.circular(11)),
        child: Text(label, style: const TextStyle(color: Color(0xFF5DCAA5), fontWeight: FontWeight.w900)),
      );
    }
    return GestureDetector(
      onTap: busy == null && e['live'] == true ? () => _claim(e) : null,
      child: AnimatedBuilder(
        animation: anim,
        builder: (_, child) {
          final p = (anim.value * 3) % 1; // reflet qui passe
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (r) => LinearGradient(
              begin: Alignment(-1.5 + p * 3 - 0.3, -0.2),
              end: Alignment(-1.5 + p * 3 + 0.3, 0.2),
              colors: const [Color(0x00FFFFFF), Color(0x88FFFFFF), Color(0x00FFFFFF)],
            ).createShader(r),
            child: child,
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFFFE08A), Color(0xFFEF9F27)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
            borderRadius: BorderRadius.circular(11),
            boxShadow: const [BoxShadow(color: Color(0xFF8A4E00), offset: Offset(0, 4)), BoxShadow(color: Color(0x99FFD166), blurRadius: 16)],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (busy == Events._id(e))
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2A1800)))
            else
              const Icon(Icons.card_giftcard, size: 17, color: Color(0xFF2A1800)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Color(0xFF2A1800), fontWeight: FontWeight.w900, fontSize: 13)),
          ]),
        ),
      ),
    );
  }

  /// Frise des 14 prochains jours, un point par événement ces jours-là
  Widget _calendar(List<Map<String, dynamic>> list) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = [for (var i = 0; i < 14; i++) today.add(Duration(days: i))];
    final names = rcFrench ? const ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'] : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return SizedBox(
      height: 66,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final d = days[i];
          final next = d.add(const Duration(days: 1));
          final dots = [
            for (final e in list)
              if ((_date(e, 'starts_at')?.toLocal().isBefore(next) ?? false) && ((_date(e, 'ends_at')?.toLocal().isAfter(d)) ?? true)) _color(e['color'] as String?)
          ];
          return Container(
            width: 46,
            decoration: BoxDecoration(
              color: i == 0 ? const Color(0x26FFD166) : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: i == 0 ? Border.all(color: const Color(0xFFFFD166), width: 1.5) : null,
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(i == 0 ? t('auj.', 'today') : names[d.weekday - 1],
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: i == 0 ? const Color(0xFFFFD166) : Colors.white54)),
              Text('${d.day}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (final c in dots.take(4))
                  Container(width: 6, height: 6, margin: const EdgeInsets.symmetric(horizontal: 1.5), decoration: BoxDecoration(shape: BoxShape.circle, color: c)),
              ]),
            ]),
          );
        },
      ),
    );
  }

  /// Carte d'un événement en cours (autre que l'affiche)
  Widget _card(Map<String, dynamic> e) {
    final c = _color(e['color'] as String?);
    final kind = e['kind'] as String? ?? 'info';
    final upcoming = e['live'] != true && e['ended'] != true;
    final action = upcoming ? null : _kTabs[e['action']];
    final body = _body(e);
    final tag = switch (kind) { 'effect' => t('EFFET', 'EFFECT'), 'goal' => t('DÉFI', 'CHALLENGE'), _ => _hasGift(e) ? t('CADEAU', 'GIFT') : t('INFO', 'INFO') };
    final start = _date(e, 'starts_at')?.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return Opacity(
      opacity: upcoming ? 0.92 : 1,
      child: Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.withOpacity(0.6), width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(gradient: LinearGradient(colors: [Color.lerp(c, Colors.black, 0.15)!, Color.lerp(c, const Color(0xFF0B1036), 0.65)!])),
          child: Row(children: [
            Container(
              width: 50,
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white24, width: 2)),
              child: Text(e['icon'] as String? ?? '🎉', style: const TextStyle(fontSize: 26)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_title(e), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                if (upcoming)
                  Text.rich(TextSpan(children: [
                    TextSpan(text: t('Commence dans ', 'Starts in ')),
                    TextSpan(text: _chrono(e), style: pixelStyle(size: 8, color: const Color(0xFFFFD166), shadow: false)),
                  ]), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xD9FFFFFF)))
                else
                  Text(_when(e), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xD9FFFFFF))),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(5)),
              child: Text(px(upcoming ? t('BIENTÔT', 'SOON') : tag), style: pixelStyle(size: 6.5, color: Colors.white, shadow: false)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (body.isNotEmpty) ...[Text(body, style: const TextStyle(fontSize: 13, height: 1.45, color: Color(0xC7FFFFFF))), const SizedBox(height: 10)],
            if (kind == 'effect') ...[_effectBox(e, c), const SizedBox(height: 10)],
            if (kind == 'goal') ...[_goalBox(e, c), const SizedBox(height: 10)],
            if (upcoming)
              // pas encore utilisable : récompense visible, verrouillée jusqu'au début
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(11), border: Border.all(color: Colors.white24)),
                child: Text(
                    [
                      '🔒 ${start == null ? '' : t('Disponible le ${two(start.day)}/${two(start.month)} à ${two(start.hour)}:${two(start.minute)}', 'Available on ${start.month}/${start.day} at ${two(start.hour)}:${two(start.minute)}')}',
                      if (_hasGift(e)) '· ${_reward(_n(e, 'coins'), _n(e, 'pixels'))}',
                    ].join(' '),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: Colors.white70)),
              )
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (_hasGift(e)) _claimButton(e),
                if (kind == 'goal' && Events._reachable(e) > 0) _claimButton(e),
                if (action != null)
                  OutlinedButton(onPressed: () => _go(action), child: Text(t('Y aller ›', 'Go ›'), style: const TextStyle(fontWeight: FontWeight.w900))),
              ]),
          ]),
        ),
      ]),
      ),
    );
  }

  /// Effet en cours : multiplicateur qui pulse
  Widget _effectBox(Map<String, dynamic> e, Color c) {
    final v = (e['effect_value'] as num? ?? 2).toInt();
    final (big, text) = switch (e['effect']) {
      'pixels_x2' => ('×$v', t('Chaque booster ouvert rapporte $v pixels au lieu d\'1.', 'Every booster you open gives $v pixels instead of 1.')),
      'free_fast' => ('$v h', t('Le paquet gratuit revient toutes les $v heures au lieu de 6.', 'The free pack comes back every $v hours instead of 6.')),
      _ => ('★', ''),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        AnimatedBuilder(
          animation: anim,
          builder: (_, child) => Transform.scale(scale: 1 + 0.1 * sin(anim.value * 2 * pi * 5), child: child),
          child: Text(px(big), style: pixelStyle(size: 18, color: const Color(0xFFFFD166), shadow: false).copyWith(shadows: const [Shadow(color: Color(0x99FFD166), blurRadius: 12)])),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.35))),
      ]),
    );
  }

  /// Défi : piste avec des coffres (✓ récupéré, 🎁 prêt, 🔒 à atteindre)
  Widget _goalBox(Map<String, dynamic> e, Color c) {
    final steps = [for (final s in (e['steps'] as List? ?? const [])) Map<String, dynamic>.from(s as Map)];
    if (steps.isEmpty) return const SizedBox();
    final prog = _n(e, 'progress'), claimed = _n(e, 'claimed');
    final target = max(1, (steps.last['n'] as num? ?? 1).toInt());
    final label = switch (e['goal']) {
      'packs' => t('Boosters ouverts', 'Boosters opened'),
      'c4_wins' => t('Parties de 4 en ligne gagnées', 'Connect 4 games won'),
      'bs_wins' => t('Parties de Console Wars gagnées', 'Console Wars games won'),
      'gamedle' => t('Gamedle trouvés', 'Gamedles solved'),
      _ => t('Progression', 'Progress'),
    };
    String reward(Map s) => [if (_n(s, 'coins') > 0) '${s['coins']} 🪙', if (_n(s, 'pixels') > 0) '${s['pixels']} ▦'].join(' + ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w800))),
        Text('${min(prog, target)} / $target', style: const TextStyle(fontWeight: FontWeight.w900)),
      ]),
      const SizedBox(height: 6),
      LayoutBuilder(builder: (_, box) {
        final w = box.maxWidth - 30;
        return SizedBox(
          height: 56,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(left: 15, right: 15, top: 12, height: 7, child: Container(decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(4)))),
            Positioned(
              left: 15,
              top: 12,
              height: 7,
              width: w * (prog / target).clamp(0.0, 1.0),
              child: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [c, Color.lerp(c, Colors.white, 0.4)!]), borderRadius: BorderRadius.circular(4))),
            ),
            for (var i = 0; i < steps.length; i++)
              Builder(builder: (_) {
                final n = _n(steps[i], 'n');
                final got = i < claimed, ready = !got && prog >= n && e['live'] == true;
                final x = 15 + w * (n / target).clamp(0.0, 1.0);
                return Positioned(
                  left: x - 15,
                  top: 0,
                  child: Column(children: [
                    AnimatedBuilder(
                      animation: anim,
                      builder: (_, child) => Transform.rotate(angle: ready ? 0.14 * sin(anim.value * 2 * pi * 6) : 0, child: child),
                      child: GestureDetector(
                        onTap: ready && busy == null ? () => _claim(e) : null,
                        child: Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: ready ? Color.lerp(c, const Color(0xFF1B2254), 0.6) : const Color(0xFF1B2254),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: ready ? const Color(0xFFFFD166) : Colors.white24, width: 2),
                            boxShadow: [if (ready) const BoxShadow(color: Color(0x99FFD166), blurRadius: 12)],
                          ),
                          child: Opacity(opacity: got ? 0.6 : 1, child: Text(got ? '✓' : (ready ? '🎁' : '🔒'), style: const TextStyle(fontSize: 14))),
                        ),
                      ),
                    ),
                  ]),
                );
              }),
            for (var i = 0; i < steps.length; i++)
              Positioned(
                left: (15 + w * (_n(steps[i], 'n') / target).clamp(0.0, 1.0)) - (i == steps.length - 1 ? 90 : 40),
                width: 80,
                top: 34,
                child: Text('${_n(steps[i], 'n')} · ${reward(steps[i])}',
                    textAlign: i == steps.length - 1 ? TextAlign.right : TextAlign.center,
                    style: const TextStyle(fontSize: 10.5, color: Colors.white60, fontWeight: FontWeight.w800)),
              ),
          ]),
        );
      }),
    ]);
  }

  /// À venir : boîte « ? » qui tremble, sans nom ni contenu
  Widget _mystery(Map<String, dynamic> e) {
    final c = _color(e['color'] as String?);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(colors: [Color.lerp(c, const Color(0xFF0B1036), 0.55)!, const Color(0xFF0E1340)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: Border.all(color: c.withOpacity(0.5), width: 1.5),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        AnimatedBuilder(
          animation: anim,
          builder: (_, child) {
            final p = (anim.value * 2.6) % 1;
            return Transform.rotate(angle: p > 0.85 ? 0.18 * sin((p - 0.85) / 0.15 * pi * 4) : 0, child: child);
          },
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24, width: 2)),
            child: Text('?', style: pixelStyle(size: 16, color: Colors.white, shadow: false)),
          ),
        ),
        const SizedBox(height: 6),
        Text(t('Événement mystère', 'Mystery event'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
        const SizedBox(height: 2),
        Text(_chrono(e), style: pixelStyle(size: 7.5, color: const Color(0xFFFFD166), shadow: false)),
      ]),
    );
  }

  /// Compte à rebours jusqu'au début : « 5 j 04:12:33 »
  String _chrono(Map<String, dynamic> e) {
    final start = _date(e, 'starts_at');
    if (start == null) return '';
    var d = start.difference(DateTime.now().add(_skew));
    if (d.isNegative) d = Duration.zero;
    String two(int v) => v.toString().padLeft(2, '0');
    final hms = '${two(d.inHours % 24)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    return d.inDays > 0 ? t('${d.inDays} j $hms', '${d.inDays} d $hms') : hms;
  }

  /// Terminé : une ligne
  Widget _ended(Map<String, dynamic> e) {
    final got = e['got'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Text(e['icon'] as String? ?? '🎉', style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: _title(e), style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xBFFFFFFF))),
              if (got && _hasGift(e)) TextSpan(text: t(' · récupéré', ' · claimed')),
            ]),
            style: const TextStyle(fontSize: 12.5, color: Colors.white54),
          ),
        ),
        // reste 3 jours dans « Terminés », puis disparaît
        if (_date(e, 'ends_at') != null)
          Builder(builder: (_) {
            final gone = _date(e, 'ends_at')!.add(const Duration(days: 3)).difference(DateTime.now());
            return Text(t('encore ${_span(gone)}', '${_span(gone)} left'), style: const TextStyle(fontSize: 10.5, color: Colors.white38, fontWeight: FontWeight.w800));
          }),
      ]),
    );
  }
}

/// Décor de l'affiche : petits émojis animés selon un mouvement
class _Decor extends StatelessWidget {
  final String decor, fx;
  final Animation<double> anim;
  const _Decor({required this.decor, required this.fx, required this.anim});

  @override
  Widget build(BuildContext context) {
    final color = decor == '▦' ? const Color(0xFFFF4FD8) : null;
    Widget emo(double size, double op) =>
        Opacity(opacity: op.clamp(0.0, 1.0), child: Text(decor, style: TextStyle(fontSize: size, color: color, fontWeight: FontWeight.w900)));
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) => LayoutBuilder(builder: (_, box) {
        final w = box.maxWidth, h = box.maxHeight, v = anim.value;
        final items = <Widget>[];
        switch (fx) {
          case 'fall': // flocons, feuilles, confettis qui tombent en se balançant
            for (var k = 0; k < 9; k++) {
              final p = (v * (1.6 + (k % 3) * 0.4) + k * 0.13) % 1;
              items.add(Positioned(
                left: w * ((k * 0.117 + 0.04) % 1) + 10 * sin((p + k) * 2 * pi),
                top: p * (h + 30) - 24,
                child: emo(k.isEven ? 15 : 11, 0.75),
              ));
            }
          case 'rise': // bulles, ballons, étincelles qui montent
            for (var k = 0; k < 8; k++) {
              final p = (v * (1.3 + (k % 3) * 0.3) + k * 0.17) % 1;
              items.add(Positioned(
                left: w * ((k * 0.131 + 0.06) % 1) + 8 * sin((p * 3 + k) * pi),
                top: h - p * (h + 30),
                child: emo(k.isEven ? 15 : 11, 0.85 - p * 0.6),
              ));
            }
          case 'rain': // déluge de petits émojis
            for (var k = 0; k < 16; k++) {
              final p = (v * (3.0 + (k % 4) * 0.5) + k * 0.07) % 1;
              items.add(Positioned(left: w * ((k * 0.0631 + 0.02) % 1), top: p * (h + 24) - 20, child: emo(k % 3 == 0 ? 13 : 10, 0.7)));
            }
          case 'fireworks': // éclats qui explosent de temps en temps
            for (var b = 0; b < 3; b++) {
              final p = (v * 2.2 + b * 0.33) % 1;
              final cx = w * (0.2 + 0.3 * b), cy = h * (0.25 + 0.15 * (b % 2));
              for (var k = 0; k < 8; k++) {
                final a = k * pi / 4, d = 46 * Curves.easeOut.transform(p);
                items.add(Positioned(left: cx + cos(a) * d - 7, top: cy + sin(a) * d - 7 + 14 * p * p, child: emo(12, 1 - p)));
              }
            }
          default: // traverse en diagonale
            for (var k = 0; k < 4; k++) {
              final p = (v + k * 0.27) % 1;
              items.add(Positioned(left: p * (w + 60) - 40, top: h * (0.12 + 0.18 * k) - p * 30, child: emo(k.isEven ? 16 : 12, 0.7)));
            }
        }
        return Stack(clipBehavior: Clip.hardEdge, children: items);
      }),
    );
  }
}
