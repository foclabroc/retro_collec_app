import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'arcade.dart';
import 'audio.dart';
import 'game.dart';
import 'main.dart';
import 'neighbors.dart';
import 'profile.dart';
import 'retro_theme.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Bornes jouables (27/10) : chaque borne du Voisinage lance un mini-jeu choisi
// par son propriétaire (Snake, Casse-briques, Esquive). Record de la semaine
// affiché sur l'écran de la borne (remis à zéro le lundi et au changement de jeu).
// Serveur : rc_cab_board / rc_cab_get / rc_cab_set_game / rc_cab_start / rc_cab_end
// (sql/2026-10-27_bornes_jouables.sql). Record battu = +20 pièces (1 fois par jour
// et par borne, pas la sienne) ; propriétaire = +1 pièce par partie d'un autre
// (5 par joueur, 30 par jour). Le serveur refuse un score impossible pour la durée
// de la partie : garder les barèmes ci-dessous sous ses plafonds (250 / 450 / 120
// points par seconde).
// ═══════════════════════════════════════════════════════════════════════════

class CabGame {
  final String id, fr, en, icon, dfr, den;
  const CabGame(this.id, this.fr, this.en, this.icon, this.dfr, this.den);
  String get name => t(fr, en);
  String get desc => t(dfr, den);
}

const kCabGames = <String, CabGame>{
  'snake': CabGame('snake', 'Snake', 'Snake', '🐍', 'Mange les pixels sans te mordre la queue', 'Eat the pixels, don\'t bite your tail'),
  'bricks': CabGame('bricks', 'Casse-briques', 'Brick breaker', '🧱', 'Casse toutes les briques avec la balle', 'Break every brick with the ball'),
  'dodge': CabGame('dodge', 'Esquive', 'Dodge', '☄️', 'Évite ce qui tombe le plus longtemps possible', 'Dodge the falling rocks as long as you can'),
};

const _kMint = Color(0xFF7DFFB0);
const _kPink = Color(0xFFFF3DF0);
const _kYellow = Color(0xFFFFD166);

String _n(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

/// Jeu + record de chaque borne (rc_cab_board), lu avec le Voisinage
class CabBoard {
  static final _m = <String, Map<String, dynamic>>{};
  static Map<String, dynamic>? of(String pid) => _m[pid];

  static Future<void> load() async {
    try {
      final r = await RcServer.cabBoard();
      _m
        ..clear()
        ..addEntries(r.map((x) => MapEntry(x['pid'] as String? ?? '', x)));
    } catch (_) {}
  }

  static void put(String pid, String game, int? rec, String? recName) =>
      _m[pid] = {'pid': pid, 'game': game, 'rec': rec, 'rec_name': recName};
}

extension FloorCab on FloorData {
  FloorData withCab(String? game, int? rec, String? recName) => FloorData(
        pid: pid,
        name: name,
        avatar: avatar,
        score: score,
        cards: cards,
        coins: coins,
        pixels: pixels,
        theme: theme,
        online: online,
        me: me,
        busy: busy,
        rank: rank,
        seenAt: seenAt,
        trophies: trophies,
        cabGame: game,
        cabRec: rec,
        cabRecName: recName,
      );
}

/// Texte qui clignote (une fois par demi-seconde)
class CabBlink extends StatefulWidget {
  final Widget child;
  const CabBlink({super.key, required this.child});
  @override
  State<CabBlink> createState() => _CabBlinkState();
}

class _CabBlinkState extends State<CabBlink> {
  Timer? _t;
  bool _on = true;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 550), (_) {
      if (mounted) setState(() => _on = !_on);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Opacity(opacity: _on ? 1 : 0, child: widget.child);
}

/// Écran d'une borne en mode jeu : icône, nom du jeu, record et son détenteur
class CabScreen extends StatelessWidget {
  final FloorData d;
  final Rect sr;
  final bool on, start;
  const CabScreen({super.key, required this.d, required this.sr, required this.on, this.start = false});

  @override
  Widget build(BuildContext context) {
    final g = kCabGames[d.cabGame] ?? kCabGames['snake']!;
    final rec = d.cabRec;
    Widget fit(Widget w) => FittedBox(child: w);
    return Opacity(
      opacity: on ? 1 : 0.6,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: sr.width * 0.07, vertical: sr.height * 0.06),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(flex: 30, child: fit(Text(g.icon, style: const TextStyle(fontSize: 40)))),
          SizedBox(height: sr.height * 0.02),
          Expanded(flex: 13, child: fit(Text(g.fr.toUpperCase(), style: pixelStyle(size: 20, color: Colors.white, shadow: false)))),
          SizedBox(height: sr.height * 0.03),
          Expanded(
            flex: 10,
            child: start
                ? fit(Text('RECORD', style: pixelStyle(size: 20, color: _kMint, shadow: false)))
                : CabBlink(child: fit(Text('RECORD', style: pixelStyle(size: 20, color: _kMint, shadow: false)))),
          ),
          SizedBox(height: sr.height * 0.02),
          Expanded(flex: 15, child: fit(Text(rec == null ? '----' : _n(rec), style: pixelStyle(size: 20, color: _kYellow, shadow: false)))),
          SizedBox(height: sr.height * 0.02),
          Expanded(
            flex: 11,
            child: fit(Text(rec == null ? t('À TOI DE JOUER', 'YOUR TURN') : (d.cabRecName ?? '?'),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white.withOpacity(0.85)))),
          ),
          if (start) ...[
            SizedBox(height: sr.height * 0.03),
            Expanded(flex: 10, child: CabBlink(child: fit(Text('PRESS START', style: pixelStyle(size: 20, color: Colors.white, shadow: false))))),
          ],
        ]),
      ),
    );
  }
}

