import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'game.dart';
import 'live_link.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Spectateurs d'un duel en direct (4 en ligne / Console Wars), côté joueurs et
// côté spectateurs (SQL : sql/2026-10-22_spectateurs.sql).
//  · WatchCtl : le spectateur se signale toutes les 20 s (rc_watch_join) et part
//    au dispose (rc_watch_leave) ; les joueurs relisent la liste (rc_watchers).
//    Temps réel : 'watchers' {game, gid, list} et 'wreact' {game, gid, pid, name, e}.
//  · WatchersChip : « 👁 3 » dans la barre du haut → liste des spectateurs.
//  · WatchLayer : réactions qui montent sur l'écran + barre d'emojis (spectateurs).
// ═══════════════════════════════════════════════════════════════════════════

const kWatchEmojis = ['👏', '🔥', '😂', '😮', '😱', '👍', '💀', '🎉', '😭', '🤯'];

class WatchCtl extends ChangeNotifier {
  final String game;
  final int id;
  final bool spectator; // moi = spectateur (sinon : un des 2 joueurs)
  List<Map<String, dynamic>> list = [];
  final _reactions = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get reactions => _reactions.stream;
  Timer? _t;
  StreamSubscription? _sub;
  bool _closed = false;
  DateTime _last = DateTime(2000);

  WatchCtl(this.game, this.id, {required this.spectator}) {
    _sub = LiveLink.i.other.listen(_on);
    _tick();
    // spectateur : se signale toutes les 20 s ; joueur : la liste arrive par événement ('watchers'),
    // relue en secours toutes les 25 s, ou toutes les 75 s si le temps réel marche
    var n = 0;
    _t = Timer.periodic(Duration(seconds: spectator ? 20 : 25), (_) {
      if (spectator || !LiveLink.i.connected || (++n) % 3 == 0) _tick();
    });
  }

  Future<void> _tick() async {
    try {
      final l = spectator ? await RcServer.watchJoin(game, id) : await RcServer.watchers(game, id);
      if (_closed) return;
      list = l;
      notifyListeners();
    } catch (_) {}
  }

  void _on(Map<String, dynamic> e) {
    if (_closed || e['game'] != game || (e['gid'] as num?)?.toInt() != id) return;
    if (e['ev'] == 'watchers') {
      list = [for (final x in (e['list'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
      notifyListeners();
    } else if (e['ev'] == 'wreact') {
      if (spectator && e['pid'] == Game.i.pid) return; // déjà affichée en local
      _reactions.add(e);
    }
  }

  /// Spectateur : envoyer une réaction (une toutes les 1,5 s)
  void react(String e) {
    if (!spectator || _closed) return;
    final now = DateTime.now();
    if (now.difference(_last).inMilliseconds < 1500) return;
    _last = now;
    _reactions.add({'e': e, 'name': Game.i.name, 'pid': Game.i.pid});
    RcServer.watchReact(game, id, e).catchError((_) {});
  }

  @override
  void dispose() {
    _closed = true;
    _t?.cancel();
    _sub?.cancel();
    _reactions.close();
    if (spectator) RcServer.watchLeave(game, id).catchError((_) {});
    super.dispose();
  }
}

/// « 👁 3 » : nombre de spectateurs, touche → la liste
class WatchersChip extends StatelessWidget {
  final WatchCtl? ctl;
  const WatchersChip(this.ctl, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = ctl;
    if (c == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final n = c.list.length;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _sheet(context, c),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: n > 0 ? const Color(0xFF7B3DFF).withOpacity(0.35) : Colors.black26,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: n > 0 ? const Color(0xFFB57BFF) : Colors.white24),
                ),
                child: Text('👁 $n', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: n > 0 ? Colors.white : Colors.white54)),
              ),
            ),
          ),
        );
      },
    );
  }

  static void _sheet(BuildContext context, WatchCtl c) {
    showModalBottomSheet(
      context: context,
      backgroundColor: kBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: ListenableBuilder(
          listenable: c,
          builder: (ctx, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(t('👁 Spectateurs (${c.list.length})', '👁 Spectators (${c.list.length})'),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            if (c.list.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(t('Personne ne regarde pour le moment', 'Nobody is watching right now'),
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
              )
            else
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final p in c.list)
                    ListTile(
                      dense: true,
                      leading: avatarWidget((p['avatar'] as num? ?? 0).toInt(), size: 34),
                      title: Text(p['name']?.toString() ?? '?', style: const TextStyle(fontWeight: FontWeight.w700)),
                      trailing: p['pid'] == Game.i.pid ? Text(t('toi', 'you'), style: const TextStyle(color: kGold, fontSize: 12)) : null,
                    ),
                ]),
              ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }
}

/// Réactions qui montent sur l'écran (tout le monde) + barre d'emojis (spectateurs)
class WatchLayer extends StatelessWidget {
  final WatchCtl? ctl;
  final Widget child;
  const WatchLayer({super.key, required this.ctl, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = ctl;
    if (c == null) return child;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Stack(children: [
      Positioned.fill(child: child),
      Positioned.fill(child: IgnorePointer(child: _Floats(c))),
      if (c.spectator)
        Positioned(
          left: 8,
          right: 8,
          bottom: bottom + 8,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.72),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFB57BFF).withOpacity(0.7)),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final e in kWatchEmojis)
                      InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => c.react(e),
                        child: Padding(padding: const EdgeInsets.all(6), child: Text(e, style: const TextStyle(fontSize: 22))),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

class _Floats extends StatefulWidget {
  final WatchCtl c;
  const _Floats(this.c);
  @override
  State<_Floats> createState() => _FloatsState();
}

class _Float {
  final String e, name;
  final double x;
  final AnimationController a;
  _Float(this.e, this.name, this.x, this.a);
}

class _FloatsState extends State<_Floats> with TickerProviderStateMixin {
  final _list = <_Float>[];
  final _rnd = Random();
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.c.reactions.listen(_add);
  }

  void _add(Map<String, dynamic> r) {
    if (!mounted || _list.length >= 24) return;
    final a = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
    final f = _Float(r['e']?.toString() ?? '👏', r['name']?.toString() ?? '', 0.08 + _rnd.nextDouble() * 0.84, a);
    setState(() => _list.add(f));
    a.forward().whenComplete(() {
      a.dispose();
      if (mounted) setState(() => _list.remove(f));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final f in _list) {
      f.a.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      return Stack(children: [
        for (final f in _list)
          AnimatedBuilder(
            animation: f.a,
            builder: (_, __) {
              final v = Curves.easeOut.transform(f.a.value);
              final op = f.a.value < 0.75 ? 1.0 : (1 - f.a.value) / 0.25;
              return Positioned(
                left: f.x * box.maxWidth - 30,
                top: box.maxHeight * (0.82 - 0.55 * v),
                child: Opacity(
                  opacity: op.clamp(0.0, 1.0),
                  child: SizedBox(
                    width: 60,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Transform.scale(scale: 0.8 + 0.5 * sin(pi * f.a.value), child: Text(f.e, style: const TextStyle(fontSize: 34))),
                      Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white, shadows: [Shadow(blurRadius: 4)])),
                    ]),
                  ),
                ),
              );
            },
          ),
      ]);
    });
  }
}
