import 'package:flutter/material.dart';

import 'audio.dart';
import 'cab_games.dart';
import 'connect4.dart';
import 'duel_watch.dart';
import 'game.dart';
import 'packs.dart';
import 'arcade.dart';
import 'live_events.dart';
import 'missing.dart';
import 'main.dart';
import 'notifs.dart';
import 'profile.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Voisinage : la salle « Pixel Arcade », une borne par joueur classée par score
// (habillage au choix). Toucher une borne : profil et album du joueur ;
// 🎁 : offrir un paquet. Ma borne, mon habillage et mon profil en haut.
// ═══════════════════════════════════════════════════════════════════════════

/// Offre le paquet du jour à un joueur (avec confirmation). Vrai si offert.
Future<bool> giftPack(BuildContext context, String pid, String name) async {
  if (!Notifs.i.canGift) {
    toast(t('Tu as déjà offert tes 3 paquets aujourd\'hui, reviens demain !', 'You already gave your 3 packs today, come back tomorrow!'));
    return false;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('Offrir un paquet ?', 'Give a pack?')),
      content: Text(t('$name recevra un paquet de 5 cartes à ouvrir. C\'est gratuit pour toi : 3 paquets par jour, un par joueur (il t\'en reste ${Notifs.i.giftsLeft}).',
          '$name will receive a 5-card pack to open. It\'s free for you: 3 packs a day, one per player (${Notifs.i.giftsLeft} left).')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Annuler', 'Cancel'))),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.card_giftcard),
          label: Text(t('Offrir', 'Give')),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await RcServer.gift(pid);
    kGiftedToday.add(pid);
    RcAudio.sfx('powerup');
    toast(t('🎁 Paquet offert à $name !', '🎁 Pack given to $name!'));
    await Notifs.i.refresh();
    return true;
  } catch (e) {
    toast(errText(e));
    Notifs.i.refresh();
    return false;
  }
}

class NeighborsScreen extends StatefulWidget {
  const NeighborsScreen({super.key});
  @override
  State<NeighborsScreen> createState() => NeighborsScreenState();
}

/// Voisinage en salle d'arcade : une borne par joueur (classement), podium pour les 3 premiers.
class NeighborsScreenState extends State<NeighborsScreen> {
  static NeighborsScreenState? current;
  static String? pendingPid; // borne à montrer dès que la salle est chargée (liste « En ligne » du menu)
  List<Map<String, dynamic>>? rows;
  Map<String, dynamic>? mine; // ma borne si je ne suis pas dans les 100 premiers
  String query = '';
  bool searching = false;
  String? error;
  final scroll = ScrollController();
  bool _jumped = false;

  @override
  void initState() {
    super.initState();
    current = this;
    load();
  }

  @override
  void dispose() {
    if (current == this) current = null;
    scroll.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final q = query.trim();
      final cab = CabBoard.load(); // jeu + record de chaque borne, en même temps
      final r = q.isEmpty ? await RcServer.board() : await RcServer.find(q);
      final me = r.where((p) => p['pid'] == Game.i.pid).firstOrNull;
      if (me != null) {
        Game.i.house = me['house'] as String? ?? Game.i.house;
        mine = null;
      } else if (q.isEmpty) {
        mine = await RcServer.myFloor().catchError((_) => null);
        if (mine != null) Game.i.house = mine!['house'] as String? ?? Game.i.house;
      }
      await cab;
      if (mounted) {
        setState(() {
          rows = r;
          error = null;
        });
        if (!_jumped && q.isEmpty) {
          _jumped = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final p = pendingPid;
            pendingPid = null;
            p != null ? goTo(p) : goMe(animate: false);
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = errText(e));
    }
  }

  List<FloorData> get _floors {
    final ranked = query.trim().isEmpty;
    final list = [for (var i = 0; i < (rows ?? const []).length; i++) FloorData.of(rows![i], rank: ranked ? i + 1 : null)];
    if (ranked && mine != null && !list.any((f) => f.me)) list.add(FloorData.of(mine!));
    return list;
  }

  /// Fait défiler la salle jusqu'à ma borne
  void goMe({bool animate = true}) => goTo(Game.i.pid, animate: animate);

  // géométrie de la salle (calculée au rendu) pour retrouver une borne
  double _podiumH = 0, _rowH = 0;

  /// Rangées de 3 après le podium : les 6 suivants par allée
  static const _cols = 3, _rowsPerAisle = 2;

