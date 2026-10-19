part of 'admin.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Page admin, partie 2 : actions sur un joueur (cadeau, renommer, bloquer) et
// onglet Outils (annonce / cadeau à tous, sondage, événements, réglages en
// direct, version minimale, offres de la Bourse).
// ─────────────────────────────────────────────────────────────────────────────

Future<bool?> _confirm(BuildContext context, String title, String text, {String? ok, bool danger = false}) => showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Annuler', 'Cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: danger ? ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8A2232)) : null,
            child: Text(ok ?? 'OK'),
          ),
        ],
      ),
    );

/// Lance une action admin : toast du résultat ou de l'erreur, puis recharge
Future<void> _run(Future<void> Function() f, String done, [Future<void> Function()? reload]) async {
  try {
    await f();
    toast(done);
    if (reload != null) await reload();
  } catch (e) {
    toast(errText(e));
  }
}

Widget _section(String title, String help, List<Widget> children) => _box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        if (help.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(help, style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
        ],
        const SizedBox(height: 10),
        ...children,
      ]),
    );

InputDecoration _field(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );

// ─── Courrier (annonce ou cadeau) ───────────────────────────────────────────

/// Écrire un message : pid vide = tous les joueurs. Renvoie true si envoyé.
Future<bool> _composeMail(BuildContext context, {String pid = '', String? toName}) async {
  final title = TextEditingController(), body = TextEditingController();
  final coins = TextEditingController(text: '0'), pixels = TextEditingController(text: '0'), packs = TextEditingController(text: '0');
  final send = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(toName == null ? t('Message à tous les joueurs', 'Message to all players') : t('Cadeau pour $toName', 'Gift for $toName')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              toName == null
                  ? t('Une fenêtre à la prochaine ouverture du jeu, une fois par joueur (inscrits avant l\'envoi, pendant 30 jours). Sans récompense = simple annonce.',
                      'A window at next launch, once per player (signed up before sending, for 30 days). No reward = plain announcement.')
                  : t('Une fenêtre à sa prochaine ouverture du jeu.', 'A window at their next launch.'),
              style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
          const SizedBox(height: 12),
          TextField(controller: title, maxLength: 80, decoration: _field(t('Titre', 'Title'), hint: t('Week-end double pixels !', 'Double pixels weekend!'))),
          const SizedBox(height: 4),
          TextField(controller: body, maxLength: 600, minLines: 2, maxLines: 5, decoration: _field(t('Message', 'Message'))),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: coins, keyboardType: TextInputType.number, decoration: _field('🪙'))),
            const SizedBox(width: 6),
            Expanded(child: TextField(controller: pixels, keyboardType: TextInputType.number, decoration: _field('▦'))),
            const SizedBox(width: 6),
            Expanded(child: TextField(controller: packs, keyboardType: TextInputType.number, decoration: _field(t('premium', 'premium')))),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Annuler', 'Cancel'))),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Envoyer', 'Send'))),
      ],
    ),
  );
  if (send != true) return false;
  final c = int.tryParse(coins.text.trim()) ?? 0, px = int.tryParse(pixels.text.trim()) ?? 0, pk = int.tryParse(packs.text.trim()) ?? 0;
  try {
    await RcServer.adminMail(pid, title.text.trim(), body.text.trim(), c, px, pk);
    toast(t('Message envoyé', 'Message sent'));
    return true;
  } catch (e) {
    toast(errText(e));
    return false;
  }
}

// ─── Actions sur un joueur ──────────────────────────────────────────────────

class _PlayerActions extends StatelessWidget {
  final String pid;
  final Map<String, dynamic> player;
  final Future<void> Function() reload;
  const _PlayerActions({required this.pid, required this.player, required this.reload});

