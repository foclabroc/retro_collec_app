import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'cab_games.dart';
import 'catalog.dart';
import 'packs.dart';
import 'game.dart';
import 'main.dart';
import 'notifs.dart';
import 'retro_theme.dart';
import 'server.dart';
import 'trophies.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Voisinage « Pixel Arcade » : chaque joueur a sa borne d'arcade (habillage au
// choix, débloqué au nombre de cartes), rangées par classement : podium pour
// les 3 premiers puis des rangées de 3 bornes. Écran allumé (PLAYING) si le
// joueur est en ligne, OFFLINE sinon. Comptoir en bas : cadeaux, recherche.
// Images des bornes : assets/arcade/<id>.webp (360 x 594, fond transparent).
// ═══════════════════════════════════════════════════════════════════════════

/// Habillage de borne (« house » côté serveur = son numéro)
class CabinetSkin {
  final String fr, en, id;
  final int need; // cartes pour le débloquer
  final Color glow; // lueur / couleur d'accent
  const CabinetSkin(this.fr, this.en, this.id, this.need, this.glow);
  String get name => t(fr, en);
  String get asset => 'assets/arcade/$id.webp';
}

/// Ordre = numéros déjà enregistrés pour les anciens thèmes d'étage (ne pas changer)
const kFloorThemes = [
  CabinetSkin('Pierre', 'Stone', 'pierre', 0, Color(0xFFD9C8A3)),
  CabinetSkin('Brique', 'Brick', 'brique', 0, Color(0xFFD9694A)),
  CabinetSkin('Bois', 'Wood', 'bois', 0, Color(0xFFE0A050)),
  CabinetSkin('Lierre', 'Ivy', 'lierre', 50, Color(0xFF6FBF5A)),
  CabinetSkin('Néon', 'Neon', 'neon', 100, Color(0xFFFF4FD8)),
  CabinetSkin('Art déco', 'Art deco', 'artdeco', 150, Color(0xFFD9B45A)),
  CabinetSkin('Verre', 'Glass', 'verre', 200, Color(0xFF8FB4E0)),
  CabinetSkin('Château', 'Castle', 'chateau', 250, Color(0xFFC0B8C8)),
  CabinetSkin('Japonais', 'Japanese', 'japonais', 300, Color(0xFFE04040)),
  CabinetSkin('Arcade', 'Arcade', 'arcade', 400, Color(0xFFFF3DF0)),
  CabinetSkin('Spatial', 'Space', 'spatial', 500, Color(0xFF7DFFB0)),
  CabinetSkin('Sous-marin', 'Submarine', 'sousmarin', 600, Color(0xFF6FE0C0)),
  CabinetSkin('Plage', 'Beach', 'plage', 700, Color(0xFF7FD0F0)),
  CabinetSkin('Neige', 'Snow', 'neige', 800, Color(0xFFBFE6FF)),
  CabinetSkin('Halloween', 'Halloween', 'halloween', 1000, Color(0xFFFF8A1A)),
  CabinetSkin('Or', 'Gold', 'or', 1200, Color(0xFFFFD166)),
];

/// Habillage d'un joueur ; par défaut un des 3 offerts, varié selon le joueur
int floorThemeOf(String? house, String pid) {
  final n = int.tryParse(house ?? '');
  if (n != null && n >= 0 && n < kFloorThemes.length) return n;
  return pid.hashCode.abs() % 3;
}

class FloorData {
  final String pid, name;
  final int avatar, score, cards, coins, pixels, theme;
  final int? rank;
  final bool online, me;
  final bool busy; // en duel en direct (rc_board)
  final DateTime? seenAt; // dernière connexion
  final String trophies; // vitrine de trophées « type:palier,,type:palier »
  final String? cabGame; // mini-jeu de la borne (rc_cab_board), null si pas encore chargé
  final int? cabRec; // record de la semaine
  final String? cabRecName; // pseudo du détenteur du record
  const FloorData({
    this.cabGame,
    this.cabRec,
    this.cabRecName,
    this.trophies = '',
    this.seenAt,
    required this.pid,
    required this.name,
    required this.avatar,
    required this.score,
    required this.cards,
    required this.coins,
    this.pixels = 0,
    required this.theme,
    required this.online,
    required this.me,
    this.busy = false,
    this.rank,
  });

  factory FloorData.of(Map<String, dynamic> p, {int? rank}) {
    final pid = p['pid'] as String? ?? '';
    final me = pid == Game.i.pid;
    final cab = CabBoard.of(pid);
    return FloorData(
      cabGame: cab?['game'] as String?,
      cabRec: (cab?['rec'] as num?)?.toInt(),
      cabRecName: cab?['rec_name'] as String?,
      pid: pid,
      name: p['name'] as String? ?? '?',
      avatar: me ? Game.i.avatar : (p['avatar'] as num? ?? 0).toInt(),
      score: me ? Game.i.score : (p['score'] as num? ?? 0).toInt(),
      cards: me ? Game.i.cards : (p['cards'] as num? ?? 0).toInt(),
      coins: me ? Game.i.coins : (p['coins'] as num? ?? 0).toInt(),
      pixels: me ? Game.i.pixels : (p['pixels'] as num? ?? 0).toInt(),
      theme: floorThemeOf(me ? Game.i.house : p['house'] as String?, pid),
      online: me || p['online'] == true,
      me: me,
      busy: !me && p['busy'] == true,
      seenAt: DateTime.tryParse(p['seen_at']?.toString() ?? '')?.toLocal(),
      rank: rank ?? (p['rank'] as num?)?.toInt(),
      trophies: (me ? myTrophyShow.value : null) ?? p['trophies'] as String? ?? '',
    );
  }
}

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Dernière connexion, version courte (plaque) : « vu à 14:32 », « vu hier », « vu le 12/10 »
String lastSeenShort(DateTime? d) {
  if (d == null) return '';
  final now = DateTime.now();
  final day = DateTime(d.year, d.month, d.day), today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return t('vu à ${_hm(d)}', 'seen at ${_hm(d)}');
  if (diff == 1) return t('vu hier', 'seen yesterday');
  return t('vu le ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}', 'seen ${d.month}/${d.day}');
}

/// Dernière connexion, version longue (profil) : « aujourd'hui à 14:32 (il y a 3 h) »
String lastSeenLong(DateTime? d) {
  if (d == null) return t('inconnue', 'unknown');
  final now = DateTime.now();
  final day = DateTime(d.year, d.month, d.day), today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  final m = now.difference(d).inMinutes;
  final ago = m < 1
      ? t('à l\'instant', 'just now')
      : m < 60
          ? t('il y a $m min', '$m min ago')
          : m < 48 * 60
              ? t('il y a ${m ~/ 60} h', '${m ~/ 60} h ago')
              : t('il y a ${m ~/ 1440} jours', '${m ~/ 1440} days ago');
  final when = diff <= 0
      ? t('aujourd\'hui à ${_hm(d)}', 'today at ${_hm(d)}')
      : diff == 1
          ? t('hier à ${_hm(d)}', 'yesterday at ${_hm(d)}')
          : t('le ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} à ${_hm(d)}', 'on ${d.month}/${d.day} at ${_hm(d)}');
  return '$when ($ago)';
}

String pctOf(int cards) => '${Catalog.cards.isEmpty ? 0 : (cards * 100 ~/ Catalog.cards.length)} %';

/// Joueurs à qui j'ai offert un paquet aujourd'hui (🎁 grisé)
final kGiftedToday = <String>{};

// ─── Géométrie commune à toutes les images de borne ──────────────────────
const kCabRatio = 360 / 594; // largeur / hauteur
const _kScreen = Rect.fromLTRB(0.135, 0.19, 0.865, 0.495); // écran noir
const _kMarquee = Rect.fromLTRB(0.08, 0.022, 0.92, 0.108); // fronton

/// Texte qui clignote (PLAYING)
class _Blink extends StatefulWidget {
  final Widget child;
  const _Blink({required this.child});
  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> {
  bool on = true;
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 650), (_) {
      if (mounted) setState(() => on = !on);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Opacity(opacity: on ? 1 : 0, child: widget.child);
}

/// Texte d'afficheur : immobile s'il tient, sinon il défile en boucle de droite à gauche
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const MarqueeText(this.text, {super.key, required this.style});
  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final tp = TextPainter(text: TextSpan(text: widget.text, style: widget.style), maxLines: 1, textDirection: TextDirection.ltr)..layout();
      if (tp.width <= box.maxWidth) {
        _c?.stop();
        return Text(widget.text, maxLines: 1, softWrap: false, style: widget.style);
      }
      final gap = tp.height * 4;
      final dist = tp.width + gap;
      // vitesse constante (≈ 2,5 hauteurs de texte par seconde), comme un afficheur à LED
      final ms = (dist / (tp.height * 2.5) * 1000).round();
      final c = _c ??= AnimationController(vsync: this, duration: Duration(milliseconds: ms));
      if (c.duration!.inMilliseconds != ms) c.duration = Duration(milliseconds: ms);
      if (!c.isAnimating) c.repeat();
      final label = Text(widget.text, maxLines: 1, softWrap: false, style: widget.style);
      return SizedBox(
        width: box.maxWidth,
        height: tp.height,
        child: ClipRect(
          child: AnimatedBuilder(
            animation: c,
            builder: (_, child) => Transform.translate(offset: Offset(-c.value * dist, 0), child: child),
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: double.infinity,
              child: Row(mainAxisSize: MainAxisSize.min, children: [label, SizedBox(width: gap), label, SizedBox(width: gap)]),
            ),
          ),
        ),
      );
    });
  }
}