  /// Fait défiler la salle jusqu'à la borne d'un joueur
  void goTo(String pid, {bool animate = true}) {
    final floors = _floors;
    final i = floors.indexWhere((f) => f.pid == pid);
    if (i < 0 || !scroll.hasClients || _rowH == 0) return;
    final podium = _hasPodium(floors);
    double y;
    if (podium && i < 3) {
      y = kSignH;
    } else {
      final row = (i - (podium ? 3 : 0)) ~/ _cols;
      y = kSignH + _podiumH + row * _rowH + (row ~/ _rowsPerAisle + 1) * kAisleH;
    }
    y = (y - scroll.position.viewportDimension / 4).clamp(0.0, scroll.position.maxScrollExtent);
    if (animate) {
      scroll.animateTo(y, duration: const Duration(milliseconds: 700), curve: Curves.easeInOutCubic);
    } else {
      scroll.jumpTo(y);
    }
  }

  Future<void> _editTheme() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const FloorThemePage()));
    if (ok == true && mounted) setState(() {});
  }

  void _open(FloorData f) {
    if (f.busy) {
      // borne « IN GAME » : regarder sa partie ou voir son profil
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: const Color(0xFF12173F),
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Text('👁', style: TextStyle(fontSize: 22)),
              title: Text(t('Regarder sa partie en direct', 'Watch their live game'), style: const TextStyle(fontWeight: FontWeight.w900)),
              onTap: () {
                Navigator.pop(ctx);
                watchPlayer(context, f.pid);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: Text(t('Voir le profil de ${f.name}', 'See ${f.name}\'s profile')),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerProfilePage(pid: f.pid)));
              },
            ),
          ]),
        ),
      );
      return;
    }
    // borne jouable : page de la borne (jouer, records, profil)
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CabinetPage(f: f)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Game.i, Notifs.i]),
      builder: (context, _) {
        return Column(children: [
          TabHeader(t('Voisinage', 'Neighbors'), icon: 'neighbors'),
          // raccourcis sous le titre (le titre garde toute sa taille)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Row(children: [
              _onlineButton(),
              const SizedBox(width: 6),
              for (final (icon, label, onTap) in <(IconData, String, VoidCallback)>[
                (Icons.my_location, t('Ma borne', 'My cabinet'), () => goMe()),
                (Icons.tune, t('Jeu & style', 'Game & style'), () => _editTheme()),
                (Icons.person, t('Profil', 'Profile'), () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyProfilePage()))),
              ]) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.black.withOpacity(0.25),
                    ),
                    onPressed: onTap,
                    icon: Icon(icon, size: 16),
                    label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                ),
                if (icon != Icons.person) const SizedBox(width: 6),
              ],
            ]),
          ),
          // mes cartes manquantes chez les voisins
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  side: const BorderSide(color: kGold),
                  foregroundColor: kGold,
                  backgroundColor: Colors.black.withOpacity(0.25),
                ),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MissingFinderPage())),
                icon: const Icon(Icons.travel_explore, size: 18),
                label: Text(t('Trouver mes cartes manquantes chez les voisins', 'Find my missing cards at neighbors'),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
          // cadeau du jour
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
            child: Row(children: [
              Icon(Icons.card_giftcard, size: 18, color: Notifs.i.canGift ? kGold : Colors.white38),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  Notifs.i.canGift
                      ? t('Encore ${Notifs.i.giftsLeft} paquet(s) à offrir aujourd\'hui : touche 🎁 sur une borne',
                          '${Notifs.i.giftsLeft} pack(s) left to give today: tap 🎁 on a cabinet')
                      : t('3 paquets offerts aujourd\'hui · reviens demain', '3 packs given today · come back tomorrow'),
                  style: TextStyle(color: Notifs.i.canGift ? kGold : Colors.white38, fontSize: 12),
                ),
              ),
            ]),
          ),
          if (searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        searching = false;
                        query = '';
                      });
                      load();
                    },
                  ),
                  hintText: t('Chercher un voisin', 'Search a neighbor'),
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0x33000000),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                onChanged: (v) {
                  query = v;
                  load();
                },
              ),
            ),
          Expanded(child: _room()),
        ]);
      },
    );
  }

  /// « 🟢 3 en ligne » : la liste des joueurs connectés (défier, aller à leur borne)
  Widget _onlineButton() {
    final on = _floors.where((f) => f.online && !f.me).toList();
    const teal = Color(0xFF5DCAA5);
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        visualDensity: VisualDensity.compact,
        side: const BorderSide(color: teal, width: 1.5),
        backgroundColor: teal.withOpacity(0.14),
        foregroundColor: const Color(0xFF9FE0C4),
      ),
      onPressed: () => _showOnline(on),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: teal, boxShadow: [BoxShadow(color: teal, blurRadius: 6)])),
        const SizedBox(width: 6),
        Text('${on.length}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  void _showOnline(List<FloorData> on) => _onlineSheet(context, on, goTo);

  bool _hasPodium(List<FloorData> floors) => query.trim().isEmpty && floors.isNotEmpty;

  Widget _room() {
    if (error != null) {
      return Center(child: TextButton(onPressed: load, child: Text('$error\n${t('Réessayer', 'Retry')}', textAlign: TextAlign.center)));
    }
    if (rows == null) return const Center(child: CircularProgressIndicator(color: kGold));
    final floors = _floors;
    final podium = _hasPodium(floors);
    final top = podium ? floors.take(3).toList() : <FloorData>[];
    final rest = podium ? floors.skip(3).toList() : floors;
    final nRows = (rest.length + _cols - 1) ~/ _cols;
    void open(FloorData f) => _open(f);
    VoidCallback? gift(FloorData f) => f.me ? null : () => giftPack(context, f.pid, f.name).then((_) {
          if (mounted) setState(() {});
        });

    return LayoutBuilder(builder: (context, box) {
      const pad = 14.0, gap = 12.0;
      final cw = (box.maxWidth > 480 ? 480.0 : box.maxWidth) - 2 * pad;
      final cellW = (cw - gap * (_cols - 1)) / _cols;
      _rowH = cellW / kCabRatio + kTagH + 16;
      // podium : le n°1 au centre, plus grand
      final bigW = cw * 0.36, sideW = cw * 0.28;
      const steps = [54.0, 38.0, 26.0];
      _podiumH = podium ? bigW / kCabRatio + kTagH + steps[0] + 22 : 0;

      Widget podiumView() {
        Widget slot(int k, double w) {
          if (k >= top.length) return SizedBox(width: w);
          final f = top[k];
          return SizedBox(
            width: w,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ArcadeCabinet(d: f, width: w * 0.92, onTap: () => open(f), onGift: gift(f)),
              CabinetTag(d: f),
              PodiumStep(place: k + 1, height: steps[k]),
            ]),
          );
        }

        return SizedBox(
          height: _podiumH,
          child: Stack(alignment: Alignment.bottomCenter, children: [
            // projecteur sur le n°1
            Positioned(
              top: 0,
              left: cw * 0.15,
              right: cw * 0.15,
              height: _podiumH * 0.75,
              child: IgnorePointer(child: CustomPaint(painter: ArcadeSpotlight())),
            ),
            Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              slot(1, sideW),
              slot(0, bigW),
              slot(2, sideW),
            ]),
          ]),
        );
      }

      Widget rowView(int r) {
        final cells = rest.skip(r * _cols).take(_cols).toList();
        final first = (podium ? 4 : 1) + r * _cols;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          if (r % _rowsPerAisle == 0)
            ArcadeAisle(podium
                ? t('RANGÉE ${r ~/ _rowsPerAisle + 1} · #$first À #${(first + _cols * _rowsPerAisle - 1).clamp(first, floors.length)}',
                    'ROW ${r ~/ _rowsPerAisle + 1} · #$first TO #${(first + _cols * _rowsPerAisle - 1).clamp(first, floors.length)}')
                : t('RANGÉE ${r ~/ _rowsPerAisle + 1}', 'ROW ${r ~/ _rowsPerAisle + 1}')),
          SizedBox(
            height: _rowH,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var k = 0; k < _cols; k++) ...[
                if (k > 0) const SizedBox(width: gap),
                SizedBox(
                  width: cellW,
                  child: k < cells.length
                      ? Column(children: [
                          const SizedBox(height: 8),
                          ArcadeCabinet(d: cells[k], width: cellW, onTap: () => open(cells[k]), onGift: gift(cells[k])),
                          CabinetTag(d: cells[k]),
                        ])
                      : null,
                ),
              ],
            ]),
          ),
        ]);
      }

      final counter = ArcadeCounter(
        gifts: Notifs.i.gifts,
        onGifts: () {
          if (Notifs.i.gifts > 0) {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GiftsPage()));
          } else {
            toast(t('Aucun cadeau pour le moment', 'No gifts right now'));
          }
        },
        onSearch: () => setState(() => searching = true),
      );

      return Stack(children: [
        RefreshIndicator(
          onRefresh: load,
          child: ListView.builder(
            controller: scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: 3 + nRows,
            itemBuilder: (_, i) {
              Widget frame(Widget c) => Center(child: SizedBox(width: cw, child: c));
              if (i == 0) return frame(ArcadeSign(ranked: podium));
              if (i == 1) return podium ? frame(podiumView()) : const SizedBox.shrink();
              if (i == 2 + nRows) return frame(counter);
              return frame(rowView(i - 2));
            },
          ),
        ),
      ]);
    });
  }
}

