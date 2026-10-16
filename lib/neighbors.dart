import 'package:flutter/material.dart';

import 'audio.dart';
import 'game.dart';
import 'house.dart';
import 'main.dart';
import 'notifs.dart';
import 'profile.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Voisinage : un quartier de parcelles avec la maison (personnalisable) de
// chaque joueur, classées par score. Toucher une maison : profil et album du
// joueur ; 🎁 : offrir le paquet du jour. Ma parcelle et mes réglages en haut.
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

class NeighborsScreenState extends State<NeighborsScreen> {
  static NeighborsScreenState? current;
  List<Map<String, dynamic>>? rows;
  String query = '';
  String? error;

  @override
  void initState() {
    super.initState();
    current = this;
    load();
  }

  @override
  void dispose() {
    if (current == this) current = null;
    super.dispose();
  }

  bool _houseLoaded = false;

  Future<void> load() async {
    try {
      final q = query.trim();
      final r = q.isEmpty ? await RcServer.board() : await RcServer.find(q);
      if (!_houseLoaded) {
        _houseLoaded = true;
        final me = r.where((p) => p['pid'] == Game.i.pid).firstOrNull;
        if (me != null) {
          Game.i.house = me['house'] as String? ?? '';
        } else {
          RcServer.profile(Game.i.pid).then((p) {
            if (p != null && mounted) setState(() => Game.i.house = p['house'] as String? ?? '');
          }).catchError((_) {});
        }
      }
      if (mounted) {
        setState(() {
          rows = r;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = errText(e));
    }
  }

  Future<void> _editHouse() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => HouseEditorPage(initial: HouseSpec.parse(Game.i.house, seed: Game.i.pid)),
    ));
    if (ok == true) load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Game.i, Notifs.i]),
      builder: (context, _) {
        final g = Game.i;
        return Column(children: [
          TabHeader(t('Voisinage', 'Neighbors')),
          // ma parcelle
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(16), border: Border.all(color: kGold.withOpacity(0.6))),
              child: Row(children: [
                GestureDetector(
                  onTap: _editHouse,
                  child: SizedBox(width: 104, height: 96, child: HouseView(HouseSpec.parse(g.house, seed: g.pid), highlight: true)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      avatarWidget(g.avatar, size: 26),
                      const SizedBox(width: 6),
                      Expanded(child: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                    ]),
                    const SizedBox(height: 2),
                    Text(t('${g.cards} cartes · score ${g.score}', '${g.cards} cards · score ${g.score}'), style: const TextStyle(color: kGold, fontSize: 12)),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: kGold,
                            foregroundColor: const Color(0xFF2A1800),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: _editHouse,
                          icon: const Icon(Icons.format_paint, size: 16),
                          label: Text(t('Ma maison', 'My house'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), visualDensity: VisualDensity.compact),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyProfilePage())),
                          icon: const Icon(Icons.person, size: 16),
                          label: Text(t('Profil', 'Profile'), style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ]),
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
                      ? t('Encore ${Notifs.i.giftsLeft} paquet(s) à offrir aujourd\'hui : touche 🎁 sur une maison',
                          '${Notifs.i.giftsLeft} pack(s) left to give today: tap 🎁 on a house')
                      : t('3 paquets offerts aujourd\'hui · reviens demain', '3 packs given today · come back tomorrow'),
                  style: TextStyle(color: Notifs.i.canGift ? kGold : Colors.white38, fontSize: 12),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
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
          Expanded(child: _grid()),
        ]);
      },
    );
  }

  Widget _grid() {
    if (error != null) {
      return Center(child: TextButton(onPressed: load, child: Text('$error\n${t('Réessayer', 'Retry')}', textAlign: TextAlign.center)));
    }
    if (rows == null) return const Center(child: CircularProgressIndicator(color: kGold));
    if (rows!.isEmpty) return Center(child: Text(t('Aucun voisin', 'No neighbors'), style: const TextStyle(color: Colors.white38)));
    final ranked = query.trim().isEmpty;
    return RefreshIndicator(
      onRefresh: load,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 200, childAspectRatio: 0.82, crossAxisSpacing: 10, mainAxisSpacing: 10),
        itemCount: rows!.length,
        itemBuilder: (_, i) => _plot(rows![i], ranked ? i + 1 : null),
      ),
    );
  }

  Widget _plot(Map<String, dynamic> p, int? rank) {
    final pid = p['pid'] as String;
    final me = pid == Game.i.pid;
    final name = p['name'] as String? ?? '?';
    final spec = HouseSpec.parse(me ? Game.i.house : p['house'] as String?, seed: pid);
    return GestureDetector(
      onTap: me
          ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyProfilePage()))
          : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerProfilePage(pid: pid))),
      child: Column(children: [
        Expanded(
          child: Stack(children: [
            Positioned.fill(child: HouseView(spec, highlight: me)),
            // rang
            if (rank != null)
              Positioned(
                left: 6,
                top: 6,
                child: rank <= 3
                    ? Text(const ['🥇', '🥈', '🥉'][rank - 1], style: const TextStyle(fontSize: 20))
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: kBg.withOpacity(0.67), borderRadius: BorderRadius.circular(8)),
                        child: Text('#$rank', style: const TextStyle(color: kGold, fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
              ),
            // offrir un paquet
            if (!me)
              Positioned(
                right: 2,
                top: 2,
                child: IconButton(
                  tooltip: t('Offrir un paquet', 'Give a pack'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => giftPack(context, pid, name),
                  icon: Opacity(opacity: Notifs.i.canGift ? 1 : 0.35, child: const Text('🎁', style: TextStyle(fontSize: 20))),
                ),
              ),
          ]),
        ),
        // panneau en bois avec le pseudo
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: me ? const Color(0xFF5A3A08) : const Color(0xFF5C3D24),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: me ? kGold : const Color(0xFF2E1D10), width: 1.5),
          ),
          child: Row(children: [
            avatarWidget((p['avatar'] as num? ?? 0).toInt(), size: 22),
            const SizedBox(width: 6),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(me ? t('$name (moi)', '$name (me)') : name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                Text(t('${p['cards']} cartes', '${p['cards']} cards'), style: const TextStyle(color: Color(0xFFF3D9A4), fontSize: 10.5)),
              ]),
            ),
          ]),
        ),
      ]),
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