// ─── Page d'une borne ─────────────────────────────────────────────────────
class CabinetPage extends StatefulWidget {
  final FloorData f;
  const CabinetPage({super.key, required this.f});
  @override
  State<CabinetPage> createState() => _CabinetPageState();
}

class _CabinetPageState extends State<CabinetPage> {
  late FloorData f = widget.f;
  Map<String, dynamic>? info;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await RcServer.cabGet(f.pid);
      final top = (r['top'] as List? ?? const []).cast<Map<String, dynamic>>();
      final game = r['game'] as String? ?? 'snake';
      final rec = top.isEmpty ? null : (top.first['score'] as num?)?.toInt();
      final recName = top.isEmpty ? null : top.first['name'] as String?;
      CabBoard.put(f.pid, game, rec, recName);
      if (mounted) {
        setState(() {
          info = r;
          error = null;
          f = f.withCab(game, rec, recName);
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = errText(e));
    }
  }

  Future<void> _play() async {
    final game = info?['game'] as String? ?? f.cabGame ?? 'snake';
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CabPlayPage(pid: f.pid, owner: f.name, game: game)));
    if (!mounted) return;
    await _load();
    NeighborsScreenState.current?.load();
  }

  Future<void> _myGame() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FloorThemePage()));
    if (!mounted) return;
    f = FloorData.of({'pid': f.pid, 'name': f.name, 'house': Game.i.house}); // habillage peut-être changé
    await _load();
  }

  Widget _panel(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          const SizedBox(height: 8),
          ...children,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final me = f.me;
    final i = info;
    final top = (i?['top'] as List? ?? const []).cast<Map<String, dynamic>>();
    final best = (i?['best'] as num?)?.toInt();
    final w = math.min(230.0, MediaQuery.sizeOf(context).width * 0.56);
    return Scaffold(
      appBar: AppBar(title: Text(me ? t('Ma borne', 'My cabinet') : t('Borne de ${f.name}', '${f.name}\'s cabinet'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 28), children: [
        Center(child: ArcadeCabinet(d: f, width: w, game: f.cabGame != null)),
        const SizedBox(height: 14),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _kPink,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: i == null ? null : _play,
          child: Text('▶  ${t('JOUER', 'PLAY')}', style: pixelStyle(size: 13, color: Colors.white, shadow: false)),
        ),
        const SizedBox(height: 8),
        if (me)
          OutlinedButton.icon(
            onPressed: _myGame,
            icon: const Icon(Icons.tune, size: 18),
            label: Text(t('Changer le jeu ou l\'habillage', 'Change game or skin'), style: const TextStyle(fontWeight: FontWeight.w800)),
          )
        else
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerProfilePage(pid: f.pid))),
            icon: const Icon(Icons.person, size: 18),
            label: Text(t('Voir le profil de ${f.name}', 'See ${f.name}\'s profile'), style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Color(0xFFFF8A8A)))),
        if (i == null && error == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (i != null) ...[
          _panel('🏆 ${t('Records de la semaine', 'This week\'s records')}', [
            if (top.isEmpty)
              Text(t('Personne n\'a encore joué cette semaine : le premier score sera le record !', 'Nobody has played this week yet: the first score will be the record!'),
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            for (var k = 0; k < top.length; k++) _row(k, top[k]),
            if (best != null && !top.any((x) => x['pid'] == Game.i.pid))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(t('Ton meilleur score : ${_n(best)}', 'Your best score: ${_n(best)}'),
                    style: const TextStyle(color: _kMint, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
          ]),
          if (me)
            _panel('📊 ${t('Ma borne cette semaine', 'My cabinet this week')}', [
              Row(children: [
                _stat('${i['plays'] ?? 0}', t('parties jouées', 'games played')),
                const SizedBox(width: 8),
                _stat('+${i['comm'] ?? 0} 🪙', t('commission', 'commission')),
                const SizedBox(width: 8),
                _stat('${i['held'] ?? 0}', t('records détenus ailleurs', 'records held elsewhere')),
              ]),
            ]),
          _panel('📜 ${t('Règles', 'Rules')}', [
            Text(
              t('Partie gratuite, autant que tu veux.\n'
                  'Battre le record de la borne : +20 🪙 (une fois par jour et par borne${me ? ', pas sur la tienne' : ''}).\n'
                  'Le propriétaire gagne 1 🪙 par partie d\'un autre joueur (30 max par jour).\n'
                  'Records remis à zéro chaque lundi.',
                  'Free to play, as much as you want.\n'
                  'Beat the cabinet\'s record: +20 🪙 (once a day per cabinet${me ? ', not on yours' : ''}).\n'
                  'The owner earns 1 🪙 per game played by someone else (30 max a day).\n'
                  'Records reset every Monday.'),
              style: const TextStyle(fontSize: 13, height: 1.55, color: Color(0xFFE5DCFF)),
            ),
            if (!me && i['paid'] == true)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(t('Prime du jour déjà gagnée sur cette borne.', 'Today\'s bonus already earned on this cabinet.'),
                    style: const TextStyle(fontSize: 12, color: _kYellow, fontWeight: FontWeight.w700)),
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _row(int k, Map<String, dynamic> x) {
    final mine = x['pid'] == Game.i.pid;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 30, child: Text('${k + 1}.', style: pixelStyle(size: 9, color: _kYellow, shadow: false))),
        avatarWidget((x['avatar'] as num? ?? 0).toInt(), size: 24),
        const SizedBox(width: 8),
        Expanded(
          child: Text(x['name'] as String? ?? '?',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: mine ? _kMint : Colors.white)),
        ),
        Text(_n((x['score'] as num? ?? 0).toInt()), style: pixelStyle(size: 10, color: _kYellow, shadow: false)),
      ]),
    );
  }

  Widget _stat(String v, String l) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.25), borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            FittedBox(child: Text(v, style: pixelStyle(size: 12, color: _kYellow, shadow: false))),
            const SizedBox(height: 6),
            Text(l, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, color: Colors.white70)),
          ]),
        ),
      );
}

