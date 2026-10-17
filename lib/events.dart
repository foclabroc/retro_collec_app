import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio.dart';
import 'game.dart';
import 'layout.dart';
import 'main.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Événements : la liste vient du serveur (table rc_events), on peut donc en
// ajouter, modifier ou arrêter sans mettre à jour l'appli. Chaque événement
// peut offrir une récompense (pièces, pixels) et ouvrir un onglet.
// ═══════════════════════════════════════════════════════════════════════════

class Events extends ChangeNotifier {
  static final i = Events();
  List<Map<String, dynamic>> list = [];
  int _seen = 0; // plus grand numéro d'événement déjà vu (pastille « nouveau »)
  static const _kSeen = 'rc_events_seen';

  /// Événements en cours pas encore vus, ou avec une récompense pas encore récupérée
  int get unseen => list.where((e) => e['live'] == true && (_id(e) > _seen || _claimable(e))).length;

  static int _id(Map e) => (e['id'] as num? ?? 0).toInt();
  static bool _claimable(Map e) =>
      e['live'] == true && e['got'] != true && ((e['coins'] as num? ?? 0) > 0 || (e['pixels'] as num? ?? 0) > 0);

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
    final top = list.fold<int>(_seen, (m, e) => _id(e) > m ? _id(e) : m);
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
            return RefreshIndicator(
              onRefresh: Events.i.refresh,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (_, i) => _card(list[i]),
              ),
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

  Widget _card(Map<String, dynamic> e) {
    final color = _color(e['color'] as String?);
    final fr = rcFrench;
    final title = (fr ? e['title'] : (e['title_en'] ?? e['title'])) as String? ?? '';
    final body = (fr ? e['body'] : (e['body_en'] ?? e['body'])) as String? ?? '';
    final image = e['image'] as String?;
    final live = e['live'] == true, ended = e['ended'] == true, got = e['got'] == true;
    final coins = (e['coins'] as num? ?? 0).toInt(), pixels = (e['pixels'] as num? ?? 0).toInt();
    final hasReward = coins > 0 || pixels > 0;
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
