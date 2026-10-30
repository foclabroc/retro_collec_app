import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'cards.dart';
import 'catalog.dart';
import 'game.dart';
import 'live_link.dart';
import 'main.dart';
import 'notifs.dart';
import 'profile.dart';
import 'retro_theme.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Fil d'actualité : les exploits de tous les joueurs (cartes rares, séries,
// Gamedle, duels, échanges, ventes, cadeaux, arrivées, records), avec filtres.
// Rempli côté serveur par des triggers (rc_feed, patch_actu_plus.sql).
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
    var n = 0; // temps réel branché : secours toutes les 3 min au lieu de 45 s
    _timer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!LiveLink.i.connected || (n++) % 4 == 0) load();
    });
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
      // réactions à mes nouvelles : vues si l'onglet est affiché
      if (HomeShellState.current?.tab == 6 && Notifs.i.reacts > 0) {
        RcServer.reactsSeen().then((_) => Notifs.i.refresh()).catchError((_) {});
      }
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

  String filter = 'all';

  static String _cat(String kind) => switch (kind) {
        'c4' || 'c4draw' || 'bs' || 'bsdraw' || 'rj' || 'rjdraw' || 'rjsolo' || 'rn' || 'rndraw' || 'rnsolo' || 'tour' || 'tournew' => 'duel',
        'trade' || 'gift' => 'trade',
        'join' || 'streak' || 'packs' => 'player',
        _ => 'card',
      };

  /// « AUJOURD'HUI », « HIER » ou la date
  static String _day(String? at) {
    final d = DateTime.tryParse(at ?? '')?.toLocal();
    if (d == null) return '';
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (days <= 0) return t('AUJOURD\'HUI', 'TODAY');
    if (days == 1) return t('HIER', 'YESTERDAY');
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  Widget _chip(String id, String label) {
    final on = filter == id;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: on ? rcTheme.onAccent : Colors.white70)),
        selected: on,
        showCheckmark: false,
        selectedColor: rcTheme.accent,
        backgroundColor: kPanel,
        onSelected: (_) => setState(() => filter = id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // liste filtrée avec un intertitre à chaque changement de jour
    final rows = <Object>[];
    String? lastDay;
    for (final e in items ?? const <Map<String, dynamic>>[]) {
      if (filter != 'all' && _cat(e['kind'] as String? ?? '') != filter) continue;
      final d = _day(e['at'] as String?);
      if (d != lastDay) {
        rows.add(d);
        lastDay = d;
      }
      rows.add(e);
    }
    return Column(children: [
      TabHeader(t('Actualités', 'News'), icon: 'news', actions: [
        IconButton(onPressed: load, icon: const Icon(Icons.refresh), tooltip: t('Actualiser', 'Refresh')),
      ]),
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), children: [
          _chip('all', t('Tout', 'All')),
          _chip('duel', t('⚔ Duels', '⚔ Duels')),
          _chip('card', t('🃏 Cartes', '🃏 Cards')),
          _chip('trade', t('🔁 Échanges', '🔁 Trades')),
          _chip('player', t('👋 Joueurs', '👋 Players')),
        ]),
      ),
      Expanded(
        child: items == null
            ? Center(
                child: error
                    ? Text(t('Pas de connexion au serveur', 'No connection to the server'), style: const TextStyle(color: Colors.white54))
                    : const CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: load,
                child: rows.isEmpty
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
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final r = rows[i];
                          if (r is String) {
                            return Padding(
                              padding: EdgeInsets.only(left: 4, top: i == 0 ? 0 : 6),
                              child: Text(r, style: pixelStyle(size: 8, color: Colors.white54, shadow: false)),
                            );
                          }
                          return _FeedTile(r as Map<String, dynamic>);
                        },
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

  void _open(BuildContext context, String? pid) {
    if (pid == null || pid == Game.i.pid) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerProfilePage(pid: pid)));
  }

  /// Toucher : profil du joueur (pour 2 joueurs, choix entre les deux, sauf soi)
  void _tap(BuildContext context, String? pid, String name, String? pid2, String? name2) {
    final mine = Game.i.pid;
    final opts = [if (pid != null && pid != mine) (pid, name), if (pid2 != null && pid2 != mine) (pid2, name2 ?? '?')];
    if (opts.isEmpty) return;
    if (opts.length == 1) return _open(context, opts.first.$1);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kBg,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (p, n) in opts)
            ListTile(
              leading: const Icon(Icons.person),
              title: Text(t('Voir le profil de $n', 'See $n\'s profile')),
              onTap: () {
                Navigator.pop(ctx);
                _open(context, p);
              },
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kind = e['kind'] as String? ?? '';
    final card = Catalog.cards[e['card'] as String? ?? ''];
    final f = (e['f'] as num? ?? 0).toInt();
    final n = (e['n'] as num? ?? 0).toInt();
    final x = e['x'] as String?;
    final pid = e['pid'] as String?, pid2 = e['pid2'] as String?;
    final me = pid != null && pid == Game.i.pid;
    final me2 = pid2 != null && pid2 == Game.i.pid;
    final name = me ? t('Toi', 'You') : (e['name'] as String? ?? '?');
    final name2 = me2 ? t('toi', 'you') : (e['name2'] as String? ?? '?');
    final sysName = Catalog.system(e['sys'] as String? ?? '')?.name ?? (e['sys'] ?? '');
    final saga = sagaOfSys(e['sys'] as String?) ?? sagaById(card?.saga);
    final title = card?.title ?? '';
    final duo = pid2 != null;

    // morceaux de phrase : (texte, en gras ?)
    List<(String, bool)> s(String fr, String en) {
      // **mot** = en gras
      final out = <(String, bool)>[];
      final parts = t(fr, en).split('**');
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) out.add((parts[i], i.isOdd));
      }
      return out;
    }

    final a = '**$name**', b = '**$name2**';
    final how = switch (x) {
      'resign' => t(' · $name2 a abandonné', ' · $name2 resigned'),
      'timeout' => t(' · temps écoulé pour $name2', ' · $name2 ran out of time'),
      _ => '',
    };
    final (List<(String, bool)> what, Color accent, String icon, String? prize) = switch (kind) {
      'legend' => (s('$a a obtenu la légendaire **$title**', '$a got the legendary **$title**'), kRarityColor[4], '🌟', null),
      'gold' => (s('$a a obtenu **$title** en version dorée', '$a got a gold **$title**'), const Color(0xFFFFD54F), '★', null),
      'fullart' => (s('$a a obtenu **$title** en **full art** ★★', '$a got **$title** in **full art** ★★'), const Color(0xFFFF9FE5), '★★', null),
      'set' when saga != null => (s('$a a complété la saga **${saga!.name}** ! 🌈', '$a completed the **${saga!.name}** saga! 🌈'), saga!.accent, '🏆', null),
      'half' when saga != null => (s('$a a la moitié de la saga **${saga!.name}**', '$a has half of the **${saga!.name}** saga'), saga!.color, '📈', null),
      'set' => (s('$a a complété la série **$sysName** à 100 % !', '$a completed the **$sysName** set!'), const Color(0xFF5DCAA5), '🏆', null),
      'half' => (s('$a a atteint **50 %** de la série **$sysName**', '$a reached **50%** of the **$sysName** set'), const Color(0xFF77AADD), '📈', null),
      'saga' => (s('$a a obtenu la carte de saga **$title** 📚', '$a got the **$title** saga card 📚'), saga?.color ?? const Color(0xFFFF9FE5), '📚', null),
      'gamedle' => (
          n == 1
              ? s('$a a trouvé le Gamedle du jour du premier coup !', '$a solved today\'s Gamedle on the first try!')
              : s('$a a trouvé le Gamedle du jour en $n essais', '$a solved today\'s Gamedle in $n tries'),
          const Color(0xFF3DD9FF),
          '🧩',
          null
        ),
      'c4' => (s('$a a battu $b au 4 en ligne$how', '$a beat $b at Connect 4$how'), const Color(0xFFFF4757), '🔴', n > 0 ? '+$n 🪙' : null),
      'c4draw' => (s('$a et $b ont fait match nul au 4 en ligne', '$a and $b drew at Connect 4'), const Color(0xFF99AAAA), '🤝', null),
      'bs' => (s('$a a coulé la flotte de $b à Console Wars$how', '$a sank $b\'s fleet in Console Wars$how'), const Color(0xFF3EC7FF), '🚢', n > 0 ? '+$n 🪙' : null),
      'bsdraw' => (s('$a et $b ont fait match nul à Console Wars', '$a and $b drew in Console Wars'), const Color(0xFF99AAAA), '🤝', null),
      'rj' => (s('$a est monté plus haut que $b à Rétro Jump$how', '$a climbed higher than $b at Rétro Jump$how'), const Color(0xFF69F0AE), '🚀', n > 0 ? '+$n 🪙' : null),
      'rjsolo' => (s('$a a gagné le Rétro Jump solo d\'hier avec **$n points** !', '$a won yesterday\'s solo Rétro Jump with **$n points**!'), const Color(0xFF69F0AE), '🚀', null),
      'rn' => (s('$a a couru plus loin que $b à la Course de jaquettes$how', '$a ran farther than $b at Cover Run$how'), const Color(0xFFFFB74D), '🏃', n > 0 ? '+$n 🪙' : null),
      'rnsolo' => (s('$a a gagné la Course de jaquettes solo d\'hier avec **$n m** !', '$a won yesterday\'s solo Cover Run with **$n m**!'), const Color(0xFFFFB74D), '🏃', null),
      'rndraw' => (s('$a et $b ont fait égalité à la Course de jaquettes', '$a and $b tied at Cover Run'), const Color(0xFF99AAAA), '🤝', null),
      'rjdraw' => (s('$a et $b ont fait égalité à Rétro Jump', '$a and $b tied at Rétro Jump'), const Color(0xFF99AAAA), '🤝', null),
      'tour' => (
          duo
              ? s('$a a gagné le tournoi **${x ?? ''}** (${_tourGame(e['sys'])}) en battant $b en finale !', '$a won the **${x ?? ''}** tournament (${_tourGame(e['sys'])}), beating $b in the final!')
              : s('$a a gagné le tournoi **${x ?? ''}** (${_tourGame(e['sys'])}) !', '$a won the **${x ?? ''}** tournament (${_tourGame(e['sys'])})!'),
          kGold,
          '🏆',
          n > 0 ? '+$n 🪙' : null
        ),
      'tournew' => (
          s('Nouveau tournoi **${x ?? ''}** (${_tourGame(e['sys'])}, $n places) : inscriptions ouvertes dans la Salle de jeux !',
              'New tournament **${x ?? ''}** (${_tourGame(e['sys'])}, $n spots): sign up in the Game room!'),
          kGold,
          '🏆',
          null
        ),
      'trade' => (
          card == null
              ? s('$a et $b ont échangé $n carte${n > 1 ? 's' : ''}', '$a and $b traded $n card${n > 1 ? 's' : ''}')
              : s('$a et $b ont échangé $n carte${n > 1 ? 's' : ''}, dont **$title**', '$a and $b traded $n card${n > 1 ? 's' : ''}, including **$title**'),
          const Color(0xFF5DCAA5),
          '🔁',
          null
        ),
      'sale' => (s('$a a acheté **$title** à $b à la Bourse pour', '$a bought **$title** from $b on the Exchange for'), const Color(0xFFFFB347), '💱', '$n 🪙'),
      'gift' => (s('$a a offert un paquet à $b 🎁', '$a gave $b a pack 🎁'), const Color(0xFFFF6B9A), '🎁', null),
      'join' => (s('Bienvenue à $a qui rejoint Pixel Trade ! 👋', 'Welcome $a, who just joined Pixel Trade! 👋'), const Color(0xFF9A7DFF), '👋', null),
      'streak' => (s('$a se connecte depuis **$n jours** d\'affilée 🔥', '$a has logged in **$n days** in a row 🔥'), const Color(0xFFFF8A5B), '🔥', null),
      'packs' => (s('$a a ouvert son **${n}e paquet** 📦', '$a opened their **${n}th pack** 📦'), const Color(0xFF6EA8FF), '📦', null),
      _ => (<(String, bool)>[], Colors.white54, '•', null),
    };
    if (what.isEmpty) return const SizedBox.shrink();

    final av1 = (e['avatar'] as num? ?? 0).toInt(), av2 = (e['avatar2'] as num? ?? 0).toInt();
    final loserGrey = kind == 'c4' || kind == 'bs' || kind == 'rj' || kind == 'rn';
    final anyMe = me || me2;
    return Material(
      color: kPanel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _tap(context, pid, e['name'] as String? ?? '?', pid2, e['name2'] as String?),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withOpacity(anyMe ? 0.9 : 0.45), width: anyMe ? 1.6 : 1),
            gradient: LinearGradient(colors: [accent.withOpacity(0.14), Colors.transparent]),
          ),
          child: Row(children: [
            if (duo)
              SizedBox(
                width: 54,
                height: 44,
                child: Stack(children: [
                  Positioned(left: 0, top: 0, child: avatarWidget(av1, size: 34)),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Opacity(opacity: loserGrey ? 0.55 : 1, child: avatarWidget(av2, size: 34)),
                  ),
                ]),
              )
            else
              avatarWidget(av1, size: 42),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(
                  TextSpan(children: [
                    for (final (txt, bold) in what)
                      TextSpan(
                        text: txt,
                        style: bold
                            ? TextStyle(fontWeight: FontWeight.w800, color: (txt == '$name' && me) || (txt == '$name2' && me2) ? rcTheme.accent : Colors.white)
                            : null,
                      ),
                    if (prize != null)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Container(
                          margin: const EdgeInsets.only(left: 5),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(8)),
                          child: Text(prize, style: const TextStyle(color: Color(0xFFFFD166), fontWeight: FontWeight.w900, fontSize: 12)),
                        ),
                      ),
                  ]),
                  style: const TextStyle(fontSize: 14, height: 1.3, color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(child: Text(_ago(e['at'] as String?), style: const TextStyle(color: Colors.white38, fontSize: 11))),
                  _Reacts(e),
                ]),
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