class _Scanlines extends CustomPainter {
  final double dark;
  _Scanlines(this.dark);
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = Colors.black.withOpacity(dark);
    for (var y = 0.0; y < s.height; y += 3) {
      c.drawRect(Rect.fromLTWH(0, y + 2, s.width, 1), p);
    }
  }

  @override
  bool shouldRepaint(_Scanlines o) => o.dark != dark;
}

/// Une borne d'arcade : image de l'habillage, pseudo sur le fronton, écran avec
/// avatar / score / PLAYING ou OFFLINE en alternance avec le mini-jeu de la borne
/// et son record (mode démo, 3 s chacun), 🎁 et badge 1P.
class ArcadeCabinet extends StatefulWidget {
  final FloorData d;
  final double width;
  final VoidCallback? onTap, onGift;
  final bool showName; // pseudo sur le fronton
  final bool game; // écran du mini-jeu en permanence (page de la borne, Ma borne)
  const ArcadeCabinet({super.key, required this.d, required this.width, this.onTap, this.onGift, this.showName = true, this.game = false});

  @override
  State<ArcadeCabinet> createState() => _ArcadeCabinetState();
}

/// Effets de lumière (bornes en ligne seulement) : une seule animation de 6 s par borne,
/// décalée selon le joueur pour que la salle ne clignote pas en même temps.
///  · halo de la couleur de l'habillage autour de la borne · fronton rétroéclairé qui respire
///  · écran qui pulse + reflet qui balaie la vitre · lumière de l'écran sur le panneau · lueur au sol
class _ArcadeCabinetState extends State<ArcadeCabinet> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6));
  bool _alt = false; // mode démo : moitié du tour sur l'avatar, moitié sur le jeu

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      final a = _c.value >= 0.5;
      if (a != _alt && mounted) setState(() => _alt = a);
    });
    _sync();
  }

  @override
  void didUpdateWidget(covariant ArcadeCabinet old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.d.online) {
      if (!_c.isAnimating) {
        _c.value = (widget.d.pid.hashCode.abs() % 1000) / 1000;
        _c.repeat();
      }
    } else if (_c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Respiration 0 → 1 → 0, deux fois par tour
  double get _breath => 0.5 - 0.5 * math.cos(_c.value * 4 * math.pi);

  /// Position du reflet sur l'écran (-1 = pas de reflet)
  double get _sweep => _c.value < 0.3 ? _c.value / 0.3 : -1;

  Widget _lit(Widget Function(double b) f) =>
      IgnorePointer(child: RepaintBoundary(child: AnimatedBuilder(animation: _c, builder: (_, __) => f(_breath))));

  @override
  Widget build(BuildContext context) {
    final d = widget.d, width = widget.width, onTap = widget.onTap, onGift = widget.onGift, showName = widget.showName;
    final skin = kFloorThemes[d.theme];
    final w = width, h = width / kCabRatio;
    final sr = Rect.fromLTRB(_kScreen.left * w, _kScreen.top * h, _kScreen.right * w, _kScreen.bottom * h);
    final mr = Rect.fromLTRB(_kMarquee.left * w, _kMarquee.top * h, _kMarquee.right * w, _kMarquee.bottom * h);
    final on = d.online;
    final gifted = kGiftedToday.contains(d.pid);
    final showGift = onGift != null && !d.me && (Notifs.i.canGift || gifted);
    final tro = parseTrophyShow(d.trophies).whereType<(String, int)>().toList();
    final g = (w / 110).clamp(0.6, 2.2); // échelle des textes
    // écran du mini-jeu : toujours sur la page de la borne ; sinon en alternance (en ligne) ou fixe (hors ligne), jamais en duel
    final showGame = d.cabGame != null && !d.busy && (widget.game || !on || !_alt);

    final screen = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.04),
        gradient: on
            ? const RadialGradient(colors: [Color(0xFF4F9AD0), Color(0xFF1C4C78), Color(0xFF0C2440)], stops: [0, 0.6, 1], radius: 0.95)
            : const RadialGradient(colors: [Color(0xFF15151C), Color(0xFF050508)], radius: 0.9),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        if (showGame) Positioned.fill(child: CabScreen(d: d, sr: sr, on: on, start: widget.game)),
        // contenu de l'écran agrandi au maximum : avatar en grand, score et statut sur toute la largeur
        if (!showGame)
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: sr.width * 0.06, vertical: sr.height * 0.05),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                flex: 58,
                child: Opacity(
                  opacity: on ? 1 : 0.55,
                  child: FittedBox(child: AvatarFloat(d.avatar, size: sr.height * 0.6, on: on)),
                ),
              ),
              Expanded(
                flex: 22,
                child: FittedBox(child: Text('${d.score}', style: pixelStyle(size: 20, color: on ? kGold : const Color(0xFF8A7A50), shadow: false))),
              ),
              SizedBox(height: sr.height * 0.03),
              Expanded(
                flex: 15,
                child: FittedBox(
                  child: on
                      ? (d.busy
                          ? _Blink(child: Text('IN GAME', style: pixelStyle(size: 20, color: const Color(0xFFFFB347), shadow: false)))
                          : _Blink(child: Text(d.me ? '1P READY' : 'PLAYING', style: pixelStyle(size: 20, color: const Color(0xFF7DFFB0), shadow: false))))
                      : Text('OFFLINE', style: pixelStyle(size: 20, color: const Color(0xFFFF5A6A), shadow: false)),
                ),
              ),
            ]),
          ),
        ),
        Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Scanlines(on ? 0.12 : 0.22)))),
        // reflet qui balaie la vitre
        if (on)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, __) {
                    final x = _sweep;
                    if (x < 0) return const SizedBox.shrink();
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(-1.0 + x * 2.6 - 0.5, -1),
                          end: Alignment(-1.0 + x * 2.6 + 0.5, 1),
                          colors: [Colors.white.withOpacity(0), Colors.white.withOpacity(0.16), Colors.white.withOpacity(0)],
                          stops: const [0.35, 0.5, 0.65],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
      ]),
    );

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(clipBehavior: Clip.none, children: [
          // halo de la couleur de l'habillage autour de la borne
          if (on)
            Positioned(
              left: w * 0.12,
              right: w * 0.12,
              top: h * 0.06,
              bottom: h * 0.08,
              child: _lit((b) => DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(w * 0.2),
                      boxShadow: [BoxShadow(color: skin.glow.withOpacity(0.18 + 0.17 * b), blurRadius: w * 0.22, spreadRadius: w * 0.03)],
                    ),
                  )),
            ),
          // lueur au sol
          if (on)
            Positioned(
              left: w * 0.1,
              right: w * 0.1,
              bottom: -h * 0.02,
              height: h * 0.05,
              child: _lit((b) => DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(h),
                      boxShadow: [BoxShadow(color: skin.glow.withOpacity(0.4 + 0.3 * b), blurRadius: w * (0.13 + 0.05 * b), spreadRadius: w * 0.02)],
                    ),
                  )),
            ),
          Positioned.fill(child: Image.asset(skin.asset, fit: BoxFit.fill, filterQuality: FilterQuality.medium)),
          // fronton rétroéclairé qui respire
          if (on)
            Positioned.fromRect(
              rect: mr,
              child: _lit((b) => DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(w * 0.03),
                      gradient: RadialGradient(
                        radius: 1.2,
                        colors: [skin.glow.withOpacity(0.10 + 0.16 * b), skin.glow.withOpacity(0)],
                      ),
                    ),
                  )),
            ),
          // lumière de l'écran qui tombe sur le panneau de commandes
          if (on)
            Positioned(
              left: sr.left - w * 0.03,
              width: sr.width + w * 0.06,
              top: sr.bottom,
              height: h * 0.14,
              child: _lit((b) => DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [const Color(0xFF6FE8FF).withOpacity(0.10 + 0.08 * b), const Color(0xFF6FE8FF).withOpacity(0)],
                      ),
                    ),
                  )),
            ),
          // l'écran éclaire autour de lui (lueur qui déborde sur le cadre)
          if (on)
            Positioned.fromRect(
              rect: sr,
              child: _lit((b) => DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(w * 0.04),
                      boxShadow: [BoxShadow(color: const Color(0xFF6FE8FF).withOpacity(0.35 + 0.3 * b), blurRadius: w * (0.10 + 0.05 * b), spreadRadius: w * 0.01)],
                    ),
                  )),
            ),
          Positioned.fromRect(rect: sr, child: screen),
          // vitrine de trophées sous l'écran
          if (tro.isNotEmpty)
            Positioned(
              left: sr.left,
              width: sr.width,
              top: sr.bottom + h * 0.012,
              height: h * 0.075,
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: w * 0.02, vertical: h * 0.006),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(w * 0.03)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final x in tro) Padding(padding: EdgeInsets.symmetric(horizontal: w * 0.01), child: TrophyMedal(x.$1, x.$2, size: h * 0.06)),
                  ]),
                ),
              ),
            ),
          if (showName)
            Positioned.fromRect(
              rect: mr,
              child: Center(
                child: Container(
                  constraints: BoxConstraints(maxWidth: mr.width * 0.94),
                  padding: EdgeInsets.symmetric(horizontal: w * 0.03, vertical: h * 0.006),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.62), borderRadius: BorderRadius.circular(w * 0.03)),
                  child: MarqueeText(d.name.toUpperCase(),
                      style: pixelStyle(size: 7 * g, color: Colors.white, shadow: false).copyWith(shadows: [Shadow(color: skin.glow, blurRadius: 6)])),
                ),
              ),
            ),
          if (d.me)
            Positioned(
              left: -w * 0.04,
              top: -h * 0.015,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 5 * g, vertical: 3 * g),
                decoration: BoxDecoration(
                  color: const Color(0xFF7DFFB0),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: const [BoxShadow(color: Color(0xFF7DFFB0), blurRadius: 8)],
                ),
                child: Text('1P', style: pixelStyle(size: 7 * g, color: Colors.black, shadow: false)),
              ),
            ),
          if (showGift)
            Positioned(
              right: -w * 0.05,
              top: h * 0.2,
              child: GestureDetector(
                onTap: gifted ? null : onGift,
                child: Container(
                  width: 28 * g.clamp(0.9, 1.4),
                  height: 28 * g.clamp(0.9, 1.4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: gifted ? const Color(0xFF444450) : const Color(0xFFFF3DF0),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: gifted ? null : const [BoxShadow(color: Color(0xFFFF3DF0), blurRadius: 10)],
                  ),
                  child: gifted
                      ? const Icon(Icons.check, size: 15, color: Colors.white70)
                      : Icon(Icons.card_giftcard, size: 15 * g.clamp(0.9, 1.4), color: Colors.white),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Étiquette sous une borne : rang, score, collection, dernière connexion
const kTagH = 62.0;

class CabinetTag extends StatelessWidget {
  final FloorData d;
  const CabinetTag({super.key, required this.d});
  @override
  Widget build(BuildContext context) {
    final r = d.rank;
    final status = d.me ? t('toi', 'you') : d.online ? t('● en ligne', '● online') : lastSeenShort(d.seenAt);
    return SizedBox(
      height: kTagH,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        FittedBox(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (r != null)
              Text(r <= 3 ? const ['🥇', '🥈', '🥉'][r - 1] : '#$r ',
                  style: r <= 3 ? const TextStyle(fontSize: 13) : pixelStyle(size: 9, color: kGold, shadow: false)),
            Text(' ${d.score} pts', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFFF3EAFF))),
          ]),
        ),
        FittedBox(
          child: Text('${pctOf(d.cards)} · ${t('${d.cards} cartes', '${d.cards} cards')}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF9FE0C4))),
        ),
        FittedBox(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('🪙 ${d.coins}   ', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFFFD166))),
            const PixelIcon(size: 10),
            Text(' ${d.pixels}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFFFD166))),
          ]),
        ),
        if (status.isNotEmpty)
          FittedBox(
            child: Text(status,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: d.online && !d.me ? const Color(0xFF7DFFB0) : Colors.white54)),
          ),
      ]),
    );
  }
}

