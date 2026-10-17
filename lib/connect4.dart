import 'dart:async';

import 'package:flutter/material.dart';

import 'audio.dart';
import 'cards.dart';
import 'game.dart';
import 'layout.dart';
import 'main.dart';
import 'retro_theme.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 4 en ligne à 2 joueurs (onglet « Bonus / Jeux ») : 50 pièces chacun, le
// gagnant prend 100 + 1 pixel. « En direct » : 1 min par coup, contre un joueur en ligne.
// « Tour par tour » : 24 h par coup. Tout est vérifié par le serveur (rc_c4_*).
// Plateau : 42 caractères, case (ligne r de 0 en haut, colonne c) = r*7 + c.
// ═══════════════════════════════════════════════════════════════════════════

const _kRed = Color(0xFFE8434A), _kYellow = Color(0xFFFFCF33), _kBoard = Color(0xFF2457C5);
const kC4Stake = 50; // mise de chaque joueur ; le gagnant reçoit les deux mises + 1 pixel

Widget _avatar(int a, {double size = 38}) => avatarWidget(a, size: size);

/// Case de l'onglet Bonus / Jeux
class Connect4Tile extends StatefulWidget {
  const Connect4Tile({super.key});
  @override
  State<Connect4Tile> createState() => _Connect4TileState();
}

class _Connect4TileState extends State<Connect4Tile> {
  int myTurn = 0, invites = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await RcServer.c4List();
      if (!mounted) return;
      setState(() {
        myTurn = l.where((g) => g['status'] == 'playing' && g['turn'] == g['side']).length;
        invites = l.where((g) => g['status'] == 'invite' && g['side'] == 2).length;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    const accent = _kRed;
    final status = [
      if (myTurn > 0) t('$myTurn à toi de jouer', '$myTurn your turn'),
      if (invites > 0) t('$invites invitation${invites > 1 ? 's' : ''}', '$invites invitation${invites > 1 ? 's' : ''}'),
    ].join(' · ');
    return Material(
      color: kPanel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const Connect4Lobby()));
          _load();
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withOpacity(0.7), width: 1.5),
            gradient: LinearGradient(colors: [accent.withOpacity(0.16), Colors.transparent]),
          ),
          child: Row(children: [
            Container(
              width: 58,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: kBg, shape: BoxShape.circle, border: Border.all(color: accent, width: 2)),
              child: const SizedBox(width: 40, height: 34, child: _MiniBoard()),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('4 en ligne', 'Connect 4'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 3),
                Text(t('Défie un joueur : $kC4Stake pièces chacun, le gagnant prend tout + 1 pixel', 'Challenge a player: $kC4Stake coins each, winner takes all + 1 pixel'),
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
                if (status.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(status, style: const TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ]),
            ),
            Badge(
              isLabelVisible: myTurn + invites > 0,
              label: Text('${myTurn + invites}'),
              child: const Icon(Icons.play_arrow_rounded, color: accent, size: 32),
            ),
          ]),
        ),
      ),
    );
  }
}

class _MiniBoard extends StatelessWidget {
  const _MiniBoard();
  @override
  Widget build(BuildContext context) {
    const cells = [0, 2, 0, 0, 1, 1, 2, 0, 2, 1, 1, 2];
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: _kBoard, borderRadius: BorderRadius.circular(4)),
      child: GridView.count(
        crossAxisCount: 4,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final c in cells)
            Container(decoration: BoxDecoration(shape: BoxShape.circle, color: c == 1 ? _kRed : c == 2 ? _kYellow : kBg)),
        ],
      ),
    );
  }
}

// ─── Salon : invitations, en direct, tour par tour, résultats ─────────────
class Connect4Lobby extends StatefulWidget {
  const Connect4Lobby({super.key});
  @override
  State<Connect4Lobby> createState() => _Connect4LobbyState();
}

