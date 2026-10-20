import 'dart:convert';

import 'package:flutter/material.dart';

import 'cards.dart';
import 'catalog.dart';
import 'game.dart';
import 'main.dart';
import 'events.dart' show goalLabel;
import 'profile.dart';
import 'rewards.dart';
import 'server.dart';
import 'arcade.dart';
import 'update_check.dart';

part 'admin_tools.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Page admin (réservée aux comptes de rc_admins : le bouton n'apparaît que si
// le serveur le confirme, et chaque fonction du serveur revérifie).
// Onglets : Comptes, Liens, Stats, Chat, Outils.
// ─────────────────────────────────────────────────────────────────────────────

const _red = Color(0xFFFF5A5A);
const _org = Color(0xFFFFB347);
const _ok = Color(0xFF5DCAA5);

/// Le compte courant est-il admin ? (vérifié par le serveur, mémorisé pour la session)
final ValueNotifier<bool> rcIsAdmin = ValueNotifier(false);
Future<void> checkAdmin() async {
  if (rcIsAdmin.value) return;
  rcIsAdmin.value = await RcServer.adminCheck();
}

class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          backgroundColor: kBg,
          title: Row(children: [
            const Text('ADMIN', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(border: Border.all(color: _red), borderRadius: BorderRadius.circular(8)),
              child: Text(t('visible par toi seul', 'only you can see this'),
                  style: const TextStyle(color: Color(0xFFFF8A8A), fontSize: 11, fontWeight: FontWeight.w900)),
            ),
          ]),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: kGold,
            labelColor: kGold,
            unselectedLabelColor: Colors.white60,
            labelStyle: const TextStyle(fontWeight: FontWeight.w900),
            tabs: [
              Tab(text: t('Comptes', 'Accounts')),
              Tab(text: t('Liens', 'Links')),
              const Tab(text: 'Stats'),
              const Tab(text: 'Chat'),
              Tab(text: t('Outils', 'Tools')),
            ],
          ),
        ),
        body: const TabBarView(children: [_AccountsTab(), _LinksTab(), _StatsTab(), _ChatTab(), _ToolsTab()]),
      ),
    );
  }
}

// ─── Petits outils d'affichage ──────────────────────────────────────────────

int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
DateTime? _d(dynamic v) => DateTime.tryParse(v?.toString() ?? '')?.toLocal();

String _ago(DateTime? d) {
  if (d == null) return '?';
  final m = DateTime.now().difference(d).inMinutes;
  if (m < 60) return t('$m min', '$m min');
  if (m < 48 * 60) return t('${m ~/ 60} h', '${m ~/ 60} h');
  return t('${m ~/ 1440} j', '${m ~/ 1440} d');
}

String _two(int n) => n.toString().padLeft(2, '0');
String _date(DateTime? d) => d == null ? '' : '${_two(d.day)}/${_two(d.month)} ${_two(d.hour)}:${_two(d.minute)}';

String _cardName(dynamic id) {
  final c = Catalog.cards[id?.toString() ?? ''];
  return c?.title ?? (id?.toString() ?? '?');
}

String _finish(dynamic f) => switch (_i(f)) { 1 => ' (holo)', 2 => ' (or)', 3 => ' (full art)', _ => '' };

class _Tag {
  final String text;
  final Color color;
  const _Tag(this.text, this.color);
}

Widget _tags(List<_Tag> tags) => Wrap(spacing: 4, runSpacing: 4, children: [
      for (final g in tags)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(color: g.color.withOpacity(0.18), borderRadius: BorderRadius.circular(8)),
          child: Text(g.text, style: TextStyle(color: Color.lerp(g.color, Colors.white, 0.45), fontSize: 11, fontWeight: FontWeight.w900)),
        ),
    ]);

Widget _box({required Widget child, Color? border, VoidCallback? onTap}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: kPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border ?? Colors.transparent, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.all(10), child: child)),
      ),
    );

