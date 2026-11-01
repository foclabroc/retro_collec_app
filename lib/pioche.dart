import 'package:flutter/material.dart';

import 'audio.dart';
import 'cards.dart';
import 'catalog.dart';
import 'game.dart';
import 'main.dart';
import 'rewards.dart';
import 'server.dart';

Widget _tileBox(Color color, String icon, String title, String sub, String? info, VoidCallback onTap) {
  return Material(
    color: kPanel,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.7), width: 1.5),
          gradient: LinearGradient(colors: [color.withOpacity(0.16), Colors.transparent]),
        ),
        child: Row(children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: kBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color, width: 2),
              boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 12)],
            ),
            child: Center(child: Text(icon, style: const TextStyle(fontSize: 28))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 3),
              Text(sub, style: const TextStyle(color: Colors.white60, fontSize: 12)),
              if (info != null) ...[
                const SizedBox(height: 4),
                Text(info, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: color, size: 30),
        ]),
      ),
    ),
  );
}

// ── Pioche du jour ──────────────────────────────────────────────────────────
class PiocheTile extends StatefulWidget {
  const PiocheTile({super.key});
  @override
  State<PiocheTile> createState() => _PiocheTileState();
}

class _PiocheTileState extends State<PiocheTile> {
  bool? ready;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await RcServer.piocheStatus();
      if (mounted) setState(() => ready = r);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return _tileBox(
      const Color(0xFFB36BFF),
      '🃏',
      t('Pioche du jour', 'Daily draw'),
      t('5 cartes face cachée : choisis-en une, pas de seconde chance', '5 face-down cards: pick one, no second chance'),
      ready == null ? null : (ready! ? t('Disponible !', 'Available!') : t('Reviens demain', 'Come back tomorrow')),
      () async {
        if (ready == false) {
          toast(t('Tu as déjà pioché aujourd\'hui, reviens demain', 'You already drew today, come back tomorrow'));
          return;
        }
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PiochePage()));
        _load();
      },
    );
  }
}

class PiochePage extends StatefulWidget {
  const PiochePage({super.key});
  @override
  State<PiochePage> createState() => _PiochePageState();
}

class _PiochePageState extends State<PiochePage> {
  Map<String, dynamic>? res;
  int? pick;
  bool busy = false;
  bool shown = false; // cartes retournées

  Future<void> _choose(int i) async {
    if (busy || res != null) return;
    setState(() {
      busy = true;
      pick = i;
    });
    try {
      final r = await RcServer.pioche(i);
      if (!mounted) return;
      setState(() {
        res = r;
        busy = false;
      });
      Game.i.sync();
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) setState(() => shown = true);
      RcAudio.sfx('powerup');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        pick = null;
      });
      toast(errText(e));
    }
  }

  Widget _slot(int i) {
    final c = res == null ? null : (res!['cards'] as List)[i] as Map;
    final card = c == null ? null : Catalog.cards['${c['c']}'];
    final mine = pick == i;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: mine && shown ? [BoxShadow(color: kGold.withOpacity(0.8), blurRadius: 18, spreadRadius: 2)] : null,
      ),
      child: GestureDetector(
        onTap: () => _choose(i),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
          child: shown && card != null
              ? Opacity(
                  key: ValueKey('f$i'),
                  opacity: mine ? 1 : 0.55,
                  child: CardView(card: card, finish: (c!['f'] as num).toInt()),
                )
              : const CardBack(key: ValueKey('b')),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = res?['n'] == true;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(title: Text(t('Pioche du jour', 'Daily draw'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Text(
              shown
                  ? (isNew ? t('Nouvelle carte pour ta collection !', 'New card for your collection!') : t('Voilà ta carte (les autres étaient perdues)', 'Here is your card (the others are lost)'))
                  : t('Choisis une carte', 'Pick a card'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(builder: (ctx, box) {
                final w = (box.maxWidth - 24) / 3;
                return Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [for (var i = 0; i < 5; i++) SizedBox(width: w, child: _slot(i))],
                );
              }),
            ),
            if (shown) FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(t('Fermer', 'Close'))),
          ]),
        ),
      ),
    );
  }
}

// ── Défi express ────────────────────────────────────────────────────────────
String _expLabel(String k, int goal) => switch (k) {
      'open' => t('Ouvre $goal paquets', 'Open $goal packs'),
      'gift' => t('Envoie $goal cadeau', 'Send $goal gift'),
      'trade' => t('Fais $goal échange, achat ou vente', 'Make $goal trade, purchase or sale'),
      'win' => t('Gagne $goal duel', 'Win $goal duel'),
      'gamedle' => t('Réussis $goal Gamedle', 'Solve $goal Gamedle'),
      'play' => t('Joue $goal duels', 'Play $goal duels'),
      'new' => t('Obtiens $goal nouvelles cartes', 'Get $goal new cards'),
      'quiz' => t('Donne $goal bonnes réponses au quiz', 'Give $goal right quiz answers'),
      'sale' => t('Vends $goal carte à la Bourse', 'Sell $goal card on the market'),
      'free' => t('Ouvre le paquet gratuit', 'Open the free pack'),
      'premium' => t('Ouvre $goal paquet premium', 'Open $goal premium pack'),
      _ => t('Obtiens une carte épique ou mieux', 'Get an epic card or better'),
    };

class ExpressTile extends StatefulWidget {
  const ExpressTile({super.key});
  @override
  State<ExpressTile> createState() => _ExpressTileState();
}

class _ExpressTileState extends State<ExpressTile> with WidgetsBindingObserver {
  Map<String, dynamic>? d;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final r = await RcServer.expressGet();
      if (mounted && r.isNotEmpty) setState(() => d = r);
    } catch (_) {}
  }

  Future<void> _claim() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final r = await RcServer.expressClaim();
      Game.i.sync();
      toast(t('Récompense : ${rewardText(r['reward'])}', 'Reward: ${rewardText(r['reward'])}'));
    } catch (e) {
      toast(errText(e));
    }
    busy = false;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFFF8A3D);
    final x = d;
    if (x == null) return const SizedBox.shrink();
    final goal = (x['goal'] as num).toInt();
    final prog = ((x['prog'] as num?) ?? 0).toInt().clamp(0, goal);
    final claimed = x['claimed'] == true;
    final done = prog >= goal;
    return Material(
      color: kPanel,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.7), width: 1.5),
          gradient: LinearGradient(colors: [color.withOpacity(0.16), Colors.transparent]),
        ),
        child: Row(children: [
          const Text('⚡', style: TextStyle(fontSize: 30)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('Défi express du jour', 'Daily express challenge'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 3),
              Text(_expLabel('${x['kind']}', goal), style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: prog / goal, minHeight: 8, color: color, backgroundColor: Colors.white12),
              ),
              const SizedBox(height: 4),
              Text('$prog / $goal · ${rewardText(x['reward'])}', style: const TextStyle(color: kGold, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(width: 8),
          if (claimed)
            const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 30)
          else if (done)
            FilledButton(onPressed: busy ? null : _claim, child: Text(t('Récupérer', 'Claim'))),
        ]),
      ),
    );
  }
}
