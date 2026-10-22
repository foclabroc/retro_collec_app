import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio.dart';
import 'cards.dart';
import 'connect4.dart';
import 'duel_watch.dart';
import 'game.dart';
import 'layout.dart';
import 'live_link.dart';
import 'main.dart';
import 'retro_theme.dart';
import 'rewards.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Tournois (22/10) : créés par l'admin (AdminTourPage), inscriptions dans la
// Salle de jeux (TourTile → TourListPage / TourPage), matchs en direct.
//  · serveur : sql/2026-10-22_tournois.sql (rc_tour_*, horloge rc__tour_tick)
//  · mon match : rc_duel_ping renvoie 'tour' → TourWatch.handle (fenêtre
//    « Ton match commence », puis ouverture automatique de chaque partie)
//  · temps réel : événement 'tour' (LiveEvents) → Tours.ping (pages ouvertes)
// ═══════════════════════════════════════════════════════════════════════════

int _n(dynamic v, [int d = 0]) => (v as num?)?.toInt() ?? d;

String tourGameName(String? g) => g == 'bs' ? 'Console Wars' : t('4 en ligne', 'Connect 4');
String tourGameIcon(String? g) => g == 'bs' ? '🚢' : '🔴';

/// Heure locale « sam. 25/10 à 21:00 »
String tourDate(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '';
  const fr = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
  const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  String two(int x) => x.toString().padLeft(2, '0');
  return t('${fr[d.weekday - 1]} ${two(d.day)}/${two(d.month)} à ${two(d.hour)}:${two(d.minute)}',
      '${en[d.weekday - 1]} ${two(d.day)}/${two(d.month)} at ${two(d.hour)}:${two(d.minute)}');
}

/// « 1 j 03 h 42 », « 12:05 »
String tourLeft(Duration d) {
  if (d.isNegative) return '0:00';
  String two(int x) => x.toString().padLeft(2, '0');
  if (d.inDays > 0) return '${d.inDays} ${t('j', 'd')} ${two(d.inHours % 24)} h ${two(d.inMinutes % 60)}';
  if (d.inHours > 0) return '${d.inHours} h ${two(d.inMinutes % 60)}';
  return '${d.inMinutes}:${two(d.inSeconds % 60)}';
}

/// Écart entre l'horloge du serveur et la nôtre (champ 'now' des réponses)
Duration _skew(Map m) {
  final now = DateTime.tryParse(m['now'] as String? ?? '');
  return now == null ? Duration.zero : DateTime.now().difference(now);
}

DateTime? _at(Map m, String k) {
  final d = DateTime.tryParse(m[k] as String? ?? '');
  return d?.add(_skew(m));
}

// ─── État partagé : un tournoi a bougé ─────────────────────────────────────
class Tours {
  Tours._();

  /// Incrémenté à chaque événement temps réel 'tour'
  static final ping = ValueNotifier<int>(0);
}

// ─── Mon match (rc_duel_ping → 'tour') ─────────────────────────────────────
class TourWatch {
  TourWatch._();
  static final _called = <int>{}; // matchs déjà annoncés
  static final _opened = <int>{}; // parties déjà ouvertes automatiquement
  static final _soon = <int>{}; // rappels « commence bientôt » déjà montrés
  static bool _showing = false;
  static Map<String, dynamic>? current; // dernier état connu de mon match

  /// Mon match de tournoi est en cours ou va commencer : pas de défi par-dessus
  static bool get busy => current != null && (current!['status'] == 'wait' || current!['status'] == 'play');