// ─── Choix du jeu de ma borne (page Ma borne / habillage) ──────────────────
class MyCabGamePicker extends StatefulWidget {
  final ValueChanged<String>? onChanged;
  const MyCabGamePicker({super.key, this.onChanged});
  @override
  State<MyCabGamePicker> createState() => _MyCabGamePickerState();
}

class _MyCabGamePickerState extends State<MyCabGamePicker> {
  String? game;
  int? rec;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await RcServer.cabGet(Game.i.pid);
      final top = (r['top'] as List? ?? const []).cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          game = r['game'] as String?;
          rec = top.isEmpty ? null : (top.first['score'] as num?)?.toInt();
        });
        if (game != null) widget.onChanged?.call(game!);
      }
    } catch (e) {
      toast(errText(e));
    }
  }

  Future<void> _pick(String id) async {
    if (busy || id == game) return;
    if (rec != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('Changer de jeu ?', 'Switch game?')),
          content: Text(t('Le record de ta borne (${_n(rec!)}) sera remis à zéro.', 'Your cabinet\'s record (${_n(rec!)}) will be reset.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Annuler', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Changer', 'Switch'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => busy = true);
    try {
      await RcServer.cabSetGame(id);
      CabBoard.put(Game.i.pid, id, null, null);
      if (mounted) {
        setState(() {
          game = id;
          rec = null;
        });
      }
      widget.onChanged?.call(id);
      NeighborsScreenState.current?.load();
      toast(t('Ta borne lance maintenant « ${kCabGames[id]!.fr} »', 'Your cabinet now runs « ${kCabGames[id]!.en} »'));
    } catch (e) {
      toast(errText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('🎮 ${t('Jeu de ma borne', 'My cabinet\'s game')}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
      const SizedBox(height: 4),
      Text(t('Les visiteurs y jouent en tapant sur ta borne. Changer de jeu remet son record à zéro.',
              'Visitors play it by tapping your cabinet. Switching resets its record.'),
          style: const TextStyle(fontSize: 12, color: Colors.white70)),
      const SizedBox(height: 8),
      if (game == null) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
      if (game != null)
        for (final g in kCabGames.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: busy ? null : () => _pick(g.id),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1030),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: g.id == game ? _kMint : Colors.white12, width: 2),
                ),
                child: Row(children: [
                  SizedBox(width: 40, child: Text(g.icon, textAlign: TextAlign.center, style: const TextStyle(fontSize: 26))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(g.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
                      Text(g.desc, style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
                    ]),
                  ),
                  if (g.id == game) const Icon(Icons.check_circle, color: _kMint, size: 20),
                ]),
              ),
            ),
          ),
    ]);
  }
}

