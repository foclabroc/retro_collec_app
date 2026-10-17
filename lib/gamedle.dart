import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio.dart';
import 'cards.dart';
import 'catalog.dart';
import 'layout.dart';
import 'game.dart';
import 'main.dart';
import 'retro_theme.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// GAMEDLE — le jeu du jour, le même pour tout le monde (choisi par le serveur).
// 6 essais : la jaquette pixelisée se précise à chaque essai, et chaque
// proposition indique si la console, l'année et le genre correspondent.
// Résultat à partager en émojis, comme Wordle.
// ═══════════════════════════════════════════════════════════════════════════

const _kMax = 6;
const _kReward = [100, 80, 60, 45, 30, 20];
const _kPixels = [26, 38, 54, 76, 110, 160]; // largeur de la jaquette (en pixels) selon le nombre d'essais
const _kColor = Color(0xFF3DD9FF);
const _green = Color(0xFF3FB950), _yellow = Color(0xFFE3B341), _red = Color(0xFFB0413E);

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
Set<String> _genres(RcCard c) =>
    {for (final g in c.genreL.split(RegExp(r'\s*[,/]\s*'))) if (g.trim().isNotEmpty) g.trim().toLowerCase()};

/// Comparaison d'une proposition avec la réponse (indices affichés sous la jaquette)
class _Hint {
  final bool same, sameSys;
  final int year; // 0 : bonne année, 1 : la réponse est plus récente, -1 : plus ancienne, 9 : inconnue
  final int genre; // 0 : identique, 1 : en partie, 2 : différent
  _Hint(RcCard g, RcCard a)
      : same = _norm(g.title) == _norm(a.title),
        sameSys = g.sys == a.sys,
        year = g.year == null || a.year == null ? 9 : (a.year! > g.year! ? 1 : a.year! < g.year! ? -1 : 0),
        genre = _genres(g).isNotEmpty && _genres(g).containsAll(_genres(a)) && _genres(a).containsAll(_genres(g))
            ? 0
            : _genres(g).intersection(_genres(a)).isNotEmpty
                ? 1
                : 2;

  String get emoji =>
      (sameSys ? '🟩' : '🟥') + (year == 0 ? '🟩' : year == 1 ? '⬆️' : year == -1 ? '⬇️' : '⬛') + (genre == 0 ? '🟩' : genre == 1 ? '🟨' : '🟥');
}

// ── Tuile de l'onglet Bonus ─────────────────────────────────────────────────
class GamedleTile extends StatefulWidget {
  const GamedleTile({super.key});
  @override
  State<GamedleTile> createState() => _GamedleTileState();
}

class _GamedleTileState extends State<GamedleTile> {
  Map<String, dynamic>? st;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await RcServer.gamedleState();
      if (mounted) setState(() => st = s);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final guesses = (st?['guesses'] as List?)?.length ?? 0;
    final won = st?['won'] == true;
    final done = won || guesses >= _kMax;
    final status = st == null
        ? ''
        : won
            ? t('Trouvé en $guesses essai${guesses > 1 ? 's' : ''} ✓ · reviens demain', 'Solved in $guesses ✓ · back tomorrow')
            : done
                ? t('Raté aujourd\'hui · nouveau jeu demain', 'Missed today · new game tomorrow')
                : guesses > 0
                    ? t('En cours : ${_kMax - guesses} essais restants', 'In progress: ${_kMax - guesses} tries left')
                    : t('Jusqu\'à 100 pièces à gagner !', 'Up to 100 coins to win!');
    return Material(
      color: kPanel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GamedlePage()));
          _load();
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kColor.withOpacity(0.7), width: 1.5),
            gradient: LinearGradient(colors: [const Color(0xFF3FB950).withOpacity(0.16), Colors.transparent]),
          ),
          child: Row(children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: kBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _green, width: 2),
                boxShadow: [BoxShadow(color: _green.withOpacity(0.5), blurRadius: 12)],
              ),
              padding: const EdgeInsets.all(9),
              child: GridView.count(
                crossAxisCount: 3,
                mainAxisSpacing: 3,
                crossAxisSpacing: 3,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final c in const [_red, _yellow, _green, _yellow, _green, _red, _green, _green, _green])
                    DecoratedBox(decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Gamedle${st == null ? '' : ' #${st!['day']}'}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 3),
                Text(t('Devine le jeu du jour en 6 essais', 'Guess the game of the day in 6 tries'),
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
                const SizedBox(height: 4),
                Text(status,
                    style: TextStyle(color: done ? Colors.white38 : kGold, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
            Icon(done ? Icons.check_circle : Icons.play_arrow_rounded, color: done ? _green : _kColor, size: 32),
          ]),
        ),
      ),
    );
  }
}