  @override
  Widget build(BuildContext context) {
    final name = player['name']?.toString() ?? '?';
    final blocked = player['blocked'] == true;
    Widget btn(IconData icon, String label, VoidCallback onTap, {bool danger = false}) => ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 17),
          label: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
          style: ElevatedButton.styleFrom(
            backgroundColor: danger ? const Color(0xFF5A1D2A) : const Color(0xFF2C3770),
            foregroundColor: danger ? const Color(0xFFFFC4CF) : Colors.white,
          ),
        );
    return Wrap(spacing: 6, runSpacing: 6, children: [
      btn(Icons.person, t('Profil', 'Profile'),
          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerProfilePage(pid: pid)))),
      btn(Icons.card_giftcard, t('Offrir…', 'Gift…'), () => _composeMail(context, pid: pid, toName: name)),
      btn(Icons.edit, t('Renommer', 'Rename'), () => _rename(context, name)),
      blocked
          ? btn(Icons.lock_open, t('Débloquer', 'Unblock'), () => _block(context, name, false))
          : btn(Icons.block, t('Bloquer', 'Block'), () => _block(context, name, true), danger: true),
    ]);
  }

  Future<void> _rename(BuildContext context, String name) async {
    final ctl = TextEditingController(text: name);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Renommer $name', 'Rename $name')),
        content: TextField(controller: ctl, maxLength: 16, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Annuler', 'Cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('OK')),
        ],
      ),
    );
    if (v == null || v.isEmpty || v == name) return;
    try {
      final r = await RcServer.adminRename(pid, v);
      toast(r == 'taken' ? t('Pseudo déjà pris', 'Name already taken') : t('Renommé en $v', 'Renamed to $v'));
      if (r != 'taken') await reload();
    } catch (e) {
      toast(errText(e));
    }
  }

  Future<void> _block(BuildContext context, String name, bool on) async {
    final ok = await _confirm(
      context,
      on ? t('Bloquer $name ?', 'Block $name?') : t('Débloquer $name ?', 'Unblock $name?'),
      on
          ? t('Il ne pourra plus échanger, vendre, acheter ni offrir. Il peut toujours jouer seul. Réversible.',
              'They can no longer trade, sell, buy or gift. They can still play solo. Reversible.')
          : t('Il retrouve les échanges, la Bourse et les cadeaux.', 'Trades, market and gifts are back.'),
      ok: on ? t('Bloquer', 'Block') : t('Débloquer', 'Unblock'),
      danger: on,
    );
    if (ok != true) return;
    await _run(() => RcServer.adminBlock(pid, on), on ? t('$name est bloqué', '$name is blocked') : t('$name est débloqué', '$name is unblocked'), reload);
  }
}

// ─── Onglet Outils ──────────────────────────────────────────────────────────

class _ToolsTab extends StatelessWidget {
  const _ToolsTab();

  static Future<Map<String, dynamic>> _load() async {
    final r = await Future.wait([RcServer.appConfig(), RcServer.adminMails(), RcServer.adminPolls()]);
    final cfg = r[0] as Map<String, dynamic>;
    applyLive(cfg['live']);
    return {'cfg': cfg, 'mails': r[1], 'polls': r[2]};
  }