  static void handle(dynamic x) {
    current = x is Map ? Map<String, dynamic>.from(x) : null;
    final m = current;
    if (m == null) return;
    final tid = _n(m['tid']);
    // rappel : mon tournoi commence dans moins de 10 min
    if (m['soon'] != null) {
      if (_soon.add(tid)) {
        RcAudio.sfx('logo');
        rcMessenger.currentState
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            backgroundColor: const Color(0xFF3C3489),
            duration: const Duration(seconds: 8),
            content: Text(t('🏆 Le tournoi « ${m['name']} » commence dans ${_soonMin(m)} min : reste connecté !',
                '🏆 The "${m['name']}" tournament starts in ${_soonMin(m)} min: stay online!')),
            action: SnackBarAction(label: t('Voir', 'See'), textColor: const Color(0xFFFFD166), onPressed: () => _openTour(tid)),
          ));
      }
      return;
    }
    // tournoi fini, je suis sur le podium : félicitations (une fois par tournoi)
    if (m['done'] == true) {
      _congrats(m);
      return;
    }
    final mid = _n(m['mid']);
    if (m['status'] == 'wait' && m['ready'] != true) {
      if (!_called.contains(mid)) _call(m);
      return;
    }
    final gid = _n(m['gid']);
    if (m['status'] == 'play' && gid > 0 && !_opened.contains(gid) && DuelWatch.i.inGame == 0 && !_showing) {
      _opened.add(gid);
      _openGame(m['game'] as String? ?? 'c4', gid);
    }
  }

  static bool _congratsBusy = false;

  static Future<void> _congrats(Map<String, dynamic> m) async {
    if (_congratsBusy || _showing || DuelWatch.i.inGame > 0) return;
    final c = _ctx;
    if (c == null) return;
    _congratsBusy = true;
    try {
      final tid = _n(m['tid']);
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getStringList('rc_tour_done') ?? [];
      if (seen.contains('$tid')) return;
      await prefs.setStringList('rc_tour_done', [...seen.length > 20 ? seen.sublist(seen.length - 20) : seen, '$tid']);
      Game.i.sync();
      final c2 = _ctx;
      if (c2 == null) return;
      final place = _n(m['place']);
      final pot = _n(m['pot']);
      final parts = [if (rewardText(m['reward']).isNotEmpty) rewardText(m['reward']), if (pot > 0) '$pot 🪙 ${t('de cagnotte', 'from the pot')}'];
      final hasPack = (m['reward'] is Map) && (m['reward'] as Map)['packs'] is Map && ((m['reward'] as Map)['packs'] as Map).isNotEmpty;
      if (place == 1) RcAudio.win(); else RcAudio.sfx('powerup');
      await showDialog<void>(
        context: c2,
        builder: (ctx) => AlertDialog(
          title: Text(
              px(place == 1 ? t('🏆 CHAMPION !', '🏆 CHAMPION!') : place == 2 ? t('🥈 FINALISTE', '🥈 RUNNER-UP') : t('🥉 DEMI-FINALE', '🥉 SEMI-FINAL')),
              style: pixelStyle(size: 13)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                place == 1
                    ? t('Tu as gagné le tournoi « ${m['name']} » !', 'You won the "${m['name']}" tournament!')
                    : place == 2
                        ? t('Tu termines 2e du tournoi « ${m['name']} ».', 'You finished 2nd in "${m['name']}".')
                        : t('Tu as atteint les demi-finales du tournoi « ${m['name']} ».', 'You reached the semi-finals of "${m['name']}".'),
                style: const TextStyle(fontWeight: FontWeight.w800)),
            if (parts.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(t('Tes lots : ${parts.join(' + ')}', 'Your prizes: ${parts.join(' + ')}'), style: const TextStyle(color: Color(0xFFFFD166))),
            ],
            if (hasPack) ...[
              const SizedBox(height: 6),
              Text(t('Les boosters t\'attendent dans Paquets → Cadeaux reçus.', 'Your boosters are waiting in Packs → Gifts received.'),
                  style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
            ],
            if (place == 1) ...[
              const SizedBox(height: 6),
              Text(t('Trophée « Champion » à récupérer dans ton profil.', '"Champion" trophy to claim in your profile.'), style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
            ],
          ]),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _openTour(tid);
              },
              child: Text(t('Voir le podium', 'See the podium')),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    } finally {
      _congratsBusy = false;
    }
  }

  static int _soonMin(Map m) {
    final d = _at(m, 'soon')?.difference(DateTime.now()).inMinutes ?? 10;
    return d < 1 ? 1 : d;
  }

  static BuildContext? get _ctx {
    final c = HomeShellState.current?.context;
    return c != null && c.mounted ? c : null;
  }

  static void _openTour(int tid) {
    final c = _ctx;
    if (c == null) return;
    Navigator.of(c).push(MaterialPageRoute(builder: (_) => TourPage(id: tid)));
  }

  static Future<void> _openGame(String game, int gid) async {
    final c = _ctx;
    if (c == null) return;
    try {
      final g = game == 'bs' ? await RcServer.bsState(gid) : await RcServer.c4State(gid);
      final c2 = _ctx;
      if (c2 == null || g['status'] != 'playing' || DuelWatch.i.inGame > 0) return;
      RcAudio.sfx('powerup');
      await Navigator.of(c2).push(MaterialPageRoute(builder: (_) => (game == 'bs' ? kBsDuel : kC4Duel).page(g)));
      Game.i.sync();
    } catch (_) {}
    DuelWatch.i.refresh(); // manche suivante déjà prête ?
  }

  /// « Ton match commence ! » : Jouer (je suis là) ou plus tard (avant le forfait)
  static Future<void> _call(Map<String, dynamic> m) async {
    if (_showing || DuelWatch.i.inGame > 0) return;
    final c = _ctx;
    if (c == null) return;
    final mid = _n(m['mid']);
    _called.add(mid);
    _showing = true;
    RcAudio.sfx('logo');
    final go = await showGeneralDialog<bool>(
      context: c,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.6),
      transitionDuration: const Duration(milliseconds: 380),
      transitionBuilder: (_, a, __, child) => SlideTransition(
        position: Tween(begin: const Offset(0, -0.6), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
        child: FadeTransition(opacity: a, child: child),
      ),
      pageBuilder: (_, __, ___) => _MatchCall(m: m),
    );
    _showing = false;
    if (go == true) {
      await ready(mid);
    } else if (go == false) {
      _openTour(_n(m['tid']));
    }
  }

  /// Je suis là : la partie démarre dès que l'adversaire l'est aussi (ouverture auto)
  static Future<void> ready(int mid, {bool openPage = true}) async {
    try {
      final r = await RcServer.tourReady(mid);
      final match = r['match'] as Map? ?? const {};
      if (match['status'] == 'done') {
        toast(match['won'] == true ? t('🏆 Ton adversaire ne s\'est pas présenté : tu passes !', '🏆 Your opponent didn\'t show up: you go through!')
            : t('Trop tard : forfait', 'Too late: forfeit'));
        return;
      }
      handle(r.isEmpty ? null : r);
      if (r['status'] == 'wait') {
        toast(t('C\'est noté ! La partie démarre dès que ton adversaire est là.', 'Got it! The game starts as soon as your opponent is here.'));
        if (openPage) _openTour(_n(r['tid']));
      }
    } catch (e) {
      RcAudio.wrong();
      toast(errText(e));
    }
  }
}

/// Fenêtre « Ton match de tournoi commence »
class _MatchCall extends StatefulWidget {
  final Map<String, dynamic> m;
  const _MatchCall({required this.m});
  @override
  State<_MatchCall> createState() => _MatchCallState();
}