Widget _num(String value, String label, {VoidCallback? onTap, bool on = false}) => Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.all(3),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: kPanel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? _org : (onTap != null ? Colors.white24 : Colors.transparent), width: 1.5),
          ),
          child: Column(children: [
            Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: on ? _org : null)),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 11)),
          ]),
        ),
      ),
    );

/// Chargement + erreur + tirer pour rafraîchir
class _Loader<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext, T, Future<void> Function() reload) builder;
  const _Loader({super.key, required this.load, required this.builder});
  @override
  State<_Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<_Loader<T>> with AutomaticKeepAliveClientMixin {
  T? data;
  String? error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final d = await widget.load();
      if (mounted) {
        setState(() {
          data = d;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (data == null) {
      return Center(
        child: error == null
            ? const CircularProgressIndicator()
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Text(error!, style: const TextStyle(color: Colors.white70)),
                TextButton(onPressed: reload, child: Text(t('Réessayer', 'Retry'))),
              ]),
      );
    }
    return RefreshIndicator(onRefresh: reload, child: widget.builder(context, data as T, reload));
  }
}

// ─── Comptes ────────────────────────────────────────────────────────────────

List<_Tag> _accountTags(Map<String, dynamic> p) {
  final tags = <_Tag>[];
  final age = _i(p['age_h']);
  final given = _i(p['trade_given']), got = _i(p['trade_got']);
  if (given - got >= 150) tags.add(_Tag(t('donne ${given - got} de valeur sans contrepartie', 'gave away ${given - got} in value'), _red));
  if (_i(p['overpaid']) > 0) tags.add(_Tag(t('${_i(p['overpaid'])} achat(s) à 5× le prix moyen', '${_i(p['overpaid'])} buy(s) at 5× avg price'), _red));
  // cadeaux : seulement si la plupart vont au même joueur (au moins 3 et 60 %)
  final gOut = _i(p['gifts_out']), gTop = _i(p['gifts_top']);
  if (gTop >= 3 && gTop * 10 >= gOut * 6) {
    tags.add(_Tag(t('$gTop cadeaux sur $gOut à ${p['gifts_top_name'] ?? '?'}', '$gTop of $gOut gifts to ${p['gifts_top_name'] ?? '?'}'), _org));
  }
  if (p['blocked'] == true) tags.add(_Tag(t('⛔ compte bloqué', '⛔ account blocked'), _red));
  if (p['chat_banned'] == true) tags.add(_Tag(t('chat interdit', 'chat banned'), _org));
  if (age < 72 && tags.isNotEmpty) tags.add(_Tag(t('compte récent', 'new account'), _org));
  if (tags.isEmpty) tags.add(_Tag(t('rien à signaler', 'nothing to report'), _ok));
  return tags;
}

Color? _level(List<_Tag> tags) =>
    tags.any((g) => g.color == _red) ? _red : tags.any((g) => g.color == _org) ? _org : null;

