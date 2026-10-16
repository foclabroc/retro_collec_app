import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio.dart';
import 'cards.dart';
import 'catalog.dart';
import 'game.dart';
import 'main.dart';
import 'retro_theme.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Quiz rétro : une capture d'écran, 4 titres, 12 secondes pour trouver le jeu.
// 10 questions par partie. 5 pièces par bonne réponse, 100 pièces max par jour
// (plafond vérifié par le serveur).
// ═══════════════════════════════════════════════════════════════════════════

const kQuizQuestions = 10;
const kQuizSeconds = 12;
const kQuizCoinsPerAnswer = 5;

class _Question {
  final RcCard answer;
  final List<RcCard> options;
  const _Question(this.answer, this.options);
}

/// Cartes utilisables pour le quiz : celles dont la capture est sur le téléphone.
List<RcCard> quizPool() => [for (final c in Catalog.cards.values) if (Catalog.hasShot(c)) c];

List<_Question> _makeQuestions(Random rnd) {
  final pool = quizPool()..shuffle(rnd);
  final out = <_Question>[];
  final usedTitles = <String>{};
  for (final c in pool) {
    if (out.length >= kQuizQuestions) break;
    final key = c.title.toLowerCase();
    if (usedTitles.contains(key)) continue;
    // mauvaises réponses : même console de préférence (plus dur), titres différents
    final same = (Catalog.bySys[c.sys] ?? const <RcCard>[]).where((o) => o.title.toLowerCase() != key).toList()..shuffle(rnd);
    final others = Catalog.cards.values.where((o) => o.sys != c.sys && o.title.toLowerCase() != key).toList()..shuffle(rnd);
    final wrong = <RcCard>[];
    final seen = {key};
    for (final o in [...same, ...others]) {
      if (wrong.length >= 3) break;
      if (seen.add(o.title.toLowerCase())) wrong.add(o);
    }
    if (wrong.length < 3) continue;
    usedTitles.add(key);
    out.add(_Question(c, [c, ...wrong]..shuffle(rnd)));
  }
  return out;
}

/// Tuile d'accès au quiz (écran Paquets)
class QuizTile extends StatefulWidget {
  const QuizTile({super.key});
  @override
  State<QuizTile> createState() => _QuizTileState();
}

class _QuizTileState extends State<QuizTile> {
  int? left;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await RcServer.quizStatus();
      if (mounted) setState(() => left = l);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF3DD9FF);
    return Material(
      color: kPanel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          if (quizPool().length < 20) {
            toast(t('Les captures d\'écran sont encore en téléchargement, réessaie dans un instant',
                'Screenshots are still downloading, try again in a moment'));
            return;
          }
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuizPage()));
          _load();
        },
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
              child: Center(child: Text('?', style: pixelStyle(size: 24, color: color))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('Quiz rétro', 'Retro quiz'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 3),
                Text(t('Devine le jeu à partir de sa capture d\'écran', 'Guess the game from its screenshot'),
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  left == null
                      ? ''
                      : left! > 0
                          ? t('Encore $left pièces à gagner aujourd\'hui', '$left coins left to win today')
                          : t('Plafond du jour atteint · rejouable pour le fun', 'Daily cap reached · play for fun'),
                  style: TextStyle(color: left != null && left! > 0 ? kGold : Colors.white38, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ]),
            ),
            const Icon(Icons.play_arrow_rounded, color: color, size: 32),
          ]),
        ),
      ),
    );
  }
}

