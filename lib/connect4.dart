import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'audio.dart';
import 'cards.dart';
import 'duel_watch.dart';
import 'game.dart';
import 'layout.dart';
import 'main.dart';
import 'retro_theme.dart';
import 'server.dart';

part 'battleship.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 4 en ligne à 2 joueurs (onglet « Bonus / Jeux ») : gratuit, le gagnant
// gagne 150 pièces + 1 pixel, le perdant 10 pièces de consolation. « En direct » : 1 min par coup, contre un joueur
// en ligne. « Tour par tour » : 24 h par coup. Tout est vérifié par le serveur
// (rc_c4_*). Plateau : 42 caractères, case (ligne r de 0 en haut, colonne c) = r*7 + c.
// ═══════════════════════════════════════════════════════════════════════════

const _kRed = Color(0xFFFF4757), _kYellow = Color(0xFFFFD23F), _kNeon = Color(0xFFFF4FD8), _kCyan = Color(0xFF3EE6FF);
const _kTeal = Color(0xFF5DCAA5), _kGoldHi = Color(0xFFFFD166);
const kC4Stake = 50; // ancienne mise (parties commencées avant les parties gratuites)
const kDuelWin = 150, kDuelLose = 10; // parties gratuites : gain du gagnant (+1 pixel), consolation du perdant

/// Gain du gagnant : les deux mises pour une ancienne partie, sinon 150
int duelPrize(int stake) => stake > 0 ? stake * 2 : kDuelWin;

/// Ce que gagne le perdant (ou chacun sur un match nul) : sa mise est perdue (ancienne partie) ou 10 pièces
String duelLoseText(int stake) => stake > 0 ? '−$stake' : '+$kDuelLose';

/// Partie amicale : pas de gains (adversaire de moins d'un jour, ou déjà 4 parties payées aujourd'hui contre lui)
bool duelFriendly(Map g) => g['paid'] == false;
String get duelFriendlyText => t('Partie amicale : pas de gains', 'Friendly game: no rewards');

/// Pourquoi la partie sera amicale (renvoyé par le serveur : 'new' ou 'limit')
String duelWhyText(String? why) => why == 'new'
    ? t('un des deux comptes a moins d\'un jour', 'one of the accounts is less than a day old')
    : t('déjà 4 parties payées aujourd\'hui contre ce joueur', 'already 4 paid games today against this player');

/// « Partie amicale (sans gains) : … » avant de jouer
String duelWhyLine(String? why) => t('🤝 Partie amicale, sans gains : ${duelWhyText(why)}', '🤝 Friendly game, no rewards: ${duelWhyText(why)}');
String get duelLimitsText => t(
    'Gains seulement contre un joueur inscrit depuis au moins un jour, et 4 parties payées par jour contre le même adversaire. Au-delà : parties amicales, sans gains.',
    'Rewards only against players who joined at least a day ago, and 4 paid games a day against the same opponent. After that: friendly games, no rewards.');
const _kEmotes = ['👍', '😮', '😂', '🔥', '👏'];

Widget _avatar(int a, {double size = 40, Color? ring}) => Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(shape: BoxShape.circle, color: ring ?? const Color(0xFF3A4590)),
      child: avatarWidget(a, size: size),
    );

int _i(dynamic v, [int d = 0]) => (v as num?)?.toInt() ?? d;

/// Pièce dorée dessinée
class _Coin extends StatelessWidget {
  final double size;
  const _Coin({this.size = 14});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(center: Alignment(-0.3, -0.4), colors: [Color(0xFFFFF3C4), _kGoldHi, Color(0xFFC98A12)], stops: [0, 0.45, 1]),
          boxShadow: [BoxShadow(color: Color(0x55000000), offset: Offset(0, 1))],
        ),
      );
}

/// Mini plateau (case de l'onglet, miniatures des parties)
class _Thumb extends StatelessWidget {
  final String board;
  final double width;
  const _Thumb(this.board, {this.width = 52});
  @override
  Widget build(BuildContext context) {
    final cell = (width - 8) / 7;
    return Container(
      width: width,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF2D64D6), Color(0xFF1D47A8)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        borderRadius: BorderRadius.circular(width * 0.11),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var r = 0; r < 6; r++)
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (var c = 0; c < 7; c++)
              Container(
                width: cell - 1,
                height: cell - 1,
                margin: const EdgeInsets.all(0.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: board.length > r * 7 + c && board[r * 7 + c] == '1'
                      ? _kRed
                      : board.length > r * 7 + c && board[r * 7 + c] == '2'
                          ? _kYellow
                          : const Color(0xFF0B1030),
                ),
              ),
          ]),
      ]),
    );
  }
}

const _kTileBoard = '000000000000000001000000210000212000211202';

/// Case de l'onglet Bonus / Jeux
class Connect4Tile extends StatefulWidget {
  const Connect4Tile({super.key});
  @override
  State<Connect4Tile> createState() => _Connect4TileState();
}

class _Connect4TileState extends State<Connect4Tile> {
  int myTurn = 0, invites = 0, online = 0;

  int _lastBadge = -1;

  @override
  void initState() {
    super.initState();
    _load();
    DuelWatch.i.addListener(_onWatch);
  }

  @override
  void dispose() {
    DuelWatch.i.removeListener(_onWatch);
    super.dispose();
  }