class _MatchCallState extends State<_MatchCall> {
  Timer? _tick;
  late final DateTime _end = _at(widget.m, 'deadline') ?? DateTime.now().add(const Duration(minutes: 3));

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final left = _end.difference(DateTime.now()).inSeconds;
      final cur = TourWatch.current;
      if (left <= 0 || cur == null || _n(cur['mid']) != _n(widget.m['mid']) || cur['status'] != 'wait') {
        Navigator.of(context).pop();
        return;
      }
      if (left <= 10) RcAudio.tick();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final opp = m['opp'] as Map? ?? const {};
    final left = _end.difference(DateTime.now()).inSeconds.clamp(0, 180);
    final rounds = _n(m['rounds'], 1), round = _n(m['round'], 1);
    final final_ = round == rounds;
    final stage = final_ ? t('FINALE', 'FINAL') : round == rounds - 1 ? t('DEMI-FINALE', 'SEMI-FINAL') : round == rounds - 2 ? t('QUART DE FINALE', 'QUARTER-FINAL') : t('TOUR $round', 'ROUND $round');
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 360,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF3A2A06), Color(0xFF141A4C)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: kGold, width: 2),
              boxShadow: [BoxShadow(color: kGold.withOpacity(0.45), blurRadius: 40, spreadRadius: -6)],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(8)),
                child: Text(px('🏆 $stage'), style: pixelStyle(size: 8, color: const Color(0xFF1A1000), shadow: false)),
              ),
              const SizedBox(height: 8),
              Text(m['name'] as String? ?? '', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFFFFD166))),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                avatarWidget(Game.i.avatar, size: 58),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('VS', style: pixelStyle(size: 13, color: kGold, shadow: false))),
                avatarWidget(_n(opp['avatar']), size: 58),
              ]),
              const SizedBox(height: 8),
              Text(t('Ton match contre ${opp['name'] ?? '?'} commence !', 'Your match against ${opp['name'] ?? '?'} is starting!'),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(
                  '${tourGameIcon(m['game'] as String?)} ${tourGameName(m['game'] as String?)} · ${final_ ? t('2 manches gagnantes', 'best of 3') : t('1 manche', 'single game')}'
                  '${m['opp_ready'] == true ? t(' · il est prêt !', ' · they\'re ready!') : ''}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: m['opp_ready'] == true ? const Color(0xFF5DCAA5) : Colors.white60)),
              const SizedBox(height: 12),
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(child: CircularProgressIndicator(value: left / 180, strokeWidth: 5, color: kGold, backgroundColor: Colors.white12)),
                  Text('${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}', style: pixelStyle(size: 10, color: Colors.white, shadow: false)),
                ]),
              ),
              const SizedBox(height: 4),
              Text(t('Absent à la fin du temps = forfait', 'Not there when time runs out = forfeit'), style: const TextStyle(fontSize: 11.5, color: Colors.white38)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF1A1000), padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(t('⚔ Jouer', '⚔ Play'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(t('Voir l\'arbre d\'abord', 'See the bracket first'), style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── Case de la Salle de jeux ──────────────────────────────────────────────
class TourTile extends StatefulWidget {
  const TourTile({super.key});
  @override
  State<TourTile> createState() => _TourTileState();
}

class _TourTileState extends State<TourTile> {
  List<Map<String, dynamic>> list = [];
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
    Tours.ping.addListener(_load);
  }

  @override
  void dispose() {
    Tours.ping.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final l = await RcServer.tourList();
      if (mounted) setState(() {
        list = l;
        loaded = true;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final active = list.where((x) => x['status'] == 'open' || x['status'] == 'running').toList();
    final top = active.isNotEmpty ? active.first : (list.isNotEmpty ? list.first : null);
    final running = top?['status'] == 'running';
    String sub;
    if (top == null) {
      sub = loaded ? t('Aucun tournoi prévu pour l\'instant', 'No tournament planned yet') : '…';
    } else if (running) {
      sub = t('En cours · ${top['name']}', 'Live · ${top['name']}');
    } else if (top['status'] == 'open') {
      sub = '${top['name']} · ${tourDate(top['start_at'] as String?)} · ${tourGameName(top['game'] as String?)}';
    } else {
      final w = top['winner'] as Map?;
      sub = w != null ? t('Dernier : ${top['name']}, gagné par ${w['name']}', 'Last: ${top['name']}, won by ${w['name']}') : t('Dernier : ${top['name']}', 'Last: ${top['name']}');
    }
    final hot = active.isNotEmpty;
    return Material(
      color: kPanel,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => active.length == 1 ? TourPage(id: _n(active.first['id'])) : const TourListPage()));
          _load();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: hot ? kGold : Colors.white12),
            gradient: LinearGradient(colors: [kGold.withOpacity(hot ? 0.18 : 0.06), Colors.transparent]),
          ),
          child: Row(children: [
            const Text('🏆', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(px(t('TOURNOI', 'TOURNAMENT')), style: pixelStyle(size: 10, color: hot ? kGold : Colors.white70, shadow: false)),
                const SizedBox(height: 4),
                Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: hot ? Colors.white : Colors.white54)),
              ]),
            ),
            if (top != null && top['status'] == 'open')
              _Pill('${_n(top['n'])}/${_n(top['size'])}', kGold, dark: true)
            else if (running)
              const _Pill('● LIVE', Color(0xFFE24B4A)),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ]),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  final bool dark;
  const _Pill(this.text, this.color, {this.dark = false});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(9)),
        child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: dark ? const Color(0xFF1A1000) : Colors.white)),
      );
}

// ─── Liste des tournois ────────────────────────────────────────────────────
class TourListPage extends StatefulWidget {
  const TourListPage({super.key});
  @override
  State<TourListPage> createState() => _TourListPageState();
}

class _TourListPageState extends State<TourListPage> {
  List<Map<String, dynamic>>? list;

  @override
  void initState() {
    super.initState();
    _load();
    Tours.ping.addListener(_load);
  }

  @override
  void dispose() {
    Tours.ping.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final l = await RcServer.tourList();
      if (mounted) setState(() => list = l);
    } catch (e) {
      if (mounted && list == null) setState(() => list = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = list;
    return MaxWidth(
      child: Scaffold(
        appBar: AppBar(title: Text(t('Tournois', 'Tournaments'))),
        body: l == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
                  if (l.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 60),
                      child: Text(t('Aucun tournoi pour l\'instant.\nSurveille l\'Actu : les prochains y sont annoncés !', 'No tournament yet.\nWatch the News: new ones are announced there!'),
                          textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
                    ),
                  for (final x in l) ...[TourCard(x, onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TourPage(id: _n(x['id']))));
                    _load();
                  }), const SizedBox(height: 10)],
                ]),
              ),
      ),
    );
  }
}