/// Mon profil (réglages compris), ouvert depuis le Voisinage
class MyProfilePage extends StatelessWidget {
  const MyProfilePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(t('Mon profil', 'My profile')),
        ),
        body: const ProfileScreen(embedded: true),
      );
}

/// Une ligne de la liste « En ligne » : défier (4 en ligne ou Console Wars) ou aller à sa borne
class _OnlineRow extends StatefulWidget {
  final FloorData f;
  final VoidCallback onFloor;
  const _OnlineRow({required this.f, required this.onFloor});
  @override
  State<_OnlineRow> createState() => _OnlineRowState();
}

class _OnlineRowState extends State<_OnlineRow> {
  bool pick = false;

  void _challenge(DuelKind kind) {
    final f = widget.f;
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute(builder: (_) => Connect4Lobby(kind: kind, inviteOnOpen: (f.pid, f.name, f.avatar))));
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.f;
    const rich = true; // parties gratuites : tout le monde peut être défié
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF5DCAA5)),
            child: avatarWidget(f.avatar, size: 36),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              f.busy
                  ? Text(t('⚔ En partie', '⚔ In a game'), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFFFFB347)))
                  : Text(
                      rich
                          ? t('${f.rank == null ? '' : '#${f.rank} · '}${f.score} pts', '${f.rank == null ? '' : '#${f.rank} · '}${f.score} pts')
                          : t('Moins de 50 pièces : ne peut pas être défié', 'Under 50 coins: can\'t be challenged'),
                      style: const TextStyle(fontSize: 11.5, color: Colors.white60)),
            ]),
          ),
          f.busy
              ? FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7B3DFF), foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
                  onPressed: () {
                    final nav = Navigator.of(context);
                    final ctx = HomeShellState.current?.context ?? context;
                    nav.pop();
                    watchPlayer(ctx, f.pid);
                  },
                  child: Text(t('👁 Regarder', '👁 Watch'), style: const TextStyle(fontWeight: FontWeight.w900)),
                )
              : FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800), visualDensity: VisualDensity.compact),
                  onPressed: rich ? () => setState(() => pick = !pick) : null,
                  child: Text(t('⚔ Défier', '⚔ Challenge'), style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
          const SizedBox(width: 6),
          OutlinedButton(
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: widget.onFloor,
            child: Text(t('Borne', 'Cabinet')),
          ),
        ]),
        if (pick)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 48),
            child: Row(children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC3202E), foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
                  onPressed: () => _challenge(kC4Duel),
                  child: Text(t('🔴 4 en ligne', '🔴 Connect 4'), style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1C7ED6), foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
                  onPressed: () => _challenge(kBsDuel),
                  child: const Text('🚢 Console Wars', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// Joueurs en ligne (gardés 60 s pour ne pas recharger la salle à chaque ouverture du menu)
class OnlineNow {
  static DateTime? _at;
  static List<FloorData>? _list;
  static List<FloorData>? get cached => _list;

  static Future<List<FloorData>> get({bool force = false}) async {
    if (!force && _list != null && _at != null && DateTime.now().difference(_at!) < const Duration(seconds: 15)) return _list!;
    final r = await RcServer.board();
    _list = [for (var i = 0; i < r.length; i++) FloorData.of(r[i], rank: i + 1)].where((f) => f.online && !f.me).toList();
    _at = DateTime.now();
    return _list!;
  }
}

/// Liste « En ligne » ouverte depuis le panneau latéral ; « Borne » ouvre le Voisinage à sa borne
Future<void> showOnlinePlayers(BuildContext context) async {
  List<FloorData> on;
  try {
    on = await OnlineNow.get(force: true);
  } catch (e) {
    toast(errText(e));
    return;
  }
  if (!context.mounted) return;
  _onlineSheet(context, on, (pid) {
    final n = NeighborsScreenState.current;
    HomeShellState.current?.goTo(5);
    if (n != null && n.rows != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => n.goTo(pid));
    } else {
      NeighborsScreenState.pendingPid = pid;
    }
  });
}