  @override
  Widget build(BuildContext context) {
    return _Loader<Map<String, dynamic>>(
      load: _load,
      builder: (context, data, reload) {
        final cfg = data['cfg'] as Map<String, dynamic>;
        final mails = data['mails'] as List<Map<String, dynamic>>;
        final polls = data['polls'] as List<Map<String, dynamic>>;
        final live = cfg['live'] is Map ? Map<String, dynamic>.from(cfg['live'] as Map) : <String, dynamic>{};
        return ListView(padding: const EdgeInsets.all(10), children: [
          _mailSection(context, mails, reload),
          _pollSection(context, polls, reload),
          _section(t('🎉 Événements', '🎉 Events'), t('Infos, cadeaux, effets (pixels ×2, paquet gratuit plus fréquent) et défis à paliers.',
              'Info, gifts, effects (pixels ×2, faster free pack) and tiered challenges.'), [
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminEventsPage())),
              icon: const Icon(Icons.event),
              label: Text(t('Gérer les événements', 'Manage events')),
            ),
          ]),
          _liveSection(context, live, reload),
          _versionSection(context, cfg['min_version']?.toString() ?? '1.0.0', reload),
          _section(t('💱 Bourse', '💱 Market'), t('Retirer une offre abusive : la carte retourne au vendeur.', 'Remove an abusive offer: the card goes back to the seller.'), [
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminMarketPage())),
              icon: const Icon(Icons.storefront),
              label: Text(t('Voir les offres', 'See offers')),
            ),
          ]),
        ]);
      },
    );
  }

  Widget _mailSection(BuildContext context, List<Map<String, dynamic>> mails, Future<void> Function() reload) {
    return _section(t('📢 Annonce et 🎁 cadeau à tous', '📢 Announcement and 🎁 gift to all'),
        t('Une fenêtre à la prochaine ouverture du jeu. Pièces, pixels ou paquets premium en option (ex. : dédommagement après un bug). Pour un seul joueur : sa fiche → Offrir.',
            'A window at next launch. Optional coins, pixels or premium packs (e.g. after a bug). For one player: their file → Gift.'),
        [
          ElevatedButton.icon(
            onPressed: () async {
              if (await _composeMail(context)) await reload();
            },
            icon: const Icon(Icons.campaign),
            label: Text(t('Nouveau message à tous', 'New message to all')),
          ),
          if (mails.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(t('Derniers envoyés', 'Recently sent'), style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w800)),
            for (final m in mails.take(10))
              Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                      Text(
                          '${_date(_d(m['at']))} · ${m['to'] == null ? t('tous', 'all') : '→ ${m['to']}'}'
                          '${_i(m['coins']) > 0 ? ' · ${_i(m['coins'])} 🪙' : ''}${_i(m['pixels']) > 0 ? ' · ${_i(m['pixels'])} ▦' : ''}'
                          '${_i(m['packs']) > 0 ? ' · ${_i(m['packs'])} premium' : ''} · ${t('lu ${_i(m['read'])} fois', 'read ${_i(m['read'])}×')}',
                          style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
                    ]),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.white54),
                    tooltip: t('Supprimer', 'Delete'),
                    onPressed: () async {
                      final ok = await _confirm(context, t('Supprimer ce message ?', 'Delete this message?'),
                          t('Ceux qui ne l\'ont pas encore ouvert ne le verront pas. Ceux qui l\'ont lu gardent leur cadeau.',
                              'Players who haven\'t opened it won\'t see it. Those who did keep their gift.'),
                          danger: true);
                      if (ok == true) await _run(() => RcServer.adminMailDelete(_i(m['id'])), t('Message supprimé', 'Message deleted'), reload);
                    },
                  ),
                ]),
              ),
          ],
        ]);
  }

  Widget _pollSection(BuildContext context, List<Map<String, dynamic>> polls, Future<void> Function() reload) {
    final cur = polls.isEmpty ? null : polls.first;
    final open = cur != null && cur['closed'] != true;
    Widget results(Map<String, dynamic> p) {
      final opts = [for (final o in (p['options'] as List? ?? const [])) o.toString()];
      final votes = [for (final v in (p['votes'] as List? ?? const [])) _i(v)];
      final total = _i(p['total']);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p['question']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        for (final (k, o) in opts.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Container(
              height: 30,
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
              clipBehavior: Clip.antiAlias,
              child: Stack(children: [
                FractionallySizedBox(
                    widthFactor: total == 0 || k >= votes.length ? 0 : votes[k] / total,
                    heightFactor: 1,
                    child: Container(color: kGold.withOpacity(0.35))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(children: [
                    Expanded(child: Text(o, style: const TextStyle(fontSize: 13))),
                    Text(total == 0 || k >= votes.length ? '0 %' : '${(votes[k] * 100 / total).round()} %',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                  ]),
                ),
              ]),
            ),
          ),
        Text(
            p['closed'] == true
                ? t('$total votes · terminé', '$total votes · closed')
                : t('$total votes · se termine ${_date(_d(p['ends_at']))}', '$total votes · ends ${_date(_d(p['ends_at']))}'),
            style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
      ]);
    }

    return _section(t('📊 Sondage', '📊 Poll'),
        t('Une question et 2 à 4 réponses ; les joueurs votent à l\'ouverture du jeu. Un seul sondage à la fois.',
            'One question and 2 to 4 answers; players vote at launch. One poll at a time.'),
        [
          if (cur != null) ...[results(cur), const SizedBox(height: 8)],
          Row(children: [
            ElevatedButton(onPressed: () => _newPoll(context, reload), child: Text(t('Nouveau sondage', 'New poll'))),
            const SizedBox(width: 8),
            if (open)
              OutlinedButton(
                onPressed: () async {
                  final ok = await _confirm(context, t('Clore le sondage ?', 'Close the poll?'), t('Plus personne ne pourra voter.', 'Nobody can vote anymore.'));
                  if (ok == true) await _run(() => RcServer.adminPollClose(_i(cur['id'])), t('Sondage clos', 'Poll closed'), reload);
                },
                child: Text(t('Clore', 'Close')),
              ),
          ]),
          if (polls.length > 1) ...[
            const SizedBox(height: 10),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(t('Anciens sondages', 'Past polls'), style: const TextStyle(fontSize: 13, color: Colors.white70)),
              children: [for (final p in polls.skip(1)) Padding(padding: const EdgeInsets.only(bottom: 12), child: results(p))],
            ),
          ],
        ]);
  }

  Future<void> _newPoll(BuildContext context, Future<void> Function() reload) async {
    final q = TextEditingController();
    final opts = [for (var i = 0; i < 4; i++) TextEditingController()];
    var days = 3;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(t('Nouveau sondage', 'New poll')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: q, maxLength: 140, decoration: _field(t('Question', 'Question'), hint: t('Quelle saga ajouter ensuite ?', 'Which saga next?'))),
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: TextField(controller: opts[i], maxLength: 60, decoration: _field(t('Réponse ${i + 1}${i >= 2 ? ' (facultative)' : ''}', 'Answer ${i + 1}${i >= 2 ? ' (optional)' : ''}'))),
                ),
              Row(children: [
                Text(t('Durée', 'Length'), style: const TextStyle(color: Colors.white70)),
                const Spacer(),
                DropdownButton<int>(
                  value: days,
                  items: [for (final d in const [1, 2, 3, 5, 7, 14]) DropdownMenuItem(value: d, child: Text(t('$d jour${d > 1 ? 's' : ''}', '$d day${d > 1 ? 's' : ''}')))],
                  onChanged: (v) => setD(() => days = v ?? 3),
                ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Annuler', 'Cancel'))),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Lancer', 'Start'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final options = opts.map((c) => c.text.trim().replaceAll('\n', ' ')).where((s) => s.isNotEmpty).join('\n');
    await _run(() => RcServer.adminPollNew(q.text.trim(), options, days), t('Sondage lancé', 'Poll started'), reload);
  }

  Widget _liveSection(BuildContext context, Map<String, dynamic> live, Future<void> Function() reload) {
    String v(String k) {
      final n = live[k];
      if (n is! num) return '?';
      final s = n == n.roundToDouble() ? n.toInt().toString() : n.toString();
      return rcFrench ? s.replaceAll('.', ',') : s;
    }

    Widget line(String a, String b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(a, style: const TextStyle(color: Colors.white60, fontSize: 13))),
            Text(b, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ]),
        );
    return _section(t('⚙️ Réglages en direct', '⚙️ Live settings'),
        t('Appliqués tout de suite, sans nouvel APK (les APK jusqu\'à la 1.0.12 affichent encore les anciens prix et chances).',
            'Applied right away, no new APK (APKs up to 1.0.12 still show the old prices and odds).'),
        [
          line(t('Cartes de saga (par carte)', 'Saga cards (per card)'), '${v('saga')} %'),
          line(t('Brillante · dorée', 'Holo · gold'), '${v('holo')} % · ${v('gold')} %'),
          line(t('Full art (épiques et légendaires)', 'Full art (epic & legendary)'), '${v('fullart')} %'),
          line(t('Paquets mixte · console · premium · mystère', 'Packs mixed · console · premium · mystery'),
              '${v('mixte')} · ${v('console')} · ${v('premium')} · ${v('mystery')} 🪙'),
          line(t('Coffre des défis', 'Challenge chest'), '${v('chest_coins')} 🪙 + ${v('chest_pixels')} ▦ + 1 premium'),
          const SizedBox(height: 8),
          Row(children: [
            ElevatedButton(onPressed: () => _editLive(context, live, reload), child: Text(t('Modifier', 'Edit'))),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () async {
                final ok = await _confirm(context, t('Valeurs d\'origine ?', 'Back to defaults?'),
                    t('Saga 3,2 %, brillante 5 %, dorée 0,5 %, full art 0,2 %, paquets 100 / 150 / 400 / 120, coffre 500 🪙 + 2 ▦.',
                        'Saga 3.2%, holo 5%, gold 0.5%, full art 0.2%, packs 100 / 150 / 400 / 120, chest 500 🪙 + 2 ▦.'));
                if (ok != true) return;
                await _run(
                    () => RcServer.adminSetLive(const {
                          'saga': 3.2, 'holo': 5, 'gold': 0.5, 'fullart': 0.2, 'mixte': 100, 'console': 150,
                          'premium': 400, 'mystery': 120, 'chest_coins': 500, 'chest_pixels': 2,
                        }).then(applyLive),
                    t('Valeurs d\'origine remises', 'Defaults restored'),
                    reload);
              },
              child: Text(t('Origine', 'Defaults')),
            ),
          ]),
        ]);
  }

  Future<void> _editLive(BuildContext context, Map<String, dynamic> live, Future<void> Function() reload) async {
    const keys = ['saga', 'holo', 'gold', 'fullart', 'mixte', 'console', 'premium', 'mystery', 'chest_coins', 'chest_pixels'];
    final labels = {
      'saga': t('Saga (%)', 'Saga (%)'),
      'holo': t('Brillante (%)', 'Holo (%)'),
      'gold': t('Dorée (%)', 'Gold (%)'),
      'fullart': t('Full art (%)', 'Full art (%)'),
      'mixte': t('Paquet mixte 🪙', 'Mixed pack 🪙'),
      'console': t('Paquet console 🪙', 'Console pack 🪙'),
      'premium': t('Paquet premium 🪙', 'Premium pack 🪙'),
      'mystery': t('Paquet mystère 🪙', 'Mystery pack 🪙'),
      'chest_coins': t('Coffre : pièces', 'Chest: coins'),
      'chest_pixels': t('Coffre : pixels', 'Chest: pixels'),
    };
    final ctl = {
      for (final k in keys)
        k: TextEditingController(text: live[k] is num ? ((live[k] as num) == (live[k] as num).roundToDouble() ? (live[k] as num).toInt().toString() : live[k].toString()) : '')
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Réglages en direct', 'Live settings')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final k in keys)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: ctl[k],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _field(labels[k]!),
                ),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Annuler', 'Cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Appliquer', 'Apply'))),
        ],
      ),
    );
    if (ok != true) return;
    final values = <String, num>{};
    for (final k in keys) {
      final n = num.tryParse(ctl[k]!.text.trim().replaceAll(',', '.'));
      if (n != null && n != live[k]) values[k] = n;
    }
    if (values.isEmpty) return;
    await _run(() => RcServer.adminSetLive(values).then(applyLive), t('Réglages appliqués', 'Settings applied'), reload);
  }

  Widget _versionSection(BuildContext context, String min, Future<void> Function() reload) {
    Future<void> change() async {
      final ctl = TextEditingController(text: min);
      final v = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('Version minimale', 'Minimum version')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                t('Les applis plus anciennes affichent une fenêtre bloquante avec le bouton de téléchargement (web : recharger).',
                    'Older apps show a blocking window with the download button (web: reload).'),
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 10),
            TextField(controller: ctl, autofocus: true, decoration: const InputDecoration(hintText: '1.0.12')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Annuler', 'Cancel'))),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('OK')),
          ],
        ),
      );
      if (v == null || v.isEmpty || v == min) return;
      await _run(() => RcServer.adminSetConfig('min_version', v), t('Version minimale : $v', 'Minimum version: $v'), reload);
    }

    return _section(t('📱 Version minimale', '📱 Minimum version'),
        t('Les APK plus anciens doivent se mettre à jour pour jouer (fenêtre bloquante avec le bouton de téléchargement).',
            'Older APKs must update to play (blocking window with the download button).'),
        [
          Row(children: [
            _num(kRetroCollecVersion, t('actuelle', 'current')),
            _num(min, t('minimale', 'minimum')),
            const SizedBox(width: 6),
            ElevatedButton(onPressed: change, child: Text(t('Changer', 'Change'))),
          ]),
          const SizedBox(height: 6),
          Text(
              t('⚠️ Ne mets pas une version plus récente que le dernier APK publié, sinon personne ne pourra jouer.',
                  '⚠️ Never set a version newer than the latest published APK, or nobody can play.'),
              style: const TextStyle(color: _org, fontSize: 11.5)),
        ]);
  }
}