/// Résumé d'un tournoi (liste, admin)
class TourCard extends StatelessWidget {
  final Map<String, dynamic> x;
  final VoidCallback? onTap;
  final Widget? trailing;
  const TourCard(this.x, {super.key, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final st = x['status'] as String? ?? '';
    final (label, col) = switch (st) {
      'open' => (t('INSCRIPTIONS', 'SIGN-UP'), kGold),
      'running' => (t('● EN DIRECT', '● LIVE'), const Color(0xFFE24B4A)),
      'done' => (t('TERMINÉ', 'OVER'), const Color(0xFF5DCAA5)),
      _ => (t('ANNULÉ', 'CANCELLED'), Colors.white38),
    };
    final w = x['winner'] as Map?;
    return Material(
      color: kPanel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: st == 'open' || st == 'running' ? col : Colors.white12)),
          child: Row(children: [
            Text(tourGameIcon(x['game'] as String?), style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(x['name'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
                  if (x['mine'] == true) const _Pill('✓', Color(0xFF2FBF8A)),
                ]),
                const SizedBox(height: 2),
                Text(
                    st == 'done' && w != null
                        ? t('🥇 ${w['name']} · ${tourGameName(x['game'] as String?)}', '🥇 ${w['name']} · ${tourGameName(x['game'] as String?)}')
                        : '${tourGameName(x['game'] as String?)} · ${_n(x['n'])}/${_n(x['size'])} · ${tourDate(x['start_at'] as String?)}',
                    style: const TextStyle(fontSize: 12, color: Colors.white60)),
              ]),
            ),
            _Pill(label, col, dark: st == 'open'),
            if (trailing != null) trailing!,
          ]),
        ),
      ),
    );
  }
}

// ─── Page d'un tournoi : fiche, inscription, arbre ─────────────────────────
class TourPage extends StatefulWidget {
  final int id;
  const TourPage({super.key, required this.id});
  @override
  State<TourPage> createState() => _TourPageState();
}

class _TourPageState extends State<TourPage> {
  Map<String, dynamic>? x;
  bool busy = false;
  String? error;
  Timer? _tick, _poll;