/// Case « Joueurs en ligne » du panneau latéral (nombre de connectés, liste au toucher)
class OnlineMenuTile extends StatefulWidget {
  final bool compact; // barre latérale étroite (tablette)
  final VoidCallback? beforeOpen; // fermer le menu avant d'ouvrir la liste
  const OnlineMenuTile({super.key, this.compact = false, this.beforeOpen});
  @override
  State<OnlineMenuTile> createState() => _OnlineMenuTileState();
}

class _OnlineMenuTileState extends State<OnlineMenuTile> {
  int? n = OnlineNow.cached?.length;

  @override
  void initState() {
    super.initState();
    // le nombre arrive avec le ping des duels (toutes les 10-20 s) ; la liste complète seulement au départ
    DuelWatch.i.addListener(_ping);
    if (DuelWatch.i.online != null) {
      n = DuelWatch.i.online;
    } else {
      OnlineNow.get().then((l) {
        if (mounted && DuelWatch.i.online == null) setState(() => n = l.length);
      }).catchError((_) {});
    }
  }

  void _ping() {
    final v = DuelWatch.i.online;
    if (v != null && v != n && mounted) setState(() => n = v);
  }

  @override
  void dispose() {
    DuelWatch.i.removeListener(_ping);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF5DCAA5);
    final dot = Container(
        width: 10, height: 10, decoration: const BoxDecoration(shape: BoxShape.circle, color: teal, boxShadow: [BoxShadow(color: teal, blurRadius: 6)]));
    void open() {
      final ctx = HomeShellState.current?.context ?? context;
      widget.beforeOpen?.call();
      showOnlinePlayers(ctx);
    }