// ─── Partie ───────────────────────────────────────────────────────────────
class CabPlayPage extends StatefulWidget {
  final String pid, owner, game;
  const CabPlayPage({super.key, required this.pid, required this.owner, required this.game});
  @override
  State<CabPlayPage> createState() => _CabPlayPageState();
}

class _CabPlayPageState extends State<CabPlayPage> {
  final _view = GlobalKey<MiniGameViewState>();
  Key _gameKey = UniqueKey();
  late String game = widget.game;
  int? run, rec;
  int score = 0;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      ready = false;
      score = 0;
    });
    try {
      final r = await RcServer.cabStart(widget.pid);
      if (!mounted) return;
      setState(() {
        run = (r['run'] as num).toInt();
        rec = (r['rec'] as num?)?.toInt();
        game = r['game'] as String? ?? game;
        _gameKey = UniqueKey();
        ready = true;
      });
    } catch (e) {
      toast(errText(e));
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _over(int s) async {
    RcAudio.sfx('hurt');
    final id = run;
    Map<String, dynamic>? r;
    if (id != null && s > 0) {
      try {
        r = await RcServer.cabEnd(id, s);
        if (r['coins'] != null) Game.i.setCoins((r['coins'] as num).toInt());
      } catch (e) {
        toast(errText(e));
      }
    }
    if (!mounted) return;
    final newRec = r?['newrec'] == true;
    final gain = (r?['gain'] as num? ?? 0).toInt();
    final best = (r?['best'] as num?)?.toInt();
    final recNow = (r?['rec'] as num?)?.toInt() ?? rec;
    if (newRec) RcAudio.sfx(gain > 0 ? 'coin' : 'powerup');
    final again = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F1440),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: _kYellow, width: 2)),
        title: Text(newRec ? t('NOUVEAU RECORD !', 'NEW RECORD!') : 'GAME OVER',
            textAlign: TextAlign.center, style: pixelStyle(size: 13, color: _kYellow, shadow: false)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_n(s), style: pixelStyle(size: 20, color: newRec ? _kYellow : Colors.white, shadow: false)),
          const SizedBox(height: 12),
          if (gain > 0) Text('+$gain 🪙', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _kYellow)),
          if (newRec && widget.pid != Game.i.pid)
            Text(t('Ton pseudo s\'affiche sur la borne de ${widget.owner}.', 'Your name now shows on ${widget.owner}\'s cabinet.'),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
          if (!newRec && recNow != null) ...[
            Text(t('Record de la borne : ${_n(recNow)}', 'Cabinet record: ${_n(recNow)}'), style: const TextStyle(fontSize: 13)),
            if (best != null && best > s) Text(t('Ton meilleur : ${_n(best)}', 'Your best: ${_n(best)}'), style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ]),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Retour à la borne', 'Back to cabinet'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kPink, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Rejouer', 'Play again'), style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (newRec && recNow != null) rec = recNow;
    if (again == true) {
      _start();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = kCabGames[game] ?? kCabGames['snake']!;
    final hd = pixelStyle(size: 9, color: Colors.white, shadow: false);
    return Scaffold(
      backgroundColor: const Color(0xFF05030C),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
            child: Row(children: [
              Expanded(child: FittedBox(alignment: Alignment.centerLeft, fit: BoxFit.scaleDown, child: Text(g.fr.toUpperCase(), style: hd))),
              const SizedBox(width: 8),
              Text('SCORE ', style: hd),
              Text(_n(score), style: pixelStyle(size: 9, color: _kYellow, shadow: false)),
              const SizedBox(width: 12),
              Text('REC ', style: hd),
              Text(rec == null ? '-' : _n(rec!), style: pixelStyle(size: 9, color: _kMint, shadow: false)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: AspectRatio(
                  aspectRatio: kMiniW / kMiniH,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF3A2A6A), width: 3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ready
                        ? MiniGameView(
                            key: _view,
                            gameKey: _gameKey,
                            game: game,
                            onScore: (v) {
                              if (mounted) setState(() => score = v);
                            },
                            onOver: _over,
                          )
                        : const ColoredBox(color: Color(0xFF0B0820), child: Center(child: CircularProgressIndicator())),
                  ),
                ),
              ),
            ),
          ),
          if (game == 'snake')
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _Joystick(onDir: (dx, dy) => _view.currentState?.turn(dx, dy)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Text(
              game == 'snake'
                  ? t('Glisse sur le jeu, utilise le joystick ou les flèches du clavier', 'Swipe on the game, use the joystick or arrow keys')
                  : t('Glisse le doigt (ou la souris) pour bouger', 'Drag your finger (or the mouse) to move'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Joystick tactile : le pouce glisse depuis le centre, l'axe dominant donne la direction.
class _Joystick extends StatefulWidget {
  final void Function(int dx, int dy) onDir;
  const _Joystick({required this.onDir});
  @override
  State<_Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<_Joystick> {
  static const size = 132.0, knob = 54.0, dead = 16.0;
  Offset off = Offset.zero;
  (int, int) last = (0, 0);

  void _move(Offset local) {
    var d = local - const Offset(size / 2, size / 2);
    const max = (size - knob) / 2;
    if (d.distance > max) d = d / d.distance * max;
    setState(() => off = d);
    if (d.distance < dead) return;
    final dir = d.dx.abs() > d.dy.abs() ? (d.dx > 0 ? 1 : -1) : 0;
    final dirY = d.dx.abs() > d.dy.abs() ? 0 : (d.dy > 0 ? 1 : -1);
    if ((dir, dirY) == last) return;
    last = (dir, dirY);
    widget.onDir(dir, dirY);
  }

  void _end() {
    setState(() => off = Offset.zero);
    last = (0, 0);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onPanStart: (d) => _move(d.localPosition),
        onPanUpdate: (d) => _move(d.localPosition),
        onPanEnd: (_) => _end(),
        onPanCancel: _end,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(alignment: Alignment.center, children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1F1440),
                border: Border.all(color: const Color(0xFF3A2A6A), width: 3),
              ),
            ),
            Transform.translate(
              offset: off,
              child: Container(
                width: knob,
                height: knob,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF6B4FD8),
                  border: Border.all(color: Colors.white38, width: 2),
                ),
              ),
            ),
          ]),
        ),
      );
}