class _Connect4LobbyState extends State<Connect4Lobby> {
  List<Map<String, dynamic>> games = [], online = [];
  bool loaded = false, busy = false, inGame = false;
  Timer? _poll;
  final _opened = <int>{}; // parties en direct déjà ouvertes automatiquement

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!inGame) _load();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([RcServer.c4List(), RcServer.c4Online()]);
      if (!mounted) return;
      setState(() {
        games = r[0];
        online = r[1];
        loaded = true;
      });
      // une partie en direct que j'ai lancée vient d'être acceptée : on l'ouvre
      for (final g in games) {
        final id = (g['id'] as num).toInt();
        if (g['mode'] == 'live' && g['status'] == 'playing' && !_opened.contains(id)) {
          _opened.add(id);
          _openGame(g);
          break;
        }
      }
    } catch (e) {
      if (mounted && !loaded) setState(() => loaded = true);
    }
  }

  Future<void> _openGame(Map<String, dynamic> g) async {
    _opened.add((g['id'] as num).toInt());
    inGame = true;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => Connect4GamePage(initial: g)));
    inGame = false;
    Game.i.sync();
    _load();
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() f, {bool open = false, String? ok}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final g = await f();
      if (ok != null) toast(ok);
      Game.i.sync();
      if (open && g['status'] == 'playing') {
        await _openGame(g);
      } else {
        await _load();
      }
    } catch (e) {
      toast(errText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  void _invite(Map<String, dynamic> p, String mode) {
    if (Game.i.coins < kC4Stake) {
      toast(t('Il te faut $kC4Stake pièces pour jouer', 'You need $kC4Stake coins to play'));
      return;
    }
    final name = p['name'] as String? ?? '?';
    _run(() => RcServer.c4Invite(p['pid'] as String, mode),
        ok: mode == 'live'
            ? t('Défi envoyé à $name : il a 2 minutes pour accepter', 'Challenge sent to $name: 2 minutes to accept')
            : t('Invitation envoyée à $name', 'Invitation sent to $name'));
  }

  Future<void> _pickTurnOpponent() async {
    final p = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kBg.withOpacity(0.97),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _PlayerPicker(),
    );
    if (p != null) _invite(p, 'turn');
  }

  String _left(Map g) {
    final now = DateTime.tryParse(g['now'] as String? ?? '') ?? DateTime.now();
    final dl = DateTime.tryParse(g['deadline'] as String? ?? '');
    if (dl == null) return '';
    final d = dl.difference(now);
    if (d.isNegative) return t('expiré', 'expired');
    if (d.inHours >= 1) return t('${d.inHours} h', '${d.inHours} h');
    if (d.inMinutes >= 1) return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    return '0:${d.inSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final mine = games;
    final invitesIn = mine.where((g) => g['status'] == 'invite' && g['side'] == 2).toList();
    final liveGames = mine.where((g) => g['mode'] == 'live' && g['status'] == 'playing').toList();
    final liveOut = mine.where((g) => g['mode'] == 'live' && g['status'] == 'invite' && g['side'] == 1).toList();
    final turnGames = mine.where((g) => g['mode'] == 'turn' && (g['status'] == 'playing' || (g['status'] == 'invite' && g['side'] == 1))).toList()
      ..sort((a, b) => ((b['status'] == 'playing' && b['turn'] == b['side']) ? 1 : 0).compareTo((a['status'] == 'playing' && a['turn'] == a['side']) ? 1 : 0));
    final done = mine.where((g) => g['status'] == 'done' && !['declined', 'cancelled', 'expired'].contains(g['reason'])).take(8).toList();

    Widget section(String title, String sub) => Padding(
          padding: const EdgeInsets.fromLTRB(2, 16, 2, 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(width: 8),
            Expanded(child: Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 12))),
          ]),
        );

    Widget row(Map? opp, String title, Widget sub, List<Widget> btns, {bool hl = false, bool invite = false, bool on = false}) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          decoration: BoxDecoration(
            color: kPanel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: hl || invite ? kGold : Colors.transparent, width: 1.5),
            gradient: invite ? LinearGradient(colors: [kGold.withOpacity(0.2), Colors.transparent]) : null,
          ),
          child: Row(children: [
            _avatar((opp?['avatar'] as num? ?? 0).toInt()),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (on)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: const BoxDecoration(color: Color(0xFF5DCAA5), shape: BoxShape.circle),
                    ),
                  Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
                ]),
                DefaultTextStyle.merge(style: const TextStyle(fontSize: 12, color: Colors.white60), child: sub),
              ]),
            ),
            ...btns,
          ]),
        );

    Widget btn(String label, VoidCallback? onTap, {bool ghost = false, bool no = false}) => Padding(
          padding: const EdgeInsets.only(left: 6),
          child: no
              ? IconButton.filledTonal(onPressed: busy ? null : onTap, icon: const Icon(Icons.close, size: 18), visualDensity: VisualDensity.compact)
              : ghost
                  ? OutlinedButton(onPressed: busy ? null : onTap, style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact), child: Text(label))
                  : FilledButton(
                      onPressed: busy ? null : onTap,
                      style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800), visualDensity: VisualDensity.compact),
                      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
        );

    String name(Map g) => (g['opp'] as Map?)?['name'] as String? ?? '?';

    return MaxWidth(
      max: 760,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('4 en ligne', 'Connect 4')),
          actions: [ListenableBuilder(listenable: Game.i, builder: (_, __) => CoinChip(Game.i.coins)), const SizedBox(width: 12)],
        ),
        body: !loaded
            ? const Center(child: CircularProgressIndicator(color: kGold))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 24), children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.25), borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      t('Chaque joueur mise $kC4Stake pièces, le gagnant remporte ${kC4Stake * 2} pièces + 1 pixel. Match nul : mises rendues. Délai dépassé = abandon.',
                          'Each player bets $kC4Stake coins, the winner gets ${kC4Stake * 2} coins + 1 pixel. Draw: bets returned. Time out = forfeit.'),
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.4),
                    ),
                  ),
                  if (invitesIn.isNotEmpty) ...[
                    section(t('Invitations', 'Invitations'), ''),
                    for (final g in invitesIn)
                      row(
                        g['opp'] as Map?,
                        t('${name(g)} te défie', '${name(g)} challenges you'),
                        Text('${g['mode'] == 'live' ? t('En direct', 'Live') : t('Tour par tour', 'Turn-based')} · ${t('expire dans', 'expires in')} ${_left(g)}'),
                        [
                          btn(t('Accepter', 'Accept'), () => _run(() => RcServer.c4Answer((g['id'] as num).toInt(), true), open: true)),
                          btn('', () => _run(() => RcServer.c4Answer((g['id'] as num).toInt(), false), ok: t('Invitation refusée', 'Invitation declined')), no: true),
                        ],
                        invite: true,
                      ),
                  ],
                  section(t('En direct', 'Live'), t('1 min par coup · joueurs en ligne', '1 min per move · online players')),
                  for (final g in liveGames)
                    row(g['opp'] as Map?, name(g),
                        Text(g['turn'] == g['side'] ? t('Partie en cours · à toi !', 'Game on · your turn!') : t('Partie en cours', 'Game on'),
                            style: const TextStyle(color: kGold, fontWeight: FontWeight.w800)),
                        [btn(t('Reprendre', 'Resume'), () => _openGame(g))],
                        hl: true),
                  for (final g in liveOut)
                    row(g['opp'] as Map?, name(g), Text(t('Défi envoyé · attend sa réponse (${_left(g)})', 'Challenge sent · waiting (${_left(g)})')),
                        [btn(t('Annuler', 'Cancel'), () => _run(() => RcServer.c4Answer((g['id'] as num).toInt(), false)), ghost: true)]),
                  if (online.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(t('Personne d\'autre en ligne pour l\'instant.', 'Nobody else online right now.'), style: const TextStyle(color: Colors.white38)),
                    ),
                  for (final p in online)
                    row(
                      p,
                      p['name'] as String? ?? '?',
                      Text(p['busy'] == true ? t('En ligne · en partie', 'Online · in a game') : t('En ligne · ${p['score']} pts', 'Online · ${p['score']} pts')),
                      [btn(p['busy'] == true ? t('Occupé', 'Busy') : t('Défier', 'Challenge'), p['busy'] == true ? null : () => _invite(p, 'live'))],
                      on: true,
                    ),
                  section(t('Tour par tour', 'Turn-based'), t('24 h par coup', '24 h per move')),
                  for (final g in turnGames)
                    if (g['status'] == 'invite')
                      row(g['opp'] as Map?, name(g), Text(t('Invitation envoyée · expire dans ${_left(g)}', 'Invitation sent · expires in ${_left(g)}')),
                          [btn(t('Annuler', 'Cancel'), () => _run(() => RcServer.c4Answer((g['id'] as num).toInt(), false)), ghost: true)])
                    else if (g['turn'] == g['side'])
                      row(g['opp'] as Map?, name(g),
                          Text(t('À toi de jouer · reste ${_left(g)}', 'Your turn · ${_left(g)} left'), style: const TextStyle(color: kGold, fontWeight: FontWeight.w800)),
                          [btn(t('Jouer', 'Play'), () => _openGame(g))],
                          hl: true)
                    else
                      row(g['opp'] as Map?, name(g), Text(t('Au tour de ${name(g)} · reste ${_left(g)}', '${name(g)}\'s turn · ${_left(g)} left')),
                          [btn(t('Voir', 'View'), () => _openGame(g), ghost: true)]),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : _pickTurnOpponent,
                      icon: const Icon(Icons.add),
                      label: Text(t('Nouvelle partie tour par tour', 'New turn-based game')),
                    ),
                  ),
                  if (done.isNotEmpty) ...[
                    section(t('Résultats récents', 'Recent results'), ''),
                    for (final g in done) row(g['opp'] as Map?, name(g), _resultLine(g), const []),
                  ],
                ]),
              ),
      ),
    );
  }
}