// ─── Décor de la salle ────────────────────────────────────────────────────
const kSignH = 78.0;

/// Enseigne néon « PIXEL ARCADE »
class ArcadeSign extends StatelessWidget {
  final bool ranked;
  const ArcadeSign({super.key, this.ranked = true});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: kSignH,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          FittedBox(
            child: Text('PIXEL ARCADE',
                style: pixelStyle(size: 19, color: Colors.white, shadow: false).copyWith(shadows: const [
                  Shadow(color: Colors.white, blurRadius: 4),
                  Shadow(color: Color(0xFFFF3DF0), blurRadius: 12),
                  Shadow(color: Color(0xFFFF3DF0), blurRadius: 26),
                ])),
          ),
          const SizedBox(height: 8),
          Text(ranked ? t('HIGH SCORES · 7 DERNIERS JOURS', 'HIGH SCORES · LAST 7 DAYS') : t('RÉSULTATS', 'RESULTS'),
              style: pixelStyle(size: 7, color: const Color(0xFF28E0FF), shadow: false)
                  .copyWith(shadows: const [Shadow(color: Color(0xFF28E0FF), blurRadius: 8)])),
        ]),
      );
}

/// Marche du podium sous une borne
class PodiumStep extends StatelessWidget {
  final int place;
  final double height;
  const PodiumStep({super.key, required this.place, required this.height});
  @override
  Widget build(BuildContext context) {
    const c = [Color(0xFFFFD166), Color(0xFFC9D4E0), Color(0xFFD0884A)];
    return Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(c[place - 1], Colors.white, 0.35)!, c[place - 1]]),
      ),
      child: Text('$place', style: pixelStyle(size: 14, color: Colors.black87, shadow: false)),
    );
  }
}