class _AccountsTab extends StatefulWidget {
  const _AccountsTab();
  @override
  State<_AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends State<_AccountsTab> with AutomaticKeepAliveClientMixin {
  final _ctl = TextEditingController();
  String _q = '';
  List<Map<String, dynamic>>? _rows;
  String? _error;
  int _filter = 0; // 0 : tous, 1 : vus aujourd'hui, 2 : à vérifier

  bool _seenToday(Map<String, dynamic> p) {
    final s = _d(p['seen_at']), n = DateTime.now();
    return s != null && s.year == n.year && s.month == n.month && s.day == n.day;
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final q = _q;
    try {
      final r = await RcServer.adminAccounts(q);
      if (mounted && q == _q) {
        setState(() {
          _rows = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final rows = _rows;
    final today = DateTime.now();
    final active = rows?.where((p) {
          final s = _d(p['seen_at']);
          return s != null && s.year == today.year && s.month == today.month && s.day == today.day;
        }).length ??
        0;
    final flagged = rows?.where((p) => _level(_accountTags(p)) != null).length ?? 0;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(10), children: [
        TextField(
          controller: _ctl,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: t('Chercher un pseudo…', 'Search a name…'),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _q.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _ctl.clear();
                      setState(() {
                        _q = '';
                        _rows = null;
                      });
                      _load();
                    }),
            filled: true,
            fillColor: kPanel,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
          onSubmitted: (v) {
            setState(() {
              _q = v.trim();
              _rows = null;
            });
            _load();
          },
        ),
        const SizedBox(height: 8),
        if (rows != null && _q.isEmpty)
          Row(children: [
            _num('${rows.length}', t('nouveaux · 7 j', 'new · 7 d'), on: _filter == 0, onTap: () => setState(() => _filter = 0)),
            _num('$active', t('vus aujourd\'hui', 'seen today'), on: _filter == 1, onTap: () => setState(() => _filter = _filter == 1 ? 0 : 1)),
            _num('$flagged', t('à vérifier', 'to check'), on: _filter == 2, onTap: () => setState(() => _filter = _filter == 2 ? 0 : 2)),
          ]),
        const SizedBox(height: 6),
        if (rows == null)
          Padding(
            padding: const EdgeInsets.all(30),
            child: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!)),
          )
        else if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(30),
            child: Center(child: Text(t('Aucun compte', 'No account'), style: const TextStyle(color: Colors.white60))),
          )
        else
          for (final p in rows)
            if (_q.isNotEmpty || _filter == 0 || (_filter == 1 && _seenToday(p)) || (_filter == 2 && _level(_accountTags(p)) != null))
              _accountRow(context, p),
      ]),
    );
  }

  Widget _accountRow(BuildContext context, Map<String, dynamic> p) {
    final tags = _accountTags(p);
    return _box(
      border: _level(tags),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminPlayerPage(pid: p['pid'].toString()))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          avatarWidget(_i(p['avatar']), size: 30),
          const SizedBox(width: 8),
          Expanded(child: Text(p['name']?.toString() ?? '?', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5))),
          Text(t('créé il y a ${_ago(_d(p['created_at']))}', 'created ${_ago(_d(p['created_at']))} ago'),
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 38, top: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                '${_i(p['packs'])} ${t('paquets', 'packs')} · ${_i(p['cards'])} ${t('cartes', 'cards')} · ${_i(p['score'])} pts · '
                '${fmt(_i(p['coins']))} 🪙 · ${_i(p['pixels'])} ▦ · ${t('vu il y a', 'seen')} ${_ago(_d(p['seen_at']))}',
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 6),
            _tags(tags),
          ]),
        ),
      ]),
    );
  }
}

// ─── Fiche d'un joueur ──────────────────────────────────────────────────────

class AdminPlayerPage extends StatelessWidget {
  final String pid;
  const AdminPlayerPage({super.key, required this.pid});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(backgroundColor: kBg, title: Text(t('Fiche joueur', 'Player file'))),
      body: _Loader<Map<String, dynamic>>(
        load: () => RcServer.adminPlayer(pid),
        builder: (context, p, reload) {
          final events = [for (final e in (p['events'] as List? ?? const [])) if (e is Map) Map<String, dynamic>.from(e)];
          return ListView(padding: const EdgeInsets.all(12), children: [
            Row(children: [
              avatarWidget(_i(p['avatar']), size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p['name']?.toString() ?? '?', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  Text(
                      '${t('créé le', 'created')} ${_date(_d(p['created_at']))} · ${t('vu', 'seen')} ${lastSeenLong(_d(p['seen_at']))}',
                      style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  if (p['referrer'] != null)
                    Text(t('parrainé par ${p['referrer']}', 'referred by ${p['referrer']}'),
                        style: const TextStyle(color: Colors.white60, fontSize: 12)),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _num(fmt(_i(p['coins'])), '🪙'),
              _num('${_i(p['pixels'])}', '▦'),
              _num('${_i(p['packs'])}', t('paquets', 'packs')),
              _num('${_i(p['cards'])}', t('cartes', 'cards')),
              _num('${_i(p['days'])}', t('jours', 'days')),
            ]),
            const SizedBox(height: 8),
            if (p['blocked'] == true)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _tags([_Tag(t('⛔ compte bloqué : ni échange, ni vente, ni achat, ni cadeau', '⛔ blocked: no trade, sale, buy or gift'), _red)]),
              ),
            _PlayerActions(pid: pid, player: p, reload: reload),
            const SizedBox(height: 12),
            Text(t('Activité (100 dernières actions)', 'Activity (last 100 actions)'),
                style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            if (events.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(t('Rien pour l\'instant', 'Nothing yet'), style: const TextStyle(color: Colors.white54)),
              ),
            for (final e in events) _eventLine(e),
          ]);
        },
      ),
    );
  }

