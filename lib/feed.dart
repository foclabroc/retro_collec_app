import 'dart:async';

import 'package:flutter/material.dart';

import 'cards.dart';
import 'catalog.dart';
import 'game.dart';
import 'main.dart';
import 'profile.dart';
import 'retro_theme.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Fil d'actualité : les exploits de tous les joueurs (légendaire ou dorée
// obtenue, série complétée, Gamedle trouvé). Rempli côté serveur (rc_feed).
// ═══════════════════════════════════════════════════════════════════════════

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});
  @override
  State<FeedScreen> createState() => FeedScreenState();
}

class FeedScreenState extends State<FeedScreen> {
  static FeedScreenState? current;
  List<Map<String, dynamic>>? items;
  bool error = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    current = this;
    load();
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (current == this) current = null;
    super.dispose();
  }

  Future<void> load() async {
    try {
      final l = await RcServer.feed();
      if (mounted) {
        setState(() {
          items = l;
          error = false;
        });
      }
    } catch (_) {
      if (mounted && items == null) setState(() => error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TabHeader(t('Actualités', 'News'), actions: [
        IconButton(onPressed: load, icon: const Icon(Icons.refresh), tooltip: t('Actualiser', 'Refresh')),
      ]),
      Expanded(
        child: items == null
            ? Center(
                child: error
                    ? Text(t('Pas de connexion au serveur', 'No connection to the server'), style: const TextStyle(color: Colors.white54))
                    : const CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: load,
                child: items!.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 120),
                        const Center(child: Text('📰', style: TextStyle(fontSize: 44))),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(t('Rien pour l\'instant…\nTire une légendaire pour faire la une !', 'Nothing yet…\nPull a legendary to make the headlines!'),
                              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
                        ),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        itemCount: items!.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _FeedTile(items![i]),
                      ),
              ),
      ),
    ]);
  }
}

String _ago(String? at) {
  final d = DateTime.tryParse(at ?? '');
  if (d == null) return '';
  final s = DateTime.now().toUtc().difference(d.toUtc());
  if (s.inMinutes < 1) return t('à l\'instant', 'just now');
  if (s.inMinutes < 60) return t('il y a ${s.inMinutes} min', '${s.inMinutes} min ago');
  if (s.inHours < 24) return t('il y a ${s.inHours} h', '${s.inHours} h ago');
  return t('il y a ${s.inDays} j', '${s.inDays} d ago');
}

class _FeedTile extends StatelessWidget {
  final Map<String, dynamic> e;
  const _FeedTile(this.e);

  @override
  Widget build(BuildContext context) {
    final kind = e['kind'] as String? ?? '';
    final card = Catalog.cards[e['card'] as String? ?? ''];
    final f = (e['f'] as num? ?? 0).toInt();
    final n = (e['n'] as num? ?? 0).toInt();
    final name = e['name'] as String? ?? '?';
    final pid = e['pid'] as String?;
    final me = pid != null && pid == Game.i.pid;
    final sysName = Catalog.system(e['sys'] as String? ?? '')?.name ?? (e['sys'] ?? '');

    // texte, couleur d'accent et icône selon l'événement
    final (String what, Color accent, String icon) = switch (kind) {
      'legend' => (t('a obtenu la légendaire ${card?.title ?? ''}', 'got the legendary ${card?.title ?? ''}'), kRarityColor[4], '🌟'),
      'gold' => (t('a obtenu ${card?.title ?? ''} en version dorée', 'got a gold ${card?.title ?? ''}'), const Color(0xFFFFD54F), '★'),
      'set' => (t('a complété la série $sysName à 100 % !', 'completed the $sysName set!'), const Color(0xFF5DCAA5), '🏆'),
      'gamedle' => (
          n == 1
              ? t('a trouvé le Gamedle du jour du premier coup !', 'solved today\'s Gamedle on the first try!')
              : t('a trouvé le Gamedle du jour en $n essais', 'solved today\'s Gamedle in $n tries'),
          const Color(0xFF3DD9FF),
          '🧩'
        ),
      _ => ('', Colors.white54, '•'),
    };

    return Material(
      color: kPanel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: pid == null || me ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerProfilePage(pid: pid))),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withOpacity(me ? 0.9 : 0.45), width: me ? 1.6 : 1),
            gradient: LinearGradient(colors: [accent.withOpacity(0.14), Colors.transparent]),
          ),
          child: Row(children: [
            avatarWidget((e['avatar'] as num? ?? 0).toInt(), size: 42),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: me ? t('Toi ', 'You ') : '$name ', style: TextStyle(fontWeight: FontWeight.w800, color: me ? kGold : Colors.white)),
                    TextSpan(text: what, style: const TextStyle(color: Colors.white70)),
                  ]),
                  style: const TextStyle(fontSize: 14, height: 1.3),
                ),
                const SizedBox(height: 4),
                Text(_ago(e['at'] as String?), style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ]),
            ),
            const SizedBox(width: 8),
            // la carte (pas pour le Gamedle : ce serait la réponse du jour !)
            if (card != null && kind != 'gamedle')
              SizedBox(width: 44, child: CardView(card: card, finish: f))
            else
              SizedBox(
                width: 44,
                child: Center(child: Text(icon, style: pixelStyle(size: 22, color: accent, shadow: false))),
              ),
          ]),
        ),
      ),
    );
  }
}
