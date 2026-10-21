import 'dart:async';

import 'package:flutter/material.dart';

import 'audio.dart';
import 'connect4.dart';
import 'duel_msg.dart';
import 'game.dart';
import 'live_link.dart';
import 'main.dart';
import 'push.dart';
import 'retro_theme.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Défis reçus (4 en ligne, Console Wars), appli ouverte : toutes les 10 s,
// une petite requête (rc_duel_ping, ~60 octets quand il n'y a rien).
//  · défi en direct → fenêtre par-dessus l'écran (Accepter / Refuser / Plus tard)
//  · invitations tour par tour et parties où c'est mon tour → pastille sur « Bonus / Jeux »
// Rien pendant une partie (la fenêtre attend la fin), rien quand l'appli est en arrière-plan.
// ═══════════════════════════════════════════════════════════════════════════

class DuelWatch extends ChangeNotifier {
  static final i = DuelWatch();
  Timer? _timer;
  int invites = 0, turns = 0;
  int? online; // joueurs en ligne (hors moi), renvoyé par rc_duel_ping
  String? lastFrom;
  List<Map<String, dynamic>> live = [];
  final _handled = <String>{}; // défis déjà montrés (jeu:id)
  final _replies = <String>{}; // réponses à mes défis déjà annoncées (jeu:id:texte)
  bool _showing = false;
  int inGame = 0; // pages de partie ouvertes : pas de fenêtre par-dessus

  int get badge => invites + turns;

  StreamSubscription? _rt;
  Timer? _rtDebounce;

  void start() {
    _timer?.cancel();
    // Realtime : un duel qui me concerne a changé → on recharge tout de suite
    LiveLink.i.start();
    _rt ??= LiveLink.i.events.listen((_) {
      _rtDebounce?.cancel();
      _rtDebounce = Timer(const Duration(milliseconds: 300), refresh);
    });
    // toutes les 10 s s'il y a une partie ou un défi en cours, sinon toutes les 20 s (moins de charge serveur)
    var n = 0;
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (live.isNotEmpty || badge > 0 || inGame > 0 || (n++).isEven) refresh();
    });
    refresh();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    LiveLink.i.stop();
  }

  Future<void> refresh() async {
    try {
      final r = await RcServer.duelPing();
      live = [for (final x in (r['live'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
      invites = (r['invites'] as num? ?? 0).toInt();
      turns = (r['turns'] as num? ?? 0).toInt();
      online = (r['online'] as num?)?.toInt();
      lastFrom = r['last_from'] as String?;
      PushWatch.seenDuels(invites, turns); // déjà visible dans l'appli : pas de notification
      notifyListeners();
      _announceReplies(r['replies']);
      _maybeShow();
    } catch (_) {
      // serveur pas encore à jour ou hors ligne : on réessaiera
    }
  }

  /// Réponse reçue à un défi que j'ai lancé : toast où que je sois, avec « Voir » (salon du jeu)
  void _announceReplies(dynamic list) {
    if (list is! List) return;
    for (final x in list) {
      if (x is! Map) continue;
      final key = '${x['game']}:${x['id']}:${x['reply']}';
      if (!_replies.add(key)) continue;
      final bs = x['game'] == 'bs';
      final name = x['name']?.toString() ?? '?';
      RcAudio.sfx('logo');
      rcMessenger.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          backgroundColor: const Color(0xFF3C3489),
          duration: const Duration(seconds: 6),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('💬 $name a répondu à ton défi', '💬 $name replied to your challenge'), style: const TextStyle(fontWeight: FontWeight.w900)),
            Text('« ${x['reply']} »', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            Text(t('${bs ? 'Console Wars' : '4 en ligne'} · le défi attend toujours', '${bs ? 'Console Wars' : 'Connect 4'} · the challenge is still pending'),
                style: const TextStyle(fontSize: 11.5, color: Color(0xFFCFCAFF))),
          ]),
          action: SnackBarAction(
            label: t('Voir', 'See'),
            textColor: const Color(0xFFFFD166),
            onPressed: () {
              final ctx = HomeShellState.current?.context;
              if (ctx == null || !ctx.mounted) return;
              Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => Connect4Lobby(kind: bs ? kBsDuel : kC4Duel)));
            },
          ),
        ));
      break; // une à la fois ; les suivantes au prochain passage
    }
  }

  bool stillValid(String key) => live.any((x) => '${x['game']}:${x['id']}' == key);

  Future<void> _maybeShow() async {
    if (_showing || inGame > 0) return;
    final ctx = HomeShellState.current?.context;
    if (ctx == null || !ctx.mounted) return;
    final todo = live.where((x) => !_handled.contains('${x['game']}:${x['id']}'));
    if (todo.isEmpty) return;
    final next = todo.first;
    final key = '${next['game']}:${next['id']}';
    _handled.add(key);
    _showing = true;
    RcAudio.sfx('logo');
    final kind = next['game'] == 'bs' ? kBsDuel : kC4Duel;
    final choice = await showGeneralDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.6),
      transitionDuration: const Duration(milliseconds: 380),
      transitionBuilder: (_, a, __, child) => SlideTransition(
        position: Tween(begin: const Offset(0, -0.6), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
        child: FadeTransition(opacity: a, child: child),
      ),
      pageBuilder: (_, __, ___) => _DuelInvite(x: next, keyId: key),
    );
    _showing = false;
    final id = (next['id'] as num).toInt();
    if (choice == true) {
      try {
        final g = await kind.answer(id, true);
        Game.i.sync();
        RcAudio.sfx('powerup');
        final nav = HomeShellState.current?.context;
        if (nav != null && nav.mounted && g['status'] == 'playing') {
          await Navigator.of(nav).push(MaterialPageRoute(builder: (_) => kind.page(g)));
          Game.i.sync();
        }
      } catch (e) {
        RcAudio.wrong();
        toast(errText(e));
      }
    } else if (choice == false) {
      try {
        await kind.answer(id, false);
        toast(t('Défi refusé', 'Challenge declined'));
      } catch (_) {}
    }
    refresh();
  }
}

