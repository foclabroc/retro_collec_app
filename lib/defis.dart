import 'dart:async';

import 'package:flutter/material.dart';

import 'audio.dart';
import 'game.dart';
import 'main.dart';
import 'notifs.dart';
import 'retro_theme.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Défis de la semaine : 6 défis du lundi au dimanche + un coffre
// ═══════════════════════════════════════════════════════════════════════════

class DefisScreen extends StatefulWidget {
  const DefisScreen({super.key});
  @override
  State<DefisScreen> createState() => DefisScreenState();
}

class DefisScreenState extends State<DefisScreen> {
  static DefisScreenState? current;
  Map<String, dynamic>? data;
  bool error = false;
  int? busy; // défi en cours de récupération
  Timer? _tick;

  // défis tirés chaque semaine dans un réservoir (rc__wpool côté serveur) : icône et texte selon leur type
  static const _old = ['open', 'gift', 'trade', 'win', 'gamedle', 'epic']; // ancien serveur sans « kinds »

  static String _icon(String k) => switch (k) {
        'open' => '📦',
        'gift' => '🎁',
        'trade' => '🤝',
        'win' => '⚔️',
        'gamedle' => '🟨',
        'epic' => '💜',
        'play' => '🕹️',
        'new' => '✨',
        'quiz' => '❓',
        'sale' => '💰',
        'free' => '📅',
        'premium' => '⭐',
        _ => '🏆',
      };

  static String _label(String k, int goal) => switch (k) {
        'open' => t('Ouvrir $goal paquets', 'Open $goal packs'),
        'gift' => t('Envoyer $goal cadeaux', 'Send $goal gifts'),
        'trade' => t('Faire $goal échanges, achats ou ventes', 'Make $goal trades, purchases or sales'),
        'win' => t('Gagner $goal duels (4 en ligne ou Console Wars)', 'Win $goal duels (Connect 4 or Console Wars)'),
        'gamedle' => t('Réussir $goal Gamedle', 'Solve $goal Gamedles'),
        'play' => t('Jouer $goal duels (gagnés ou perdus)', 'Play $goal duels (won or lost)'),
        'new' => t('Obtenir $goal nouvelles cartes', 'Get $goal new cards'),
        'quiz' => t('Donner $goal bonnes réponses au quiz', 'Give $goal right quiz answers'),
        'sale' => t('Vendre $goal cartes à la Bourse', 'Sell $goal cards on the market'),
        'free' => t('Ouvrir le paquet gratuit $goal jours', 'Open the free pack on $goal days'),
        'premium' => t('Ouvrir $goal paquets premium', 'Open $goal premium packs'),
        _ => goal == 1 ? t('Obtenir une carte épique ou mieux', 'Get an epic card or better') : t('Obtenir $goal cartes épiques ou mieux', 'Get $goal epic cards or better'),
      };

  String _kind(int i) {
    final k = data?['kinds'];
    if (k is List && i < k.length) return '${k[i]}';
    return i < _old.length ? _old[i] : '';
  }

  @override
  void initState() {
    super.initState();
    current = this;
    load();
    // compte à rebours mis à jour chaque minute
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (current == this) current = null;
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await RcServer.week();
      if (mounted) {
        setState(() {
          data = r;
          error = false;
        });
      }
    } catch (_) {
      if (mounted && data == null) setState(() => error = true);
    }
  }

  List<int> _ints(String k) => [for (final x in (data?[k] as List? ?? const [])) (x as num).toInt()];

  Future<void> _claim(int i) async {
    if (busy != null) return;
    setState(() => busy = i);
    try {
      final r = await RcServer.weekClaim(i + 1);
      Game.i.setWallet(r);
      final gain = (r['gain'] as num? ?? 0).toInt();
      RcAudio.sfx(i == 6 ? 'powerup' : 'coin');
      if (i == 6) {
        toast(t('🎁 Coffre ouvert : +$gain pièces, +2 pixels et un paquet premium dans ton stock !',
            '🎁 Chest opened: +$gain coins, +2 pixels and a premium pack in your stock!'));
      } else {
        toast(t('+$gain pièces !', '+$gain coins!'));
      }
      if (mounted) setState(() => data = r);
      Notifs.i.refresh();
    } catch (_) {
      toast(t('Impossible de récupérer pour l\'instant', 'Could not claim right now'));
      load();
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  String _left() {
    final ends = (data?['ends'] as num? ?? 0).toInt();
    if (ends == 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ends * 1000).difference(DateTime.now());
    if (d.isNegative) return '0H';
    if (d.inDays > 0) return '${d.inDays}J ${d.inHours % 24}H';
    if (d.inHours > 0) return '${d.inHours}H ${d.inMinutes % 60}MIN';
    return '${d.inMinutes}MIN';
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TabHeader(t('Défis', 'Challenges'), icon: 'defis'),
      Expanded(
        child: data == null
            ? Center(
                child: error
                    ? Text(t('Pas de connexion au serveur', 'No connection to the server'), style: const TextStyle(color: Colors.white54))
                    : const CircularProgressIndicator())
            : RefreshIndicator(onRefresh: load, child: _body()),
      ),
    ]);
  }

  Widget _body() {
    final goals = _ints('goals'), rewards = _ints('rewards'), prog = _ints('prog');
    final claim = (data?['claim'] as num? ?? 0).toInt();
    final n = goals.length;
    final got = [for (var i = 0; i < n; i++) if (claim & (1 << i) != 0) i].length;
    final chestOpen = claim & 64 != 0;
    final chestReady = !chestOpen && n > 0 && got == n;
    return ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 24), children: [
      _Chest(got: got, total: n, ready: chestReady, open: chestOpen, busy: busy == 6, onTap: chestReady ? () => _claim(6) : null),
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
        child: Row(children: [
          Expanded(child: Text(t('Nouveaux défis lundi', 'New challenges on Monday'), style: const TextStyle(color: Colors.white60, fontSize: 13))),
          Text('⏳ ${_left()}', style: pixelStyle(size: 9)),
        ]),
      ),
      for (var i = 0; i < n; i++)
        _ChallengeRow(
          icon: _icon(_kind(i)),
          label: _label(_kind(i), goals[i]),
          cur: i < prog.length ? prog[i] : 0,
          goal: goals[i],
          reward: i < rewards.length ? rewards[i] : 0,
          claimed: claim & (1 << i) != 0,
          busy: busy == i,
          onClaim: () => _claim(i),
        ),
      const SizedBox(height: 10),
      Text(
        t('Connexion : 50 pièces par jour, 200 tous les 7 jours d\'affilée (série : ${Game.i.streak})',
            'Login: 50 coins a day, 200 every 7 days in a row (streak: ${Game.i.streak})'),
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
    ]);
  }
}