  @override
  void initState() {
    super.initState();
    _load();
    Tours.ping.addListener(_load);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final s = x?['status'];
      // compte à rebours ; recharge quand le début ou un forfait arrive
      if (s == 'open') {
        final st = _at(x!, 'start_at');
        if (st != null && DateTime.now().isAfter(st.add(const Duration(seconds: 2))) && DateTime.now().second % 5 == 0) _load();
      }
      if (s == 'open' || s == 'running') setState(() {});
    });
    // secours sans temps réel
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!LiveLink.i.connected && (x?['status'] == 'open' || x?['status'] == 'running')) _load();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _poll?.cancel();
    Tours.ping.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await RcServer.tourGet(widget.id);
      if (mounted) setState(() {
        x = r;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = errText(e));
    }
  }

  Future<void> _join(bool join) async {
    final v = x;
    if (v == null || busy) return;
    final fee = _n(v['fee']);
    if (join && fee > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('S\'inscrire ?', 'Sign up?')),
          content: Text(t('L\'inscription coûte $fee pièces. Elles vont dans la cagnotte du vainqueur, et te sont rendues si tu te désinscris avant le début ou si le tournoi est annulé.',
              'Entry costs $fee coins. They go to the winner\'s pot, and are refunded if you leave before the start or if the tournament is cancelled.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Annuler', 'Cancel'))),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Payer $fee 🪙', 'Pay $fee 🪙'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => busy = true);
    try {
      final r = join ? await RcServer.tourJoin(widget.id) : await RcServer.tourLeave(widget.id);
      Game.i.sync();
      if (join) RcAudio.sfx('powerup');
      toast(join ? t('Inscrit ! Sois connecté à l\'heure du début.', 'Signed up! Be online at start time.') : t('Désinscrit', 'Left the tournament'));
      if (mounted) setState(() => x = r);
    } catch (e) {
      RcAudio.wrong();
      toast(errText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final v = x;
    return MaxWidth(
      child: Scaffold(
        appBar: AppBar(
          title: Text(v?['name'] as String? ?? t('Tournoi', 'Tournament'), maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [ListenableBuilder(listenable: Game.i, builder: (_, __) => CoinChip(Game.i.coins)), const SizedBox(width: 12)],
        ),
        body: v == null
            ? Center(child: error != null ? Text(error!, style: const TextStyle(color: Colors.white54)) : const CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.fromLTRB(14, 10, 14, 28), children: [
                  _head(v),
                  const SizedBox(height: 10),
                  if (v['status'] == 'running') ...[_myMatch(v), Bracket(tour: v), const SizedBox(height: 10)],
                  if (v['status'] == 'done') ...[_podium(v), const SizedBox(height: 10), Bracket(tour: v), const SizedBox(height: 10)],
                  _lots(v),
                  const SizedBox(height: 10),
                  if (v['status'] == 'open') _players(v),
                  if (v['status'] == 'open') _rules(),
                ]),
              ),
      ),
    );
  }

  Widget _panel(Widget child, {Color? border}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(14), border: Border.all(color: border ?? Colors.white12)),
        child: child,
      );

  Widget _head(Map<String, dynamic> v) {
    final st = v['status'];
    final start = _at(v, 'start_at');
    final left = start?.difference(DateTime.now());
    final rounds = _n(v['rounds']), round = _n(v['round']);
    String line;
    if (st == 'open') {
      line = left != null && !left.isNegative ? t('Début dans ${tourLeft(left)}', 'Starts in ${tourLeft(left)}') : t('Ça commence…', 'Starting…');
    } else if (st == 'running') {
      line = round >= rounds
          ? t('Finale en cours', 'Final in progress')
          : round == rounds - 1
              ? t('Demi-finales en cours', 'Semi-finals in progress')
              : t('Tour $round sur $rounds', 'Round $round of $rounds');
    } else if (st == 'done') {
      line = t('Terminé', 'Over');
    } else {
      line = t('Annulé : mises rendues', 'Cancelled: fees refunded');
    }
    return _panel(
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(tourGameIcon(v['game'] as String?), style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
          Expanded(child: Text(px(v['name'] as String? ?? ''), style: pixelStyle(size: 10, color: kGold, shadow: false))),
        ]),
        const SizedBox(height: 8),
        Text('${tourGameName(v['game'] as String?)} · ${_n(v['size'])} ${t('places', 'spots')} · ${tourDate(v['start_at'] as String?)}',
            style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
        const SizedBox(height: 4),
        Text(line, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: st == 'running' ? const Color(0xFFFF8A95) : Colors.white)),
        if (st == 'open') ...[
          const SizedBox(height: 10),
          if (v['mine'] == true) ...[
            Row(children: [
              const Icon(Icons.check_circle, color: Color(0xFF2FBF8A), size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(t('Tu es inscrit · sois connecté à l\'heure !', 'You\'re in · be online on time!'), style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF5DCAA5)))),
              TextButton(onPressed: busy ? null : () => _join(false), child: Text(t('Se désinscrire', 'Leave'), style: const TextStyle(color: Colors.white54))),
            ]),
          ] else
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF1A1000), padding: const EdgeInsets.symmetric(vertical: 13)),
                onPressed: busy || _n(v['n']) >= _n(v['size']) ? null : () => _join(true),
                child: Text(
                    _n(v['n']) >= _n(v['size'])
                        ? t('Complet', 'Full')
                        : _n(v['fee']) > 0
                            ? t('S\'inscrire · ${_n(v['fee'])} 🪙', 'Sign up · ${_n(v['fee'])} 🪙')
                            : t('S\'inscrire · gratuit', 'Sign up · free'),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              ),
            ),
        ],
      ]),
      border: st == 'open' || st == 'running' ? kGold : null,
    );
  }

  /// Mon match en cours : adversaire, compte à rebours, Jouer / Reprendre
  Widget _myMatch(Map<String, dynamic> v) {
    final me = v['me'] as String?;
    Map? mine;
    for (final m in (v['matches'] as List? ?? const [])) {
      if (m is Map && m['mine'] == true && m['status'] != 'done') mine = m;
    }
    if (mine == null) {
      // éliminé ou en attente du tour suivant
      final out = (v['matches'] as List? ?? const []).any((m) => m is Map && m['mine'] == true && m['status'] == 'done' && m['winner'] != me);
      final inTour = (v['players'] as List? ?? const []).any((p) => p is Map && p['pid'] == me);
      if (!inTour) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _panel(Text(out ? t('Tu es éliminé · regarde la suite en direct 👁', 'You\'re out · watch the rest live 👁') : t('Qualifié ! Ton prochain match commence dès la fin de ce tour.', 'Through! Your next match starts when this round ends.'),
            style: TextStyle(fontWeight: FontWeight.w800, color: out ? Colors.white60 : const Color(0xFF5DCAA5)))),
      );
    }
    final m = mine;
    final p1 = m['p1'] as Map? ?? const {}, p2 = m['p2'] as Map? ?? const {};
    final iAmP1 = p1['pid'] == me;
    final opp = iAmP1 ? p2 : p1;
    final myReady = iAmP1 ? m['ready1'] == true : m['ready2'] == true;
    final oppReady = iAmP1 ? m['ready2'] == true : m['ready1'] == true;
    final dl = DateTime.tryParse(m['deadline'] as String? ?? '')?.add(_skew(v));
    final left = dl?.difference(DateTime.now());
    final best = _n(m['best'], 1);
    final myW = iAmP1 ? _n(m['w1']) : _n(m['w2']), oppW = iAmP1 ? _n(m['w2']) : _n(m['w1']);
    final playing = m['status'] == 'play';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _panel(
        Column(children: [
          Text(px(t('TON MATCH', 'YOUR MATCH')), style: pixelStyle(size: 8, color: const Color(0xFF6CB4FF), shadow: false)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            avatarWidget(Game.i.avatar, size: 44),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(best > 1 ? '$myW - $oppW' : 'VS', style: pixelStyle(size: 12, color: kGold, shadow: false)),
            ),
            avatarWidget(_n(opp['avatar']), size: 44),
          ]),
          const SizedBox(height: 6),
          Text(t('contre ${opp['name'] ?? '?'}', 'against ${opp['name'] ?? '?'}'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          if (best > 1) Text(t('Finale en 2 manches gagnantes', 'Final, best of 3'), style: const TextStyle(fontSize: 12, color: Colors.white60)),
          const SizedBox(height: 4),
          if (!playing)
            Text(
                myReady
                    ? (oppReady ? t('Les deux sont prêts…', 'Both ready…') : t('Tu es prêt · on attend ${opp['name'] ?? '?'} (forfait dans ${tourLeft(left ?? Duration.zero)})', 'You\'re ready · waiting for ${opp['name'] ?? '?'} (forfeit in ${tourLeft(left ?? Duration.zero)})'))
                    : t('Forfait dans ${tourLeft(left ?? Duration.zero)}${oppReady ? ' · il est prêt !' : ''}', 'Forfeit in ${tourLeft(left ?? Duration.zero)}${oppReady ? ' · they\'re ready!' : ''}'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: myReady ? const Color(0xFF5DCAA5) : const Color(0xFFFFB3B2), fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (!myReady && !playing)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF1A1000), padding: const EdgeInsets.symmetric(vertical: 13)),
                onPressed: () async {
                  await TourWatch.ready(_n(m['id']), openPage: false);
                  _load();
                },
                child: Text(t('⚔ Jouer', '⚔ Play'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              ),
            ),
          if (playing && _n(m['game_id']) > 0)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF1A1000), padding: const EdgeInsets.symmetric(vertical: 13)),
                onPressed: () => TourWatch._openGame(v['game'] as String? ?? 'c4', _n(m['game_id'])),
                child: Text(t('▶ Reprendre ma partie', '▶ Back to my game'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              ),
            ),
        ]),
        border: const Color(0xFF6CB4FF),
      ),
    );
  }

  Widget _podium(Map<String, dynamic> v) {
    final players = [for (final p in (v['players'] as List? ?? const [])) if (p is Map) p];
    Map? at(int place) => players.where((p) => _n(p['place']) == place).firstOrNull;
    final semis = players.where((p) => _n(p['place']) == 3).toList();
    final w = at(1), s = at(2);
    Widget step(Map? p, String rank, double h, Color c, {double av = 40, List<Map>? many}) => SizedBox(
          width: 96,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (many != null && many.isNotEmpty)
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (final q in many) Padding(padding: const EdgeInsets.all(1), child: avatarWidget(_n(q['avatar']), size: 30))])
            else if (p != null)
              avatarWidget(_n(p['avatar']), size: av),
            const SizedBox(height: 4),
            Text(many != null ? many.map((q) => q['name']).join(' · ') : p?['name'] as String? ?? '—',
                maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Container(
              height: h,
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(color: c, borderRadius: const BorderRadius.vertical(top: Radius.circular(8))),
              child: Text(rank, style: pixelStyle(size: 13, color: const Color(0xFF1A1000), shadow: false)),
            ),
          ]),
        );
    return _panel(
      Column(children: [
        Text(px(t('VAINQUEUR', 'WINNER')), style: pixelStyle(size: 9, color: kGold, shadow: false)),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          step(s, '2', 56, const Color(0xFFC8CCD4)),
          const SizedBox(width: 6),
          step(w, '1', 86, kGold, av: 54),
          const SizedBox(width: 6),
          if (semis.isNotEmpty) step(null, '3', 38, const Color(0xFFC98A5A), many: semis),
        ]),
        if (_n(v['pot']) > 0) ...[
          const SizedBox(height: 8),
          Text(t('Cagnotte : ${_n(v['pot'])} 🪙', 'Pot: ${_n(v['pot'])} 🪙'), style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      ]),
      border: kGold,
    );
  }

  Widget _lots(Map<String, dynamic> v) {
    final lots = v['lots'] is Map ? Map<String, dynamic>.from(v['lots'] as Map) : <String, dynamic>{};
    final pot = _n(v['pot']), fee = _n(v['fee']), split = _n(v['split'], 100);
    String potPart(int place) {
      if (fee <= 0) return '';
      if (place == 1) return split >= 100 ? t('cagnotte', 'pot') : t('70 % de la cagnotte', '70% of the pot');
      if (place == 2 && split < 100) return t('30 % de la cagnotte', '30% of the pot');
      return '';
    }

    Widget row(String icon, String who, int place) {
      final parts = [
        if (lots['$place'] != null && rewardText(lots['$place']).isNotEmpty) rewardText(lots['$place']),
        if (potPart(place).isNotEmpty) potPart(place),
      ];
      if (parts.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text('$icon $who', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
          Expanded(child: Text(parts.join(' + '), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, color: Colors.white70))),
        ]),
      );
    }

    return _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(px(t('LOTS', 'PRIZES')), style: pixelStyle(size: 8, color: Colors.white70, shadow: false)),
      const SizedBox(height: 6),
      row('🥇', t('1er', '1st'), 1),
      row('🥈', t('2e', '2nd'), 2),
      row('🥉', t('Demi-finales', 'Semi-finals'), 3),
      const SizedBox(height: 4),
      Text(
          fee > 0
              ? t('Inscription : $fee 🪙 · cagnotte actuelle : $pot 🪙', 'Entry: $fee 🪙 · current pot: $pot 🪙')
              : t('Inscription gratuite', 'Free entry'),
          style: const TextStyle(fontSize: 12, color: Colors.white54)),
      Text(t('+ trophée « Champion » pour le vainqueur', '+ "Champion" trophy for the winner'), style: const TextStyle(fontSize: 12, color: Colors.white54)),
    ]));
  }

  Widget _players(Map<String, dynamic> v) {
    final players = [for (final p in (v['players'] as List? ?? const [])) if (p is Map) p];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(px(t('INSCRITS ${players.length}/${_n(v['size'])}', 'PLAYERS ${players.length}/${_n(v['size'])}')), style: pixelStyle(size: 8, color: Colors.white70, shadow: false)),
        const SizedBox(height: 8),
        if (players.isEmpty) Text(t('Personne pour l\'instant : sois le premier !', 'Nobody yet: be the first!'), style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final p in players)
            Container(
              padding: const EdgeInsets.fromLTRB(3, 3, 9, 3),
              decoration: BoxDecoration(color: kPanel2, borderRadius: BorderRadius.circular(14)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                avatarWidget(_n(p['avatar']), size: 22),
                const SizedBox(width: 5),
                Text(p['name'] as String? ?? '?', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                if (p['online'] == true) const Padding(padding: EdgeInsets.only(left: 4), child: Text('●', style: TextStyle(fontSize: 9, color: Color(0xFF5DCAA5)))),
              ]),
            ),
        ]),
      ])),
    );
  }

  Widget _rules() => _panel(Text(
      t('Matchs en direct à élimination directe : 1 manche, finale en 2 manches gagnantes, un match nul se rejoue. '
          'Quand ton match commence, touche « Jouer » : absent au bout de 3 min = forfait. Moins de 2 inscrits : annulé et remboursé.',
          'Live knockout matches: single game, final best of 3, a draw is replayed. '
          'When your match starts, tap "Play": not there after 3 min = forfeit. Fewer than 2 players: cancelled and refunded.'),
      style: const TextStyle(fontSize: 12, color: Colors.white54)));
}

