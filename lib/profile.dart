import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account.dart';
import 'admin.dart';

import 'album.dart';
import 'audio.dart';
import 'cards.dart';
import 'catalog.dart';
import 'layout.dart';
import 'game.dart';
import 'arcade.dart';
import 'main.dart';
import 'server.dart';
import 'trades.dart';
import 'trophies.dart';
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
    checkAdmin();
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
          TabHeader(widget.embedded ? '' : t('Profil', 'Profile'), icon: 'profile', actions: [
            IconButton(
              tooltip: t('Son (musique et bruitages)', 'Sound (music and effects)'),
              icon: Icon(RcAudio.soundOn ? Icons.volume_up : Icons.volume_off),
              onPressed: () async {
                await RcAudio.setSound(!RcAudio.soundOn);
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
                  GestureDetector(onTap: _editAvatar, child: AvatarPulseSquare(g.avatar, size: 64)),
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
                Text(t('Touche un « + » pour ajouter une carte · maintiens une carte puis fais-la glisser pour changer l\'ordre',
                        'Tap a « + » to add a card · hold a card and drag it to reorder'),
                    style: const TextStyle(color: Colors.white38, fontSize: 12)),
                const SizedBox(height: 8),
                const _MyShowcase(),
                const SizedBox(height: 18),
                const MyTrophies(),
                const SizedBox(height: 18),
                Text(t('Mes séries', 'My sets'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 8),
                for (final s in [...Catalog.systems, ...Catalog.sagaSystems]) _setRow(s.name, g.ownedIn(s.id), s.count),
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
                    // Admin : visible seulement si le serveur confirme que ce compte est admin
                    ValueListenableBuilder<bool>(
                      valueListenable: rcIsAdmin,
                      builder: (context, admin, _) => !admin
                          ? const SizedBox.shrink()
                          : ListTile(
                              leading: const Icon(Icons.admin_panel_settings, color: Color(0xFFFF8A8A)),
                              title: const Text('Admin', style: TextStyle(fontWeight: FontWeight.w900)),
                              subtitle: Text(t('Comptes, liens, stats, chat, outils', 'Accounts, links, stats, chat, tools'),
                                  style: const TextStyle(fontSize: 12, color: Colors.white54)),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminPage())),
                            ),
                    ),
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
                    if (!kIsWeb)
                      FutureBuilder<(DateTime?, bool)>(
                        future: Future.wait([PushWatch.lastRun(), PushWatch.batteryFree()]).then((r) => (r[0] as DateTime?, r[1] as bool)),
                        builder: (context, snap) {
                          final last = snap.data?.$1;
                          final free = snap.data?.$2 ?? true;
                          String ago(DateTime d) {
                            final m = DateTime.now().difference(d).inMinutes;
                            if (m < 1) return t('à l\'instant', 'just now');
                            if (m < 60) return t('il y a $m min', '$m min ago');
                            if (m < 48 * 60) return t('il y a ${m ~/ 60} h', '${m ~/ 60} h ago');
                            return t('il y a ${m ~/ 1440} j', '${m ~/ 1440} d ago');
                          }

                          return ListTile(
                            leading: Icon(free ? Icons.battery_full : Icons.battery_alert, color: free ? null : const Color(0xFFFFB547)),
                            title: Text(t('Notifications appli fermée', 'Notifications when closed')),
                            subtitle: Text(
                                [
                                  last == null ? t('Aucune vérification en arrière-plan pour l\'instant', 'No background check yet') : t('Dernière vérification : ${ago(last)}', 'Last check: ${ago(last)}'),
                                  if (!free) t('L\'économie de batterie bloque les notifications : touche pour régler', 'Battery saving blocks notifications: tap to fix'),
                                ].join('\n'),
                                style: TextStyle(fontSize: 12, color: free ? Colors.white54 : const Color(0xFFFFB547))),
                            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                            onTap: () async {
                              await PushWatch.showReliableDialog(context);
                              setState(() {});
                            },
                          );
                        },
                      ),
                    const Divider(height: 1, color: Colors.white12),
                    ListTile(
                      leading: const Icon(Icons.palette),
                      title: Text(t('Thème', 'Theme')),
                      subtitle: Text(rcThemeRandom ? '${t('Aléatoire', 'Random')} · ${rcTheme.name}' : rcTheme.name,
                          style: const TextStyle(fontSize: 12, color: Colors.white54)),
                      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                      onTap: () async {
                        final i = await showDialog<int>(
                          context: context,
                          builder: (ctx) => SimpleDialog(
                            title: Text(t('Thème de l\'interface', 'Interface theme')),
                            children: [
                              SimpleDialogOption(
                                onPressed: () => Navigator.pop(ctx, -1),
                                child: Row(children: [
                                  Container(
                                    width: 64,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      gradient: const LinearGradient(colors: [Color(0xFFFF4FD8), Color(0xFF3DD9FF), Color(0xFF7DFF3D)]),
                                      border: Border.all(color: rcThemeRandom ? kGold : Colors.white24, width: rcThemeRandom ? 2.5 : 1.5),
                                    ),
                                    child: const Center(child: Text('🎲', style: TextStyle(fontSize: 22))),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(t('Aléatoire', 'Random'),
                                          style: TextStyle(fontWeight: FontWeight.w700, color: rcThemeRandom ? kGold : Colors.white)),
                                      Text(t('Un thème différent à chaque lancement', 'A different theme at each launch'),
                                          style: const TextStyle(fontSize: 11, color: Colors.white54)),
                                    ]),
                                  ),
                                  if (rcThemeRandom) const Icon(Icons.check, color: kGold),
                                ]),
                              ),
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
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(kThemes[k].name,
                                            style: TextStyle(fontWeight: FontWeight.w700, color: !rcThemeRandom && rcThemeIndex.value == k ? kThemes[k].accent : Colors.white)),
                                        Text(kThemes[k].motifName, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                                      ]),
                                    ),
                                    if (!rcThemeRandom && rcThemeIndex.value == k) const Icon(Icons.check, color: kGold),
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
                      subtitle: Text(RcAudio.homeTrackNone ? t('Aucune', 'None') : RcAudio.homeTrackRandom ? '${t('Aléatoire', 'Random')} · ${RcAudio.kTracks[RcAudio.homeTrack]}' : RcAudio.kTracks[RcAudio.homeTrack], style: const TextStyle(fontSize: 12, color: Colors.white54)),
                      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                      onTap: () async {
                        final i = await showDialog<int>(
                          context: context,
                          builder: (ctx) => SimpleDialog(
                            title: Text(t('Musique', 'Music')),
                            children: [
                              RadioListTile<int>(
                                value: -2,
                                groupValue: RcAudio.homeTrackNone ? -2 : RcAudio.homeTrackRandom ? -1 : RcAudio.homeTrack,
                                activeColor: kGold,
                                title: Text(t('🔇 Aucune', '🔇 None')),
                                subtitle: Text(t('Pas de musique, les bruitages restent', 'No music, sound effects stay on'),
                                    style: const TextStyle(fontSize: 11, color: Colors.white54)),
                                onChanged: (v) => Navigator.pop(ctx, v),
                              ),
                              RadioListTile<int>(
                                value: -1,
                                groupValue: RcAudio.homeTrackNone ? -2 : RcAudio.homeTrackRandom ? -1 : RcAudio.homeTrack,
                                activeColor: kGold,
                                title: Text(t('🎲 Aléatoire', '🎲 Random')),
                                subtitle: Text(t('Un morceau différent à chaque lancement', 'A different track at each launch'),
                                    style: const TextStyle(fontSize: 11, color: Colors.white54)),
                                onChanged: (v) => Navigator.pop(ctx, v),
                              ),
                              for (var k = 0; k < RcAudio.kTracks.length; k++)
                                RadioListTile<int>(
                                  value: k,
                                  groupValue: RcAudio.homeTrackNone ? -2 : RcAudio.homeTrackRandom ? -1 : RcAudio.homeTrack,
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

/// Ma vitrine : « + » dans les cases vides (choix parmi mes cartes, de la plus rare à la moins rare),
/// et les cartes se déplacent au doigt (appui long puis glisser sur une autre case).
class _MyShowcase extends StatefulWidget {
  const _MyShowcase();
  @override
  State<_MyShowcase> createState() => _MyShowcaseState();
}

class _MyShowcaseState extends State<_MyShowcase> {
  bool busy = false;

  Future<void> _save(List<(String, int)> items) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await Game.i.setProfile(newShowcase: itemsToString(items));
    } catch (e) {
      toast(errText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  /// Déplace la carte de la case [from] vers la case [to] (les autres se décalent)
  void _move(List<(String, int)> items, int from, int to) {
    if (from == to || from >= items.length) return;
    final l = [...items];
    final x = l.removeAt(from);
    l.insert(to.clamp(0, l.length), x);
    RcAudio.sfx('jump');
    _save(l);
  }

  Future<void> _add(List<(String, int)> items) async {
    final g = Game.i;
    final inShow = items.map((e) => e.$1).toSet();
    // mes cartes, une par jeu dans sa meilleure finition, de la plus rare à la moins rare
    final cards = <(RcCard, int)>[
      for (final e in g.owned.entries)
        if (Catalog.cards[e.key] != null && qSum(e.value) > 0 && !inShow.contains(e.key)) (Catalog.cards[e.key]!, bestFinish(e.value)),
    ]..sort((a, b) {
        if (a.$1.rarity != b.$1.rarity) return b.$1.rarity.compareTo(a.$1.rarity);
        if (a.$2 != b.$2) return b.$2.compareTo(a.$2);
        return a.$1.title.toLowerCase().compareTo(b.$1.title.toLowerCase());
      });
    final pick = await showModalBottomSheet<(String, int)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (ctx, scroll) => Column(children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 6, 4),
            child: Row(children: [
              Expanded(child: Text(t('Ajouter à ma vitrine', 'Add to my showcase'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
              // fermer sans choisir
              TextButton.icon(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, size: 18),
                label: Text(t('Fermer', 'Close')),
              ),
            ]),
          ),
          Expanded(
            child: cards.isEmpty
                ? Center(child: Text(t('Aucune carte à ajouter', 'No cards to add'), style: const TextStyle(color: Colors.white54)))
                : CustomScrollView(controller: scroll, slivers: [
                    // un intertitre par rareté, de légendaire à commune
                    for (var r = 4; r >= 0; r--)
                      if (cards.any((c) => c.$1.rarity == r)) ...[
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                          sliver: SliverToBoxAdapter(
                            child: Text(px(rarityName(r).toUpperCase()), style: pixelStyle(size: 7.5, color: kRarityLight[r], shadow: false)),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          sliver: SliverGrid(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: 5 / 7, crossAxisSpacing: 8, mainAxisSpacing: 8),
                            delegate: SliverChildListDelegate([
                              for (final c in cards.where((c) => c.$1.rarity == r))
                                GestureDetector(
                                  onTap: () => Navigator.pop(ctx, (c.$1.id, c.$2)),
                                  child: CardView(card: c.$1, finish: c.$2),
                                ),
                            ]),
                          ),
                        ),
                      ],
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  ]),
          ),
        ]),
      ),
    );
    if (pick == null) return;
    RcAudio.sfx('coin');
    await _save([...items, pick]);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Game.i,
      builder: (context, _) {
        final items = [for (final e in Game.i.showcaseItems) if (Catalog.cards[e.$1] != null) e];
        return LayoutBuilder(builder: (context, box) {
          final w = (box.maxWidth - 16) / 3;
          Widget slot(int i) {
            if (i >= items.length) {
              // case vide : « + »
              return DragTarget<int>(
                onWillAcceptWithDetails: (_) => true,
                onAcceptWithDetails: (d) => _move(items, d.data, items.length - 1),
                builder: (_, cand, __) => GestureDetector(
                  onTap: busy || items.length >= 6 ? null : () => _add(items),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.white.withOpacity(cand.isEmpty ? 0.03 : 0.1),
                      border: Border.all(color: rcTheme.accent.withOpacity(0.45), width: 2),
                    ),
                    child: Center(child: Icon(Icons.add_circle_outline, color: rcTheme.accent.withOpacity(0.8), size: w * 0.32)),
                  ),
                ),
              );
            }
            final (id, f) = items[i];
            final card = CardView(card: Catalog.cards[id]!, finish: f);
            return DragTarget<int>(
              onWillAcceptWithDetails: (d) => d.data != i,
              onAcceptWithDetails: (d) => _move(items, d.data, i),
              builder: (_, cand, __) => LongPressDraggable<int>(
                data: i,
                hapticFeedbackOnStart: true,
                feedback: Material(
                  color: Colors.transparent,
                  child: Transform.scale(scale: 1.08, child: SizedBox(width: w, child: card)),
                ),
                childWhenDragging: Opacity(opacity: 0.25, child: card),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 120),
                  scale: cand.isEmpty ? 1 : 0.92,
                  child: GestureDetector(
                    onTap: () => openCardDetail(context, Catalog.cards[id]!),
                    child: card,
                  ),
                ),
              ),
            );
          }

          return GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 5 / 7,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            children: [for (var i = 0; i < 6; i++) slot(i)],
          );
        });
      },
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

  int _his(String id) => owned[id] == null ? 0 : qSum(owned[id]!);

  /// Ses cartes que je n'ai pas : ses doubles d'abord, puis les plus rares
  List<RcCard> get _theyHave {
    final l = [
      for (final e in owned.entries)
        if (qSum(e.value) > 0 && !Game.i.has(e.key) && Catalog.cards[e.key] != null) Catalog.cards[e.key]!
    ];
    l.sort((a, b) {
      final d = (_his(b.id) > 1 ? 1 : 0) - (_his(a.id) > 1 ? 1 : 0);
      return d != 0 ? d : b.rarity != a.rarity ? b.rarity - a.rarity : a.title.compareTo(b.title);
    });
    return l;
  }

  /// Mes cartes qu'il n'a pas : mes doubles d'abord, puis les plus rares
  List<RcCard> get _iHave {
    final l = [
      for (final e in Game.i.owned.entries)
        if (qSum(e.value) > 0 && _his(e.key) == 0 && Catalog.cards[e.key] != null) Catalog.cards[e.key]!
    ];
    l.sort((a, b) {
      final d = (Game.i.qty(b.id) > 1 ? 1 : 0) - (Game.i.qty(a.id) > 1 ? 1 : 0);
      return d != 0 ? d : b.rarity != a.rarity ? b.rarity - a.rarity : a.title.compareTo(b.title);
    });
    return l;
  }

  void _askCard(BuildContext context, RcCard c, String name) {
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
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => TradeBuilderPage(pid: widget.pid, name: name, wantCard: c.id)));
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
  }

  void _offerCard(BuildContext context, RcCard c, String name) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kPanel,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.swap_horiz, color: kGold),
            title: Text(t('Lui proposer cette carte', 'Offer this card')),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => TradeBuilderPage(pid: widget.pid, name: name, giveCard: c.id)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(t('Voir la fiche', 'View card')),
            onTap: () {
              Navigator.pop(ctx);
              openCardDetail(context, c);
            },
          ),
        ]),
      ),
    );
  }

  /// Rubrique « Il a, tu n'as pas » / « Tu as, il n'a pas » : une bande de cartes + « Tout voir »
  Widget _diff(BuildContext context, String title, String empty, List<RcCard> cards, Map<String, List<int>> from, void Function(RcCard) onTap) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('$title · ${cards.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        if (cards.length > 4)
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _DiffPage(title: title, cards: cards, from: from, onTap: onTap),
            )),
            child: Text(t('Tout voir ›', 'See all ›')),
          ),
      ]),
      const SizedBox(height: 4),
      if (cards.isEmpty)
        Text(empty, style: const TextStyle(color: Colors.white38, fontSize: 12.5))
      else
        SizedBox(
          height: 118,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: min(cards.length, 30),
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => SizedBox(width: 84, child: _DiffCard(card: cards[i], q: from[cards[i].id], onTap: () => onTap(cards[i]))),
          ),
        ),
    ]);
  }

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
                  // sa borne dans la salle d'arcade
                  Center(child: ArcadeCabinet(d: FloorData.of(p!), width: 150)),
                  const SizedBox(height: 12),
                  Row(children: [
                    AvatarPulseSquare((p!['avatar'] as num? ?? 0).toInt(), size: 60),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                        Text(t('Score ${p!['score']} · ${p!['cards']} cartes · ${p!['packs']} paquets', 'Score ${p!['score']} · ${p!['cards']} cards · ${p!['packs']} packs'),
                            style: const TextStyle(color: kGold, fontSize: 13)),
                        const SizedBox(height: 2),
                        p!['online'] == true
                            ? Text(t('● En ligne', '● Online'), style: const TextStyle(color: Color(0xFF5DCAA5), fontSize: 12, fontWeight: FontWeight.w800))
                            : Text(t('🕒 Dernière connexion : ', '🕒 Last seen: ') + _lastSeen(p!),
                                style: const TextStyle(color: Colors.white60, fontSize: 12)),
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
                  const SizedBox(height: 14),
                  _diff(context, t('🎯 Il a, tu n\'as pas', '🎯 They have, you don\'t'),
                      t('Tu as déjà toutes ses cartes.', 'You already have all their cards.'), _theyHave, owned, (c) => _askCard(context, c, name)),
                  const SizedBox(height: 14),
                  _diff(context, t('🔁 Tu as, il n\'a pas', '🔁 You have, they don\'t'),
                      t('Il a déjà toutes tes cartes.', 'They already have all your cards.'), _iHave, Game.i.owned, (c) => _offerCard(context, c, name)),
                  const SizedBox(height: 18),
                  Text(t('Vitrine', 'Showcase'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 8),
                  _Showcase(parseItems(p!['showcase'] as String? ?? ''), owned: owned, ownerName: name),
                  const SizedBox(height: 18),
                  if (p!.containsKey('trophies')) ...[
                    OtherTrophies(show: p!['trophies'] as String?, total: (p!['tro_total'] as num? ?? 0).toInt()),
                    const SizedBox(height: 18),
                  ],
                  Text(t('Statistiques', 'Statistics'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 8),
                  StatsPanel(
                    owned: owned,
                    packs: (p!['packs'] as num?)?.toInt(),
                    since: DateTime.tryParse(p!['since']?.toString() ?? ''),
                    onCard: (c) => openCardDetail(context, c, otherOwned: owned, otherName: name),
                  ),
                  const SizedBox(height: 18),
                  Text(t('📊 Vous deux, console par console', '📊 You two, system by system'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(t('Touche une console pour voir son album', 'Tap a system to see their album'), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(height: 8),
                  Row(children: [
                    const SizedBox(width: 110),
                    Expanded(child: Text(t('Toi', 'You'), style: const TextStyle(color: Colors.white60, fontSize: 11.5, fontWeight: FontWeight.w800))),
                    const SizedBox(width: 10),
                    Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 11.5, fontWeight: FontWeight.w800))),
                  ]),
                  for (final s in [...Catalog.systems, ...Catalog.sagaSystems])
                    InkWell(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => OtherAlbumPage(sys: s.id, owned: owned, name: name, pid: widget.pid),
                      )),
                      child: _cmpRow(s.name, Game.i.ownedIn(s.id), _in(s.id), s.count),
                    ),
                ]),
    ));
  }
}

