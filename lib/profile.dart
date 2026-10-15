import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'album.dart';
import 'audio.dart';
import 'cards.dart';
import 'catalog.dart';
import 'game.dart';
import 'main.dart';
import 'server.dart';
import 'trades.dart';
import 'update_check.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Profil : le mien (pseudo, avatar, vitrine, statistiques, classement) et
// celui des autres joueurs (vitrine + collection complète consultable)
// ═══════════════════════════════════════════════════════════════════════════

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Map<String, dynamic>>? board;
  (int, int)? rank;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await RcServer.board();
      final r = await RcServer.rank();
      if (mounted) {
        setState(() {
          board = b;
          rank = r;
        });
      }
    } catch (_) {}
  }

  Future<void> _editName() async {
    final ctl = TextEditingController(text: Game.i.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Ton pseudo', 'Your name')),
        content: TextField(controller: ctl, maxLength: 16, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Annuler', 'Cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: Text(t('OK', 'OK'))),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == Game.i.name) return;
    try {
      await Game.i.setProfile(newName: name);
      _load();
    } catch (e) {
      toast(errText(e));
    }
  }

  Future<void> _editAvatar() async {
    final a = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Ton avatar', 'Your avatar')),
        content: Wrap(spacing: 12, runSpacing: 12, children: [
          for (var i = 0; i < kAvatars.length; i++) GestureDetector(onTap: () => Navigator.pop(ctx, i), child: avatarWidget(i, size: 54)),
        ]),
      ),
    );
    if (a == null) return;
    try {
      await Game.i.setProfile(newAvatar: a);
      _load();
    } catch (e) {
      toast(errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Game.i,
      builder: (context, _) {
        final g = Game.i;
        final total = Catalog.cards.length;
        return Column(children: [
          TabHeader(t('Profil', 'Profile'), actions: [
            IconButton(
              tooltip: t('Son', 'Sound'),
              icon: Icon(RcAudio.enabled ? Icons.volume_up : Icons.volume_off),
              onPressed: () => setState(() => RcAudio.enabled = !RcAudio.enabled),
            ),
            IconButton(
              tooltip: t('Musique', 'Music'),
              icon: Icon(RcAudio.musicEnabled ? Icons.music_note : Icons.music_off),
              onPressed: () async {
                await RcAudio.setMusicEnabled(!RcAudio.musicEnabled);
                if (RcAudio.musicEnabled) RcAudio.musicStart(1);
                setState(() {});
              },
            ),
          ]),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await g.sync();
                await _load();
              },
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                Row(children: [
                  GestureDetector(onTap: _editAvatar, child: avatarWidget(g.avatar, size: 64)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      GestureDetector(
                        onTap: _editName,
                        child: Row(children: [
                          Flexible(child: Text(g.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
                          const SizedBox(width: 6),
                          const Icon(Icons.edit, size: 16, color: Colors.white38),
                        ]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        rank == null || rank!.$1 == 0
                            ? t('Score ${g.score}', 'Score ${g.score}')
                            : t('Score ${g.score} · ${rank!.$1}e sur ${rank!.$2}', 'Score ${g.score} · #${rank!.$1} of ${rank!.$2}'),
                        style: const TextStyle(color: kGold),
                      ),
                    ]),
                  ),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  _stat(t('Cartes', 'Cards'), '${g.cards}/$total'),
                  _stat(t('Paquets', 'Packs'), '${g.packs}'),
                  _stat(t('Série', 'Streak'), t('${g.streak} j', '${g.streak} d')),
                ]),
                const SizedBox(height: 18),
                Text(t('Ma vitrine', 'My showcase'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                Text(t('Ajoute une carte depuis sa fiche (Collection → console → carte → Mettre en vitrine)', 'Add a card from its page (Collection → system → card → Add to showcase)'),
                    style: const TextStyle(color: Colors.white38, fontSize: 12)),
                const SizedBox(height: 8),
                _Showcase(g.showcaseItems),
                const SizedBox(height: 18),
                Text(t('Mes séries', 'My sets'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 8),
                for (final s in Catalog.systems) _setRow(s.name, g.ownedIn(s.id), s.count),
                const SizedBox(height: 18),
                Text(t('Classement', 'Leaderboard'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                if (board == null) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: kGold))),
                if (board != null)
                  for (var i = 0; i < board!.length; i++) _boardRow(i + 1, board![i]),
                const SizedBox(height: 18),
                Text(t('Réglages', 'Settings'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(12)),
                  child: Column(children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.screen_rotation),
                      title: Text(t('Inclinaison des cartes (gyroscope)', 'Card tilt (gyroscope)')),
                      subtitle: Text(t('Les cartes bougent quand tu penches le téléphone', 'Cards move when you tilt the phone'),
                          style: const TextStyle(fontSize: 12, color: Colors.white54)),
                      value: Tilt.enabled,
                      activeColor: kGold,
                      onChanged: (v) async {
                        await Tilt.setEnabled(v);
                        setState(() {});
                      },
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    ListTile(
                      leading: const Icon(Icons.key, color: kGold),
                      title: Text(t('Mon code de sauvegarde', 'My backup code')),
                      subtitle: Text(t('Pour retrouver ton profil sur un autre téléphone', 'To get your profile back on another phone'),
                          style: const TextStyle(fontSize: 12, color: Colors.white54)),
                      onTap: _showBackup,
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    ListTile(
                      leading: const Icon(Icons.restore),
                      title: Text(t('Restaurer un profil', 'Restore a profile')),
                      subtitle: Text(t('Entrer un code de sauvegarde', 'Enter a backup code'), style: const TextStyle(fontSize: 12, color: Colors.white54)),
                      onTap: _restore,
                    ),
                  ]),
                ),
                const SizedBox(height: 18),
                Center(
                  child: TextButton(
                    onPressed: () async {
                      final st = context.findAncestorStateOfType<UpdateGateState>();
                      final r = await st?.check(manual: true) ?? 0;
                      if (r == 0) toast(t('L\'appli est à jour (v$kRetroCollecVersion)', 'The app is up to date (v$kRetroCollecVersion)'));
                      if (r == 2) toast(t('Vérification impossible (hors ligne)', 'Could not check (offline)'));
                    },
                    child: Text('Rétro Collec v$kRetroCollecVersion — ${t('vérifier les mises à jour', 'check for updates')}',
                        style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  ),
                ),
              ]),
            ),
          ),
        ]);
      },
    );
  }

  Future<void> _showBackup() async {
    final code = await RcServer.backupCode();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Code de sauvegarde', 'Backup code')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('Note ce code (ou fais une capture d\'écran). Sur un nouveau téléphone : Profil → Restaurer un profil.',
              'Write this code down (or take a screenshot). On a new phone: Profile → Restore a profile.')),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF0A1033), borderRadius: BorderRadius.circular(8), border: Border.all(color: kGold)),
            child: SelectableText(code, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'monospace', fontSize: 15, letterSpacing: 1.2, color: kGold, height: 1.5)),
          ),
          const SizedBox(height: 12),
          Text(t('⚠ Ne le donne à personne : ce code permet de jouer avec ton profil.', '⚠ Never share it: this code gives access to your profile.'),
              style: const TextStyle(color: Color(0xFFF09595), fontSize: 12)),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              toast(t('Code copié', 'Code copied'));
            },
            child: Text(t('Copier', 'Copy')),
          ),
          ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _restore() async {
    final ctl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Restaurer un profil', 'Restore a profile')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(t('Le profil actuel de ce téléphone sera remplacé. Garde d\'abord son code si tu veux pouvoir y revenir.',
              'This phone\'s current profile will be replaced. Keep its code first if you want to come back to it.'),
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: ctl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Annuler', 'Cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: Text(t('Restaurer', 'Restore'))),
        ],
      ),
    );
    if (code == null || code.trim().isEmpty) return;
    try {
      final name = await RcServer.restore(code);
      await Game.i.refresh();
      _load();
      toast(t('Profil « $name » restauré !', 'Profile "$name" restored!'));
    } catch (e) {
      toast(errText(e));
    }
  }

  Widget _stat(String k, String v) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(k, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ),
      );

  Widget _boardRow(int pos, Map<String, dynamic> p) {
    final me = p['pid'] == Game.i.pid;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      tileColor: me ? const Color(0xFF2A1F0C) : null,
      leading: SizedBox(
        width: 72,
        child: Row(children: [
          SizedBox(
            width: 26,
            child: Text('$pos', style: TextStyle(fontWeight: FontWeight.w800, color: pos <= 3 ? kGold : Colors.white54)),
          ),
          avatarWidget((p['avatar'] as num? ?? 0).toInt(), size: 36),
        ]),
      ),
      title: Text(p['name'] as String? ?? '?', style: TextStyle(fontWeight: me ? FontWeight.w800 : FontWeight.w500)),
      subtitle: Text(t('${p['cards']} cartes', '${p['cards']} cards'), style: const TextStyle(fontSize: 12)),
      trailing: Text('${p['score']}', style: const TextStyle(color: kGold, fontWeight: FontWeight.w700)),
      onTap: me ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerProfilePage(pid: p['pid'] as String))),
    );
  }
}