// ─── Moteur des mini-jeux (coordonnées logiques 340 × 440, 60 pas / s) ─────
const kMiniW = 340.0, kMiniH = 440.0;

abstract class _Mini {
  int score = 0;
  int frame = 0;
  bool dead = false;
  double aim = kMiniW / 2; // position du doigt
  bool get started => frame >= 60; // 1 s « PRÊT ? »
  void step();
  void paint(Canvas c);
  void turn(int dx, int dy) {}
  void nudge(double dx) => aim = (aim + dx).clamp(0.0, kMiniW);
}

final _rnd = math.Random();
Paint _glow(Color c) => Paint()
  ..color = c.withOpacity(0.55)
  ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

class _Snake extends _Mini {
  static const c = 20.0;
  static const cols = 17, rows = 22;
  final body = <math.Point<int>>[const math.Point(5, 11), const math.Point(4, 11), const math.Point(3, 11)];
  math.Point<int> dir = const math.Point(1, 0);
  final turns = <math.Point<int>>[]; // virages en attente (2 max)
  late math.Point<int> food = _place();
  int every = 8, wait = 0, eaten = 0;

  math.Point<int> _place() {
    while (true) {
      final p = math.Point(_rnd.nextInt(cols), _rnd.nextInt(rows));
      if (!body.contains(p)) return p;
    }
  }

