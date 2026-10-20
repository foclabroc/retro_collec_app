import 'dart:async';

import 'package:flutter/material.dart';

import 'catalog.dart';
import 'game.dart';
import 'main.dart';
import 'notifs.dart';
import 'retro_theme.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Voisinage « Pixel Arcade » : chaque joueur a sa borne d'arcade (habillage au
// choix, débloqué au nombre de cartes), rangées par classement : podium pour
// les 3 premiers puis des rangées de 3 bornes. Écran allumé (PLAYING) si le
// joueur est en ligne, GAME OVER sinon. Comptoir en bas : cadeaux, recherche.
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
  final int avatar, score, cards, coins, theme;
  final int? rank;
  final bool online, me;
  final DateTime? seenAt; // dernière connexion
  const FloorData({
    this.seenAt,
    required this.pid,
    required this.name,
    required this.avatar,
    required this.score,
    required this.cards,
    required this.coins,
    required this.theme,
    required this.online,
    required this.me,
    this.rank,
  });

  factory FloorData.of(Map<String, dynamic> p, {int? rank}) {
    final pid = p['pid'] as String? ?? '';
    final me = pid == Game.i.pid;
    return FloorData(
      pid: pid,
      name: p['name'] as String? ?? '?',
      avatar: me ? Game.i.avatar : (p['avatar'] as num? ?? 0).toInt(),
      score: me ? Game.i.score : (p['score'] as num? ?? 0).toInt(),
      cards: me ? Game.i.cards : (p['cards'] as num? ?? 0).toInt(),
      coins: me ? Game.i.coins : (p['coins'] as num? ?? 0).toInt(),
      theme: floorThemeOf(me ? Game.i.house : p['house'] as String?, pid),
      online: me || p['online'] == true,
      me: me,
      seenAt: DateTime.tryParse(p['seen_at']?.toString() ?? '')?.toLocal(),
      rank: rank ?? (p['rank'] as num?)?.toInt(),
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

class _Scanlines extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = Colors.black.withOpacity(0.22);
    for (var y = 0.0; y < s.height; y += 3) {
      c.drawRect(Rect.fromLTWH(0, y + 2, s.width, 1), p);
    }
  }

  @override
  bool shouldRepaint(_Scanlines o) => false;
}

/// Une borne d'arcade : image de l'habillage, pseudo sur le fronton, écran avec
/// avatar / score / PLAYING ou GAME OVER, 🎁 et badge 1P.
class ArcadeCabinet extends StatelessWidget {
  final FloorData d;
  final double width;
  final VoidCallback? onTap, onGift;
  final bool showName; // pseudo sur le fronton
  const ArcadeCabinet({super.key, required this.d, required this.width, this.onTap, this.onGift, this.showName = true});

  @override
  Widget build(BuildContext context) {
    final skin = kFloorThemes[d.theme];
    final w = width, h = width / kCabRatio;
    final sr = Rect.fromLTRB(_kScreen.left * w, _kScreen.top * h, _kScreen.right * w, _kScreen.bottom * h);
    final mr = Rect.fromLTRB(_kMarquee.left * w, _kMarquee.top * h, _kMarquee.right * w, _kMarquee.bottom * h);
    final on = d.online;
    final gifted = kGiftedToday.contains(d.pid);
    final showGift = onGift != null && !d.me && (Notifs.i.canGift || gifted);
    final g = (w / 110).clamp(0.6, 2.2); // échelle des textes

    final screen = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.04),
        gradient: on
            ? const RadialGradient(colors: [Color(0xFF1E4A70), Color(0xFF071526)], radius: 0.9)
            : const RadialGradient(colors: [Color(0xFF15151C), Color(0xFF050508)], radius: 0.9),
        boxShadow: on ? [BoxShadow(color: const Color(0xFF28E0FF).withOpacity(0.35), blurRadius: w * 0.08)] : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.all(w * 0.03),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Opacity(opacity: on ? 1 : 0.55, child: avatarWidget(d.avatar, size: sr.height * 0.46)),
              SizedBox(height: sr.height * 0.04),
              FittedBox(child: Text('${d.score}', style: pixelStyle(size: 8 * g, color: on ? kGold : const Color(0xFF8A7A50), shadow: false))),
              SizedBox(height: sr.height * 0.04),
              if (on)
                _Blink(child: Text(d.me ? '1P READY' : 'PLAYING', style: pixelStyle(size: 5.5 * g, color: const Color(0xFF7DFFB0), shadow: false)))
              else
                Text('GAME OVER', style: pixelStyle(size: 5.5 * g, color: const Color(0xFFFF5A6A), shadow: false)),
            ]),
          ),
        ),
        Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Scanlines()))),
      ]),
    );

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(clipBehavior: Clip.none, children: [
          // lueur au sol quand le joueur est en ligne
          if (on)
            Positioned(
              left: w * 0.1,
              right: w * 0.1,
              bottom: -h * 0.02,
              height: h * 0.05,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(h),
                  boxShadow: [BoxShadow(color: skin.glow.withOpacity(0.55), blurRadius: w * 0.15, spreadRadius: w * 0.02)],
                ),
              ),
            ),
          Positioned.fill(child: Image.asset(skin.asset, fit: BoxFit.fill, filterQuality: FilterQuality.medium)),
          Positioned.fromRect(rect: sr, child: screen),
          if (showName)
            Positioned.fromRect(
              rect: mr,
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: w * 0.04, vertical: h * 0.006),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.62), borderRadius: BorderRadius.circular(w * 0.03)),
                  child: FittedBox(
                    child: Text(d.name.toUpperCase(),
                        maxLines: 1,
                        style: pixelStyle(size: 7 * g, color: Colors.white, shadow: false)
                            .copyWith(shadows: [Shadow(color: skin.glow, blurRadius: 6)])),
                  ),
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
                      : const Text('🎁', style: TextStyle(fontSize: 13)),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Étiquette sous une borne : rang, score, collection, dernière connexion
const kTagH = 46.0;

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

/// Fond de la salle (moquette d'arcade)
class ArcadeCarpet extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF120A26));
    final stripe = Paint()..color = const Color(0xFF170D30);
    for (var x = -s.height; x < s.width; x += 28) {
      c.drawPath(
          Path()
            ..moveTo(x, s.height)
            ..lineTo(x + 14, s.height)
            ..lineTo(x + 14 + s.height, 0)
            ..lineTo(x + s.height, 0)
            ..close(),
          stripe);
    }
    const dots = [Color(0x40FF3DF0), Color(0x4028E0FF), Color(0x40FFD166)];
    var i = 0;
    for (var y = 20.0; y < s.height; y += 60) {
      for (var x = 12.0 + (i.isEven ? 0 : 30); x < s.width; x += 60) {
        c.drawCircle(Offset(x, y), 2.2, Paint()..color = dots[(i + x ~/ 60) % 3]);
      }
      i++;
    }
  }

  @override
  bool shouldRepaint(ArcadeCarpet o) => false;
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
    final me = FloorData(pid: g.pid, name: g.name, avatar: g.avatar, score: g.score, cards: g.cards, coins: g.coins, theme: sel, online: true, me: true);
    return Scaffold(
      appBar: AppBar(title: Text(t('Habillage de ma borne', 'My cabinet skin'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
        Center(child: ArcadeCabinet(d: me, width: 150)),
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