// ─── Bourse : offres en cours ───────────────────────────────────────────────

class AdminMarketPage extends StatefulWidget {
  const AdminMarketPage({super.key});
  @override
  State<AdminMarketPage> createState() => _AdminMarketPageState();
}

class _AdminMarketPageState extends State<AdminMarketPage> {
  final _ctl = TextEditingController();
  String _q = '';
  Key _key = UniqueKey();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(backgroundColor: kBg, title: Text(t('Offres de la Bourse', 'Market offers'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
          child: TextField(
            controller: _ctl,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: t('Vendeur (pseudo)…', 'Seller (name)…'),
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: kPanel,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            onSubmitted: (v) => setState(() {
              _q = v.trim();
              _key = UniqueKey();
            }),
          ),
        ),
        Expanded(
          child: _Loader<List<Map<String, dynamic>>>(
            key: _key,
            load: () => RcServer.adminMarket(_q),
            builder: (context, rows, reload) => ListView(padding: const EdgeInsets.all(10), children: [
              Text(t('${rows.length} offres · les plus chères par rapport au prix moyen d\'abord', '${rows.length} offers · most overpriced first'),
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 8),
              for (final m in rows) _offer(context, m, reload),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _offer(BuildContext context, Map<String, dynamic> m, Future<void> Function() reload) {
    final ratio = (m['ratio'] as num?)?.toDouble();
    final border = ratio != null && ratio >= 5 ? _red : ratio != null && ratio >= 3 ? _org : null;
    final card = '${_cardName(m['card'])}${_finish(m['f'])}';
    return _box(
      border: border,
      child: Row(children: [
        avatarWidget(_i(m['avatar']), size: 28),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(card, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
            Text(
                '${m['name']} · ${_i(m['price'])} 🪙${m['avg'] != null ? t(' (moy. ${_i(m['avg'])}', ' (avg ${_i(m['avg'])}') + (ratio != null ? ', ×${ratio.toString()}' : '') + ')' : ''} · ${_date(_d(m['at']))}',
                style: TextStyle(color: border ?? Colors.white60, fontSize: 12)),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.remove_shopping_cart, color: Color(0xFFFFC4CF)),
          tooltip: t('Retirer', 'Remove'),
          onPressed: () async {
            final ok = await _confirm(context, t('Retirer cette offre ?', 'Remove this offer?'),
                t('$card retourne dans la collection de ${m['name']}.', '$card goes back to ${m['name']}\'s collection.'),
                ok: t('Retirer', 'Remove'), danger: true);
            if (ok != true) return;
            await _run(() async {
              if (!await RcServer.adminMarketRemove(_i(m['id']))) throw RcError(t('déjà vendue ou retirée', 'already sold or removed'));
            }, t('Offre retirée', 'Offer removed'), reload);
          },
        ),
      ]),
    );
  }
}

// ─── Événements ─────────────────────────────────────────────────────────────

const _kEvColors = ['#EF9F27', '#E24B4A', '#5DCAA5', '#4FA3FF', '#B57BFF', '#FF4FD8', '#FFD166'];

Color _hex(String? s) {
  final h = (s ?? '').replaceAll('#', '');
  return Color(int.tryParse('FF${h.padLeft(6, '0')}', radix: 16) ?? 0xFFEF9F27);
}

class AdminEventsPage extends StatefulWidget {
  const AdminEventsPage({super.key});
  @override
  State<AdminEventsPage> createState() => _AdminEventsPageState();
}

class _AdminEventsPageState extends State<AdminEventsPage> {
  Key _key = UniqueKey();

  void _refresh() => setState(() => _key = UniqueKey());

  Future<void> _edit([Map<String, dynamic>? e]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _EventEditor(event: e)));
    if (saved == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(backgroundColor: kBg, title: Text(t('Événements', 'Events'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        backgroundColor: kGold,
        foregroundColor: const Color(0xFF2A1800),
        icon: const Icon(Icons.add),
        label: Text(t('Nouvel événement', 'New event'), style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: _Loader<List<Map<String, dynamic>>>(
        key: _key,
        load: RcServer.adminEvents,
        builder: (context, rows, reload) {
          final live = rows.where((e) => e['live'] == true).toList();
          final next = rows.where((e) => e['upcoming'] == true).toList();
          final other = rows.where((e) => e['live'] != true && e['upcoming'] != true).toList();
          Widget group(String title, List<Map<String, dynamic>> l) => l.isEmpty
              ? const SizedBox.shrink()
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                    child: Text(title, style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w900)),
                  ),
                  for (final e in l) _row(e, reload),
                ]);
          return ListView(padding: const EdgeInsets.fromLTRB(10, 0, 10, 90), children: [
            group(t('En cours', 'Live'), live),
            group(t('À venir', 'Upcoming'), next),
            group(t('Terminés (7 j) ou désactivés', 'Ended (7 d) or disabled'), other),
            if (rows.isEmpty) Padding(padding: const EdgeInsets.all(30), child: Center(child: Text(t('Aucun événement', 'No event')))),
          ]);
        },
      ),
    );
  }

  Widget _row(Map<String, dynamic> e, Future<void> Function() reload) {
    final active = e['active'] == true;
    final kind = switch (e['kind']) {
      'effect' => t('effet', 'effect'),
      'goal' => t('défi', 'challenge'),
      _ => _i(e['coins']) > 0 || _i(e['pixels']) > 0 ? t('cadeau', 'gift') : 'info',
    };
    final when = '${_date(_d(e['starts_at']))} → ${e['ends_at'] == null ? '∞' : _date(_d(e['ends_at']))}';
    return Opacity(
      opacity: active ? 1 : 0.5,
      child: _box(
        border: _hex(e['color']?.toString()).withOpacity(0.7),
        onTap: () => _edit(e),
        child: Row(children: [
          Text(e['icon']?.toString() ?? '🎉', style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w900)),
              Text('$kind · $when${_i(e['got']) > 0 ? t(' · récupéré ${_i(e['got'])} fois', ' · claimed ${_i(e['got'])}×') : ''}',
                  style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
            ]),
          ),
          Switch(
            value: active,
            activeColor: kGold,
            onChanged: (v) => _run(() => RcServer.adminEventActive(_i(e['id']), v),
                v ? t('Événement activé', 'Event enabled') : t('Événement désactivé', 'Event disabled'), reload),
          ),
        ]),
      ),
    );
  }
}

class _EventEditor extends StatefulWidget {
  final Map<String, dynamic>? event;
  const _EventEditor({this.event});
  @override
  State<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<_EventEditor> {
  late String kind, color, effect, goal, action;
  late final TextEditingController icon, title, body, titleEn, bodyEn, coins, pixels, effectValue, decor;
  late DateTime start;
  DateTime? end;
  final steps = <(TextEditingController, TextEditingController, TextEditingController)>[];
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.event ?? const <String, dynamic>{};
    String s(String k, [String d = '']) => e[k]?.toString() ?? d;
    kind = s('kind', 'info');
    color = s('color', '#EF9F27');
    effect = s('effect', 'pixels_x2');
    goal = s('goal', 'packs');
    action = s('action');
    if (!const ['', 'packs', 'collection', 'bonus', 'market', 'messages', 'neighbors', 'news'].contains(action)) action = '';
    if (!const ['pixels_x2', 'free_fast'].contains(effect)) effect = 'pixels_x2';
    if (!const ['packs', 'c4_wins', 'bs_wins', 'gamedle'].contains(goal)) goal = 'packs';
    if (!const ['info', 'effect', 'goal'].contains(kind)) kind = 'info';
    icon = TextEditingController(text: s('icon', '🎉'));
    title = TextEditingController(text: s('title'));
    body = TextEditingController(text: s('body'));
    titleEn = TextEditingController(text: s('title_en'));
    bodyEn = TextEditingController(text: s('body_en'));
    coins = TextEditingController(text: '${_i(e['coins'])}');
    pixels = TextEditingController(text: '${_i(e['pixels'])}');
    effectValue = TextEditingController(text: e['effect_value'] == null ? '' : '${_i(e['effect_value'])}');
    decor = TextEditingController(text: s('decor'));
    final now = DateTime.now();
    start = _d(e['starts_at']) ?? DateTime(now.year, now.month, now.day, now.hour + 1);
    end = e.isEmpty ? start.add(const Duration(days: 2)) : _d(e['ends_at']);
    for (final st in (e['steps'] as List? ?? const [])) {
      if (st is Map) _addStep(_i(st['n']), _i(st['coins']), _i(st['pixels']));
    }
    if (steps.isEmpty) _addStep(5, 100, 0);
  }

