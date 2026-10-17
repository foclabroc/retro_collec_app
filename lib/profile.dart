import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account.dart';

import 'album.dart';
import 'audio.dart';
import 'cards.dart';
import 'catalog.dart';
import 'layout.dart';
import 'game.dart';
import 'house.dart';
import 'main.dart';
import 'server.dart';
import 'trades.dart';
import 'neighbors.dart';
import 'notifs.dart';
import 'push.dart';
import 'retro_theme.dart';
import 'stats.dart';
import 'update_check.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Profil : le mien (pseudo, avatar, vitrine, statistiques, classement) et
// celui des autres joueurs (vitrine + collection complète consultable)
// ═══════════════════════════════════════════════════════════════════════════

class ProfileScreen extends StatefulWidget {
  final bool embedded; // ouvert depuis le Voisinage (page avec barre de titre)
  const ProfileScreen({super.key, this.embedded = false});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Map<String, dynamic>>? board;
  (int, int)? rank;
  bool? hasPass;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await RcServer.board();
      final r = await RcServer.rank();
      final hp = await RcServer.hasPassword();
      if (mounted) {
        setState(() {
          board = b;
          rank = r;
          hasPass = hp;
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
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
              for (var i = 0; i < kAvatars.length; i++)
                GestureDetector(
                  onTap: () => Navigator.pop(ctx, i),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Game.i.avatar == i ? kGold : Colors.transparent, width: 2.5),
                    ),
                    child: avatarWidget(i, size: 58),
                  ),
                ),
            ]),
          ),
        ),
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
          TabHeader(widget.embedded ? '' : t('Profil', 'Profile'), actions: [
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
                if (RcAudio.musicEnabled) RcAudio.musicStart(RcAudio.homeTrack);
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
                Text(t('Statistiques', 'Statistics'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 8),
                StatsPanel(owned: g.owned, packs: g.packs, onCard: (c) => openCardDetail(context, c)),
                const SizedBox(height: 18),
                Text(t('Réglages', 'Settings'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(12)),
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.tablet_android),
                      title: Text(t('Affichage', 'Layout')),
                      subtitle: Text(
                          [t('Automatique', 'Automatic'), t('Toujours téléphone', 'Always phone'), t('Mode tablette (essai possible sur téléphone, en paysage)', 'Tablet mode (can be tried on a phone, in landscape)')][rcLayoutMode.value],
                          style: const TextStyle(fontSize: 12, color: Colors.white54)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final m = await showDialog<int>(
                          context: context,
                          builder: (ctx) => SimpleDialog(
                            title: Text(t('Affichage', 'Layout')),
                            children: [
                              for (final (i, label) in [
                                (0, t('Automatique (tablette sur les grands écrans)', 'Automatic (tablet on large screens)')),
                                (1, t('Toujours téléphone', 'Always phone')),
                                (2, t('Mode tablette (tourne le téléphone en paysage)', 'Tablet mode (turn the phone to landscape)')),
                              ])
                                RadioListTile<int>(
                                  value: i,
                                  groupValue: rcLayoutMode.value,
                                  activeColor: kGold,
                                  title: Text(label),
                                  onChanged: (v) => Navigator.pop(ctx, v),
                                ),
                            ],
                          ),
                        );
                        if (m != null) {
                          await setLayoutMode(m);
                          if (mounted) setState(() {});
                        }
                      },
                    ),
                    const Divider(height: 1, color: Colors.white12),
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
                    if (!kIsWeb) FutureBuilder<bool>(
                      future: PushWatch.enabled(),
                      builder: (context, snap) => SwitchListTile(
                        secondary: const Icon(Icons.notifications_active),
                        title: Text(t('Notifications', 'Notifications')),
                        subtitle: Text(t('Cadeaux, ventes, échanges, paquet gratuit… même appli fermée', 'Gifts, sales, trades, free pack… even when the app is closed'),
                            style: const TextStyle(fontSize: 12, color: Colors.white54)),
                        value: snap.data ?? true,
                        activeColor: kGold,
                        onChanged: (v) async {
                          await PushWatch.setEnabled(v);
                          setState(() {});
                        },
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    ListTile(
                      leading: const Icon(Icons.palette),
                      title: Text(t('Thème', 'Theme')),
                      subtitle: Text(rcTheme.name, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                      onTap: () async {
                        final i = await showDialog<int>(
                          context: context,
                          builder: (ctx) => SimpleDialog(
                            title: Text(t('Thème de l\'interface', 'Interface theme')),
                            children: [
                              for (var k = 0; k < kThemes.length; k++)
                                SimpleDialogOption(
                                  onPressed: () => Navigator.pop(ctx, k),
                                  child: Row(children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: rcThemeIndex.value == k ? kGold : kThemes[k].line, width: rcThemeIndex.value == k ? 2.5 : 1.5),
                                      ),
                                      child: ClipRRect(borderRadius: BorderRadius.circular(6), child: ThemePreview(k, width: 64, height: 44)),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(kThemes[k].name,
                                          style: TextStyle(fontWeight: FontWeight.w700, color: rcThemeIndex.value == k ? kGold : Colors.white)),
                                    ),
                                    if (rcThemeIndex.value == k) const Icon(Icons.check, color: kGold),
                                  ]),
                                ),
                            ],
                          ),
                        );
                        if (i != null) {
                          await setTheme(i);
                          setState(() {});
                        }
                      },
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    ListTile(
                      leading: const Icon(Icons.library_music),
                      title: Text(t('Musique', 'Music')),
                      subtitle: Text(RcAudio.kTracks[RcAudio.homeTrack], style: const TextStyle(fontSize: 12, color: Colors.white54)),
                      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                      onTap: () async {
                        final i = await showDialog<int>(
                          context: context,
                          builder: (ctx) => SimpleDialog(
                            title: Text(t('Musique', 'Music')),
                            children: [
                              for (var k = 0; k < RcAudio.kTracks.length; k++)
                                RadioListTile<int>(
                                  value: k,
                                  groupValue: RcAudio.homeTrack,
                                  activeColor: kGold,
                                  title: Text(RcAudio.kTracks[k]),
                                  onChanged: (v) => Navigator.pop(ctx, v),
                                ),
                            ],
                          ),
                        );
                        if (i != null) {
                          await RcAudio.setHomeTrack(i);
                          setState(() {});
                        }
                      },
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    ListTile(
                      leading: const Icon(Icons.translate),
                      title: Text(t('Langue', 'Language')),
                      subtitle: Text(
                          switch (rcLang) {
                            'fr' => 'Français',
                            'en' => 'English',
                            _ => t('Automatique (langue du téléphone)', 'Automatic (phone language)'),
                          },
                          style: const TextStyle(fontSize: 12, color: Colors.white54)),
                      onTap: _language,
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    ListTile(
                      leading: Icon(hasPass == true ? Icons.lock : Icons.lock_open, color: hasPass == true ? const Color(0xFF5DCAA5) : const Color(0xFFF09595)),
                      title: Text(hasPass == true ? t('Changer le mot de passe', 'Change password') : t('Protéger mon compte', 'Protect my account')),
                      subtitle: Text(
                          hasPass == true
                              ? t('Compte protégé : pseudo + mot de passe', 'Account protected: name + password')
                              : t('Choisis un mot de passe pour retrouver ton compte', 'Choose a password to get your account back'),
                          style: const TextStyle(fontSize: 12, color: Colors.white54)),
                      onTap: _password,
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
                      title: Text(t('Retrouver un compte', 'Get an account back')),
                      subtitle: Text(t('Pseudo + mot de passe ou code de sauvegarde', 'Name + password or backup code'), style: const TextStyle(fontSize: 12, color: Colors.white54)),
                      onTap: _restore,
                    ),
                  ]),
                ),
                const SizedBox(height: 18),
                Center(
                  child: TextButton.icon(
                    onPressed: _updateCards,
                    icon: const Icon(Icons.sync, size: 16, color: Colors.white38),
                    label: Text('${t('Cartes', 'Cards')} ${Catalog.version} — ${t('mettre à jour', 'update')}',
                        style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  ),
                ),
                if (!kIsWeb) Center(
                  child: TextButton(
                    onPressed: () async {
                      final st = context.findAncestorStateOfType<UpdateGateState>();
                      final r = await st?.check(manual: true) ?? 0;
                      if (r == 0) toast(t('L\'appli est à jour (v$kRetroCollecVersion)', 'The app is up to date (v$kRetroCollecVersion)'));
                      if (r == 2) toast(t('Vérification impossible (hors ligne)', 'Could not check (offline)'));
                    },
                    child: Text('Pixel Trade v$kRetroCollecVersion — ${t('vérifier les mises à jour', 'check for updates')}',
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
          Text(t('Note ce code (ou fais une capture d\'écran). Sur un nouveau téléphone : « J\'ai déjà un compte ».',
              'Write this code down (or take a screenshot). On a new phone: "I already have an account".')),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: kGold)),
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
    final name = await showAccountLogin(context, replacing: true);
    if (name == null) return;
    _load();
    toast(t('Profil « $name » restauré !', 'Profile "$name" restored!'));
  }

  /// Force la vérification du catalogue des cartes (affiche l'erreur s'il y en a une).
  Future<void> _updateCards() async {
    final status = ValueNotifier<String>(t('Recherche…', 'Checking…'));
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(children: [
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: kGold)),
          const SizedBox(width: 16),
          Expanded(child: ValueListenableBuilder<String>(valueListenable: status, builder: (_, v, __) => Text(v))),
        ]),
      ),
    );
    String msg;
    try {
      final before = Catalog.version;
      await Catalog.update(progress: (p, s) => status.value = '${t('Téléchargement', 'Downloading')} ${(p * 100).round()} %${s.isEmpty ? '' : ' — $s'}');
      msg = before == Catalog.version
          ? t('Cartes déjà à jour (${Catalog.version})', 'Cards already up to date (${Catalog.version})')
          : t('Cartes mises à jour (${Catalog.version})', 'Cards updated (${Catalog.version})');
    } catch (e) {
      msg = '${t('Échec', 'Failed')} : $e';
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    setState(() {});
    toast(msg);
  }

  Future<void> _language() async {
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(t('Langue', 'Language')),
        children: [
          for (final (code, label) in [
            ('auto', t('Automatique (langue du téléphone)', 'Automatic (phone language)')),
            ('fr', 'Français'),
            ('en', 'English'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, code),
              child: Row(children: [
                Icon(rcLang == code ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: kGold, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(label)),
              ]),
            ),
        ],
      ),
    );
    if (v == null || v == rcLang) return;
    await setLang(v);
  }

  Future<void> _password() async {
    if (await showSetPassword(context, change: hasPass == true)) {
      setState(() => hasPass = true);
      toast(t('Mot de passe enregistré', 'Password saved'));
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
    return MaxWidth(max: 820, child: Scaffold(
      appBar: AppBar(title: Text(name)),
      body: error != null
          ? Center(child: Text(error!, style: const TextStyle(color: Colors.white60)))
          : p == null
              ? const Center(child: CircularProgressIndicator(color: kGold))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  // sa maison
                  Center(
                    child: SizedBox(width: 220, height: 190, child: HouseView(HouseSpec.parse(p!['house'] as String?, seed: widget.pid))),
                  ),
                  const SizedBox(height: 12),
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
                  Row(children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.swap_horiz),
                        label: Text(t('Échanger', 'Trade')),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TradeBuilderPage(pid: widget.pid, name: name))),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ListenableBuilder(
                        listenable: Notifs.i,
                        builder: (context, _) => FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
                          icon: const Icon(Icons.card_giftcard),
                          label: Text(t('Offrir un paquet', 'Give a pack')),
                          onPressed: Notifs.i.canGift ? () => giftPack(context, widget.pid, name) : null,
                        ),
                      ),
                    ),
                  ]),
                  ListenableBuilder(
                    listenable: Notifs.i,
                    builder: (_, __) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                        Notifs.i.canGift
                            ? t('Encore ${Notifs.i.giftsLeft} paquet(s) à offrir aujourd\'hui', '${Notifs.i.giftsLeft} pack(s) left to give today')
                            : t('3 paquets offerts aujourd\'hui · reviens demain', '3 packs given today · come back tomorrow'),
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ),
                  ),
                  const SizedBox(height: 18),
                  Text(t('Vitrine', 'Showcase'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 8),
                  _Showcase(parseItems(p!['showcase'] as String? ?? ''), owned: owned, ownerName: name),
                  const SizedBox(height: 18),
                  Text(t('Statistiques', 'Statistics'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 8),
                  StatsPanel(
                    owned: owned,
                    packs: (p!['packs'] as num?)?.toInt(),
                    since: DateTime.tryParse(p!['since']?.toString() ?? ''),
                    onCard: (c) => openCardDetail(context, c, otherOwned: owned, otherName: name),
                  ),
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
    ));
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