// ─── Arbre du tournoi ──────────────────────────────────────────────────────
class Bracket extends StatelessWidget {
  final Map<String, dynamic> tour;
  const Bracket({super.key, required this.tour});

  @override
  Widget build(BuildContext context) {
    final rounds = _n(tour['rounds']);
    if (rounds <= 0) return const SizedBox.shrink();
    final matches = [for (final m in (tour['matches'] as List? ?? const [])) if (m is Map) m];
    final first = 1 << (rounds - 1); // matchs du 1er tour
    const colW = 150.0, boxH = 62.0, gap = 10.0;
    final height = first * (boxH + gap);
    String title(int r) => r == rounds
        ? t('FINALE', 'FINAL')
        : r == rounds - 1
            ? t('DEMIES', 'SEMIS')
            : r == rounds - 2
                ? t('QUARTS', 'QUARTERS')
                : t('TOUR $r', 'ROUND $r');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var r = 1; r <= rounds; r++)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(
              width: colW,
              child: Column(children: [
                Text(px(title(r)), style: pixelStyle(size: 7, color: Colors.white54, shadow: false)),
                const SizedBox(height: 6),
                SizedBox(
                  height: height,
                  child: Column(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    for (var s = 0; s < (first >> (r - 1)); s++)
                      _MatchBox(
                        m: matches.where((m) => _n(m['round']) == r && _n(m['slot']) == s).firstOrNull,
                        game: tour['game'] as String? ?? 'c4',
                        height: boxH,
                      ),
                  ]),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _MatchBox extends StatelessWidget {
  final Map? m;
  final String game;
  final double height;
  const _MatchBox({required this.m, required this.game, required this.height});

  @override
  Widget build(BuildContext context) {
    final x = m;
    final live = x != null && x['status'] == 'play' && _n(x['game_id']) > 0;
    final mine = x?['mine'] == true;
    Widget line(Map? p, int w) {
      final done = x?['status'] == 'done';
      final won = done && p != null && p['pid'] == x?['winner'];
      final lost = done && p != null && !won;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Row(children: [
            if (p != null) avatarWidget(_n(p['avatar']), size: 18) else const SizedBox(width: 18),
            const SizedBox(width: 4),
            Expanded(
              child: Text(p?['name'] as String? ?? (x == null ? '?' : (x['reason'] == 'bye' ? t('exempté', 'bye') : '?')),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: won ? FontWeight.w900 : FontWeight.w600,
                    color: won ? const Color(0xFFFFD166) : lost ? Colors.white38 : (p == null ? Colors.white38 : Colors.white),
                    decoration: lost ? TextDecoration.lineThrough : null,
                  )),
            ),
            if (_n(x?['best'], 1) > 1 && p != null) Text('$w', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white70)),
          ]),
        ),
      );
    }

    final foot = x == null
        ? null
        : live
            ? (mine ? t('● TON MATCH', '● YOUR MATCH') : t('● EN DIRECT · 👁', '● LIVE · 👁'))
            : x['status'] == 'wait'
                ? t('en attente…', 'waiting…')
                : x['reason'] == 'forfeit'
                    ? t('forfait', 'forfeit')
                    : x['reason'] == 'lot'
                        ? t('tirage au sort', 'random draw')
                        : null;
    final box = Container(
      height: height + (foot != null ? 14 : 0),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: live ? const Color(0xFFE24B4A) : mine ? const Color(0xFF6CB4FF) : Colors.white12, width: live || mine ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        line(x?['p1'] as Map?, _n(x?['w1'])),
        Container(height: 1, color: Colors.white10),
        line(x?['p2'] as Map?, _n(x?['w2'])),
        if (foot != null)
          Container(
            height: 14,
            width: double.infinity,
            alignment: Alignment.center,
            color: live ? const Color(0x33E24B4A) : Colors.white10,
            child: Text(foot, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: live ? const Color(0xFFFFB3B2) : Colors.white54)),
          ),
      ]),
    );
    if (!live || mine) return box;
    return InkWell(onTap: () => watchGame(context, game, _n(x!['game_id'])), child: box);
  }
}