Widget _setRow(String name, int mine, int total) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 120, child: Text(name, style: const TextStyle(fontSize: 13))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: total == 0 ? 0 : mine / total, minHeight: 7, color: mine >= total ? const Color(0xFF5DCAA5) : kGold, backgroundColor: kPanel2),
          ),
        ),
        SizedBox(width: 60, child: Text('$mine/$total', textAlign: TextAlign.right, style: const TextStyle(color: Colors.white54, fontSize: 12))),
      ]),
    );

class _Showcase extends StatelessWidget {
  final List<(String, int)> items;
  final Map<String, List<int>>? owned; // collection affichée (autre joueur) pour ouvrir les fiches
  final String? ownerName;
  const _Showcase(this.items, {this.owned, this.ownerName});

  @override
  Widget build(BuildContext context) {
    final valid = [for (final e in items) if (Catalog.cards[e.$1] != null) e];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 5 / 7,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      children: [
        for (var i = 0; i < 6; i++)
          if (i < valid.length)
            GestureDetector(
              onTap: () => openCardDetail(context, Catalog.cards[valid[i].$1]!, otherOwned: owned, otherName: ownerName),
              child: CardView(card: Catalog.cards[valid[i].$1]!, finish: valid[i].$2),
            )
          else
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12, width: 2),
              ),
              child: const Icon(Icons.star_border, color: Colors.white12),
            ),
      ],
    );
  }
}

