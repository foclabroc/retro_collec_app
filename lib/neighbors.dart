import 'package:flutter/material.dart';

import 'audio.dart';
import 'connect4.dart';
import 'game.dart';
import 'packs.dart';
import 'tower.dart';
import 'main.dart';
import 'notifs.dart';
import 'profile.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Voisinage : l'immeuble « Pixel Tower », un étage par joueur classé par score
// (thème de l'étage au choix). Toucher un étage : profil et album du joueur ;
// 🎁 : offrir un paquet. Mon étage, mon thème et mon profil en haut.
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

/// Voisinage en immeuble : un étage par joueur (classement), le n°1 au penthouse.
class NeighborsScreenState extends State<NeighborsScreen> {
  static NeighborsScreenState? current;
  List<Map<String, dynamic>>? rows;
  Map<String, dynamic>? mine; // mon étage si je ne suis pas dans les 100 premiers
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
      final r = q.isEmpty ? await RcServer.board() : await RcServer.find(q);
      final me = r.where((p) => p['pid'] == Game.i.pid).firstOrNull;
      if (me != null) {
        Game.i.house = me['house'] as String? ?? Game.i.house;
        mine = null;
      } else if (q.isEmpty) {
        mine = await RcServer.myFloor().catchError((_) => null);
        if (mine != null) Game.i.house = mine!['house'] as String? ?? Game.i.house;
      }
      if (mounted) {
        setState(() {
          rows = r;
          error = null;
        });
        if (!_jumped && q.isEmpty) {
          _jumped = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => goMe(animate: false));
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

  /// Fait défiler l'immeuble jusqu'à mon étage
  void goMe({bool animate = true}) => goTo(Game.i.pid, animate: animate);

  /// Fait défiler l'immeuble jusqu'à l'étage d'un joueur
  void goTo(String pid, {bool animate = true}) {
    final floors = _floors;
    final i = floors.indexWhere((f) => f.pid == pid);
    if (i < 0 || !scroll.hasClients) return;
    final pent = query.trim().isEmpty && floors.isNotEmpty;
    var y = kRoofH + (i == 0 ? 0 : (pent ? kPentH + kCorniceH : kFloorH + kCorniceH) + (i - 1) * (kFloorH + kCorniceH));
    y = (y - scroll.position.viewportDimension / 3).clamp(0.0, scroll.position.maxScrollExtent);
    if (animate) {
      scroll.animateTo(y, duration: const Duration(milliseconds: 700), curve: Curves.easeInOutCubic);
    } else {
      scroll.jumpTo(y);
    }
  }

  Future<void> _editTheme() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const FloorThemePage()));
    if (ok == true) setState(() {});
  }

  void _open(FloorData f) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => f.me ? const MyProfilePage() : PlayerProfilePage(pid: f.pid)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Game.i, Notifs.i]),
      builder: (context, _) {
        return Column(children: [
          TabHeader(t('Voisinage', 'Neighbors')),
          // raccourcis sous le titre (le titre garde toute sa taille)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Row(children: [
              _onlineButton(),
              const SizedBox(width: 6),
              for (final (icon, label, onTap) in <(IconData, String, VoidCallback)>[
                (Icons.my_location, t('Mon étage', 'My floor'), () => goMe()),
                (Icons.format_paint, t('Thème', 'Theme'), () => _editTheme()),
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
          // cadeau du jour
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
            child: Row(children: [
              Icon(Icons.card_giftcard, size: 18, color: Notifs.i.canGift ? kGold : Colors.white38),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  Notifs.i.canGift
                      ? t('Encore ${Notifs.i.giftsLeft} paquet(s) à offrir aujourd\'hui : « 🎁 Offrir » sur un étage',
                          '${Notifs.i.giftsLeft} pack(s) left to give today: « 🎁 Give » on a floor')
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
          Expanded(child: _tower()),
        ]);
      },
    );
  }

  /// « 🟢 3 en ligne » : la liste des joueurs connectés (défier, aller à leur étage)
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

  void _showOnline(List<FloorData> on) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF12173F),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 10),
            Text(t('🟢 En ligne maintenant', '🟢 Online now'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 8),
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
            Text(t('Connectés il y a moins de 10 min · « Défier » lance un défi en direct (50 pièces chacun)',
                    'Seen less than 10 min ago · « Challenge » sends a live challenge (50 coins each)'),
                style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
          ]),
        ),
      ),
    );
  }

  Widget _tower() {
    if (error != null) {
      return Center(child: TextButton(onPressed: load, child: Text('$error\n${t('Réessayer', 'Retry')}', textAlign: TextAlign.center)));
    }
    if (rows == null) return const Center(child: CircularProgressIndicator(color: kGold));
    final floors = _floors;
    final ranked = query.trim().isEmpty;
    final n = floors.length;
    Widget frame(Widget child, {bool pilasters = true}) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: pilasters
                  ? DecoratedBox(
                      decoration: const BoxDecoration(border: Border.symmetric(vertical: BorderSide(color: Color(0xFFEFE2C3), width: 8))),
                      child: child,
                    )
                  : child,
            ),
          ),
        );
    return RefreshIndicator(
      onRefresh: load,
      child: ListView.builder(
        controller: scroll,
        padding: const EdgeInsets.only(top: 8),
        itemCount: n + 2,
        itemBuilder: (_, i) {
          if (i == 0) return frame(const TowerRoof(), pilasters: false);
          if (i == n + 1) {
            return frame(
              TowerLobby(
                gifts: Notifs.i.gifts,
                onGifts: () {
                  if (Notifs.i.gifts > 0) {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GiftsPage()));
                  } else {
                    toast(t('Aucun cadeau pour le moment', 'No gifts right now'));
                  }
                },
                onSearch: () => setState(() => searching = true),
              ),
            );
          }
          final f = floors[i - 1];
          return frame(TowerFloor(
            d: f,
            level: n - (i - 1),
            penthouse: ranked && i == 1,
            index: i,
            onTap: () => _open(f),
            onGift: f.me ? null : () => giftPack(context, f.pid, f.name),
          ));
        },
      ),
    );
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

/// Une ligne de la liste « En ligne » : défier (4 en ligne ou Console Wars) ou aller à son étage
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
    final rich = f.coins >= kC4Stake;
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
              Text(
                  rich
                      ? t('${f.rank == null ? '' : '#${f.rank} · '}${f.score} pts', '${f.rank == null ? '' : '#${f.rank} · '}${f.score} pts')
                      : t('Moins de 50 pièces : ne peut pas être défié', 'Under 50 coins: can\'t be challenged'),
                  style: const TextStyle(fontSize: 11.5, color: Colors.white60)),
            ]),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800), visualDensity: VisualDensity.compact),
            onPressed: rich ? () => setState(() => pick = !pick) : null,
            child: Text(t('⚔ Défier', '⚔ Challenge'), style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 6),
          OutlinedButton(
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: widget.onFloor,
            child: Text(t('Étage', 'Floor')),
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