// ─── Admin : créer, modifier, annuler ──────────────────────────────────────
class AdminTourPage extends StatefulWidget {
  const AdminTourPage({super.key});
  @override
  State<AdminTourPage> createState() => _AdminTourPageState();
}

class _AdminTourPageState extends State<AdminTourPage> {
  List<Map<String, dynamic>>? list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await RcServer.tourList();
      if (mounted) setState(() => list = l);
    } catch (e) {
      toast(errText(e));
    }
  }

  Future<void> _edit([Map<String, dynamic>? x]) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _TourForm(x: x)));
    if (ok == true) _load();
  }

  Future<void> _cancel(Map<String, dynamic> x) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Annuler « ${x['name']} » ?', 'Cancel "${x['name']}"?')),
        content: Text(t('Les mises sont rendues aux inscrits. Les parties en cours se terminent sans compter.', 'Fees are refunded. Games in progress end without counting.'),
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Non', 'No'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8A2232)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Annuler le tournoi', 'Cancel tournament')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await RcServer.adminTourCancel(_n(x['id']));
      toast(t('Tournoi annulé, mises rendues', 'Tournament cancelled, fees refunded'));
    } catch (e) {
      toast(errText(e));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = list;
    return Scaffold(
      appBar: AppBar(title: Text(t('Tournois', 'Tournaments'))),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kGold,
        foregroundColor: const Color(0xFF1A1000),
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: Text(t('Nouveau tournoi', 'New tournament'), style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: l == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
              if (l.isEmpty) Padding(padding: const EdgeInsets.only(top: 40), child: Text(t('Aucun tournoi', 'No tournament'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54))),
              for (final x in l) ...[
                TourCard(
                  x,
                  onTap: () => x['status'] == 'open'
                      ? _edit(x)
                      : Navigator.of(context).push(MaterialPageRoute(builder: (_) => TourPage(id: _n(x['id'])))),
                  trailing: x['status'] == 'open' || x['status'] == 'running'
                      ? IconButton(tooltip: t('Annuler', 'Cancel'), onPressed: () => _cancel(x), icon: const Icon(Icons.cancel, color: Color(0xFFFF8A95)))
                      : null,
                ),
                const SizedBox(height: 8),
              ],
            ]),
    );
  }
}