  /// Une invitation ou un tour vient d'arriver (ou de partir) : on recharge la case
  void _onWatch() {
    final b = DuelWatch.i.badge;
    if (b == _lastBadge) return;
    _lastBadge = b;
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([RcServer.c4List(), RcServer.c4Online()]);
      if (!mounted) return;
      setState(() {
        myTurn = r[0].where((g) => g['status'] == 'playing' && g['turn'] == g['side']).length;
        invites = r[0].where((g) => g['status'] == 'invite' && g['side'] == 2).length;
        online = r[1].length;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final status = online > 0 ? t('$online en ligne', '$online online') : '';
    final alert = myTurn + invites > 0;
    return Material(
      color: kPanel,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const Connect4Lobby()));
          _load();
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(colors: [_kRed.withOpacity(0.16), Colors.transparent]),
            boxShadow: [BoxShadow(color: alert ? const Color(0xFFE24B4A).withOpacity(0.6) : _kRed.withOpacity(0.25), blurRadius: alert ? 22 : 18, spreadRadius: alert ? 0 : -6)],
          ),
          // bordure dessinée par-dessus le panneau du plateau (sinon il mange les coins arrondis)
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kRed.withOpacity(0.75), width: 2),
          ),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                width: 100,
                alignment: Alignment.center,
                decoration: const BoxDecoration(gradient: RadialGradient(colors: [Color(0xFF2A3B8A), Color(0xFF11184A)])),
                child: const _Thumb(_kTileBoard, width: 70),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(t('4 en ligne', 'Connect 4'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 3),
                    Text(t('Défie un joueur, c\'est gratuit : le gagnant gagne $kDuelWin pièces + 1 pixel, le perdant $kDuelLose',
                            'Challenge a player, it\'s free: the winner gets $kDuelWin coins + 1 pixel, the loser $kDuelLose'),
                        style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    if (status.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(status, style: const TextStyle(color: _kRed, fontSize: 12, fontWeight: FontWeight.w800)),
                    ],
                    if (alert) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        if (myTurn > 0) PulsePill(t('🎮 À toi de jouer${myTurn > 1 ? ' ($myTurn)' : ''}', '🎮 Your turn${myTurn > 1 ? ' ($myTurn)' : ''}')),
                        if (invites > 0) PulsePill(t('⚔ $invites invitation${invites > 1 ? 's' : ''}', '⚔ $invites invitation${invites > 1 ? 's' : ''}')),
                      ]),
                    ],
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Badge(
                    isLabelVisible: myTurn + invites > 0,
                    largeSize: 22,
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                    label: Text('${myTurn + invites}'),
                    child: const Icon(Icons.play_arrow_rounded, color: _kRed, size: 32),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── Salon (commun au 4 en ligne et à Console Wars) ─────────────────────────
/// Ce qui change d'un jeu à l'autre dans le salon
class DuelKind {
  final String title, liveSub, turnSub;
  final Future<List<Map<String, dynamic>>> Function() list, online, top;
  final Future<Map<String, dynamic>> Function() stats;
  final Future<Map<String, dynamic>> Function(String pid, String mode) invite;
  final Future<Map<String, dynamic>> Function(int id, bool accept) answer;
  final Widget Function(Map g) thumb; // miniature d'une partie tour par tour
  final Widget Function(Map<String, dynamic> g) page; // écran de jeu
  const DuelKind({
    required this.title,
    required this.liveSub,
    required this.turnSub,
    required this.list,
    required this.online,
    required this.top,
    required this.stats,
    required this.invite,
    required this.answer,
    required this.thumb,
    required this.page,
  });
}

final kC4Duel = DuelKind(
  title: '4 EN LIGNE',
  liveSub: '1 min par coup',
  turnSub: '24 h par coup',
  list: RcServer.c4List,
  online: RcServer.c4Online,
  top: RcServer.c4Top,
  stats: RcServer.c4Stats,
  invite: RcServer.c4Invite,
  answer: RcServer.c4Answer,
  thumb: (g) => _Thumb(g['board'] as String? ?? ''),
  page: (g) => Connect4GamePage(initial: g),
);

class Connect4Lobby extends StatefulWidget {
  final DuelKind? kind;
  final (String, String, int)? inviteOnOpen; // défier tout de suite ce joueur en direct (pid, pseudo, avatar)
  const Connect4Lobby({super.key, this.kind, this.inviteOnOpen});
  @override
  State<Connect4Lobby> createState() => _Connect4LobbyState();
}

class _Connect4LobbyState extends State<Connect4Lobby> {
  DuelKind get k => widget.kind ?? kC4Duel;
  List<Map<String, dynamic>> games = [], online = [], top = [];
  Map<String, dynamic> stats = {};
  bool loaded = false, busy = false, inGame = false;
  int tab = 0; // 0 en direct, 1 tour par tour
  Timer? _poll;
  final _opened = <int>{}; // parties en direct déjà ouvertes automatiquement
  final _wait = ValueNotifier<String?>(null); // défi en direct en attente : null, 'ok' (accepté), 'no' (refusé / expiré)
  int? _waitId;

  @override
  void initState() {
    super.initState();
    _load(full: true).then((_) {
      final p = widget.inviteOnOpen;
      if (p != null && mounted) _invite(p.$1, p.$2, p.$3, 'live');
    });
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!inGame) _load();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _wait.dispose();
    super.dispose();
  }

  Future<void> _load({bool full = false}) async {
    try {
      final r = await Future.wait([k.list(), k.online()]);
      if (full || !loaded) {
        final s = await Future.wait([k.stats().then((v) => [v]), k.top()]);
        stats = (s[0] as List).first as Map<String, dynamic>;
        top = s[1] as List<Map<String, dynamic>>;
      }
      if (!mounted) return;
      setState(() {
        games = r[0];
        online = r[1];
        loaded = true;
      });
      // défi en direct en attente : accepté → on ouvre la partie ; refusé / expiré → on prévient
      if (_waitId != null) {
        final m = games.where((x) => _i(x['id']) == _waitId);
        final g = m.isEmpty ? null : m.first;
        if (g != null && g['status'] == 'playing') {
          _wait.value = 'ok';
          _waitId = null;
        } else if (g == null || g['status'] == 'done') {
          _wait.value = 'no';
          _waitId = null;
          toast(t('Défi refusé ou expiré', 'Challenge declined or expired'));
        }
      }
      for (final g in games) {
        final id = _i(g['id']);
        if (g['mode'] == 'live' && g['status'] == 'playing' && !_opened.contains(id) && DuelWatch.i.inGame == 0) {
          _opened.add(id);
          RcAudio.sfx('powerup');
          _openGame(g);
          break;
        }
      }
    } catch (e) {
      if (mounted && !loaded) setState(() => loaded = true);
    }
  }

  Future<void> _openGame(Map<String, dynamic> g) async {
    _opened.add(_i(g['id']));
    inGame = true;
    final again = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => k.page(g)));
    inGame = false;
    Game.i.sync();
    await _load(full: true);
    if (again != null && mounted) _invite(again['pid'] as String, again['name'] as String? ?? '?', again['avatar'] as int? ?? 0, again['mode'] as String);
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() f, {bool open = false, String? ok}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final g = await f();
      if (ok != null) toast(ok);
      Game.i.sync();
      if (open && g['status'] == 'playing') {
        RcAudio.sfx('powerup');
        await _openGame(g);
      } else {
        await _load();
      }
    } catch (e) {
      toast(errText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _invite(String pid, String name, int avatar, String mode, {String? friendly}) async {
    if (busy) return;
    // prévenir avant d'envoyer le défi : cette partie ne rapportera rien
    if (friendly != null) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('Partie amicale', 'Friendly game')),
          content: Text(t('Cette partie ne rapportera ni pièces ni pixel : ${duelWhyText(friendly)}.\n\nDéfier $name quand même ?',
              'This game won\'t give coins or pixels: ${duelWhyText(friendly)}.\n\nChallenge $name anyway?')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Annuler', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Défier', 'Challenge'))),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    setState(() => busy = true);
    try {
      final g = await k.invite(pid, mode);
      RcAudio.sfx('continue');
      if (mode == 'live') {
        _waitId = _i(g['id']);
        _wait.value = null;
        if (mounted) setState(() => busy = false);
        final cancel = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _WaitDialog(name: name, avatar: avatar, deadline: g['deadline'] as String?, now: g['now'] as String?, state: _wait, friendly: g['friendly'] as String?),
        );
        if (cancel == true && _waitId != null) {
          final id = _waitId!;
          _waitId = null;
          try {
            await k.answer(id, false);
            toast(t('Défi annulé', 'Challenge cancelled'));
          } catch (_) {}
        }
        await _load();
      } else {
        toast(t('Invitation envoyée à $name', 'Invitation sent to $name'));
        await _load();
      }
    } catch (e) {
      RcAudio.wrong();
      toast(errText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _pickTurnOpponent() async {
    final p = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kBg.withOpacity(0.97),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _PlayerPicker(),
    );
    if (p != null) _invite(p['pid'] as String, p['name'] as String? ?? '?', _i(p['avatar']), 'turn');
  }

  Duration _leftOf(Map g) {
    final now = DateTime.tryParse(g['now'] as String? ?? '') ?? DateTime.now();
    final dl = DateTime.tryParse(g['deadline'] as String? ?? '');
    return dl == null ? Duration.zero : dl.difference(now);
  }

  String _left(Map g) {
    final d = _leftOf(g);
    if (d.isNegative) return t('expiré', 'expired');
    if (d.inHours >= 1) return '${d.inHours} h';
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  String _name(Map g) => (g['opp'] as Map?)?['name'] as String? ?? '?';
  int _av(Map g) => _i((g['opp'] as Map?)?['avatar']);

  // ── éléments ──
  Widget _section(String title, {String sub = '', Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12))),
          if (trailing != null) trailing,
        ]),
      );

  Widget _card({required Widget lead, required Widget title, required List<Widget> lines, List<Widget> btns = const [], Color? border, Color? glow}) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
        decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: border ?? Colors.white10, width: border != null ? 1.5 : 1),
          gradient: glow != null ? LinearGradient(colors: [glow.withOpacity(0.18), Colors.transparent]) : null,
          boxShadow: [if (glow != null) BoxShadow(color: glow.withOpacity(0.35), blurRadius: 14, spreadRadius: -6)],
        ),
        child: Row(children: [
          lead,
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DefaultTextStyle.merge(style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14), child: title),
              for (final l in lines) DefaultTextStyle.merge(style: const TextStyle(fontSize: 11.5, color: Colors.white60), child: l),
            ]),
          ),
          ...btns,
        ]),
      );

  Widget _btn(String label, VoidCallback? onTap, {bool ghost = false}) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: ghost
            ? OutlinedButton(
                onPressed: busy ? null : onTap,
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, side: const BorderSide(color: Colors.white30)),
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
              )
            : FilledButton(
                onPressed: busy ? null : onTap,
                style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800), visualDensity: VisualDensity.compact),
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
      );

  Widget _hero() {
    Widget stat(String v, String label, Color c) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), borderRadius: BorderRadius.circular(10)),
            child: Column(children: [
              FittedBox(child: Text(v, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: c))),
              Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.white54)),
            ]),
          ),
        );
    final net = _i(stats['net']);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kNeon.withOpacity(0.55), width: 2),
        gradient: const LinearGradient(colors: [Color(0xFF2A1360), Color(0xFF12184E)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: _kNeon.withOpacity(0.35), blurRadius: 24, spreadRadius: -8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('DUEL ARCADE', style: pixelStyle(size: 14, color: Colors.white, shadow: false).copyWith(shadows: const [Shadow(color: _kNeon, blurRadius: 10)])),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: t('Parties gratuites ! Le gagnant gagne ', 'Free games! The winner gets ')),
                  TextSpan(text: t('$kDuelWin pièces + 1 pixel', '$kDuelWin coins + 1 pixel'), style: const TextStyle(color: _kGoldHi, fontWeight: FontWeight.w900)),
                  TextSpan(text: t(', le perdant ', ', the loser ')),
                  TextSpan(text: t('$kDuelLose pièces', '$kDuelLose coins'), style: const TextStyle(color: _kGoldHi, fontWeight: FontWeight.w900)),
                  TextSpan(text: t('. Match nul : $kDuelLose chacun. Délai dépassé = abandon.', '. Draw: $kDuelLose each. Time out = forfeit.')),
                ]),
                style: const TextStyle(color: Color(0xFFCFD3FF), fontSize: 12.5, height: 1.4),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Column(children: [
            SizedBox(
              width: 46,
              height: 40,
              child: Stack(children: [for (var k = 0; k < 4; k++) Positioned(left: 4, bottom: k * 7.0, child: Container(width: 38, height: 11, decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: const RadialGradient(colors: [Color(0xFFFFF3C4), _kGoldHi, Color(0xFFC98A12)], stops: [0, 0.45, 1]), boxShadow: const [BoxShadow(color: Color(0xFF8A5A08), offset: Offset(0, 2))])))]),
            ),
            Text('GAIN $kDuelWin', style: pixelStyle(size: 8, color: _kGoldHi, shadow: false)),
          ]),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          stat('${_i(stats['wins'])}', t('victoires', 'wins'), _kTeal),
          stat('${_i(stats['losses'])}', t('défaites', 'losses'), const Color(0xFFFF8A95)),
          stat('${_i(stats['streak'])}', t('série 🔥', 'streak 🔥'), _kGoldHi),
          stat('${net >= 0 ? '+' : ''}$net', t('pièces', 'coins'), Colors.white),
        ]),
      ]),
    );
  }

  Widget _tabs(int liveCount, int turnCount) {
    Widget tabBtn(int i, String label, String sub, int count, Color badge) => Expanded(
          child: GestureDetector(
            onTap: () {
              RcAudio.sfx('jump');
              setState(() => tab = i);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: tab == i ? const Color(0xFF242D6E) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tab == i ? kGold : Colors.transparent, width: 1.5),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Column(children: [
                  Text(label, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: tab == i ? Colors.white : Colors.white60)),
                  Text(sub, style: const TextStyle(fontSize: 10.5, color: Colors.white54)),
                ]),
                if (count > 0) ...[
                  const SizedBox(width: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: badge, borderRadius: BorderRadius.circular(9)),
                    child: Text('$count', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white)),
                  ),
                ],
              ]),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), borderRadius: BorderRadius.circular(13)),
      child: Row(children: [
        tabBtn(0, t('En direct', 'Live'), t(k.liveSub, k.liveSub), liveCount, _kTeal),
        const SizedBox(width: 4),
        tabBtn(1, t('Tour par tour', 'Turn-based'), t(k.turnSub, k.turnSub), turnCount, _kRed),
      ]),
    );
  }

  Widget _empty(String text) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
      );

  @override
  Widget build(BuildContext context) {
    final invitesIn = games.where((g) => g['status'] == 'invite' && g['side'] == 2).toList();
    final liveGames = games.where((g) => g['mode'] == 'live' && g['status'] == 'playing').toList();
    final liveOut = games.where((g) => g['mode'] == 'live' && g['status'] == 'invite' && g['side'] == 1).toList();
    final myTurn = games.where((g) => g['mode'] == 'turn' && g['status'] == 'playing' && g['turn'] == g['side']).toList();
    final theirTurn = games.where((g) => g['mode'] == 'turn' && g['status'] == 'playing' && g['turn'] != g['side']).toList();
    final turnOut = games.where((g) => g['mode'] == 'turn' && g['status'] == 'invite' && g['side'] == 1).toList();
    final done = games.where((g) => g['status'] == 'done' && !['declined', 'cancelled', 'expired'].contains(g['reason'])).take(8).toList();

    final children = <Widget>[
      _hero(),
      // invitations reçues
      for (final g in invitesIn)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: _card(
            lead: _avatar(_av(g), ring: (g['opp'] as Map?)?['online'] == true ? _kTeal : null),
            title: Text(t('${_name(g)} te défie ⚔', '${_name(g)} challenges you ⚔'), maxLines: 1, overflow: TextOverflow.ellipsis),
            lines: [Text('${g['mode'] == 'live' ? t('En direct', 'Live') : t('Tour par tour', 'Turn-based')} · ${_i(g['stake'], kC4Stake) > 0 ? '${_i(g['stake'], kC4Stake)} ${t('pièces', 'coins')}' : g['friendly'] != null ? t('amicale, sans gains', 'friendly, no rewards') : t('gratuit', 'free')}')],
            btns: [
              _Countdown(total: g['mode'] == 'live' ? 120 : 86400, left: _leftOf(g), label: _left(g)),
              _btn(t('Jouer', 'Play'), () => _run(() => k.answer(_i(g['id']), true), open: true)),
              IconButton(
                onPressed: busy ? null : () => _run(() => k.answer(_i(g['id']), false), ok: t('Défi refusé', 'Challenge declined')),
                icon: const Icon(Icons.close, color: Color(0xFFFFC4CF)),
                style: IconButton.styleFrom(backgroundColor: const Color(0xFF4A1D2A)),
                visualDensity: VisualDensity.compact,
              ),
            ],
            border: _kNeon,
            glow: _kNeon,
          ),
        ),
      const SizedBox(height: 12),
      _tabs(online.length, myTurn.length),
    ];

    if (tab == 0) {
      children.addAll([
        if (liveGames.isNotEmpty) ...[
          _section(t('Parties en cours', 'Games in progress')),
          for (final g in liveGames)
            _card(
              lead: _avatar(_av(g), ring: _kTeal),
              title: Text(_name(g)),
              lines: [Text(g['turn'] == g['side'] ? t('À toi de jouer !', 'Your turn!') : t('Son tour', 'Their turn'), style: const TextStyle(color: kGold, fontWeight: FontWeight.w800))],
              btns: [_btn(t('Reprendre', 'Resume'), () => _openGame(g))],
              border: kGold,
              glow: kGold,
            ),
        ],
        _section(t('Joueurs en ligne', 'Online players'), trailing: const _LiveTag()),
        if (online.isEmpty) _empty(t('Personne d\'autre en ligne pour l\'instant · reviens plus tard ou joue en tour par tour', 'Nobody else online right now · come back later or play turn-based')),
        for (final p in online)
          Builder(builder: (_) {
            final w = _i(p['w']), l = _i(p['l']);
            final busyP = p['busy'] == true;
            final poor = p['coins_ok'] == false; // moins de 50 pièces : ne peut pas être défié
            return _card(
              lead: _avatar(_i(p['avatar']), ring: _kTeal),
              title: Row(children: [
                Flexible(child: Text(p['name'] as String? ?? '?', maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFF2A3470), borderRadius: BorderRadius.circular(4)),
                  child: Text(t('$w V · $l D', '$w W · $l L'), style: pixelStyle(size: 6.5, color: const Color(0xFFCFD3FF), shadow: false)),
                ),
              ]),
              lines: [
                Text(busyP
                    ? t('⚔ En partie', '⚔ In a game')
                    : poor
                        ? t('Pas assez de pièces pour jouer', 'Not enough coins to play')
                        : t('Disponible · ${p['score']} pts', 'Available · ${p['score']} pts')),
                if (p['friendly'] != null)
                  Text(t('🤝 Amicale (sans gains) : ${duelWhyText(p['friendly'] as String?)}', '🤝 Friendly (no rewards): ${duelWhyText(p['friendly'] as String?)}'),
                      style: const TextStyle(color: Color(0xFFFFC46B), fontSize: 11.5)),
                Padding(
                  padding: const EdgeInsets.only(top: 5, right: 6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(value: w + l == 0 ? 0 : w / (w + l), minHeight: 4, color: _kTeal, backgroundColor: Colors.white10),
                  ),
                ),
              ],
              btns: [
                _btn(busyP ? t('Occupé', 'Busy') : (poor ? t('Sans pièces', 'No coins') : t('Défier', 'Challenge')),
                    busyP || poor ? null : () => _invite(p['pid'] as String, p['name'] as String? ?? '?', _i(p['avatar']), 'live', friendly: p['friendly'] as String?))
              ],
            );
          }),
        _section(t('Défis envoyés', 'Challenges sent')),
        if (liveOut.isEmpty) _empty(t('Aucun défi en attente · touche « Défier » sur un joueur en ligne', 'No pending challenge · tap « Challenge » on an online player')),
        for (final g in liveOut)
          _card(
            lead: _avatar(_av(g)),
            title: Text(_name(g)),
            lines: [Text(t('Attend sa réponse · ${_left(g)}', 'Waiting for an answer · ${_left(g)}'))],
            btns: [_btn(t('Annuler', 'Cancel'), () => _run(() => k.answer(_i(g['id']), false), ok: t('Défi annulé', 'Challenge cancelled')), ghost: true)],
          ),
      ]);
    } else {
      children.addAll([
        _section(t('À toi de jouer', 'Your turn')),
        if (myTurn.isEmpty) _empty(t('Aucune partie où c\'est ton tour', 'No game waiting for you')),
        for (final g in myTurn)
          _card(
            lead: k.thumb(g),
            title: Text(_name(g)),
            lines: [
              Text(t('À toi de jouer · reste ${_left(g)}', 'Your turn · ${_left(g)} left'), style: const TextStyle(color: _kGoldHi, fontWeight: FontWeight.w800)),
              Text(t('Coup ${_i(g['moves']) + 1} · tu es ${g['side'] == 1 ? 'rouge' : 'jaune'}', 'Move ${_i(g['moves']) + 1} · you are ${g['side'] == 1 ? 'red' : 'yellow'}')),
            ],
            btns: [_btn(t('Jouer', 'Play'), () => _openGame(g))],
            border: kGold,
            glow: kGold,
          ),
        _section(t('En attente', 'Waiting'), sub: t('leur tour', 'their turn')),
        for (final g in theirTurn)
          _card(
            lead: k.thumb(g),
            title: Text(_name(g)),
            lines: [
              Text(t('Au tour de ${_name(g)} · reste ${_left(g)}', '${_name(g)}\'s turn · ${_left(g)} left')),
              Text(t('Coup ${_i(g['moves']) + 1} · tu es ${g['side'] == 1 ? 'rouge' : 'jaune'}', 'Move ${_i(g['moves']) + 1} · you are ${g['side'] == 1 ? 'red' : 'yellow'}')),
            ],
            btns: [_btn(t('Voir', 'View'), () => _openGame(g), ghost: true)],
          ),
        for (final g in turnOut)
          _card(
            lead: _avatar(_av(g)),
            title: Text(_name(g)),
            lines: [Text(t('Invitation envoyée · expire dans ${_left(g)}', 'Invitation sent · expires in ${_left(g)}'))],
            btns: [_btn(t('Annuler', 'Cancel'), () => _run(() => k.answer(_i(g['id']), false), ok: t('Invitation annulée', 'Invitation cancelled')), ghost: true)],
          ),
        if (theirTurn.isEmpty && turnOut.isEmpty) _empty(t('Aucune partie en attente', 'No game waiting')),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: busy ? null : _pickTurnOpponent,
            icon: const Icon(Icons.add),
            label: Text(t('Nouvelle partie tour par tour', 'New turn-based game'), style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ]);
    }

    children.addAll([
      if (top.isNotEmpty) ...[
        _section(t('Meilleurs joueurs', 'Top players'), sub: t('cette semaine', 'this week')),
        for (var i = 0; i < top.length && i < 5; i++)
          _card(
            lead: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 22,
                child: Text('${i + 1}',
                    textAlign: TextAlign.center,
                    style: pixelStyle(size: 9, color: i == 0 ? _kGoldHi : i == 1 ? const Color(0xFFD8DFF0) : i == 2 ? const Color(0xFFE6A26A) : Colors.white54, shadow: false)),
              ),
              const SizedBox(width: 6),
              _avatar(_i(top[i]['avatar']), size: 34, ring: top[i]['online'] == true ? _kTeal : null),
            ]),
            title: Text(top[i]['pid'] == Game.i.pid ? t('${top[i]['name']} (toi)', '${top[i]['name']} (you)') : top[i]['name'] as String? ?? '?'),
            lines: [Text(t('${top[i]['wins']} victoire${_i(top[i]['wins']) > 1 ? 's' : ''} cette semaine', '${top[i]['wins']} win${_i(top[i]['wins']) > 1 ? 's' : ''} this week'))],
            btns: [if (i == 0) const Padding(padding: EdgeInsets.only(right: 6), child: Text('👑', style: TextStyle(fontSize: 18)))],
          ),
      ],
      if (done.isNotEmpty) ...[
        _section(t('Résultats récents', 'Recent results')),
        for (final g in done)
          _card(
            lead: _avatar(_av(g)),
            title: Text(_name(g)),
            lines: [_resultLine(g), Text(g['mode'] == 'live' ? t('En direct', 'Live') : t('Tour par tour', 'Turn-based'))],
            btns: [
              _btn(t('Revanche', 'Rematch'), () {
                final o = g['opp'] as Map? ?? const {};
                _invite(o['pid'] as String? ?? '', o['name'] as String? ?? '?', _i(o['avatar']), g['mode'] as String? ?? 'turn');
              }, ghost: true),
            ],
          ),
      ],
    ]);

    return MaxWidth(
      max: 760,
      child: Scaffold(
        appBar: AppBar(
          title: Text(k.title, style: pixelStyle(size: 13)),
          actions: [ListenableBuilder(listenable: Game.i, builder: (_, __) => CoinChip(Game.i.coins)), const SizedBox(width: 12)],
        ),
        body: !loaded
            ? const Center(child: CircularProgressIndicator(color: kGold))
            : RefreshIndicator(
                onRefresh: () => _load(full: true),
                child: ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 24), children: children),
              ),
      ),
    );
  }
}