/// « Gagné · +100 pièces +1 pixel », « Perdu (temps écoulé) · −50 », « Match nul · mise rendue »
Widget _resultLine(Map g) {
  final w = (g['winner'] as num?)?.toInt();
  final side = (g['side'] as num? ?? 1).toInt();
  final stake = (g['stake'] as num? ?? kC4Stake).toInt();
  final why = switch (g['reason']) {
    'timeout' => t(' (temps écoulé)', ' (time out)'),
    'resign' => t(' (abandon)', ' (resigned)'),
    _ => '',
  };
  if (w == 0) return Text(t('Match nul · mise rendue', 'Draw · bet returned'));
  if (w == side) return Text(t('Gagné$why · +${stake * 2} pièces +1 pixel', 'Won$why · +${stake * 2} coins +1 pixel'), style: const TextStyle(color: Color(0xFF5DCAA5), fontWeight: FontWeight.w800));
  return Text(t('Perdu$why · −$stake', 'Lost$why · −$stake'), style: const TextStyle(color: Color(0xFFFF8A8F), fontWeight: FontWeight.w800));
}

/// Choix d'un adversaire pour une partie tour par tour (classement + recherche)
class _PlayerPicker extends StatefulWidget {
  const _PlayerPicker();
  @override
  State<_PlayerPicker> createState() => _PlayerPickerState();
}