/// Réactions 👏 🔥 😮 sous une nouvelle (une par joueur ; toucher la même l'enlève)
class _Reacts extends StatefulWidget {
  final Map<String, dynamic> e;
  const _Reacts(this.e);
  @override
  State<_Reacts> createState() => _ReactsState();
}

class _ReactsState extends State<_Reacts> {
  static const _emo = ['👏', '🔥', '😮'];
  bool busy = false;

  List<int> get rx {
    final l = widget.e['rx'];
    return [for (var i = 0; i < 3; i++) l is List && i < l.length ? (l[i] as num).toInt() : 0];
  }

  int get me => (widget.e['me'] as num? ?? -1).toInt();

  Future<void> _tap(int j) async {
    final id = (widget.e['id'] as num?)?.toInt();
    if (id == null || busy) return;
    // affichage immédiat, corrigé par la réponse du serveur
    final old = (rx, me);
    final r = rx;
    if (me >= 0) r[me] = max(0, r[me] - 1);
    final next = me == j ? -1 : j;
    if (next >= 0) r[next]++;
    setState(() {
      widget.e['rx'] = r;
      widget.e['me'] = next;
      busy = true;
    });
    try {
      final res = await RcServer.feedReact(id, j);
      widget.e['rx'] = res['rx'];
      widget.e['me'] = res['me'];
    } catch (_) {
      widget.e['rx'] = old.$1;
      widget.e['me'] = old.$2;
      toast(t('Réaction impossible pour l\'instant', 'Could not react right now'));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final r = rx, m = me;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var j = 0; j < 3; j++)
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Material(
            color: m == j ? rcTheme.accent.withOpacity(0.3) : Colors.white.withOpacity(0.05),
            shape: StadiumBorder(side: BorderSide(color: m == j ? rcTheme.accent : Colors.white24)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => _tap(j),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                child: Text(r[j] > 0 ? '${_emo[j]} ${r[j]}' : _emo[j], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// Nom du jeu d'un tournoi (actu)
String _tourGame(dynamic sys) => switch (sys) { 'bs' => 'Console Wars', 'rj' => 'Rétro Jump', _ => t('4 en ligne', 'Connect 4') };