// ── Écran de jeu ────────────────────────────────────────────────────────────
class GamedlePage extends StatefulWidget {
  const GamedlePage({super.key});
  @override
  State<GamedlePage> createState() => _GamedlePageState();
}

class _GamedlePageState extends State<GamedlePage> {
  Map<String, dynamic>? st;
  bool busy = false;
  String? error;
  final _field = TextEditingController();
  final _focus = FocusNode();
  final _inputKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    _load();
  }

  /// Champ sélectionné : on le remonte en haut de l'écran pour que la liste
  /// des propositions (en dessous) ne soit pas cachée par le clavier.
  void _onFocus() {
    setState(() {}); // marge en bas tant que le clavier est ouvert
    if (!_focus.hasFocus) return;
    for (final ms in const [350, 700]) {
      Future.delayed(Duration(milliseconds: ms), () {
        final ctx = _inputKey.currentContext;
        if (mounted && _focus.hasFocus && ctx != null) {
          Scrollable.ensureVisible(ctx, alignment: 0.02, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });
    }
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await RcServer.gamedleState();
      if (mounted) {
        setState(() {
          st = s;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = errText(e));
    }
  }

  RcCard? get answer => Catalog.cards[st?['card'] as String? ?? ''];
  List<RcCard> get guesses => [for (final id in (st?['guesses'] as List? ?? const [])) if (Catalog.cards[id] != null) Catalog.cards[id]!];
  bool get won => st?['won'] == true;
  bool get done => won || guesses.length >= _kMax;

  Future<void> _guess(RcCard c) async {
    if (busy || done) return;
    _field.clear();
    _focus.unfocus();
    setState(() => busy = true);
    try {
      final r = await RcServer.gamedleGuess(c.id);
      if (!mounted) return;
      setState(() => st = r);
      if (r['ok'] == true) {
        RcAudio.win();
        HapticFeedback.mediumImpact();
        Game.i.sync();
      } else {
        RcAudio.wrong();
        HapticFeedback.lightImpact();
        if (guesses.length >= _kMax) RcAudio.lose();
      }
    } catch (e) {
      toast(errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _shareText() {
    final a = answer!;
    final lines = [for (final g in guesses) _Hint(g, a).same ? '🟩🟩🟩 ✅' : _Hint(g, a).emoji];
    return 'Pixel Trade · Gamedle #${st!['day']}  ${won ? guesses.length : 'X'}/$_kMax\n${lines.join('\n')}\n'
        'https://foclabroc.github.io/retro_collec_app/';
  }

  @override
  Widget build(BuildContext context) {
    final a = answer;
    return MaxWidth(max: 820, child: Scaffold(
      appBar: AppBar(
        title: Text('GAMEDLE${st == null ? '' : ' #${st!['day']}'}', style: pixelStyle(size: 14, color: _kColor)),
        actions: [
          Padding(padding: const EdgeInsets.only(right: 12), child: Center(child: ListenableBuilder(listenable: Game.i, builder: (_, __) => CoinChip(Game.i.coins)))),
        ],
      ),
      body: st == null || a == null
          ? Center(
              child: error != null
                  ? Text(error!, style: const TextStyle(color: Colors.white54))
                  : st != null && a == null
                      ? Text(t('Catalogue pas à jour : relance l\'appli', 'Catalog out of date: restart the app'),
                          style: const TextStyle(color: Colors.white54))
                      : const CircularProgressIndicator())
          : ListView(padding: EdgeInsets.fromLTRB(16, 4, 16, _focus.hasFocus ? 360 : 28), children: [
              Text(
                done
                    ? (won ? t('Bravo ! Tu as trouvé le jeu du jour 🎉', 'Well done! You found today\'s game 🎉') : t('Raté… voici le jeu du jour', 'Missed… here is today\'s game'))
                    : t('Quel est ce jeu ? ${_kMax - guesses.length} essai${_kMax - guesses.length > 1 ? 's' : ''} restant${_kMax - guesses.length > 1 ? 's' : ''}',
                        'Which game is this? ${_kMax - guesses.length} tries left'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Center(child: done ? SizedBox(width: 190, child: CardView(card: a, finish: won ? 1 : 0)) : _Pixelated(card: a, level: guesses.length)),
              const SizedBox(height: 14),
              if (!done) ...[_hints(a), const SizedBox(height: 12)],
              if (!done && guesses.length >= 2) ...[_choices(a), const SizedBox(height: 12)],
              if (!done) KeyedSubtree(key: _inputKey, child: _input()),
              if (done) _result(a),
              const SizedBox(height: 14),
              if (guesses.isNotEmpty) _legend(),
              for (final g in guesses.reversed) _GuessRow(guess: g, answer: a),
              const SizedBox(height: 14),
              Text(
                t('${st!['solvers']} joueur${(st!['solvers'] as num? ?? 0) > 1 ? 's ont' : ' a'} trouvé aujourd\'hui sur ${st!['players']}',
                    '${st!['solvers']} of ${st!['players']} players solved it today'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              if (!done) ...[
                const SizedBox(height: 6),
                Text(t('Gains : ${_kReward.join(' · ')} pièces selon le nombre d\'essais', 'Rewards: ${_kReward.join(' · ')} coins by number of tries'),
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ]),
    ));
  }

  Widget _input() {
    final used = {for (final g in guesses) g.id};
    return Autocomplete<RcCard>(
      textEditingController: _field,
      focusNode: _focus,
      displayStringForOption: (c) => c.title,
      optionsBuilder: (v) {
        final q = _norm(v.text);
        if (q.isEmpty) return const Iterable<RcCard>.empty();
        final seen = <String>{};
        final out = <RcCard>[];
        for (final c in Catalog.cards.values) {
          if (c.sys != answer?.sys || used.contains(c.id) || !_norm(c.title).contains(q)) continue;
          if (!seen.add('${_norm(c.title)}|${c.sys}')) continue;
          out.add(c);
          if (out.length >= 30) break;
        }
        out.sort((x, y) => (_norm(x.title).startsWith(q) ? 0 : 1).compareTo(_norm(y.title).startsWith(q) ? 0 : 1));
        return out.take(10);
      },
      onSelected: _guess,
      fieldViewBuilder: (context, ctl, focus, onSubmit) => TextField(
        controller: ctl,
        focusNode: focus,
        enabled: !busy,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: t('Tape le nom d\'un jeu ${Catalog.system(answer?.sys ?? "")?.short ?? ""}…', 'Type a ${Catalog.system(answer?.sys ?? "")?.short ?? ""} game name…'),
          prefixIcon: busy ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : const Icon(Icons.search),
          filled: true,
          fillColor: kPanel,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _kColor)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _kColor.withOpacity(0.6))),
        ),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: kBg,
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            // hauteur limitée à la place libre au-dessus du clavier
            constraints: BoxConstraints(
              maxHeight: (MediaQuery.of(context).size.height - MediaQuery.of(context).viewInsets.bottom - 200).clamp(120.0, 300.0),
              maxWidth: MediaQuery.of(context).size.width - 32,
            ),
            child: ListView(padding: EdgeInsets.zero, shrinkWrap: true, children: [
              for (final c in options)
                ListTile(
                  dense: true,
                  title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${Catalog.system(c.sys)?.short ?? c.sys}${c.year == null ? '' : ' · ${c.year}'}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () => onSelected(c),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _result(RcCard a) {
    final reward = st?['reward'] as num?;
    return Column(children: [
      Text(a.title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      Text('${Catalog.system(a.sys)?.name ?? a.sys}${a.year == null ? '' : ' · ${a.year}'}',
          textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
      if (won && reward != null && reward > 0) ...[
        const SizedBox(height: 8),
        Text('+$reward ${t('pièces', 'coins')}', textAlign: TextAlign.center, style: pixelStyle(size: 14)),
      ],
      const SizedBox(height: 12),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: _kColor, foregroundColor: const Color(0xFF04342C)),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: _shareText()));
          toast(t('Résultat copié : colle-le dans tes messages !', 'Result copied: paste it anywhere!'));
        },
        icon: const Icon(Icons.share),
        label: Text(t('Partager mon résultat', 'Share my result')),
      ),
      const SizedBox(height: 6),
      Text(t('Nouveau jeu demain à minuit', 'New game tomorrow at midnight'), style: const TextStyle(color: Colors.white38, fontSize: 12)),
    ]);
  }

  /// Après 2 erreurs : 4 jaquettes au choix (la bonne + 3 autres de la même console, tirées de façon fixe pour la journée)
  Widget _choices(RcCard a) {
    final used = {for (final g in guesses) g.id};
    final pool = [for (final c in Catalog.bySys[a.sys] ?? const <RcCard>[]) if (c.id != a.id && _norm(c.title) != _norm(a.title)) c];
    final seed = (st?['day'] as num? ?? 0).toInt();
    pool.sort((x, y) => ((x.num * 7919 + seed * 104729) % 1009).compareTo((y.num * 7919 + seed * 104729) % 1009));
    final opts = [a, ...pool.take(3)]..sort((x, y) => ((x.num * 31 + seed) % 97).compareTo((y.num * 31 + seed) % 97));
    opts.removeWhere((c) => used.contains(c.id)); // les mauvais choix déjà tentés disparaissent
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('🃏 Joker : c\'est l\'un de ces 4 jeux !', '🃏 Joker: it\'s one of these 4 games!'),
          textAlign: TextAlign.center, style: const TextStyle(color: kGold, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
        for (final c in opts)
          SizedBox(
            width: 160,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: _kColor.withOpacity(0.6)),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: busy ? null : () => _guess(c),
              child: Text(c.title, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ),
      ]),
    ]);
  }

  /// Indices débloqués au fil des erreurs : console, année, genre, développeur, initiales du titre
  Widget _hints(RcCard a) {
    final n = guesses.length;
    final initials = a.title
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + List.filled(w.length - 1, '_').join())
        .join(' ');
    final rows = <(String, String, String)>[
      ('🎮', t('Console', 'System'), Catalog.system(a.sys)?.name ?? a.sys),
      ('📅', t('Année', 'Year'), '${a.year ?? '?'}'),
      ('🏷️', t('Genre', 'Genre'), a.genreL.isEmpty ? '?' : a.genreL),
      ('🛠️', t('Développeur', 'Developer'), a.dev.isEmpty ? '?' : a.dev),
      ('🔤', t('Titre', 'Title'), initials),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kGold.withOpacity(0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t('Indices', 'Hints'), style: pixelStyle(size: 10)),
        const SizedBox(height: 6),
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              SizedBox(width: 26, child: Text(rows[i].$1, style: const TextStyle(fontSize: 15))),
              SizedBox(width: 92, child: Text(rows[i].$2, style: const TextStyle(color: Colors.white54, fontSize: 13))),
              Expanded(
                child: i <= n
                    ? Text(rows[i].$3, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.5))
                    : Text(t('après $i erreur${i > 1 ? 's' : ''}', 'after $i miss${i > 1 ? 'es' : ''}'),
                        style: const TextStyle(color: Colors.white24, fontSize: 12, fontStyle: FontStyle.italic)),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _legend() {
    Widget h(String s) => Expanded(child: Text(s, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 11)));
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        const SizedBox(width: 4),
        Expanded(flex: 3, child: Text(t('Jeu proposé', 'Guess'), style: const TextStyle(color: Colors.white54, fontSize: 11))),
        h(t('Console', 'System')),
        h(t('Année', 'Year')),
        h(t('Genre', 'Genre')),
      ]),
    );
  }
}

/// Jaquette du jour, pixelisée selon le nombre d'essais déjà faits
class _Pixelated extends StatelessWidget {
  final RcCard card;
  final int level;
  const _Pixelated({required this.card, required this.level});

  @override
  Widget build(BuildContext context) {
    final px = _kPixels[level.clamp(0, _kPixels.length - 1)];
    return Container(
      width: 200,
      height: 260,
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kColor, width: 2),
        boxShadow: [BoxShadow(color: _kColor.withOpacity(0.35), blurRadius: 18)],
      ),
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          child: Image(
            key: ValueKey(px),
            image: ResizeImage(Catalog.image(card), width: px, policy: ResizeImagePolicy.fit),
            fit: BoxFit.contain,
            width: 184,
            height: 244,
            filterQuality: FilterQuality.none,
            errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.image_not_supported, color: Colors.white24)),
          ),
        ),
      ),
    );
  }
}

/// Une ligne de proposition : titre + 3 cases (console, année, genre)
class _GuessRow extends StatelessWidget {
  final RcCard guess, answer;
  const _GuessRow({required this.guess, required this.answer});

  @override
  Widget build(BuildContext context) {
    final h = _Hint(guess, answer);
    Widget cell(Color c, String txt, {IconData? icon}) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            height: 42,
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (icon != null) Icon(icon, size: 14, color: Colors.white),
              Text(txt, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
            ]),
          ),
        );
    final sys = Catalog.system(guess.sys)?.short ?? guess.sys;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: h.same ? _green : kPanel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            alignment: Alignment.centerLeft,
            child: Text(guess.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.15)),
          ),
        ),
        cell(h.sameSys ? _green : _red, sys),
        cell(
          h.year == 0 ? _green : (h.year == 9 ? kPanel2 : _red),
          '${guess.year ?? '?'}',
          icon: h.year == 1 ? Icons.arrow_upward : h.year == -1 ? Icons.arrow_downward : null,
        ),
        cell(h.genre == 0 ? _green : h.genre == 1 ? _yellow : _red, guess.genreL.split(RegExp(r'\s*[,/]\s*')).first),
      ]),
    );
  }
}