class _PlayerPickerState extends State<_PlayerPicker> {
  List<Map<String, dynamic>>? rows;
  String q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = q.trim().isEmpty ? await RcServer.board() : await RcServer.find(q.trim());
      if (mounted) setState(() => rows = r.where((p) => p['pid'] != Game.i.pid).toList());
    } catch (e) {
      if (mounted) setState(() => rows = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scroll) => SafeArea(
        child: Column(children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(t('Contre qui ?', 'Against whom?'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: t('Chercher un joueur', 'Search a player'),
                isDense: true,
                filled: true,
                fillColor: const Color(0x33000000),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (v) {
                q = v;
                _load();
              },
            ),
          ),
          Expanded(
            child: rows == null
                ? const Center(child: CircularProgressIndicator(color: kGold))
                : ListView.builder(
                    controller: scroll,
                    itemCount: rows!.length,
                    itemBuilder: (_, i) {
                      final p = rows![i];
                      return ListTile(
                        leading: _avatar((p['avatar'] as num? ?? 0).toInt()),
                        title: Text(p['name'] as String? ?? '?', style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(t('${p['score']} pts · ${p['cards']} cartes', '${p['score']} pts · ${p['cards']} cards')),
                        trailing: p['online'] == true ? const Icon(Icons.circle, size: 10, color: Color(0xFF5DCAA5)) : null,
                        onTap: () => Navigator.pop(context, p),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

// ─── Plateau ───────────────────────────────────────────────────────────────
class Connect4GamePage extends StatefulWidget {
  final Map<String, dynamic> initial;
  const Connect4GamePage({super.key, required this.initial});
  @override
  State<Connect4GamePage> createState() => _Connect4GamePageState();
}

class _Connect4GamePageState extends State<Connect4GamePage> {
  late Map<String, dynamic> g = widget.initial;
  bool busy = false;
  Timer? _poll, _tick;
  Duration _skew = Duration.zero; // heure du serveur - heure du téléphone
  int? _lastPlaced; // index de la dernière case posée (animation)

  int get id => (g['id'] as num).toInt();
  bool get live => g['mode'] == 'live';
  int get side => (g['side'] as num? ?? 1).toInt();
  bool get playing => g['status'] == 'playing';
  bool get myTurn => playing && (g['turn'] as num?)?.toInt() == side;

  @override
  void initState() {
    super.initState();
    _setSkew();
    _poll = Timer.periodic(Duration(seconds: live ? 2 : 8), (_) => _refresh());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
      // délai dépassé : on demande au serveur de régler la partie
      if (playing && _left().isNegative) _refresh();
    });
    _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  void _setSkew() {
    final now = DateTime.tryParse(g['now'] as String? ?? '');
    if (now != null) _skew = now.difference(DateTime.now());
  }

  Duration _left() {
    final dl = DateTime.tryParse(g['deadline'] as String? ?? '');
    if (dl == null) return Duration.zero;
    return dl.difference(DateTime.now().add(_skew));
  }

  void _apply(Map<String, dynamic> n) {
    final before = g['board'] as String? ?? '';
    final after = n['board'] as String? ?? '';
    int? placed;
    for (var i = 0; i < after.length && i < before.length; i++) {
      if (before[i] != after[i]) placed = i;
    }
    final wasPlaying = playing;
    setState(() {
      g = n;
      if (placed != null) _lastPlaced = placed;
    });
    _setSkew();
    if (placed != null) RcAudio.sfx('jump');
    if (wasPlaying && !playing) {
      final w = (g['winner'] as num?)?.toInt();
      RcAudio.sfx(w == side ? 'tier' : 'break');
      Game.i.sync();
    }
  }

  Future<void> _refresh() async {
    try {
      final n = await RcServer.c4State(id);
      if (mounted) _apply(n);
    } catch (_) {}
  }

  Future<void> _play(int col) async {
    if (busy) return;
    if (!myTurn) {
      toast(playing ? t('Ce n\'est pas ton tour', 'It\'s not your turn') : t('La partie est terminée', 'The game is over'));
      return;
    }
    if ((g['board'] as String)[col] != '0') {
      toast(t('Cette colonne est pleine', 'This column is full'));
      return;
    }
    setState(() => busy = true);
    try {
      _apply(await RcServer.c4Play(id, col));
    } catch (e) {
      toast(errText(e));
      _refresh();
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _resign() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Abandonner ?', 'Resign?')),
        content: Text(t('Ta mise de ${g['stake']} pièces est perdue, ton adversaire gagne.', 'You lose your ${g['stake']} coins bet, your opponent wins.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Continuer', 'Keep playing'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Abandonner', 'Resign'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      _apply(await RcServer.c4Resign(id));
    } catch (e) {
      toast(errText(e));
    }
  }

  /// Cases gagnantes (pour les faire briller)
  Set<int> _winCells(String b) {
    final w = (g['winner'] as num?)?.toInt();
    if (w == null || w == 0 || g['reason'] != 'win') return {};
    final s = '$w';
    for (var r = 0; r < 6; r++) {
      for (var c = 0; c < 7; c++) {
        if (b[r * 7 + c] != s) continue;
        for (final (dr, dc) in const [(0, 1), (1, 0), (1, 1), (1, -1)]) {
          final cells = <int>[];
          var rr = r, cc = c;
          while (rr >= 0 && rr < 6 && cc >= 0 && cc < 7 && b[rr * 7 + cc] == s) {
            cells.add(rr * 7 + cc);
            rr += dr;
            cc += dc;
          }
          if (cells.length >= 4) return cells.toSet();
        }
      }
    }
    return {};
  }

  @override
  Widget build(BuildContext context) {
    final opp = g['opp'] as Map? ?? const {};
    final oppName = opp['name'] as String? ?? '?';
    final board = (g['board'] as String?) ?? '0' * 42;
    final win = _winCells(board);
    final left = _left();
    final turn = (g['turn'] as num?)?.toInt() ?? 1;
    final myColor = side == 1 ? _kRed : _kYellow, oppColor = side == 1 ? _kYellow : _kRed;
    final stake = (g['stake'] as num? ?? kC4Stake).toInt();

    Widget player(String name, int avatar, Color color, bool on, {bool right = false}) => Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kPanel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: on ? kGold : Colors.transparent, width: 2),
              boxShadow: [if (on) BoxShadow(color: kGold.withOpacity(0.35), blurRadius: 12)],
            ),
            child: Row(textDirection: right ? TextDirection.rtl : TextDirection.ltr, children: [
              _avatar(avatar, size: 36),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: right ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(t('mise $stake', 'bet $stake'), style: const TextStyle(fontSize: 11, color: Colors.white54)),
                  ]),
                ]),
              ),
            ]),
          ),
        );

    String timerText() {
      if (!playing) return '';
      final d = left.isNegative ? Duration.zero : left;
      if (live) return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
      return t('${d.inHours} h ${(d.inMinutes % 60).toString().padLeft(2, '0')} min', '${d.inHours} h ${(d.inMinutes % 60).toString().padLeft(2, '0')} min');
    }

    return MaxWidth(
      max: 560,
      child: Scaffold(
        appBar: AppBar(
          title: Text(live ? t('En direct', 'Live') : t('Tour par tour', 'Turn-based')),
          actions: [ListenableBuilder(listenable: Game.i, builder: (_, __) => CoinChip(Game.i.coins)), const SizedBox(width: 12)],
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 24), children: [
          Row(children: [
            player(t('Toi', 'You'), Game.i.avatar, myColor, playing && turn == side),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('VS', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w900))),
            player(oppName, (opp['avatar'] as num? ?? 0).toInt(), oppColor, playing && turn != side, right: true),
          ]),
          const SizedBox(height: 12),
          if (g['status'] == 'invite')
            Text(t('En attente de la réponse de $oppName…', 'Waiting for $oppName to answer…'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))
          else if (playing) ...[
            Text(myTurn ? t('À toi de jouer !', 'Your turn!') : t('Au tour de $oppName…', '$oppName\'s turn…'),
                textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 4),
            Text(timerText(),
                textAlign: TextAlign.center,
                style: pixelStyle(size: 12, color: live && left.inSeconds <= 10 ? _kRed : const Color(0xFFFFD166), shadow: false)),
          ],
          const SizedBox(height: 12),
          // plateau
          AspectRatio(
            aspectRatio: 7 / 6.1,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF2D64D6), Color(0xFF1D47A8)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [BoxShadow(color: Color(0xFF12306F), offset: Offset(0, 8)), BoxShadow(color: Colors.black54, offset: Offset(0, 12), blurRadius: 20)],
              ),
              child: Row(children: [
                for (var c = 0; c < 7; c++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _play(c),
                      child: Column(children: [
                        for (var r = 0; r < 6; r++)
                          Expanded(child: Padding(padding: const EdgeInsets.all(3), child: _cell(board[r * 7 + c], r * 7 + c, win.contains(r * 7 + c)))),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          if (g['status'] == 'done') _result(oppName, stake) else if (playing)
            Center(
              child: TextButton.icon(
                onPressed: _resign,
                icon: const Icon(Icons.flag, color: Color(0xFFFF8A8F)),
                label: Text(t('Abandonner', 'Resign'), style: const TextStyle(color: Color(0xFFFF8A8F))),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _cell(String v, int idx, bool win) {
    final color = v == '1' ? _kRed : v == '2' ? _kYellow : null;
    final disc = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color ?? const Color(0xFF0B1030),
        gradient: color == null
            ? null
            : RadialGradient(center: const Alignment(-0.3, -0.4), colors: [Color.lerp(color, Colors.white, 0.45)!, color, Color.lerp(color, Colors.black, 0.3)!], stops: const [0, 0.55, 1]),
        border: win ? Border.all(color: Colors.white, width: 3) : null,
        boxShadow: [if (win) const BoxShadow(color: Colors.white, blurRadius: 12)],
      ),
    );
    if (color == null || idx != _lastPlaced) return disc;
    // le pion qui vient d'être posé tombe dans sa colonne
    return TweenAnimationBuilder<double>(
      key: ValueKey('drop$idx${g['moves']}'),
      tween: Tween(begin: -((idx ~/ 7) + 1).toDouble(), end: 0),
      duration: Duration(milliseconds: 180 + (idx ~/ 7) * 45),
      curve: Curves.easeIn,
      builder: (_, y, child) => FractionalTranslation(translation: Offset(0, y * 1.15), child: child),
      child: disc,
    );
  }

  Widget _result(String oppName, int stake) {
    final w = (g['winner'] as num?)?.toInt();
    final reason = g['reason'];
    final (title, sub) = w == 0
        ? (t('Match nul', 'Draw'), t('Chacun récupère ses $stake pièces', 'Each player gets their $stake coins back'))
        : w == side
            ? (
                t('🏆 Victoire ! +${stake * 2} pièces +1 pixel', '🏆 Victory! +${stake * 2} coins +1 pixel'),
                reason == 'timeout'
                    ? t('$oppName n\'a pas joué à temps', '$oppName ran out of time')
                    : reason == 'resign'
                        ? t('$oppName a abandonné', '$oppName resigned')
                        : t('Quatre pions alignés !', 'Four in a row!'),
              )
            : (
                t('Défaite', 'Defeat'),
                reason == 'timeout'
                    ? t('Temps écoulé : ta mise est perdue', 'Time out: you lose your bet')
                    : reason == 'resign'
                        ? t('Tu as abandonné : ta mise est perdue', 'You resigned: you lose your bet')
                        : t('$oppName a aligné quatre pions', '$oppName got four in a row'),
              );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(14), border: Border.all(color: kGold, width: 2)),
      child: Column(children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
        const SizedBox(height: 4),
        Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
        const SizedBox(height: 10),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
          onPressed: () => Navigator.pop(context),
          child: Text(t('Retour au salon', 'Back to the lobby'), style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
      ]),
    );
  }
}