  @override
  void turn(int dx, int dy) {
    final cur = turns.isEmpty ? dir : turns.last;
    if (turns.length >= 2 || (dx == -cur.x && dy == -cur.y) || (dx == cur.x && dy == cur.y)) return;
    turns.add(math.Point(dx, dy));
  }

  @override
  void step() {
    frame++;
    if (!started || ++wait < every) return;
    wait = 0;
    if (turns.isNotEmpty) dir = turns.removeAt(0);
    final h = math.Point(body.first.x + dir.x, body.first.y + dir.y);
    if (h.x < 0 || h.y < 0 || h.x >= cols || h.y >= rows || body.sublist(0, body.length - 1).contains(h)) {
      dead = true;
      return;
    }
    body.insert(0, h);
    if (h == food) {
      score += 100;
      eaten++;
      if (eaten % 3 == 0 && every > 4) every--;
      RcAudio.sfx('jump');
      food = _place();
    } else {
      body.removeLast();
    }
  }

  @override
  void paint(Canvas cv) {
    final f = Rect.fromLTWH(food.x * c + 4, food.y * c + 4, c - 8, c - 8);
    cv.drawRect(f.inflate(3), _glow(_kPink));
    cv.drawRect(f, Paint()..color = _kPink);
    for (var i = body.length - 1; i >= 0; i--) {
      final s = body[i];
      cv.drawRect(Rect.fromLTWH(s.x * c + 1, s.y * c + 1, c - 2, c - 2), Paint()..color = i == 0 ? _kMint : const Color(0xFF4FD98A));
    }
  }
}

class _Brick {
  final Rect r;
  final Color c;
  bool dead = false;
  _Brick(this.r, this.c);
}

class _Bricks extends _Mini {
  static const pw = 70.0, ph = 10.0, py = kMiniH - 30, br = 6.0;
  static const _cols = [Color(0xFFFF5A6A), Color(0xFFFFB347), _kYellow, _kMint, Color(0xFF28E0FF), Color(0xFFB07DFF)];
  double bx = kMiniW / 2, by = py - 20, vx = 2.6, vy = -4.2;
  int lives = 3, level = 0;
  List<_Brick> bricks = [];

  _Bricks() {
    _build();
  }

  void _build() {
    bricks = [
      for (var r = 0; r < 6; r++)
        for (var c = 0; c < 8; c++) _Brick(Rect.fromLTWH(10 + c * 40.0, 50 + r * 18.0, 36, 14), _cols[r]),
    ];
  }

  double get _pad => aim.clamp(pw / 2, kMiniW - pw / 2);

  void _serve() {
    bx = _pad;
    by = py - 20;
    final sp = 1 + level * 0.12;
    vx = (_rnd.nextBool() ? 2.6 : -2.6) * sp;
    vy = -4.2 * sp;
  }