    if (widget.compact) {
      return Tooltip(
        message: t('Joueurs en ligne', 'Online players'),
        child: InkWell(
          onTap: open,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                dot,
                const SizedBox(width: 5),
                Text(n == null ? '…' : '$n', style: const TextStyle(fontWeight: FontWeight.w900, color: teal)),
              ]),
              const SizedBox(height: 2),
              Text(t('En ligne', 'Online'), style: const TextStyle(fontSize: 10.5, color: Colors.white60)),
            ]),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Material(
        color: teal.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: open,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: teal.withOpacity(0.6))),
            child: Row(children: [
              dot,
              const SizedBox(width: 10),
              Expanded(child: Text(t('Joueurs en ligne', 'Online players'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5))),
              Text(n == null ? '…' : '$n', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: teal)),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ]),
          ),
        ),
      ),
    );
  }
}

void _onlineSheet(BuildContext context, List<FloorData> on, void Function(String pid) goTo) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF12173F),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _OnlineSheet(on: on, goTo: goTo),
    );
  }

/// Liste « En ligne » qui se met à jour en direct (arrivées, départs, parties commencées / finies)
class _OnlineSheet extends StatefulWidget {
  final List<FloorData> on;
  final void Function(String pid) goTo;
  const _OnlineSheet({required this.on, required this.goTo});
  @override
  State<_OnlineSheet> createState() => _OnlineSheetState();
}

class _OnlineSheetState extends State<_OnlineSheet> {
  late List<FloorData> on = widget.on;

  @override
  void initState() {
    super.initState();
    LiveEvents.online.addListener(_reload);
  }

  @override
  void dispose() {
    LiveEvents.online.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final l = await OnlineNow.get(force: true);
      if (mounted) setState(() => on = l);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext ctx) {
    final goTo = widget.goTo;
    return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 10),
            Text(t('🟢 En ligne maintenant', '🟢 Online now'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 8),
            // duels en direct à regarder
            WatchList(header: (n) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(t('👁 Duels en direct', '👁 Live duels'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFFCDB4FF))),
                )),
            if (on.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(t('Personne d\'autre en ligne pour l\'instant', 'Nobody else online right now'), style: const TextStyle(color: Colors.white54)),
              ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final f in on) _OnlineRow(f: f, onFloor: () {
                  Navigator.pop(ctx);
                  goTo(f.pid);
                }),
              ]),
            ),
            const SizedBox(height: 6),
            Text(t('Connectés il y a moins d\'1 min · « Défier » lance un défi en direct (gratuit, le gagnant gagne 150 pièces)',
                    'Seen less than 1 min ago · « Challenge » sends a live challenge (free, the winner gets 150 coins)'),
                style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
          ]),
        ),
    );
  }
}