/// Ligne de comparaison : ma barre et la sienne (la plus avancée en vert)
Widget _cmpRow(String name, int mine, int his, int total) {
  Widget bar(int n, bool lead) => Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : n / total,
              minHeight: 7,
              color: lead ? const Color(0xFF5DCAA5) : kGold,
              backgroundColor: kPanel2,
            ),
          ),
        ),
        SizedBox(width: 34, child: Text('${total == 0 ? 0 : (n * 100 / total).floor()}%', textAlign: TextAlign.right, style: const TextStyle(color: Colors.white54, fontSize: 11))),
      ]);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      SizedBox(width: 110, child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
      Expanded(child: bar(mine, mine > his)),
      const SizedBox(width: 10),
      Expanded(child: bar(his, his > mine)),
    ]),
  );
}

/// Une carte de la comparaison (×2 si elle est en double)
class _DiffCard extends StatelessWidget {
  final RcCard card;
  final List<int>? q;
  final VoidCallback onTap;
  const _DiffCard({required this.card, required this.q, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final n = q == null ? 0 : qSum(q!);
    return GestureDetector(
      onTap: onTap,
      child: Stack(children: [
        Positioned.fill(child: CardView(card: card, finish: q == null ? 0 : bestFinish(q!), owned: true)),
        if (n > 1)
          Positioned(
            top: 3,
            right: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: const Color(0xFFE24B4A), borderRadius: BorderRadius.circular(8)),
              child: Text('×$n', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
            ),
          ),
      ]),
    );
  }
}