  Widget _eventLine(Map<String, dynamic> e) {
    final (text, color) = _event(e);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 84, child: Text(_date(_d(e['at'])), style: const TextStyle(color: Colors.white54, fontSize: 12))),
        Expanded(child: Text(text, style: TextStyle(color: color ?? Colors.white, fontSize: 12.5, height: 1.3))),
      ]),
    );
  }

  (String, Color?) _event(Map<String, dynamic> e) {
    final other = e['other']?.toString() ?? '?';
    final card = '${_cardName(e['card'])}${_finish(e['f'])}';
    final price = _i(e['price']), avg = e['avg'] == null ? null : _i(e['avg']);
    final avgTxt = avg == null ? '' : t(' (moyenne : $avg 🪙)', ' (avg: $avg 🪙)');
    final over = avg != null && price >= 100 && price > 5 * avg;
    switch (e['kind']) {
      case 'listing':
        return (t('$card en vente $price 🪙 (pas vendue)', '$card for sale $price 🪙 (not sold)'), Colors.white70);
      case 'sold':
        return (t('vend $card à $other : $price 🪙$avgTxt', 'sold $card to $other: $price 🪙$avgTxt'), over ? _red : null);
      case 'bought':
        return (t('achète $card à $other : $price 🪙$avgTxt', 'bought $card from $other: $price 🪙$avgTxt'), over ? _red : null);
      case 'trade':
        final gave = parseItems(e['gave']?.toString() ?? ''), got = parseItems(e['got']?.toString() ?? '');
        final gv = _i(e['gave_v']), gt = _i(e['got_v']);
        final st = switch (e['status']) {
          'accepted' => t('accepté', 'accepted'),
          'refused' => t('refusé', 'declined'),
          'cancelled' => t('annulé', 'cancelled'),
          'pending' => t('en attente', 'pending'),
          _ => e['status']?.toString() ?? '',
        };
        String list(List<(String, int)> l) => l.isEmpty ? t('rien', 'nothing') : l.map((x) => _cardName(x.$1)).join(', ');
        final lopsided = gv - gt >= 150;
        return (
          t('échange $st avec $other : donne ${list(gave)} ($gv) ↔ reçoit ${list(got)} ($gt)',
              'trade $st with $other: gives ${list(gave)} ($gv) ↔ gets ${list(got)} ($gt)'),
          lopsided ? (e['status'] == 'accepted' ? _red : _org) : null
        );
      case 'pack':
        final k = e['pack']?.toString() ?? '';
        final name = switch (k) {
          'free' => t('gratuit', 'free'),
          'mixte' => t('mixte', 'mixed'),
          'console' => 'console',
          'premium' => 'premium',
          'mystery' => t('mystère', 'mystery'),
          'gift' => t('cadeau', 'gift'),
          'lot' => t('du lot', 'from bundle'),
          'star' => t('Étoile', 'Star'),
          'sconsole' => 'Console+',
          'gold' => t('Rétro d\'or', 'Retro Gold'),
          _ => k,
        };
        final sys = e['sys'] == null ? '' : ' · ${Catalog.system(e['sys'].toString())?.name ?? e['sys']}';
        return (t('📦 ouvre un paquet $name$sys', '📦 opens a $name pack$sys'), Colors.white70);
      case 'gift_out':
        return (t('🎁 cadeau offert à $other', '🎁 gift sent to $other'), null);
      case 'gift_in':
        return (t('🎁 cadeau reçu de $other', '🎁 gift from $other'), null);
      case 'duel':
        final game = e['game'] == 'bs' ? t('Bataille navale', 'Battleship') : t('4 en ligne', 'Connect 4');
        final res = switch (e['result']) {
          'win' => t('victoire', 'win'),
          'loss' => t('défaite', 'loss'),
          'draw' => t('nul', 'draw'),
          _ => e['reason']?.toString() ?? e['status']?.toString() ?? '',
        };
        return ('$game ${t('contre', 'vs')} $other : $res', Colors.white70);
      case 'chat':
        final rep = _i(e['reports']);
        return (
          '💬 « ${e['msg']} »${e['hidden'] == true ? t(' (masqué)', ' (hidden)') : ''}${rep > 0 ? t(' · signalé $rep fois', ' · reported $rep×') : ''}',
          rep > 0 || e['hidden'] == true ? _org : Colors.white70
        );
    }
    return (e['kind']?.toString() ?? '?', null);
  }
}