/// « LIVE » qui pulse
class _LiveTag extends StatefulWidget {
  const _LiveTag();
  @override
  State<_LiveTag> createState() => _LiveTagState();
}

class _LiveTagState extends State<_LiveTag> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        AnimatedBuilder(
          animation: c,
          builder: (_, __) => Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kTeal,
              boxShadow: [BoxShadow(color: _kTeal.withOpacity(1 - c.value), spreadRadius: 6 * c.value)],
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text('LIVE', style: pixelStyle(size: 7, color: _kTeal, shadow: false)),
      ]);
}

/// Petit anneau de compte à rebours (invitations)
class _Countdown extends StatelessWidget {
  final int total; // secondes
  final Duration left;
  final String label;
  const _Countdown({required this.total, required this.left, required this.label});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 36,
        height: 36,
        child: Stack(alignment: Alignment.center, children: [
          CircularProgressIndicator(value: (left.inSeconds / total).clamp(0.0, 1.0), strokeWidth: 3, color: _kNeon, backgroundColor: Colors.white12),
          FittedBox(child: Padding(padding: const EdgeInsets.all(5), child: Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900)))),
        ]),
      );
}

/// Défi en direct envoyé : on attend la réponse (2 minutes)
class _WaitDialog extends StatefulWidget {
  final String name;
  final int avatar;
  final String? deadline, now;
  final ValueNotifier<String?> state;
  final String? friendly; // partie amicale : raison
  const _WaitDialog({required this.name, required this.avatar, required this.deadline, required this.now, required this.state, this.friendly});
  @override
  State<_WaitDialog> createState() => _WaitDialogState();
}