class _TourForm extends StatefulWidget {
  final Map<String, dynamic>? x;
  const _TourForm({this.x});
  @override
  State<_TourForm> createState() => _TourFormState();
}

class _TourFormState extends State<_TourForm> {
  late final name = TextEditingController(text: widget.x?['name'] as String? ?? t('Coupe du samedi', 'Saturday Cup'));
  late final fee = TextEditingController(text: '${_n(widget.x?['fee'])}');
  late String game = widget.x?['game'] as String? ?? 'c4';
  late int size = _n(widget.x?['size'], 8);
  late int split = _n(widget.x?['split'], 100);
  late DateTime start = DateTime.tryParse(widget.x?['start_at'] as String? ?? '')?.toLocal() ?? _nextSaturday();
  late final Map<String, Map<String, dynamic>> lots = {
    for (final k in ['1', '2', '3'])
      k: rewardClean((widget.x?['lots'] as Map?)?[k] ??
          (widget.x == null
              ? switch (k) {
                  '1' => {'coins': 1500, 'packs': {'star': 1}},
                  '2' => {'coins': 600, 'packs': {'premium': 1}},
                  _ => {'coins': 200},
                }
              : const {})),
  };
  bool news = true, busy = false;

  static DateTime _nextSaturday() {
    final n = DateTime.now();
    var d = DateTime(n.year, n.month, n.day, 21);
    while (d.weekday != DateTime.saturday || d.isBefore(n)) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  @override
  void dispose() {
    name.dispose();
    fee.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: start, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 60)));
    if (d == null || !mounted) return;
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(start));
    if (tm == null) return;
    setState(() => start = DateTime(d.year, d.month, d.day, tm.hour, tm.minute));
  }

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      await RcServer.adminTourSave({
        if (widget.x != null) 'id': widget.x!['id'],
        'name': name.text.trim(),
        'game': game,
        'size': size,
        'start_at': start.toUtc().toIso8601String(),
        'fee': int.tryParse(fee.text.trim()) ?? 0,
        'split': split,
        'lots': lots,
        'news': news,
      });
      toast(widget.x == null ? t('Tournoi créé', 'Tournament created') : t('Tournoi modifié', 'Tournament updated'));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      toast(errText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  Widget _seg<T>(List<(T, String)> opts, T value, ValueChanged<T> on) => Row(children: [
        for (final (v, label) in opts)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  backgroundColor: v == value ? kPanel2 : null,
                  side: BorderSide(color: v == value ? kGold : Colors.white24),
                  foregroundColor: v == value ? kGold : Colors.white70,
                ),
                onPressed: () => setState(() => on(v)),
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ),
      ]);

  Widget _label(String s) => Padding(padding: const EdgeInsets.fromLTRB(4, 14, 4, 6), child: Text(s, style: const TextStyle(color: Colors.white60, fontSize: 12.5)));

  @override
  Widget build(BuildContext context) {
    final paid = (int.tryParse(fee.text.trim()) ?? 0) > 0;
    return Scaffold(
      appBar: AppBar(title: Text(widget.x == null ? t('Nouveau tournoi', 'New tournament') : t('Modifier le tournoi', 'Edit tournament'))),
      body: MaxWidth(
        max: 620,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 30), children: [
          _label(t('Nom', 'Name')),
          TextField(controller: name, maxLength: 40),
          _label(t('Jeu', 'Game')),
          _seg<String>([('c4', '🔴 ${t('4 en ligne', 'Connect 4')}'), ('bs', '🚢 Console Wars')], game, (v) => game = v),
          _label(t('Places', 'Spots')),
          _seg<int>([(4, '4'), (8, '8'), (16, '16')], size, (v) => size = v),
          _label(t('Début', 'Start')),
          OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.event), label: Text(tourDate(start.toUtc().toIso8601String()))),
          _label(t('Inscription (pièces, 0 = gratuite) : les mises font la cagnotte', 'Entry (coins, 0 = free): fees make the pot')),
          TextField(controller: fee, keyboardType: TextInputType.number, onChanged: (_) => setState(() {})),
          if (paid) ...[
            _label(t('Partage de la cagnotte', 'Pot split')),
            _seg<int>([(100, t('Tout au 1er', 'All to 1st')), (70, '70 / 30')], split, (v) => split = v),
          ],
          for (final (k, label) in [('1', t('🥇 Lot du 1er', '🥇 1st prize')), ('2', t('🥈 Lot du 2e', '🥈 2nd prize')), ('3', t('🥉 Lot des demi-finalistes', '🥉 Semi-finalists prize'))]) ...[
            _label(label),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(12)),
              child: RewardEditor(value: lots[k]!, presets: false, onChanged: (r) => lots[k] = r),
            ),
          ],
          if (widget.x == null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: news,
              onChanged: (v) => setState(() => news = v),
              title: Text(t('Annonce dans l\'Actu', 'Post in the News')),
            ),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF1A1000), padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: busy ? null : _save,
            child: Text(widget.x == null ? t('Créer le tournoi', 'Create tournament') : t('Enregistrer', 'Save'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          ),
        ]),
      ),
    );
  }
}