// ─── Liens suspects ─────────────────────────────────────────────────────────

class _LinksTab extends StatelessWidget {
  const _LinksTab();

  @override
  Widget build(BuildContext context) {
    return _Loader<List<Map<String, dynamic>>>(
      load: RcServer.adminLinks,
      builder: (context, rows, reload) => ListView(padding: const EdgeInsets.all(10), children: [
        Text(
            t('Ce qui passe d\'un joueur à l\'autre sur 14 jours (cadeaux, cartes échangées, pièces de la Bourse). Les plus déséquilibrés en premier.',
                'What goes from one player to another over 14 days (gifts, traded cards, market coins). Most lopsided first.'),
            style: const TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 8),
        if (rows.isEmpty) Center(child: Text(t('Aucun lien', 'No link'), style: const TextStyle(color: Colors.white60))),
        for (final l in rows) _link(context, l),
      ]),
    );
  }

  Widget _link(BuildContext context, Map<String, dynamic> l) {
    final score = _i(l['score']);
    final border = score >= 500 ? _red : score >= 150 ? _org : null;
    final a = l['a']?.toString() ?? '?', b = l['b']?.toString() ?? '?';
    final tags = <_Tag>[];
    void dir(String from, String to, String s) {
      final g = _i(l['gifts_$s']), c = _i(l['cards_$s']), co = _i(l['coins_$s']), ov = _i(l['over_$s']);
      if (g > 0) tags.add(_Tag(t('$g cadeau(x) $from → $to', '$g gift(s) $from → $to'), g >= 3 ? _org : Colors.white));
      if (c > 0) tags.add(_Tag(t('cartes $from → $to : $c', 'cards $from → $to: $c'), Colors.white));
      if (co > 0) tags.add(_Tag(t('$co 🪙 $from → $to', '$co 🪙 $from → $to'), Colors.white));
      if (ov > 0) tags.add(_Tag(t('$from surpaie $ov 🪙', '$from overpays $ov 🪙'), _red));
    }

    dir(a, b, 'ab');
    dir(b, a, 'ba');
    final ageA = _i(l['age_a']), ageB = _i(l['age_b']);
    if (ageA < 72) tags.add(_Tag(t('$a a ${_ago(DateTime.now().subtract(Duration(hours: ageA)))}', '$a is ${ageA}h old'), _org));
    if (ageB < 72) tags.add(_Tag(t('$b a ${_ago(DateTime.now().subtract(Duration(hours: ageB)))}', '$b is ${ageB}h old'), _org));
    if (_i(l['trades']) > 0) tags.add(_Tag(t('${_i(l['trades'])} échange(s)', '${_i(l['trades'])} trade(s)'), Colors.white));
    if (_i(l['sales']) > 0) tags.add(_Tag(t('${_i(l['sales'])} vente(s)', '${_i(l['sales'])} sale(s)'), Colors.white));

    void open(String pid) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminPlayerPage(pid: pid)));
    Widget who(String name, int av, String pid) => InkWell(
          onTap: () => open(pid),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            avatarWidget(av, size: 24),
            const SizedBox(width: 5),
            Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          ]),
        );
    return _box(
      border: border,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Flexible(child: who(a, _i(l['av_a']), l['pid_a'].toString())),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('↔', style: TextStyle(color: Colors.white54))),
          Flexible(child: who(b, _i(l['av_b']), l['pid_b'].toString())),
          const Spacer(),
          Text('$score', style: TextStyle(color: border ?? Colors.white38, fontWeight: FontWeight.w900, fontSize: 12)),
        ]),
        const SizedBox(height: 6),
        _tags(tags),
      ]),
    );
  }
}