class _WaitDialogState extends State<_WaitDialog> {
  Timer? _t;
  late final DateTime _end;

  @override
  void initState() {
    super.initState();
    final now = DateTime.tryParse(widget.now ?? '') ?? DateTime.now();
    final dl = DateTime.tryParse(widget.deadline ?? '') ?? now.add(const Duration(minutes: 2));
    _end = DateTime.now().add(dl.difference(now));
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    widget.state.addListener(_onState);
  }

  void _onState() {
    if (widget.state.value != null && mounted) Navigator.of(context).pop(false);
  }

  @override
  void dispose() {
    _t?.cancel();
    widget.state.removeListener(_onState);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = _end.difference(DateTime.now());
    final s = left.isNegative ? 0 : left.inSeconds;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF241A5E), Color(0xFF141A4C)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kNeon, width: 2),
          boxShadow: [BoxShadow(color: _kNeon.withOpacity(0.4), blurRadius: 30, spreadRadius: -8)],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _avatar(Game.i.avatar, size: 58),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text('VS', style: pixelStyle(size: 12, color: _kNeon, shadow: false).copyWith(shadows: const [Shadow(color: _kNeon, blurRadius: 8)])),
            ),
            _avatar(widget.avatar, size: 58),
          ]),
          const SizedBox(height: 12),
          Text(t('Défi envoyé à ${widget.name}', 'Challenge sent to ${widget.name}'),
              textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 12),
          SizedBox(
            width: 76,
            height: 76,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(child: CircularProgressIndicator(value: s / 120, strokeWidth: 6, color: _kCyan, backgroundColor: Colors.white12)),
              Text('${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}', style: pixelStyle(size: 11, color: _kCyan, shadow: false)),
            ]),
          ),
          const SizedBox(height: 12),
          Text(t('En attente de sa réponse…', 'Waiting for an answer…'), style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 4),
          Text(widget.friendly != null ? duelWhyLine(widget.friendly) : t('Partie gratuite : le gagnant gagne $kDuelWin pièces + 1 pixel.', 'Free game: the winner gets $kDuelWin coins + 1 pixel.'),
              textAlign: TextAlign.center, style: TextStyle(color: widget.friendly != null ? const Color(0xFFFFC46B) : Colors.white54, fontSize: 12)),
          const SizedBox(height: 14),
          OutlinedButton(onPressed: () => Navigator.of(context).pop(true), child: Text(t('Annuler le défi', 'Cancel the challenge'))),
        ]),
      ),
    );
  }
}

