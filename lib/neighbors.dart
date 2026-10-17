import 'package:flutter/material.dart';

import 'audio.dart';
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
  String? elevator; // étage où se trouve l'ascenseur (pid)
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

  /// Fait défiler l'immeuble jusqu'à mon étage (l'ascenseur y va aussi)
  void goMe({bool animate = true}) {
    final floors = _floors;
    final i = floors.indexWhere((f) => f.me);
    if (i < 0 || !scroll.hasClients) return;
    setState(() => elevator = Game.i.pid);
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
    setState(() => elevator = f.pid);
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
              for (final (icon, label, onTap) in <(IconData, String, VoidCallback)>[
                (Icons.my_location, t('Mon étage', 'My floor'), () => goMe()),
                (Icons.format_paint, t('Mon thème', 'My theme'), () => _editTheme()),
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
                      ? t('Encore ${Notifs.i.giftsLeft} paquet(s) à offrir aujourd\'hui : touche 🎁 sur un étage',
                          '${Notifs.i.giftsLeft} pack(s) left to give today: tap 🎁 on a floor')
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

  Widget _tower() {
    if (error != null) {
      return Center(child: TextButton(onPressed: load, child: Text('$error\n${t('Réessayer', 'Retry')}', textAlign: TextAlign.center)));
    }
    if (rows == null) return const Center(child: CircularProgressIndicator(color: kGold));
    final floors = _floors;
    final ranked = query.trim().isEmpty;
    final n = floors.length;
    final lift = elevator ?? Game.i.pid;
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
            elevator: f.pid == lift,
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