/// Toutes les cartes d'une rubrique de comparaison
class _DiffPage extends StatelessWidget {
  final String title;
  final List<RcCard> cards;
  final Map<String, List<int>> from;
  final void Function(RcCard) onTap;
  const _DiffPage({required this.title, required this.cards, required this.from, required this.onTap});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('$title · ${cards.length}')),
        body: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 130, childAspectRatio: 5 / 7, crossAxisSpacing: 8, mainAxisSpacing: 8),
          itemCount: cards.length,
          itemBuilder: (_, i) => _DiffCard(card: cards[i], q: from[cards[i].id], onTap: () => onTap(cards[i])),
        ),
      );
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
          final has = q != null && qSum(q) > 0;
          final best = q == null ? 0 : bestFinish(q);
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

/// Dernière connexion d'un profil : heure exacte (seen_at), sinon le dernier jour connu (seen_day, sans heure)
String _lastSeen(Map p) {
  final at = DateTime.tryParse(p['seen_at']?.toString() ?? '')?.toLocal();
  if (at != null) return lastSeenLong(at);
  final d = DateTime.tryParse(p['seen_day']?.toString() ?? '');
  if (d == null) return lastSeenLong(null);
  final days = DateTime.now().difference(DateTime(d.year, d.month, d.day)).inDays;
  String two(int n) => n.toString().padLeft(2, '0');
  return t('le ${two(d.day)}/${two(d.month)} (il y a $days jour${days > 1 ? 's' : ''})', 'on ${d.month}/${d.day} ($days day${days > 1 ? 's' : ''} ago)');
}
