import 'package:flutter/material.dart';

import 'audio.dart';
import 'cards.dart';
import 'catalog.dart';
import 'game.dart';
import 'main.dart';
import 'notifs.dart';
import 'profile.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Voisinage : les autres joueurs (classement, recherche), leur profil et leur
// album, et un paquet à offrir chaque jour. Mon profil et les réglages sont
// accessibles en haut.
// ═══════════════════════════════════════════════════════════════════════════

/// Offre le paquet du jour à un joueur (avec confirmation). Vrai si offert.
Future<bool> giftPack(BuildContext context, String pid, String name) async {
  if (!Notifs.i.canGift) {
    toast(t('Tu as déjà offert un paquet aujourd\'hui, reviens demain !', 'You already gave a pack today, come back tomorrow!'));
    return false;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('Offrir un paquet ?', 'Give a pack?')),
      content: Text(t('$name recevra un paquet de 5 cartes à ouvrir. C\'est gratuit pour toi, mais tu ne peux offrir qu\'un paquet par jour.',
          '$name will receive a 5-card pack to open. It\'s free for you, but you can only give one pack a day.')),
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

  Future<void> load() async {
    try {
      final q = query.trim();
      final r = q.isEmpty ? await RcServer.board() : await RcServer.find(q);
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Game.i, Notifs.i]),
      builder: (context, _) {
        final g = Game.i;
        return Column(children: [
          TabHeader(t('Voisinage', 'Neighbors')),
          // ma carte de joueur → mon profil et réglages
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Material(
              color: kPanel,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyProfilePage())),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: kGold.withOpacity(0.6))),
                  child: Row(children: [
                    avatarWidget(g.avatar, size: 46),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(g.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(t('${g.cards} / ${Catalog.cards.length} cartes · score ${g.score}', '${g.cards} / ${Catalog.cards.length} cards · score ${g.score}'),
                            style: const TextStyle(color: kGold, fontSize: 12)),
                      ]),
                    ),
                    Text(t('Mon profil', 'My profile'), style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    const Icon(Icons.chevron_right, color: Colors.white54),
                  ]),
                ),
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
                      ? t('Tu peux offrir un paquet aujourd\'hui : touche 🎁 à côté d\'un joueur', 'You can give a pack today: tap 🎁 next to a player')
                      : t('Paquet du jour offert · reviens demain', 'Today\'s pack given · come back tomorrow'),
                  style: TextStyle(color: Notifs.i.canGift ? kGold : Colors.white38, fontSize: 12),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: t('Chercher un joueur', 'Search a player'),
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
          Expanded(child: _list()),
        ]);
      },
    );
  }

  Widget _list() {
    if (error != null) {
      return Center(child: TextButton(onPressed: load, child: Text('$error\n${t('Réessayer', 'Retry')}', textAlign: TextAlign.center)));
    }
    if (rows == null) return const Center(child: CircularProgressIndicator(color: kGold));
    if (rows!.isEmpty) return Center(child: Text(t('Aucun joueur', 'No players'), style: const TextStyle(color: Colors.white38)));
    return RefreshIndicator(
      onRefresh: load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
        itemCount: rows!.length,
        itemBuilder: (_, i) {
          final p = rows![i];
          final me = p['pid'] == Game.i.pid;
          final pid = p['pid'] as String;
          final name = p['name'] as String? ?? '?';
          final rank = i + 1;
          final medal = query.trim().isEmpty && rank <= 3 ? const ['🥇', '🥈', '🥉'][rank - 1] : null;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: me ? const Color(0x33EF9F27) : kPanel,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              leading: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: 28,
                  child: Text(medal ?? (query.trim().isEmpty ? '$rank' : ''), textAlign: TextAlign.center,
                      style: const TextStyle(color: kGold, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 6),
                avatarWidget((p['avatar'] as num? ?? 0).toInt()),
              ]),
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(t('${p['cards']} cartes · score ${p['score']}', '${p['cards']} cards · score ${p['score']}'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              trailing: me
                  ? Text(t('Moi', 'Me'), style: const TextStyle(color: kGold, fontWeight: FontWeight.w800))
                  : IconButton(
                      tooltip: t('Offrir un paquet', 'Give a pack'),
                      icon: Opacity(opacity: Notifs.i.canGift ? 1 : 0.3, child: const Text('🎁', style: TextStyle(fontSize: 22))),
                      onPressed: () => giftPack(context, pid, name),
                    ),
              onTap: me
                  ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyProfilePage()))
                  : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerProfilePage(pid: pid))),
            ),
          );
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