  @override
  void step() {
    frame++;
    if (!started) {
      bx = _pad;
      return;
    }
    bx += vx;
    by += vy;
    if (bx < br) {
      bx = br;
      vx = vx.abs();
    } else if (bx > kMiniW - br) {
      bx = kMiniW - br;
      vx = -vx.abs();
    }
    if (by < br) {
      by = br;
      vy = vy.abs();
    }
    final p = _pad;
    if (vy > 0 && by > py - br && by < py + ph && (bx - p).abs() < pw / 2 + br) {
      final sp = math.sqrt(vx * vx + vy * vy);
      final a = ((bx - p) / (pw / 2)).clamp(-1.0, 1.0) * 1.05; // angle selon l'endroit touché
      vx = sp * math.sin(a);
      vy = -sp * math.cos(a);
      if (vy.abs() < 2.2) vy = -2.2;
      RcAudio.sfx('spring');
    }
    if (by > kMiniH + 10) {
      lives--;
      if (lives <= 0) {
        dead = true;
        return;
      }
      frame = 20; // petite pause avant de relancer
      _serve();
      return;
    }
    for (final k in bricks) {
      if (k.dead || !k.r.inflate(br).contains(Offset(bx, by))) continue;
      k.dead = true;
      score += 50;
      // côté touché : rebond horizontal si la balle arrive par le flanc
      if (bx < k.r.left || bx > k.r.right) {
        vx = -vx;
      } else {
        vy = -vy;
      }
      RcAudio.sfx('break');
      break;
    }
    if (bricks.every((k) => k.dead)) {
      score += 1000;
      level++;
      _build();
      frame = 0;
      _serve();
    }
  }

  @override
  void paint(Canvas cv) {
    for (final k in bricks) {
      if (!k.dead) cv.drawRect(k.r, Paint()..color = k.c);
    }
    final pr = Rect.fromLTWH(_pad - pw / 2, py, pw, ph);
    cv.drawRect(pr.inflate(2), _glow(const Color(0xFF28E0FF)));
    cv.drawRect(pr, Paint()..color = const Color(0xFF28E0FF));
    cv.drawCircle(Offset(bx, by), br + 3, _glow(Colors.white));
    cv.drawCircle(Offset(bx, by), br, Paint()..color = Colors.white);
    for (var i = 0; i < lives; i++) {
      cv.drawCircle(Offset(kMiniW - 14 - i * 16.0, 18), 5, Paint()..color = const Color(0xFFFF5A6A));
    }
  }
}

class _Rock {
  double x, y;
  final double r, v;
  _Rock(this.x, this.y, this.r, this.v);
}

class _Dodge extends _Mini {
  static const sy = kMiniH - 40;
  final rocks = <_Rock>[];
  int t = 0;

  double get _sx => aim.clamp(14.0, kMiniW - 14);

  @override
  void step() {
    frame++;
    if (!started) return;
    t++;
    final every = math.max(10, 40 - t ~/ 120);
    if (t % every == 0) rocks.add(_Rock(_rnd.nextDouble() * kMiniW, -12, 6 + _rnd.nextDouble() * 10, 2 + _rnd.nextDouble() * 2 + t / 600));
    for (final o in rocks) {
      o.y += o.v;
    }
    rocks.removeWhere((o) => o.y > kMiniH + 20);
    if (t % 6 == 0) score += 10; // 100 points par seconde
    final x = _sx;
    if (rocks.any((o) => math.sqrt((o.x - x) * (o.x - x) + (o.y - sy) * (o.y - sy)) < o.r + 10)) dead = true;
  }

  @override
  void paint(Canvas cv) {
    const rock = Color(0xFFFFB347);
    for (final o in rocks) {
      cv.drawCircle(Offset(o.x, o.y), o.r + 3, _glow(rock));
      cv.drawCircle(Offset(o.x, o.y), o.r, Paint()..color = rock);
    }
    final x = _sx;
    final ship = Path()
      ..moveTo(x, sy - 14)
      ..lineTo(x - 12, sy + 10)
      ..lineTo(x + 12, sy + 10)
      ..close();
    cv.drawPath(ship, _glow(_kMint));
    cv.drawPath(ship, Paint()..color = _kMint);
  }
}