// ─── Profil d'un autre joueur ─────────────────────────────────────────────
class PlayerProfilePage extends StatefulWidget {
  final String pid;
  const PlayerProfilePage({super.key, required this.pid});
  @override
  State<PlayerProfilePage> createState() => _PlayerProfilePageState();
}

class _PlayerProfilePageState extends State<PlayerProfilePage> {
  Map<String, dynamic>? p;
  Map<String, List<int>> owned = {};
  String? error;

  @override
  void initState() {
    super.initState();
    RcServer.profile(widget.pid).then((r) {
      if (!mounted) return;
      setState(() {
        p = r;
        owned = parseOwned(r?['owned']);
        if (r == null) error = t('Joueur introuvable', 'Player not found');
      });
    }).catchError((e) {
      if (mounted) setState(() => error = errText(e));
    });
  }

  int _in(String sys) => (Catalog.bySys[sys] ?? const <RcCard>[]).where((c) => (owned[c.id]?.fold<int>(0, (a, b) => a + b) ?? 0) > 0).length;

  @override
  Widget build(BuildContext context) {
    final name = p?['name'] as String? ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: error != null
          ? Center(child: Text(error!, style: const TextStyle(color: Colors.white60)))
          : p == null
              ? const Center(child: CircularProgressIndicator(color: kGold))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Row(children: [
                    avatarWidget((p!['avatar'] as num? ?? 0).toInt(), size: 60),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                        Text(t('Score ${p!['score']} · ${p!['cards']} cartes · ${p!['packs']} paquets', 'Score ${p!['score']} · ${p!['cards']} cards · ${p!['packs']} packs'),
                            style: const TextStyle(color: kGold, fontSize: 13)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.swap_horiz),
                      label: Text(t('Proposer un échange', 'Propose a trade')),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TradeBuilderPage(pid: widget.pid, name: name))),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(t('Vitrine', 'Showcase'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 8),
                  _Showcase(parseItems(p!['showcase'] as String? ?? ''), owned: owned, ownerName: name),
                  const SizedBox(height: 18),
                  Text(t('Séries (touche pour voir l\'album)', 'Sets (tap to view the album)'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 8),
                  for (final s in Catalog.systems)
                    InkWell(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => OtherAlbumPage(sys: s.id, owned: owned, name: name, pid: widget.pid),
                      )),
                      child: _setRow(s.name, _in(s.id), s.count),
                    ),
                ]),
    );
  }
}

/// Album d'un autre joueur pour une console (ses cartes en couleur, les autres en silhouette).
class OtherAlbumPage extends StatelessWidget {
  final String sys, name, pid;
  final Map<String, List<int>> owned;
  const OtherAlbumPage({super.key, required this.sys, required this.owned, required this.name, required this.pid});

  @override
  Widget build(BuildContext context) {
    final list = Catalog.bySys[sys] ?? const <RcCard>[];
    return Scaffold(
      appBar: AppBar(title: Text('$name — ${Catalog.system(sys)?.name ?? sys}')),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 5 / 7, crossAxisSpacing: 8, mainAxisSpacing: 8),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final c = list[i];
          final q = owned[c.id];
          final has = q != null && q[0] + q[1] + q[2] > 0;
          final best = q == null ? 0 : (q[2] > 0 ? 2 : q[1] > 0 ? 1 : 0);
          return GestureDetector(
            onTap: () {
              if (has && !Game.i.has(c.id)) {
                // Carte qu'il a et pas moi : proposer directement un échange
                showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: kPanel,
                  builder: (ctx) => SafeArea(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      ListTile(
                        leading: const Icon(Icons.swap_horiz, color: kGold),
                        title: Text(t('Demander cette carte en échange', 'Ask for this card in a trade')),
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => TradeBuilderPage(pid: pid, name: name, wantCard: c.id)));
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: Text(t('Voir la fiche', 'View card')),
                        onTap: () {
                          Navigator.pop(ctx);
                          openCardDetail(context, c, otherOwned: owned, otherName: name);
                        },
                      ),
                    ]),
                  ),
                );
              } else {
                openCardDetail(context, c, otherOwned: owned, otherName: name);
              }
            },
            child: CardView(card: c, finish: best, owned: has),
          );
        },
      ),
    );
  }
}