// ─── Stats ──────────────────────────────────────────────────────────────────

class _StatsTab extends StatelessWidget {
  const _StatsTab();

  @override
  Widget build(BuildContext context) {
    return _Loader<Map<String, dynamic>>(
      load: RcServer.adminStats,
      builder: (context, s, reload) {
        final days = [for (final d in (s['days'] as List? ?? const [])) if (d is Map) Map<String, dynamic>.from(d)];
        final rich = [for (final d in (s['rich'] as List? ?? const [])) if (d is Map) Map<String, dynamic>.from(d)];
        final players = _i(s['players']);
        final maxP = days.fold<int>(1, (m, d) => _i(d['players']) > m ? _i(d['players']) : m);
        Widget line(String a, String b, [VoidCallback? onTap]) => InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Expanded(child: Text(a, style: const TextStyle(color: Colors.white60, fontSize: 13))),
                  Text(b, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  if (onTap != null) const Icon(Icons.chevron_right, size: 18, color: kGold),
                ]),
              ),
            );
        return ListView(padding: const EdgeInsets.all(10), children: [
          Row(children: [
            _num('${_i(s['active7'])}', t('actifs · 7 j', 'active · 7 d'), onTap: () => _statList(context, 'active7', t('Actifs · 7 j', 'Active · 7 d'))),
            _num('${_i(s['today'])}', t('aujourd\'hui', 'today'), onTap: () => _statList(context, 'today', t('Vus aujourd\'hui', 'Seen today'))),
            _num('+${_i(s['new7'])}', t('nouveaux · 7 j', 'new · 7 d'), onTap: () => _statList(context, 'new7', t('Nouveaux · 7 j', 'New · 7 d'))),
          ]),
          Row(children: [
            _num('${_i(s['packs_today'])}', t('paquets ouverts aujourd\'hui', 'packs opened today'),
                onTap: () => _statList(context, 'packs', t('Paquets ouverts aujourd\'hui', 'Packs opened today'))),
            _num('${_i(s['sales_today'])}', t('ventes Bourse aujourd\'hui', 'market sales today'),
                onTap: () => _statList(context, 'sales', t('Ventes Bourse aujourd\'hui', 'Market sales today'))),
            _num('${_i(s['duels_today'])}', t('duels aujourd\'hui', 'duels today'), onTap: () => _statList(context, 'duels', t('Duels aujourd\'hui', 'Duels today'))),
          ]),
          const SizedBox(height: 10),
          _box(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('Économie', 'Economy'), style: const TextStyle(fontWeight: FontWeight.w900)),
              line(t('pièces en jeu', 'coins in game'),
                  '${fmt(_i(s['coins']))} 🪙${players > 0 ? t(' (moyenne ${fmt(_i(s['coins']) ~/ players)})', ' (avg ${fmt(_i(s['coins']) ~/ players)})') : ''}'),
              line(t('pixels en jeu', 'pixels in game'), '${fmt(_i(s['pixels']))} ▦'),
              line(t('offres en Bourse', 'market offers'), '${_i(s['market_open'])}',
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminMarketPage()))),
              line(t('cartes de saga sorties', 'saga cards pulled'), '${_i(s['saga'])}'),
              line(t('joueurs (au moins 1 paquet)', 'players (1+ pack)'), '$players'),
              for (final (k, r) in rich.indexed)
                line(k == 0 ? t('plus riches', 'richest') : '', '${r['name']} · ${fmt(_i(r['coins']))} 🪙',
                    r['pid'] == null ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminPlayerPage(pid: r['pid'].toString())))),
            ]),
          ),
          _box(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('Joueurs par jour (7 j)', 'Players per day (7 d)'), style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              SizedBox(
                height: 130,
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (final d in days)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                          Text('${_i(d['players'])}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Container(
                            height: 80.0 * _i(d['players']) / maxP + 2,
                            decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(4)),
                          ),
                          const SizedBox(height: 4),
                          Text(_dayLabel(d['day']), style: const TextStyle(color: Colors.white54, fontSize: 10)),
                          Text('${_i(d['packs'])} 📦', style: const TextStyle(color: Colors.white38, fontSize: 9)),
                        ]),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 4),
              Text(t('(compté depuis la mise en place de la page admin)', '(counted since the admin page went live)'),
                  style: const TextStyle(color: Colors.white38, fontSize: 10.5)),
            ]),
          ),
        ]);
      },
    );
  }

  /// Liste derrière une case des stats, en bas d'écran ; toucher une ligne ouvre la fiche du joueur
  static void _statList(BuildContext context, String kind, String title) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => FutureBuilder<List<Map<String, dynamic>>>(
          future: RcServer.adminStatList(kind),
          builder: (ctx, snap) {
            final rows = snap.data ?? const <Map<String, dynamic>>[];
            return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(12, 10, 12, 20), children: [
              Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 10),
              Text('$title${snap.hasData ? ' · ${rows.length}' : ''}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              Text(
                  kind == 'packs'
                      ? t('Par joueur · compté depuis la mise à jour du serveur', 'Per player · counted since the server update')
                      : t('Toucher une ligne ouvre la fiche du joueur', 'Tap a row to open the player file'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 8),
              if (snap.hasError) Text(errText(snap.error!), style: const TextStyle(color: _red)),
              if (!snap.hasData && !snap.hasError) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
              if (snap.hasData && rows.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text(t('Rien pour l\'instant', 'Nothing yet'), style: const TextStyle(color: Colors.white54))),
              for (final r in rows) _statRow(ctx, kind, r),
            ]);
          },
        ),
      ),
    );
  }

  static Widget _statRow(BuildContext context, String kind, Map<String, dynamic> r) {
    String packKinds(dynamic m) => m is Map
        ? m.entries.map((e) => '${e.value} ${switch (e.key) { 'free' => t('gratuit', 'free'), 'mixte' => t('mixte', 'mixed'), 'console' => 'console', 'premium' => 'premium', 'mystery' => t('mystère', 'mystery'), 'gift' => t('cadeau', 'gift'), 'lot' => t('lot', 'bundle'), 'star' => t('Étoile', 'Star'), 'sconsole' => 'Console+', 'gold' => t('Rétro d\'or', 'Retro Gold'), _ => e.key }}').join(' · ')
        : '';
    final at = _d(r['at']);
    final (right, sub) = switch (kind) {
      'active7' || 'today' => (kind == 'today' && at != null ? '${_two(at.hour)}:${_two(at.minute)}' : _ago(at), t('${_i(r['n'])} paquets · ${fmt(_i(r['coins']))} 🪙', '${_i(r['n'])} packs · ${fmt(_i(r['coins']))} 🪙')),
      'new7' => (_date(at), [t('${_i(r['n'])} paquets', '${_i(r['n'])} packs'), if (r['ref'] != null) t('parrain : ${r['ref']}', 'referrer: ${r['ref']}')].join(' · ')),
      'packs' => ('${_i(r['n'])}', packKinds(r['kinds'])),
      'sales' => ('${_i(r['price'])} 🪙', '${_cardName(r['card'])}${_finish(r['f'])} → ${r['other'] ?? '?'}'),
      'duels' => (
          at == null ? '' : '${_two(at.hour)}:${_two(at.minute)}',
          '${r['game'] == 'bs' ? 'Console Wars' : t('4 en ligne', 'Connect 4')} ${t('contre', 'vs')} ${r['other'] ?? '?'} · ${switch (_i(r['winner'])) { 1 => t('gagne', 'wins'), 2 => t('perd', 'loses'), _ => t('nul', 'draw') }}'
        ),
      _ => ('', ''),
    };
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminPlayerPage(pid: r['pid'].toString()))),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
        child: Row(children: [
          avatarWidget(_i(r['avatar']), size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r['name']?.toString() ?? '?', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
              if (sub.isNotEmpty) Text(sub, style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
            ]),
          ),
          Text(right, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: Colors.white70)),
          const Icon(Icons.chevron_right, size: 18, color: kGold),
        ]),
      ),
    );
  }

  static String _dayLabel(dynamic v) {
    final d = DateTime.tryParse(v?.toString() ?? '');
    return d == null ? '' : '${_two(d.day)}/${_two(d.month)}';
  }
}