/// « Gagné · +150 pièces +1 pixel », « Perdu (temps écoulé) · +10 », « Match nul · +10 »
Widget _resultLine(Map g) {
  final w = (g['winner'] as num?)?.toInt();
  final side = _i(g['side'], 1);
  final stake = _i(g['stake'], kC4Stake);
  final why = switch (g['reason']) {
    'timeout' => t(' (temps écoulé)', ' (time out)'),
    'resign' => t(' (abandon)', ' (resigned)'),
    _ => '',
  };
  if (duelFriendly(g) && w != null) {
    return Text('${w == 0 ? t('Match nul', 'Draw') : w == side ? t('Gagné$why', 'Won$why') : t('Perdu$why', 'Lost$why')} · ${t('amicale', 'friendly')}',
        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800));
  }
  if (w == 0) {
    return Text(stake > 0 ? t('Match nul · mise rendue', 'Draw · bet returned') : t('Match nul · +$kDuelLose pièces', 'Draw · +$kDuelLose coins'),
        style: const TextStyle(fontWeight: FontWeight.w800));
  }
  if (w == side) {
    return Text(t('Gagné$why · +${duelPrize(stake)} pièces +1 pixel', 'Won$why · +${duelPrize(stake)} coins +1 pixel'), style: const TextStyle(color: _kTeal, fontWeight: FontWeight.w900));
  }
  return Text(t('Perdu$why · ${duelLoseText(stake)}', 'Lost$why · ${duelLoseText(stake)}'), style: const TextStyle(color: Color(0xFFFF8A95), fontWeight: FontWeight.w900));
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
                      const poor = false; // parties gratuites : tout le monde peut être défié
                      return ListTile(
                        enabled: !poor,
                        leading: _avatar(_i(p['avatar']), ring: p['online'] == true ? _kTeal : null),
                        title: Text(p['name'] as String? ?? '?', style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(poor
                            ? t('Pas assez de pièces pour jouer', 'Not enough coins to play')
                            : t('${p['score']} pts · ${p['cards']} cartes', '${p['score']} pts · ${p['cards']} cards')),
                        trailing: p['online'] == true ? const Icon(Icons.circle, size: 10, color: _kTeal) : null,
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

// ─── Partie ────────────────────────────────────────────────────────────────
class Connect4GamePage extends StatefulWidget {
  final Map<String, dynamic> initial;
  const Connect4GamePage({super.key, required this.initial});
  @override
  State<Connect4GamePage> createState() => _Connect4GamePageState();
}

class _Connect4GamePageState extends State<Connect4GamePage> {
  late Map<String, dynamic> g = widget.initial;
  bool busy = false, _resultShown = false;
  Timer? _poll, _tick;
  Duration _skew = Duration.zero; // heure du serveur - heure du téléphone
  int? _lastPlaced; // case du dernier pion posé (animation)
  int? _aim; // colonne visée (pion fantôme)
  String? _emoMe, _emoOpp; // bulles de réaction
  String? _emoOppAt;
  Timer? _emoMeT, _emoOppT;

  int get id => _i(g['id']);
  bool get live => g['mode'] == 'live';
  int get side => _i(g['side'], 1);
  bool get playing => g['status'] == 'playing';
  bool get myTurn => playing && _i(g['turn']) == side;
  int get stake => _i(g['stake'], kC4Stake);
  Map get opp => g['opp'] as Map? ?? const {};

  @override
  void initState() {
    super.initState();
    _setSkew();
    _emoOppAt = g['emo_opp_at'] as String?;
    _poll = Timer.periodic(Duration(seconds: live ? 2 : 6), (_) => _refresh());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      final s = _left().inSeconds;
      if (live && myTurn && s <= 10 && s > 0) RcAudio.tick();
      if (playing && _left().isNegative) _refresh(); // délai dépassé : le serveur règle la partie
    });
    if (g['status'] == 'done') WidgetsBinding.instance.addPostFrameCallback((_) => _showResult());
    _refresh();
    DuelWatch.i.inGame++;
  }

  @override
  void dispose() {
    DuelWatch.i.inGame--;
    _poll?.cancel();
    _tick?.cancel();
    _emoMeT?.cancel();
    _emoOppT?.cancel();
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
    final wasMyTurn = myTurn;
    setState(() {
      g = n;
      if (placed != null) _lastPlaced = placed;
    });
    _setSkew();
    if (placed != null) RcAudio.sfx(after[placed] == '$side' ? 'jump' : 'stomp');
    if (!wasMyTurn && myTurn) RcAudio.correct();
    // réaction de l'adversaire
    final at = n['emo_opp_at'] as String?;
    if (at != null && at != _emoOppAt) {
      _emoOppAt = at;
      _bubble(false, n['emo_opp'] as String? ?? '👍');
    }
    if (wasPlaying && !playing) _showResult();
  }

  Future<void> _refresh() async {
    try {
      final n = await RcServer.c4State(id);
      if (mounted) _apply(n);
    } catch (_) {}
  }

  Future<void> _play(int col) async {
    setState(() => _aim = null);
    if (busy) return;
    if (!myTurn) {
      RcAudio.wrong();
      toast(playing ? t('Ce n\'est pas ton tour', 'It\'s not your turn') : t('La partie est terminée', 'The game is over'));
      return;
    }
    if ((g['board'] as String)[col] != '0') {
      RcAudio.wrong();
      toast(t('Cette colonne est pleine', 'This column is full'));
      return;
    }
    setState(() => busy = true);
    try {
      _apply(await RcServer.c4Play(id, col));
    } catch (e) {
      RcAudio.wrong();
      toast(errText(e));
      _refresh();
    }
    if (mounted) setState(() => busy = false);
  }

  void _bubble(bool me, String emo) {
    RcAudio.sfx('spring');
    setState(() => me ? _emoMe = emo : _emoOpp = emo);
    final timer = Timer(const Duration(milliseconds: 1900), () {
      if (mounted) setState(() => me ? _emoMe = null : _emoOpp = null);
    });
    if (me) {
      _emoMeT?.cancel();
      _emoMeT = timer;
    } else {
      _emoOppT?.cancel();
      _emoOppT = timer;
    }
  }

  Future<void> _emote(String e) async {
    _bubble(true, e);
    try {
      await RcServer.c4Emote(id, e);
    } catch (_) {}
  }

  Future<void> _resign() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Abandonner ?', 'Resign?')),
        content: Text(stake > 0
            ? t('Ta mise de $stake pièces est perdue, ton adversaire gagne.', 'You lose your $stake coins bet, your opponent wins.')
            : t('Ton adversaire gagne. Tu reçois quand même $kDuelLose pièces.', 'Your opponent wins. You still get $kDuelLose coins.')),
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

  void _rules() => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('Règles', 'Rules')),
          content: Text(t(
            'Aligne 4 pions de ta couleur : en ligne, en colonne ou en diagonale.\n\n'
                'Partie gratuite : le gagnant remporte $kDuelWin pièces + 1 pixel, le perdant $kDuelLose pièces. Match nul (plateau plein) : $kDuelLose pièces chacun. '
                'Gains seulement contre un joueur inscrit depuis au moins un jour, 4 parties payées par jour contre le même adversaire.\n\n'
                'En direct : 1 minute par coup. Tour par tour : 24 heures par coup. Délai dépassé = abandon.',
            'Line up 4 discs of your color: in a row, a column or a diagonal.\n\n'
                'Free game: the winner gets $kDuelWin coins + 1 pixel, the loser $kDuelLose coins. Draw (full board): $kDuelLose coins each. '
                'Rewards only against players who joined at least a day ago, 4 paid games a day against the same opponent.\n\n'
                'Live: 1 minute per move. Turn-based: 24 hours per move. Time out = forfeit.',
          )),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );

  Future<void> _showResult() async {
    if (_resultShown || !mounted) return;
    _resultShown = true;
    final w = (g['winner'] as num?)?.toInt();
    if (w == side) {
      RcAudio.win();
    } else if (w == 0) {
      RcAudio.sfx('shield');
    } else {
      RcAudio.lose();
    }
    Game.i.sync();
    Map<String, dynamic> stats = {};
    try {
      stats = await RcServer.c4Stats();
    } catch (_) {}
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    final again = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _ResultDialog(g: g, side: side, stats: stats),
    );
    if (!mounted) return;
    if (again == true) {
      Navigator.of(context).pop({'pid': opp['pid'], 'name': opp['name'], 'avatar': _i(opp['avatar']), 'mode': g['mode']});
    } else if (again == false) {
      Navigator.of(context).pop();
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
    final oppName = opp['name'] as String? ?? '?';
    final board = (g['board'] as String?) ?? '0' * 42;
    final win = _winCells(board);
    final left = _left();
    final turn = _i(g['turn'], 1);
    final myColor = side == 1 ? _kRed : _kYellow, oppColor = side == 1 ? _kYellow : _kRed;
    final limit = live ? 60 : 86400;
    final frac = playing ? (left.inSeconds / limit).clamp(0.0, 1.0) : 1.0;

    String timerText() {
      final d = left.isNegative ? Duration.zero : left;
      if (live) return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
      return '${d.inHours} h ${(d.inMinutes % 60).toString().padLeft(2, '0')}';
    }

    Widget player(String name, int avatar, Color color, bool on, String? emo, {bool right = false}) {
      final warn = on && live && left.inSeconds <= 10;
      return Expanded(
        child: Stack(clipBehavior: Clip.none, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kPanel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on ? kGold : Colors.transparent, width: 2),
              boxShadow: [if (on) BoxShadow(color: kGold.withOpacity(0.35), blurRadius: 14, spreadRadius: -4)],
            ),
            child: Row(textDirection: right ? TextDirection.rtl : TextDirection.ltr, children: [
              SizedBox(
                width: 50,
                height: 50,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(child: CircularProgressIndicator(value: on ? frac : 1, strokeWidth: 3.5, color: warn ? _kRed : color, backgroundColor: Colors.white10)),
                  avatarWidget(avatar, size: 40),
                  Positioned(
                    right: right ? null : 0,
                    left: right ? 0 : null,
                    bottom: 0,
                    child: Container(width: 14, height: 14, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: kPanel, width: 2))),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: right ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                  Text(stake > 0 ? t('mise $stake', 'bet $stake') : g['friendly'] != null ? t('amicale', 'friendly') : t('gratuit', 'free'), style: const TextStyle(fontSize: 11, color: Colors.white54)),
                  if (on && playing) Text(timerText(), style: pixelStyle(size: 8, color: warn ? _kRed : _kGoldHi, shadow: false)),
                ]),
              ),
            ]),
          ),
          if (emo != null)
            Positioned(
              top: -14,
              right: right ? null : 8,
              left: right ? 8 : null,
              child: TweenAnimationBuilder<double>(
                key: ValueKey(emo + (right ? 'o' : 'm')),
                tween: Tween(begin: 0.4, end: 1),
                duration: const Duration(milliseconds: 260),
                curve: Curves.elasticOut,
                builder: (_, s, child) => Transform.scale(scale: s, child: child),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)]),
                  child: Text(emo, style: const TextStyle(fontSize: 18)),
                ),
              ),
            ),
        ]),
      );
    }

    return MaxWidth(
      max: 560,
      child: Scaffold(
        appBar: AppBar(
          title: Text(live ? t('EN DIRECT', 'LIVE') : t('TOUR PAR TOUR', 'TURN-BASED'), style: pixelStyle(size: 12)),
          actions: [ListenableBuilder(listenable: Game.i, builder: (_, __) => CoinChip(Game.i.coins)), const SizedBox(width: 12)],
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 24), children: [
          Row(children: [
            player(t('Toi', 'You'), Game.i.avatar, myColor, playing && turn == side, _emoMe),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(children: [
                SizedBox(
                  width: 34,
                  height: 16,
                  child: Stack(children: [for (var k = 0; k < 3; k++) Positioned(left: k * 9.0, child: const _Coin(size: 16))]),
                ),
                Text(g['friendly'] != null ? '0' : '${duelPrize(stake)}', style: pixelStyle(size: 9, color: _kGoldHi, shadow: false)),
                Text(stake > 0 ? 'POT' : g['friendly'] != null ? t('AMICAL', 'FRIENDLY') : 'GAIN', style: TextStyle(fontSize: 9, color: Colors.white54, fontWeight: FontWeight.w800)),
              ]),
            ),
            player(oppName, _i(opp['avatar']), oppColor, playing && turn != side, _emoOpp, right: true),
          ]),
          const SizedBox(height: 10),
          if (g['status'] == 'invite')
            Text(t('En attente de la réponse de $oppName…', 'Waiting for $oppName to answer…'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))
          else
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (playing) Container(width: 14, height: 14, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(shape: BoxShape.circle, color: myTurn ? myColor : oppColor)),
              Text(
                playing
                    ? (myTurn ? t('À toi de jouer !', 'Your turn!') : t('$oppName réfléchit…', '$oppName is thinking…'))
                    : g['reason'] == 'draw'
                        ? t('Plateau plein', 'Board full')
                        : g['reason'] == 'win'
                            ? t('Quatre alignés !', 'Four in a row!')
                            : '',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
            ]),
          const SizedBox(height: 10),
          // borne d'arcade
          Container(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF1B2560), Color(0xFF10164A)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22), bottom: Radius.circular(10)),
              border: Border.all(color: const Color(0xFF313D8F), width: 2),
              boxShadow: [BoxShadow(color: _kCyan.withOpacity(0.25), blurRadius: 30, spreadRadius: -10)],
            ),
            child: Column(children: [
              Text('★ DUEL 4 ★', style: pixelStyle(size: 10, color: _kCyan, shadow: false).copyWith(letterSpacing: 3, shadows: const [Shadow(color: _kCyan, blurRadius: 8)])),
              const SizedBox(height: 6),
              // pion fantôme au-dessus de la colonne visée
              SizedBox(
                height: 26,
                child: Row(children: [
                  for (var c = 0; c < 7; c++)
                    Expanded(
                      child: Center(
                        child: AnimatedOpacity(
                          opacity: _aim == c && myTurn ? 0.9 : 0,
                          duration: const Duration(milliseconds: 120),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: myColor, boxShadow: [BoxShadow(color: myColor, blurRadius: 10)]),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
              AspectRatio(
                aspectRatio: 7 / 6.1,
                child: LayoutBuilder(builder: (context, box) {
                  int colAt(double x) => (x / box.maxWidth * 7).floor().clamp(0, 6);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => setState(() => _aim = colAt(d.localPosition.dx)),
                    onTapUp: (d) => _play(colAt(d.localPosition.dx)),
                    onTapCancel: () => setState(() => _aim = null),
                    onHorizontalDragUpdate: (d) {
                      final c = colAt(d.localPosition.dx);
                      if (c != _aim) setState(() => _aim = c);
                    },
                    onHorizontalDragEnd: (_) {
                      if (_aim != null) _play(_aim!);
                    },
                    child: MouseRegion(
                      onHover: (e) {
                        final c = colAt(e.localPosition.dx);
                        if (c != _aim) setState(() => _aim = c);
                      },
                      onExit: (_) => setState(() => _aim = null),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF2D64D6), Color(0xFF1D47A8)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: const [BoxShadow(color: Color(0xFF12306F), offset: Offset(0, 8))],
                        ),
                        child: Row(children: [
                          for (var c = 0; c < 7; c++)
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _aim == c && myTurn ? Colors.white.withOpacity(0.1) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(children: [
                                  for (var r = 0; r < 6; r++)
                                    Expanded(child: Padding(padding: const EdgeInsets.all(3), child: _cell(board[r * 7 + c], r * 7 + c, win.contains(r * 7 + c)))),
                                ]),
                              ),
                            ),
                        ]),
                      ),
                    ),
                  );
                }),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Row(children: [
                  Text(t('COUP ${_i(g['moves']) + (playing ? 1 : 0)}', 'MOVE ${_i(g['moves']) + (playing ? 1 : 0)}'),
                      style: pixelStyle(size: 8, color: Colors.white54, shadow: false)),
                  const Spacer(),
                  IconButton(
                    tooltip: t('Son', 'Sound'),
                    onPressed: () async {
                      await RcAudio.setSound(!RcAudio.soundOn);
                      setState(() {});
                    },
                    icon: Icon(RcAudio.soundOn ? Icons.volume_up : Icons.volume_off, color: Colors.white70),
                    style: IconButton.styleFrom(backgroundColor: Colors.white10),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          // réactions
          if (playing)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (final e in _kEmotes)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkResponse(
                    onTap: () => _emote(e),
                    radius: 26,
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: kPanel, shape: BoxShape.circle, border: Border.all(color: Colors.white12)),
                      child: Text(e, style: const TextStyle(fontSize: 20)),
                    ),
                  ),
                ),
            ]),
          const SizedBox(height: 12),
          Row(children: [
            if (playing)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4A1D2A), foregroundColor: const Color(0xFFFFC4CF)),
                onPressed: _resign,
                icon: const Icon(Icons.flag),
                label: Text(t('Abandonner', 'Resign'), style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            if (g['status'] == 'done')
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
                onPressed: () {
                  _resultShown = false;
                  _showResult();
                },
                icon: const Icon(Icons.emoji_events),
                label: Text(t('Résultat', 'Result'), style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            const Spacer(),
            OutlinedButton(onPressed: _rules, child: Text(t('Règles', 'Rules'))),
          ]),
        ]),
      ),
    );
  }

  Widget _cell(String v, int idx, bool win) {
    final color = v == '1' ? _kRed : v == '2' ? _kYellow : null;
    final last = idx == _lastPlaced || (_lastPlaced == null && g['last_col'] != null && idx % 7 == _i(g['last_col']) && _isTop(idx));
    final disc = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color ?? const Color(0xFF0A0F2E),
        gradient: color == null
            ? null
            : RadialGradient(center: const Alignment(-0.3, -0.4), colors: [Color.lerp(color, Colors.white, 0.5)!, color, Color.lerp(color, Colors.black, 0.3)!], stops: const [0, 0.52, 1]),
        border: win
            ? Border.all(color: Colors.white, width: 3)
            : color != null && last
                ? Border.all(color: Colors.white70, width: 2.5)
                : null,
        boxShadow: [
          if (win) const BoxShadow(color: Colors.white, blurRadius: 14, spreadRadius: 1),
          if (color == null) const BoxShadow(color: Color(0x30FFFFFF), offset: Offset(0, 1)),
        ],
      ),
      child: color == null ? null : FractionallySizedBox(widthFactor: 0.5, heightFactor: 0.5, child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.black12, width: 2)))),
    );
    if (color == null || idx != _lastPlaced) return disc;
    // le pion qui vient d'être posé tombe dans sa colonne, puis rebondit
    return TweenAnimationBuilder<double>(
      key: ValueKey('drop$idx${g['moves']}'),
      tween: Tween(begin: -((idx ~/ 7) + 1).toDouble(), end: 0),
      duration: Duration(milliseconds: 260 + (idx ~/ 7) * 55),
      curve: Curves.bounceOut,
      builder: (_, y, child) => FractionalTranslation(translation: Offset(0, y * 1.15), child: child),
      child: disc,
    );
  }

  /// Case la plus haute occupée de sa colonne (dernier coup quand la page s'ouvre)
  bool _isTop(int idx) {
    final b = g['board'] as String? ?? '';
    final c = idx % 7;
    for (var r = 0; r < 6; r++) {
      if (b[r * 7 + c] != '0') return r * 7 + c == idx;
    }
    return false;
  }
}