class _Chest extends StatefulWidget {
  final int got, total;
  final bool ready, open, busy;
  final VoidCallback? onTap;
  const _Chest({required this.got, required this.total, required this.ready, required this.open, required this.busy, this.onTap});
  @override
  State<_Chest> createState() => _ChestState();
}

class _ChestState extends State<_Chest> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didUpdateWidget(covariant _Chest old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  void _sync() {
    if (widget.ready && !c.isAnimating) {
      c.repeat();
    } else if (!widget.ready && c.isAnimating) {
      c.stop();
      c.value = 0;
    }
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final text = w.open
        ? t('Coffre ouvert ! Rendez-vous lundi pour de nouveaux défis.', 'Chest opened! New challenges on Monday.')
        : w.ready
            ? t('Touche le coffre : ${liveInt('chest_coins')} pièces + ${liveInt('chest_pixels')} pixels + 1 paquet premium', 'Tap the chest: ${liveInt('chest_coins')} coins + ${liveInt('chest_pixels')} pixels + 1 premium pack')
            : t('${w.got}/${w.total} défis · termine-les tous : ${liveInt('chest_coins')} pièces + ${liveInt('chest_pixels')} pixels + 1 paquet premium',
                '${w.got}/${w.total} challenges · finish them all: ${liveInt('chest_coins')} coins + ${liveInt('chest_pixels')} pixels + 1 premium pack');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: w.busy ? null : w.onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3A2A6E), Color(0xFF1D2350)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: w.ready ? kGold : const Color(0xFF6B56C9), width: w.ready ? 2 : 1.5),
            boxShadow: w.ready ? [BoxShadow(color: kGold.withOpacity(0.35), blurRadius: 16)] : null,
          ),
          child: Row(children: [
            AnimatedBuilder(
              animation: c,
              builder: (_, child) {
                final v = c.value;
                final k = v < 0.5 ? v * 2 : 2 - v * 2;
                return Transform.translate(offset: Offset(0, -5 * k), child: Transform.rotate(angle: -0.07 * k, child: child));
              },
              child: Opacity(opacity: w.open ? 0.5 : 1, child: Text(w.open ? '📭' : '🎁', style: const TextStyle(fontSize: 40))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('Coffre de la semaine', 'Weekly chest'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                const SizedBox(height: 2),
                Text(text, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                const SizedBox(height: 7),
                Row(children: [
                  for (var i = 0; i < w.total; i++)
                    Expanded(
                      child: Container(
                        height: 7,
                        margin: EdgeInsets.only(right: i < w.total - 1 ? 4 : 0),
                        decoration: BoxDecoration(
                          color: i < w.got ? const Color(0xFFFAC775) : Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                ]),
              ]),
            ),
            if (w.busy) ...[
              const SizedBox(width: 10),
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ]),
        ),
      ),
    );
  }
}

class _ChallengeRow extends StatelessWidget {
  final String icon, label;
  final int cur, goal, reward;
  final bool claimed, busy;
  final VoidCallback onClaim;
  const _ChallengeRow({
    required this.icon,
    required this.label,
    required this.cur,
    required this.goal,
    required this.reward,
    required this.claimed,
    required this.busy,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final done = cur >= goal;
    final ready = done && !claimed;
    final f = goal <= 0 ? 1.0 : (cur / goal).clamp(0.0, 1.0);
    Widget right;
    if (claimed) {
      right = const Icon(Icons.check_circle, color: Color(0xFF5DCAA5), size: 22);
    } else if (ready) {
      right = FilledButton(
        onPressed: busy ? null : onClaim,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFFAC775),
          foregroundColor: const Color(0xFF2A1800),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 34),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(t('Récupérer $reward 🪙', 'Claim $reward 🪙'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5)),
      );
    } else {
      right = Text('+$reward 🪙', style: const TextStyle(color: Color(0xFFFAC775), fontWeight: FontWeight.w900, fontSize: 13));
    }
    return Opacity(
      opacity: claimed ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 10, 11, 10),
        decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(14),
          border: ready ? Border.all(color: const Color(0xFFFAC775), width: 1.5) : null,
        ),
        child: Row(children: [
          SizedBox(width: 34, child: Text(icon, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: f,
                      minHeight: 7,
                      backgroundColor: Colors.white.withOpacity(0.12),
                      color: done ? const Color(0xFF5DCAA5) : rcTheme.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${cur > goal ? goal : cur}/$goal', style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w800)),
              ]),
            ]),
          ),
          const SizedBox(width: 10),
          right,
        ]),
      ),
    );
  }
}