/// Faisceau de projecteur au-dessus du n°1 (cône flou qui s'efface vers le bas)
class ArcadeSpotlight extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    c.clipRect(Offset.zero & s);
    final beam = Path()
      ..moveTo(s.width * 0.42, 0)
      ..lineTo(s.width * 0.58, 0)
      ..lineTo(s.width * 0.85, s.height)
      ..lineTo(s.width * 0.15, s.height)
      ..close();
    c.drawPath(
      beam,
      Paint()
        ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x55FFD166), Color(0x00FFD166)])
            .createShader(Offset.zero & s)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.width * 0.05),
    );
  }

  @override
  bool shouldRepaint(ArcadeSpotlight o) => false;
}

/// Allée entre deux rangées
const kAisleH = 26.0;

class ArcadeAisle extends StatelessWidget {
  final String label;
  const ArcadeAisle(this.label, {super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: kAisleH,
        child: Row(children: [
          const Expanded(child: Divider(color: Color(0xFF3A2A6A), thickness: 2)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(label, style: pixelStyle(size: 7, color: const Color(0xFF9B8FC0), shadow: false))),
          const Expanded(child: Divider(color: Color(0xFF3A2A6A), thickness: 2)),
        ]),
      );
}

/// Comptoir de la salle : cadeaux reçus, recherche d'un joueur
class ArcadeCounter extends StatelessWidget {
  final int gifts;
  final VoidCallback onGifts, onSearch;
  const ArcadeCounter({super.key, required this.gifts, required this.onGifts, required this.onSearch});
  @override
  Widget build(BuildContext context) {
    Widget btn(String label, List<Color> c, Color fg, VoidCallback onTap, {int badge = 0}) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black, width: 2),
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: c),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(label, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: fg)),
                if (badge > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 5),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: const Color(0xFFE33333), borderRadius: BorderRadius.circular(10)),
                    child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                  ),
              ]),
            ),
          ),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 24, 0, 30),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6A4A2A), width: 3),
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3A2412), Color(0xFF24160A)]),
      ),
      child: Column(children: [
        Text(t('★ COMPTOIR ★', '★ COUNTER ★'), style: pixelStyle(size: 10, color: kGold, shadow: false)),
        const SizedBox(height: 10),
        Row(children: [
          btn(t('🎁 Cadeaux', '🎁 Gifts'), const [Color(0xFFFFE39A), Color(0xFFE0A93A)], const Color(0xFF3A2412), onGifts, badge: gifts),
          const SizedBox(width: 8),
          btn(t('🔍 Chercher', '🔍 Search'), const [Color(0xFFBDE9FF), Color(0xFF4AA8D8)], const Color(0xFF06243A), onSearch),
        ]),
      ]),
    );
  }
}