  void _addStep(int n, int c, int p) => steps.add((
        TextEditingController(text: '$n'),
        TextEditingController(text: '$c'),
        TextEditingController(text: '$p'),
      ));

  Future<DateTime?> _pick(DateTime initial) async {
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 400)),
    );
    if (d == null || !mounted) return null;
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (tm == null) return null;
    return DateTime(d.year, d.month, d.day, tm.hour, tm.minute);
  }

  Future<void> _save() async {
    final data = <String, dynamic>{
      'kind': kind,
      'icon': icon.text.trim(),
      'title': title.text.trim(),
      'body': body.text.trim(),
      'title_en': titleEn.text.trim(),
      'body_en': bodyEn.text.trim(),
      'color': color,
      'decor': decor.text.trim(),
      'starts_at': start.toUtc().toIso8601String(),
      'ends_at': end?.toUtc().toIso8601String(),
      'action': action,
      'active': widget.event == null ? true : widget.event!['active'] == true,
      if (kind == 'info') 'coins': int.tryParse(coins.text.trim()) ?? 0,
      if (kind == 'info') 'pixels': int.tryParse(pixels.text.trim()) ?? 0,
      if (kind == 'effect') 'effect': effect,
      if (kind == 'effect') 'effect_value': effectValue.text.trim(),
      if (kind == 'goal') 'goal': goal,
      if (kind == 'goal')
        'steps': [
          for (final (n, c, p) in steps)
            if ((int.tryParse(n.text.trim()) ?? 0) > 0)
              {'n': int.tryParse(n.text.trim()) ?? 0, 'coins': int.tryParse(c.text.trim()) ?? 0, 'pixels': int.tryParse(p.text.trim()) ?? 0},
        ],
    };
    setState(() => busy = true);
    try {
      await RcServer.adminEventSave(widget.event == null ? null : _i(widget.event!['id']), data);
      toast(t('Événement enregistré', 'Event saved'));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      toast(errText(e));
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget gap() => const SizedBox(height: 10);
    Widget dateBtn(String label, DateTime? d, ValueChanged<DateTime?> set, {bool clearable = false}) => Row(children: [
          SizedBox(width: 60, child: Text(label, style: const TextStyle(color: Colors.white70))),
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                final v = await _pick(d ?? start.add(const Duration(days: 2)));
                if (v != null) setState(() => set(v));
              },
              child: Text(d == null ? t('sans fin', 'no end') : _date(d)),
            ),
          ),
          if (clearable && d != null) IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => set(null))),
        ]);
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        title: Text(widget.event == null ? t('Nouvel événement', 'New event') : t('Modifier', 'Edit')),
        actions: [
          TextButton(
            onPressed: busy ? null : _save,
            child: Text(t('Enregistrer', 'Save'), style: const TextStyle(color: kGold, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'info', label: Text(t('Info / cadeau', 'Info / gift'))),
            ButtonSegment(value: 'effect', label: Text(t('Effet', 'Effect'))),
            ButtonSegment(value: 'goal', label: Text(t('Défi', 'Challenge'))),
          ],
          selected: {kind},
          onSelectionChanged: (s) => setState(() => kind = s.first),
        ),
        gap(),
        Row(children: [
          SizedBox(width: 70, child: TextField(controller: icon, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22), decoration: _field(t('Icône', 'Icon')))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: title, maxLength: 60, decoration: _field(t('Titre', 'Title')))),
        ]),
        TextField(controller: body, maxLength: 600, minLines: 2, maxLines: 6, decoration: _field(t('Texte', 'Text'))),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(t('Version anglaise (facultative)', 'English version (optional)'), style: const TextStyle(fontSize: 13.5, color: Colors.white70)),
          children: [
            TextField(controller: titleEn, maxLength: 60, decoration: _field('Title (EN)')),
            TextField(controller: bodyEn, maxLength: 600, minLines: 2, maxLines: 6, decoration: _field('Text (EN)')),
          ],
        ),
        dateBtn(t('Début', 'Start'), start, (v) => start = v ?? start),
        const SizedBox(height: 6),
        dateBtn(t('Fin', 'End'), end, (v) => end = v, clearable: true),
        gap(),
        Text(t('Couleur', 'Color'), style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final c in _kEvColors)
            GestureDetector(
              onTap: () => setState(() => color = c),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _hex(c),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.toUpperCase() == c.toUpperCase() ? Colors.white : Colors.transparent, width: 3),
                ),
              ),
            ),
        ]),
        gap(),
        TextField(controller: decor, maxLength: 4, decoration: _field(t('Décor de l\'affiche (émoji, facultatif)', 'Poster decor (emoji, optional)'))),
        DropdownButtonFormField<String>(
          value: action,
          decoration: _field(t('Bouton « Y aller »', '"Go" button')),
          items: [
            DropdownMenuItem(value: '', child: Text(t('aucun', 'none'))),
            DropdownMenuItem(value: 'packs', child: Text(t('Paquets', 'Packs'))),
            DropdownMenuItem(value: 'collection', child: Text(t('Collection', 'Collection'))),
            DropdownMenuItem(value: 'bonus', child: Text(t('Bonus et jeux', 'Bonus & games'))),
            DropdownMenuItem(value: 'market', child: Text(t('Bourse', 'Market'))),
            DropdownMenuItem(value: 'messages', child: Text(t('Messages', 'Messages'))),
            DropdownMenuItem(value: 'neighbors', child: Text(t('Voisinage', 'Neighbors'))),
            DropdownMenuItem(value: 'news', child: Text(t('Actu', 'News'))),
          ],
          onChanged: (v) => setState(() => action = v ?? ''),
        ),
        gap(),
        if (kind == 'info') ...[
          Text(t('Récompense à récupérer (0 = simple info)', 'Reward to collect (0 = plain info)'), style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: TextField(controller: coins, keyboardType: TextInputType.number, decoration: _field('🪙'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: pixels, keyboardType: TextInputType.number, decoration: _field('▦'))),
          ]),
        ],
        if (kind == 'effect') ...[
          DropdownButtonFormField<String>(
            value: effect,
            decoration: _field(t('Effet', 'Effect')),
            items: [
              DropdownMenuItem(value: 'pixels_x2', child: Text(t('Pixels multipliés (par booster)', 'Pixels multiplied (per booster)'))),
              DropdownMenuItem(value: 'free_fast', child: Text(t('Paquet gratuit plus fréquent', 'Faster free pack'))),
            ],
            onChanged: (v) => setState(() => effect = v ?? 'pixels_x2'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: effectValue,
            keyboardType: TextInputType.number,
            decoration: _field(effect == 'pixels_x2' ? t('Multiplicateur (vide = ×2)', 'Multiplier (empty = ×2)') : t('Toutes les X heures (vide = 3)', 'Every X hours (empty = 3)')),
          ),
        ],
        if (kind == 'goal') ...[
          DropdownButtonFormField<String>(
            value: goal,
            decoration: _field(t('À compter', 'Counted')),
            items: [
              DropdownMenuItem(value: 'packs', child: Text(t('Boosters ouverts', 'Boosters opened'))),
              DropdownMenuItem(value: 'c4_wins', child: Text(t('Parties de 4 en ligne gagnées', 'Connect 4 wins'))),
              DropdownMenuItem(value: 'bs_wins', child: Text(t('Parties de Console Wars gagnées', 'Console Wars wins'))),
              DropdownMenuItem(value: 'gamedle', child: Text(t('Gamedle trouvés', 'Gamedles solved'))),
            ],
            onChanged: (v) => setState(() => goal = v ?? 'packs'),
          ),
          const SizedBox(height: 10),
          Text(t('Paliers', 'Steps'), style: const TextStyle(color: Colors.white70)),
          for (final (i, (n, c, p)) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Expanded(child: TextField(controller: n, keyboardType: TextInputType.number, decoration: _field(t('nombre', 'count')))),
                const SizedBox(width: 6),
                Expanded(child: TextField(controller: c, keyboardType: TextInputType.number, decoration: _field('🪙'))),
                const SizedBox(width: 6),
                Expanded(child: TextField(controller: p, keyboardType: TextInputType.number, decoration: _field('▦'))),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.white54),
                  onPressed: steps.length <= 1 ? null : () => setState(() => steps.removeAt(i)),
                ),
              ]),
            ),
          if (steps.length < 6)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _addStep(0, 0, 0)),
                icon: const Icon(Icons.add),
                label: Text(t('Ajouter un palier', 'Add a step')),
              ),
            ),
        ],
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: busy ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800), padding: const EdgeInsets.symmetric(vertical: 14)),
          child: Text(t('Enregistrer', 'Save'), style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
      ]),
    );
  }
}
