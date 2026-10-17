import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio.dart';
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
    final top = list.where((e) => e['hidden'] != true).fold<int>(_seen, (m, e) => _id(e) > m ? _id(e) : m);
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

class _EventsPageState extends State<EventsPage> {
  bool loading = true;
  int? busy;

  @override
  void initState() {
    super.initState();
    _load();
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
      final c = (r['gain_coins'] as num? ?? 0).toInt(), p = (r['gain_pixels'] as num? ?? 0).toInt();
      toast(t('Récompense : ${[if (c > 0) '+$c pièces', if (p > 0) '+$p pixels'].join(' · ')}',
          'Reward: ${[if (c > 0) '+$c coins', if (p > 0) '+$p pixels'].join(' · ')}'));
      await Events.i.refresh();
    } catch (err) {
      toast(errText(err));
    }
    if (mounted) setState(() => busy = null);
  }

  @override
  Widget build(BuildContext context) {
    return MaxWidth(
      max: 760,
      child: Scaffold(
        appBar: AppBar(title: Text(t('Événements', 'Events'))),
        body: ListenableBuilder(
          listenable: Events.i,
          builder: (context, _) {
            final list = Events.i.list;
            if (loading && list.isEmpty) return const Center(child: CircularProgressIndicator(color: kGold));
            if (list.isEmpty) {
              return RefreshIndicator(
                onRefresh: Events.i.refresh,
                child: ListView(children: [
                  const SizedBox(height: 120),
                  const Center(child: Text('📅', style: TextStyle(fontSize: 46))),
                  const SizedBox(height: 12),
                  Text(t('Pas d\'événement en ce moment.\nReviens bientôt !', 'No event right now.\nCome back soon!'),
                      textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, height: 1.4)),
                ]),
              );
            }
            // groupes : en cours, bientôt, terminés (déjà triés par le serveur)
            String group(Map e) => e['live'] == true ? 'live' : (e['ended'] == true ? 'ended' : 'soon');
            final items = <Widget>[];
            String? last;
            for (final e in list) {
              final gr = group(e);
              if (gr != last) {
                last = gr;
                items.add(Padding(
                  padding: EdgeInsets.fromLTRB(2, items.isEmpty ? 4 : 18, 2, 8),
                  child: Text(
                      switch (gr) { 'live' => t('EN COURS', 'NOW'), 'soon' => t('BIENTÔT', 'COMING SOON'), _ => t('TERMINÉS', 'ENDED') },
                      style: pixelStyle(size: 8, color: Colors.white54, shadow: false).copyWith(letterSpacing: 1)),
                ));
              } else {
                items.add(const SizedBox(height: 14));
              }
              items.add(e['hidden'] == true ? _mystery(e) : _card(e));
            }
            return RefreshIndicator(
              onRefresh: Events.i.refresh,
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 24), children: items),
            );
          },
        ),
      ),
    );
  }

  Color _color(String? hex) {
    final h = (hex ?? '').replaceAll('#', '');
    final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
    return v == null ? kGold : Color(v);
  }

  /// « Encore 3 j 4 h », « Commence dans 2 j », « Terminé »
  String _when(Map<String, dynamic> e) {
    final now = DateTime.tryParse(e['now'] as String? ?? '') ?? DateTime.now();
    final start = DateTime.tryParse(e['starts_at'] as String? ?? '');
    final end = DateTime.tryParse(e['ends_at'] as String? ?? '');
    String span(Duration d) {
      if (d.inDays >= 1) return t('${d.inDays} j ${d.inHours % 24} h', '${d.inDays} d ${d.inHours % 24} h');
      if (d.inHours >= 1) return t('${d.inHours} h ${d.inMinutes % 60} min', '${d.inHours} h ${d.inMinutes % 60} min');
      return t('${d.inMinutes.clamp(1, 59)} min', '${d.inMinutes.clamp(1, 59)} min');
    }

    String date(DateTime d) {
      final l = d.toLocal();
      return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
    }

    if (e['ended'] == true) return t('Terminé', 'Ended');
    if (start != null && start.isAfter(now)) return t('Commence dans ${span(start.difference(now))}', 'Starts in ${span(start.difference(now))}');
    if (end == null) return t('En cours', 'Ongoing');
    return t('Jusqu\'au ${date(end)} · encore ${span(end.difference(now))}', 'Until ${date(end)} · ${span(end.difference(now))} left');
  }

  /// Événement à venir : ni nom ni contenu, seulement la couleur et le compte à rebours
  Widget _mystery(Map<String, dynamic> e) {
    final color = _color(e['color'] as String?);
    return Container(
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color.withOpacity(0.55), Color.lerp(color, Colors.black, 0.7)!.withOpacity(0.6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)),
            child: Text('?', style: pixelStyle(size: 18, color: Colors.white, shadow: false)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('Événement mystère', 'Mystery event'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white)),
              const SizedBox(height: 2),
              Text(_when(e), style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
          const Icon(Icons.lock_clock, color: Colors.white54),
        ]),
      ),
    );
  }

  /// Effet en cours : « ×2 · Chaque booster ouvert rapporte 2 pixels »
  Widget _effect(Map<String, dynamic> e, Color color) {
    final v = (e['effect_value'] as num? ?? 2).toInt();
    final (big, text) = switch (e['effect']) {
      'pixels_x2' => ('×$v', t('Chaque booster ouvert rapporte $v pixels au lieu d\'1.', 'Every booster you open gives $v pixels instead of 1.')),
      'free_fast' => ('$v h', t('Le paquet gratuit revient toutes les $v heures au lieu de 6.', 'The free pack comes back every $v hours instead of 6.')),
      _ => ('★', ''),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.4))),
        child: Row(children: [
          Text(big, style: pixelStyle(size: 14, color: const Color(0xFFFFD166), shadow: false)),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35))),
        ]),
      ),
    );
  }

  /// Défi : barre de progression et paliers (✓ récupéré, doré atteint, gris à faire)
  Widget _goal(Map<String, dynamic> e, Color color) {
    final steps = [for (final s in (e['steps'] as List? ?? const [])) Map<String, dynamic>.from(s as Map)];
    if (steps.isEmpty) return const SizedBox();
    final prog = (e['progress'] as num? ?? 0).toInt(), claimed = (e['claimed'] as num? ?? 0).toInt();
    final target = (steps.last['n'] as num? ?? 1).toInt();
    final label = switch (e['goal']) {
      'packs' => t('Boosters ouverts', 'Boosters opened'),
      'c4_wins' => t('Parties de 4 en ligne gagnées', 'Connect 4 games won'),
      'gamedle' => t('Gamedle trouvés', 'Gamedles solved'),
      _ => t('Progression', 'Progress'),
    };
    String reward(Map s) => [
          if ((s['coins'] as num? ?? 0) > 0) '${s['coins']} 🪙',
          if ((s['pixels'] as num? ?? 0) > 0) '${s['pixels']} px',
        ].join(' + ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12.5))),
          Text('${prog.clamp(0, target)} / $target', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(value: (prog / target).clamp(0.0, 1.0), minHeight: 9, color: color, backgroundColor: Colors.white10),
        ),
        const SizedBox(height: 8),
        Row(children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Builder(builder: (_) {
                final n = (steps[i]['n'] as num? ?? 0).toInt();
                final got = i < claimed, reached = prog >= n;
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  decoration: BoxDecoration(
                    color: got ? color.withOpacity(0.3) : (reached ? kGold.withOpacity(0.22) : Colors.white.withOpacity(0.06)),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: reached && !got ? kGold : Colors.transparent),
                  ),
                  child: Column(children: [
                    Text(got ? '✓ $n' : '$n', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: reached ? Colors.white : Colors.white54)),
                    FittedBox(child: Text(reward(steps[i]), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: reached ? Colors.white : Colors.white54))),
                  ]),
                );
              }),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> e) {
    final color = _color(e['color'] as String?);
    final fr = rcFrench;
    final title = (fr ? e['title'] : (e['title_en'] ?? e['title'])) as String? ?? '';
    final body = (fr ? e['body'] : (e['body_en'] ?? e['body'])) as String? ?? '';
    final image = e['image'] as String?;
    final live = e['live'] == true, ended = e['ended'] == true, got = e['got'] == true;
    final kind = e['kind'] as String? ?? 'info';
    final isGoal = kind == 'goal';
    final coins = (e['coins'] as num? ?? 0).toInt(), pixels = (e['pixels'] as num? ?? 0).toInt();
    final hasReward = !isGoal && kind != 'effect' && (coins > 0 || pixels > 0);
    final action = _kTabs[e['action']];
    final id = Events._id(e);
    final reward = [
      if (coins > 0) t('$coins pièces', '$coins coins'),
      if (pixels > 0) t('$pixels pixels', '$pixels pixels'),
    ].join(' + ');

    return Opacity(
      opacity: ended ? 0.55 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(live ? 0.9 : 0.4), width: live ? 2 : 1),
          boxShadow: [if (live) BoxShadow(color: color.withOpacity(0.35), blurRadius: 16, spreadRadius: -4)],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // bannière
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.black, 0.45)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Row(children: [
              Text(e['icon'] as String? ?? '🎉', style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Colors.white, shadows: [Shadow(blurRadius: 4)])),
                  const SizedBox(height: 2),
                  Text(_when(e), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
              if (live)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(8)),
                  child: Text(t('EN COURS', 'LIVE'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
            ]),
          ),
          if (image != null && image.startsWith('http'))
            Image.network(image, height: 150, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
          if (body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Text(body, style: const TextStyle(color: Colors.white70, height: 1.4)),
            ),
          if (kind == 'effect') _effect(e, color),
          if (isGoal) _goal(e, color),
          if (isGoal && live && Events._reachable(e) > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
                  onPressed: busy == null ? () => _claim(e) : null,
                  icon: const Icon(Icons.card_giftcard, size: 18),
                  label: Text(
                      Events._reachable(e) > 1 ? t('Récupérer ${Events._reachable(e)} paliers', 'Claim ${Events._reachable(e)} steps') : t('Récupérer le palier', 'Claim the step'),
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ),
          if (hasReward || (action != null && live))
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                if (hasReward)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
                    onPressed: live && !got && busy == null ? () => _claim(e) : null,
                    icon: Icon(got ? Icons.check : Icons.card_giftcard, size: 18),
                    label: Text(
                      got ? t('Récupéré ($reward)', 'Claimed ($reward)') : t('Récupérer $reward', 'Claim $reward'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                if (action != null && live)
                  OutlinedButton.icon(
                    onPressed: busy == id
                        ? null
                        : () {
                            Navigator.of(context).popUntil((r) => r.isFirst);
                            HomeShellState.current?.goTo(action);
                          },
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: Text(t('Y aller', 'Go')),
                  ),
              ]),
            )
          else
            const SizedBox(height: 14),
        ]),
      ),
    );
  }
}