/// La fenêtre « X te défie ! »
class _DuelInvite extends StatefulWidget {
  final Map<String, dynamic> x;
  final String keyId;
  const _DuelInvite({required this.x, required this.keyId});
  @override
  State<_DuelInvite> createState() => _DuelInviteState();
}

class _DuelInviteState extends State<_DuelInvite> with SingleTickerProviderStateMixin {
  late final AnimationController pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  Timer? _tick;
  late final DateTime _end;

  @override
  void initState() {
    super.initState();
    final now = DateTime.tryParse(widget.x['now'] as String? ?? '') ?? DateTime.now();
    final dl = DateTime.tryParse(widget.x['deadline'] as String? ?? '') ?? now.add(const Duration(minutes: 2));
    _end = DateTime.now().add(dl.difference(now));
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final left = _end.difference(DateTime.now()).inSeconds;
      if (left <= 0 || !DuelWatch.i.stillValid(widget.keyId)) {
        Navigator.of(context).pop(); // expiré ou annulé
        if (left <= 0) toast(t('Défi expiré', 'Challenge expired'));
        return;
      }
      if (left <= 10) RcAudio.tick();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bs = widget.x['game'] == 'bs';
    final col = bs ? const Color(0xFF3EC7FF) : const Color(0xFFFF4757);
    final opp = widget.x['opp'] as Map? ?? const {};
    final name = opp['name'] as String? ?? '?';
    final stake = (widget.x['stake'] as num? ?? 0).toInt();
    final left = _end.difference(DateTime.now()).inSeconds.clamp(0, 120);
    Widget av(int a, {bool ring = false}) => SizedBox(
          width: 82,
          height: 82,
          child: Stack(alignment: Alignment.center, children: [
            if (ring)
              AnimatedBuilder(
                animation: pulse,
                builder: (_, __) => Transform.scale(
                  scale: 0.9 + 0.3 * pulse.value,
                  child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: col.withOpacity(1 - pulse.value), width: 3))),
                ),
              ),
            Container(padding: const EdgeInsets.all(3), decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF3A4590)), child: avatarWidget(a, size: 62)),
          ]),
        );
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
            gradient: const LinearGradient(colors: [Color(0xFF2A1360), Color(0xFF141A4C)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: col, width: 2),
            boxShadow: [BoxShadow(color: col.withOpacity(0.45), blurRadius: 40, spreadRadius: -6)],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: col, blurRadius: 14)]),
              child: Text(px(t('DÉFI EN DIRECT', 'LIVE CHALLENGE')), style: pixelStyle(size: 8, color: const Color(0xFF14062B), shadow: false)),
            ),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              av(Game.i.avatar),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('VS', style: pixelStyle(size: 13, color: col, shadow: false))),
              av((opp['avatar'] as num? ?? 0).toInt(), ring: true),
            ]),
            const SizedBox(height: 6),
            Text(t('$name te défie !', '$name challenges you!'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            // son petit mot
            if (widget.x['msg'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: SayBubble(widget.x['msg'] as String),
              ),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: t('● en ligne', '● online'), style: const TextStyle(color: Color(0xFF5DCAA5))),
                TextSpan(text: t(' · ${opp['w'] ?? 0} V · ${opp['l'] ?? 0} D', ' · ${opp['w'] ?? 0} W · ${opp['l'] ?? 0} L')),
              ]),
              style: const TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(13)),
              child: Row(children: [
                Icon(bs ? Icons.directions_boat : Icons.grid_on, color: col, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(bs ? 'Console Wars' : t('4 en ligne', 'Connect 4'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                    Text(
                        stake > 0
                            ? t('$stake pièces chacun · le gagnant rafle ${stake * 2} + 1 pixel', '$stake coins each · the winner takes ${stake * 2} + 1 pixel')
                            : widget.x['friendly'] != null
                                ? duelWhyLine(widget.x['friendly'] as String?)
                                : t('Gratuit · le gagnant gagne $kDuelWin pièces + 1 pixel', 'Free · the winner gets $kDuelWin coins + 1 pixel'),
                        style: const TextStyle(fontSize: 12, color: Colors.white60)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox.expand(child: CircularProgressIndicator(value: left / 120, strokeWidth: 5, color: col, backgroundColor: Colors.white12)),
                Text('${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}', style: pixelStyle(size: 10, color: Colors.white, shadow: false)),
              ]),
            ),
            const SizedBox(height: 4),
            Text(bs ? t('2 min pour placer ta flotte, puis 30 s par tir', '2 min to place your fleet, then 30 s per shot') : t('1 minute par coup', '1 minute per move'),
                style: const TextStyle(fontSize: 11.5, color: Colors.white38)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4A1D2A), foregroundColor: const Color(0xFFFFC4CF), padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(t('Refuser', 'Decline'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2FBF8A), foregroundColor: const Color(0xFF06281B), padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(t('⚔ Accepter', '⚔ Accept'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                ),
              ),
            ]),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t('Plus tard (il reste dans le salon)', 'Later (it stays in the lobby)'), style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ),
            // répondre sans jouer tout de suite
            const Divider(color: Colors.white12, height: 14),
            Text(t('ou réponds-lui :', 'or reply:'), style: const TextStyle(color: Colors.white54, fontSize: 11.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            ReplyChips(
              game: bs ? 'bs' : 'c4',
              id: (widget.x['id'] as num? ?? 0).toInt(),
              to: name,
              onSent: () {
                if (mounted) Navigator.of(context).pop(); // la réponse part : le défi reste dans le salon
              },
            ),
          ]),
        ),
       ),
      ),
    );
  }
}