// ─── Chat signalé ───────────────────────────────────────────────────────────

class _ChatTab extends StatelessWidget {
  const _ChatTab();

  @override
  Widget build(BuildContext context) {
    return _Loader<List<Map<String, dynamic>>>(
      load: RcServer.adminChat,
      builder: (context, rows, reload) => ListView(padding: const EdgeInsets.all(10), children: [
        Text(t('Messages signalés ou masqués (14 jours).', 'Reported or hidden messages (14 days).'),
            style: const TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(30),
            child: Center(child: Text(t('Rien de signalé 👍', 'Nothing reported 👍'), style: const TextStyle(color: Colors.white60))),
          ),
        for (final m in rows) _msg(context, m, reload),
      ]),
    );
  }

  Widget _msg(BuildContext context, Map<String, dynamic> m, Future<void> Function() reload) {
    final id = _i(m['id']), rep = _i(m['reports']);
    final hidden = m['hidden'] == true, banned = m['banned'] == true;
    Future<void> act(String a) async {
      try {
        await RcServer.adminChatAct(id, a);
        toast(switch (a) {
          'hide' => t('Message masqué', 'Message hidden'),
          'show' => t('Message réaffiché', 'Message shown'),
          'ban' => t('Chat interdit 24 h', 'Chat banned for 24 h'),
          _ => t('Interdiction levée', 'Ban lifted'),
        });
        await reload();
      } catch (e) {
        toast(errText(e));
      }
    }

    Widget btn(String label, String a, {bool danger = false}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: ElevatedButton(
              onPressed: () => act(a),
              style: ElevatedButton.styleFrom(
                backgroundColor: danger ? const Color(0xFF5A1D2A) : const Color(0xFF2C3770),
                foregroundColor: danger ? const Color(0xFFFFC4CF) : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              ),
              child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
            ),
          ),
        );
    return _box(
      border: rep >= 3 ? _red : _org,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminPlayerPage(pid: m['pid'].toString()))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              avatarWidget(_i(m['avatar']), size: 28),
              const SizedBox(width: 6),
              Text(m['name']?.toString() ?? '?', style: const TextStyle(fontWeight: FontWeight.w900)),
            ]),
          ),
          const Spacer(),
          Text(_date(_d(m['at'])), style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
        const SizedBox(height: 6),
        Text('« ${m['msg']} »', style: TextStyle(color: hidden ? Colors.white54 : Colors.white, fontSize: 14)),
        const SizedBox(height: 6),
        _tags([
          if (rep > 0) _Tag(t('signalé $rep fois', 'reported $rep×'), rep >= 3 ? _red : _org),
          if (hidden) _Tag(t('masqué', 'hidden'), Colors.white),
          if (banned) _Tag(t('chat interdit', 'chat banned'), _red),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          hidden ? btn(t('Réafficher', 'Show'), 'show') : btn(t('Masquer', 'Hide'), 'hide'),
          banned ? btn(t('Lever l\'interdiction', 'Lift ban'), 'unban') : btn(t('🔇 Interdire 24 h', '🔇 Ban 24 h'), 'ban', danger: true),
        ]),
      ]),
    );
  }
}