class QuizPage extends StatefulWidget {
  const QuizPage({super.key});
  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> with TickerProviderStateMixin {
  final rnd = Random();
  late List<_Question> questions = _makeQuestions(rnd);
  int index = 0, correct = 0, combo = 0, bestCombo = 0;
  RcCard? picked; // réponse choisie (null = pas encore répondu)
  bool timedOut = false, finished = false, claiming = false;
  Map<String, dynamic>? result;
  late final AnimationController timer = AnimationController(vsync: this, duration: const Duration(seconds: kQuizSeconds))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed && picked == null && !timedOut) _timeout();
    });

  _Question get q => questions[index];
  bool get answered => picked != null || timedOut;

  @override
  void initState() {
    super.initState();
    timer.forward(from: 0);
  }

  @override
  void dispose() {
    timer.dispose();
    super.dispose();
  }

  void _answer(RcCard c) {
    if (answered) return;
    timer.stop();
    final ok = c.id == q.answer.id;
    setState(() {
      picked = c;
      if (ok) {
        correct++;
        combo++;
        bestCombo = max(bestCombo, combo);
      } else {
        combo = 0;
      }
    });
    if (ok) {
      RcAudio.sfx('coin');
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    Future.delayed(const Duration(milliseconds: 1300), _next);
  }

  void _timeout() {
    setState(() {
      timedOut = true;
      combo = 0;
    });
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 1300), _next);
  }

  void _next() {
    if (!mounted) return;
    if (index + 1 >= questions.length) {
      _finish();
      return;
    }
    setState(() {
      index++;
      picked = null;
      timedOut = false;
    });
    timer.forward(from: 0);
  }

  Future<void> _finish() async {
    setState(() {
      finished = true;
      claiming = true;
    });
    try {
      final r = await RcServer.quizClaim(correct);
      Game.i.setCoins((r['coins'] as num? ?? Game.i.coins).toInt());
      if (((r['gain'] as num?) ?? 0) > 0) RcAudio.sfx('powerup');
      if (mounted) setState(() => result = r);
    } catch (e) {
      toast(errText(e));
    }
    if (mounted) setState(() => claiming = false);
  }

  void _restart() {
    setState(() {
      questions = _makeQuestions(rnd);
      index = correct = combo = bestCombo = 0;
      picked = null;
      timedOut = finished = false;
      result = null;
    });
    timer.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(t('QUIZ RÉTRO', 'RETRO QUIZ'), style: pixelStyle(size: 13)),
        actions: [
          ListenableBuilder(listenable: Game.i, builder: (_, __) => CoinChip(Game.i.coins)),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(top: false, child: finished ? _resultView() : _questionView()),
    );
  }

  Widget _questionView() {
    final shot = Catalog.shot(q.answer);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(children: [
        // progression + score
        Row(children: [
          Text('${index + 1} / ${questions.length}', style: pixelStyle(size: 11, color: Colors.white)),
          const Spacer(),
          if (combo >= 2)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text('COMBO x$combo', style: pixelStyle(size: 10, color: const Color(0xFFFF8A3D))),
            ),
          const Icon(Icons.check_circle, color: Color(0xFF5DCAA5), size: 18),
          const SizedBox(width: 4),
          Text('$correct', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
        const SizedBox(height: 10),
        // chrono
        AnimatedBuilder(
          animation: timer,
          builder: (_, __) {
            final left = 1 - timer.value;
            final c = left > 0.5 ? const Color(0xFF5DCAA5) : (left > 0.25 ? kGold : const Color(0xFFE24B4A));
            return ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: left, minHeight: 8, color: c, backgroundColor: Colors.white12),
            );
          },
        ),
        const SizedBox(height: 14),
        // capture d'écran
        Expanded(
          child: Center(
            child: Stack(alignment: Alignment.topLeft, children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24, width: 2),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 14, offset: Offset(0, 6))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: shot == null ? const SizedBox(width: 200, height: 150) : Image(image: shot, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox(width: 200, height: 150)),
                ),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(color: kBg.withOpacity(0.8), borderRadius: BorderRadius.circular(6)),
                  child: FittedBox(child: ConsoleLogo(q.answer.sys, height: 16)),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        if (timedOut)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(t('Temps écoulé !', 'Time\'s up!'), style: pixelStyle(size: 11, color: const Color(0xFFE24B4A))),
          ),
        // réponses
        for (final o in q.options) _option(o),
      ]),
    );
  }

  Widget _option(RcCard o) {
    final isAnswer = o.id == q.answer.id;
    Color border = Colors.white24, bg = kPanel;
    IconData? icon;
    if (answered) {
      if (isAnswer) {
        border = const Color(0xFF5DCAA5);
        bg = const Color(0xFF0F3D33);
        icon = Icons.check_circle;
      } else if (picked?.id == o.id) {
        border = const Color(0xFFE24B4A);
        bg = const Color(0xFF3D1418);
        icon = Icons.cancel;
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: answered ? null : () => _answer(o),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: border, width: 2)),
            child: Row(children: [
              Expanded(
                child: Text(o.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              if (icon != null) Icon(icon, color: border),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _resultView() {
    final gain = (result?['gain'] as num? ?? 0).toInt();
    final left = (result?['left'] as num?)?.toInt();
    final perfect = correct == questions.length;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Text(perfect ? t('PARFAIT !', 'PERFECT!') : t('TERMINÉ', 'FINISHED'), style: pixelStyle(size: 20)),
          const SizedBox(height: 24),
          Text('$correct / ${questions.length}', style: pixelStyle(size: 34, color: Colors.white)),
          const SizedBox(height: 8),
          Text(t('bonnes réponses', 'correct answers'), style: const TextStyle(color: Colors.white60)),
          if (bestCombo >= 3) ...[
            const SizedBox(height: 10),
            Text(t('Meilleur combo : x$bestCombo', 'Best combo: x$bestCombo'),
                style: const TextStyle(color: Color(0xFFFF8A3D), fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 28),
          if (claiming)
            const CircularProgressIndicator(color: kGold)
          else if (result != null) ...[
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('+$gain', style: pixelStyle(size: 22)),
              const SizedBox(width: 10),
              const Icon(Icons.monetization_on, color: kGold, size: 30),
            ]),
            const SizedBox(height: 10),
            Text(
              left == null
                  ? ''
                  : left > 0
                      ? t('Encore $left pièces à gagner aujourd\'hui', '$left coins left to win today')
                      : t('Plafond du jour atteint (100 pièces) · reviens demain !', 'Daily cap reached (100 coins) · come back tomorrow!'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60),
            ),
          ],
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
              onPressed: claiming ? null : _restart,
              icon: const Icon(Icons.replay),
              label: Text(t('Rejouer', 'Play again'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t('Retour', 'Back'))),
        ]),
      ),
    );
  }
}