class MiniGameView extends StatefulWidget {
  final String game;
  final Key gameKey; // change à chaque nouvelle partie
  final ValueChanged<int> onScore, onOver;
  const MiniGameView({super.key, required this.game, required this.gameKey, required this.onScore, required this.onOver});
  @override
  State<MiniGameView> createState() => MiniGameViewState();
}

class MiniGameViewState extends State<MiniGameView> with SingleTickerProviderStateMixin {
  late _Mini g;
  late final Ticker _t;
  final _frame = ValueNotifier<int>(0);
  final _focus = FocusNode();
  Duration _last = Duration.zero;
  double _acc = 0;
  int _sent = 0;
  bool _done = false;
  Offset _drag = Offset.zero;

  _Mini _make() => switch (widget.game) { 'bricks' => _Bricks(), 'dodge' => _Dodge(), _ => _Snake() };

  @override
  void initState() {
    super.initState();
    g = _make();
    _t = createTicker(_tick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant MiniGameView old) {
    super.didUpdateWidget(old);
    if (old.gameKey != widget.gameKey) {
      g = _make();
      _sent = 0;
      _done = false;
      _acc = 0;
      _last = Duration.zero;
      _t
        ..stop()
        ..start();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    _frame.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _tick(Duration e) {
    final dt = ((e - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = e;
    _acc += dt;
    while (_acc >= 1 / 60 && !g.dead) {
      g.step();
      _acc -= 1 / 60;
    }
    if (g.score != _sent) {
      _sent = g.score;
      widget.onScore(g.score);
    }
    _frame.value++;
    if (g.dead && !_done) {
      _done = true;
      _t.stop();
      final s = g.score;
      Future.microtask(() => widget.onOver(s));
    }
  }

  void turn(int dx, int dy) => g.turn(dx, dy);

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final (dx, dy) = k == LogicalKeyboardKey.arrowLeft
        ? (-1, 0)
        : k == LogicalKeyboardKey.arrowRight
            ? (1, 0)
            : k == LogicalKeyboardKey.arrowUp
                ? (0, -1)
                : k == LogicalKeyboardKey.arrowDown
                    ? (0, 1)
                    : (0, 0);
    if (dx == 0 && dy == 0) return KeyEventResult.ignored;
    if (g is _Snake) {
      g.turn(dx, dy);
    } else {
      g.nudge(dx * 16.0);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: LayoutBuilder(builder: (context, box) {
        final sc = box.maxWidth / kMiniW;
        void point(Offset p) {
          if (g is! _Snake) g.aim = (p.dx / sc).clamp(0.0, kMiniW);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) {
            _drag = Offset.zero;
            point(d.localPosition);
          },
          onPanUpdate: (d) {
            point(d.localPosition);
            if (g is _Snake) {
              _drag += d.delta;
              if (_drag.distance > 18) {
                if (_drag.dx.abs() > _drag.dy.abs()) {
                  g.turn(_drag.dx > 0 ? 1 : -1, 0);
                } else {
                  g.turn(0, _drag.dy > 0 ? 1 : -1);
                }
                _drag = Offset.zero;
              }
            }
          },
          child: MouseRegion(
            onHover: (e) => point(e.localPosition),
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _MiniPainter(this, sc))),
              ValueListenableBuilder<int>(
                valueListenable: _frame,
                builder: (_, __, ___) => g.started
                    ? const SizedBox.shrink()
                    : Center(child: Text(t('PRÊT ?', 'READY?'), style: pixelStyle(size: 18, color: Colors.white, shadow: false))),
              ),
            ]),
          ),
        );
      }),
    );
  }
}

class _MiniPainter extends CustomPainter {
  final MiniGameViewState s;
  final double sc;
  _MiniPainter(this.s, this.sc) : super(repaint: s._frame);

  @override
  void paint(Canvas c, Size size) {
    c.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0B0820));
    c.save();
    c.scale(sc);
    c.clipRect(const Rect.fromLTWH(0, 0, kMiniW, kMiniH));
    s.g.paint(c);
    c.restore();
  }

  @override
  bool shouldRepaint(_MiniPainter o) => o.sc != sc;
}