// ─── Choix de l'habillage de ma borne ─────────────────────────────────────
class FloorThemePage extends StatefulWidget {
  const FloorThemePage({super.key});
  @override
  State<FloorThemePage> createState() => _FloorThemePageState();
}

class _FloorThemePageState extends State<FloorThemePage> {
  late int sel = floorThemeOf(Game.i.house, Game.i.pid);
  bool busy = false;
  String? cabGame = CabBoard.of(Game.i.pid)?['game'] as String?; // jeu de ma borne (aperçu)

  Future<void> _apply() async {
    setState(() => busy = true);
    try {
      await RcServer.setHouse('$sel');
      Game.i.house = '$sel';
      toast(t('Habillage « ${kFloorThemes[sel].fr} » appliqué à ta borne', '« ${kFloorThemes[sel].en} » skin applied to your cabinet'));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      toast(errText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final g = Game.i;
    final th = kFloorThemes[sel];
    final ok = g.cards >= th.need;
    final current = floorThemeOf(g.house, g.pid);
    final unlocked = kFloorThemes.where((x) => g.cards >= x.need).length;
    final cab = CabBoard.of(g.pid);
    final me = FloorData(
        pid: g.pid, name: g.name, avatar: g.avatar, score: g.score, cards: g.cards, coins: g.coins, pixels: g.pixels, theme: sel, online: true, me: true,
        cabGame: cabGame,
        cabRec: cab?['game'] == cabGame ? (cab?['rec'] as num?)?.toInt() : null,
        cabRecName: cab?['game'] == cabGame ? (cab?['rec_name'] as String?) : null);
    return Scaffold(
      appBar: AppBar(title: Text(t('Ma borne : jeu et habillage', 'My cabinet: game and skin'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
        Center(child: ArcadeCabinet(d: me, width: 150, game: cabGame != null)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white12)),
          child: MyCabGamePicker(onChanged: (x) {
            if (mounted && x != cabGame) setState(() => cabGame = x);
          }),
        ),
        const SizedBox(height: 14),
        Text('🎨 ${t('Habillage', 'Skin')}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800), minimumSize: const Size.fromHeight(46)),
          onPressed: busy || !ok || sel == current ? null : _apply,
          child: Text(
            !ok
                ? t('Se débloque à ${th.need} cartes (encore ${th.need - g.cards})', 'Unlocks at ${th.need} cards (${th.need - g.cards} to go)')
                : sel == current
                    ? t('Habillage actuel', 'Current skin')
                    : t('Choisir « ${th.fr} »', 'Pick « ${th.en} »'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 14),
        Text(t('$unlocked / ${kFloorThemes.length} débloqués · tu as ${g.cards} cartes (${pctOf(g.cards)})',
                '$unlocked / ${kFloorThemes.length} unlocked · you have ${g.cards} cards (${pctOf(g.cards)})'),
            style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, box) {
          final cols = box.maxWidth > 560 ? 6 : 4;
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 8,
            childAspectRatio: 0.5,
            children: [for (var i = 0; i < kFloorThemes.length; i++) _swatch(i, g.cards >= kFloorThemes[i].need)],
          );
        }),
      ]),
    );
  }

  Widget _swatch(int i, bool ok) {
    final th = kFloorThemes[i];
    return GestureDetector(
      onTap: () => setState(() => sel = i),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1030),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: sel == i ? kGold : Colors.transparent, width: 2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              Image.asset(th.asset, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
              if (!ok)
                Container(
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(6)),
                  child: const Icon(Icons.lock, color: Colors.white70, size: 20),
                ),
            ]),
          ),
          const SizedBox(height: 4),
          Text(th.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFFFF3D6))),
          Text(th.need == 0 ? t('offert', 'free') : t('${th.need} cartes', '${th.need} cards'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: ok ? const Color(0xFF9FE0C4) : const Color(0xFFFFD166))),
        ]),
      ),
    );
  }
}