/// Fin de partie : trophée, gain qui monte, confettis, revanche
class _ResultDialog extends StatefulWidget {
  final Map<String, dynamic> g;
  final int side;
  final Map<String, dynamic> stats;
  const _ResultDialog({required this.g, required this.side, required this.stats});
  @override
  State<_ResultDialog> createState() => _ResultDialogState();
}

class _ResultDialogState extends State<_ResultDialog> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  final _rnd = Random();
  late final List<_Bit> bits;
  int shown = 0;
  bool pixel = false;
  Timer? _count;

  int get w => (widget.g['winner'] as num?)?.toInt() ?? -1;
  int get stake => _i(widget.g['stake'], kC4Stake);

  @override
  void initState() {
    super.initState();
    const cols = [_kRed, _kYellow, _kCyan, _kNeon, _kTeal, Colors.white];
    bits = List.generate(
      w == widget.side && !duelFriendly(widget.g) ? 140 : 0,
      (_) => _Bit((_rnd.nextDouble() - 0.5) * 2.2, -_rnd.nextDouble() * 2.4 - 0.6, 3 + _rnd.nextDouble() * 4, cols[_rnd.nextInt(cols.length)], _rnd.nextDouble() * 6),
    );
    if (w == widget.side && !duelFriendly(widget.g)) {
      c.forward();
      _count = Timer.periodic(const Duration(milliseconds: 30), (tm) {
        if (!mounted) return tm.cancel();
        setState(() => shown = min(shown + 2, duelPrize(stake)));
        if (shown % 10 == 0) RcAudio.sfx('coin');
        if (shown >= duelPrize(stake)) {
          tm.cancel();
          setState(() => pixel = true);
          RcAudio.sfx('powerup');
        }
      });
    }
  }

  @override
  void dispose() {
    _count?.cancel();
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final opp = (g['opp'] as Map?)?['name'] as String? ?? '?';
    final reason = g['reason'];
    final win = w == widget.side, draw = w == 0;
    final icon = win ? '🏆' : draw ? '🤝' : '💥';
    final title = win ? t('VICTOIRE !', 'VICTORY!') : draw ? t('MATCH NUL', 'DRAW') : t('DÉFAITE', 'DEFEAT');
    final sub = draw
        ? (stake > 0 ? t('Chacun récupère sa mise', 'Both players get their bet back') : t('$kDuelLose pièces chacun', '$kDuelLose coins each'))
        : win
            ? (reason == 'timeout'
                ? t('$opp n\'a pas joué à temps', '$opp ran out of time')
                : reason == 'resign'
                    ? t('$opp a abandonné', '$opp resigned')
                    : t('Quatre pions alignés', 'Four in a row'))
            : (reason == 'timeout'
                ? t('Temps écoulé', 'Time out')
                : reason == 'resign'
                    ? t('Tu as abandonné', 'You resigned')
                    : t('$opp a aligné quatre pions', '$opp got four in a row'));
    final gain = duelFriendly(g) ? '0' : win ? '+$shown' : draw ? (stake > 0 ? '+$stake' : '+$kDuelLose') : duelLoseText(stake);
    return Stack(children: [
      // confettis
      Positioned.fill(
        child: IgnorePointer(
          child: AnimatedBuilder(animation: c, builder: (_, __) => CustomPaint(painter: _ConfettiPainter(bits, c.value))),
        ),
      ),
      Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.8, end: 1),
          duration: const Duration(milliseconds: 380),
          curve: Curves.elasticOut,
          builder: (_, s, child) => Transform.scale(scale: s, child: child),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 340,
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF2A1F5E), Color(0xFF141A4C)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: kGold, width: 2),
                boxShadow: [BoxShadow(color: kGold.withOpacity(0.45), blurRadius: 36, spreadRadius: -8)],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(icon, style: const TextStyle(fontSize: 46)),
                const SizedBox(height: 6),
                Text(px(title), style: pixelStyle(size: 15, color: win ? _kGoldHi : draw ? Colors.white : const Color(0xFFFF8A95), shadow: false)),
                const SizedBox(height: 6),
                Text(duelFriendly(g) ? '$sub\n$duelFriendlyText' : sub, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const _Coin(size: 22),
                  const SizedBox(width: 8),
                  Text(gain, style: pixelStyle(size: 18, color: _kGoldHi, shadow: false)),
                  if (win && pixel) ...[
                    const SizedBox(width: 10),
                    Text('+1 ▦', style: pixelStyle(size: 11, color: _kGoldHi, shadow: false)),
                  ],
                ]),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(t('Coups ', 'Moves '), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  Text('${_i(g['moves'])}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                  const SizedBox(width: 14),
                  Text(t('Série ', 'Streak '), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  Text('${_i(widget.stats['streak'])}${_i(widget.stats['streak']) > 1 ? ' 🔥' : ''}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                ]),
                const SizedBox(height: 14),
                Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _kNeon, foregroundColor: Colors.white),
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.replay),
                    label: Text(t('Revanche', 'Rematch'), style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  OutlinedButton(onPressed: () => Navigator.pop(context, false), child: Text(t('Salon', 'Lobby'))),
                  TextButton(onPressed: () => Navigator.pop(context), child: Text(t('Voir le plateau', 'See the board'))),
                ]),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _Bit {
  final double vx, vy, size, spin;
  final Color color;
  const _Bit(this.vx, this.vy, this.size, this.color, this.spin);
}

class _ConfettiPainter extends CustomPainter {
  final List<_Bit> bits;
  final double t;
  _ConfettiPainter(this.bits, this.t);
  @override
  void paint(Canvas canvas, Size s) {
    if (t <= 0 || t >= 1) return;
    final p = Paint();
    for (final b in bits) {
      final x = s.width / 2 + b.vx * s.width * 0.5 * t;
      final y = s.height * 0.35 + (b.vy * t + 2.6 * t * t) * s.height * 0.5;
      p.color = b.color.withOpacity((1 - t).clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(b.spin * t * 6);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: b.size, height: b.size / 2), p);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter o) => o.t != t;
}
