import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio.dart';
import 'game.dart';
import 'layout.dart';
import 'main.dart';
import 'notifs.dart';
import 'profile.dart';
import 'retro_theme.dart';
import 'server.dart';
import 'share.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Parrainage : mon code (PT-XXXXXX), mes filleuls, et le code de mon parrain.
// Quand un filleul a ouvert 5 paquets et joué 2 jours différents, on reçoit
// chacun un paquet premium (dans le stock). 10 filleuls au plus.
// SQL : patch_social.sql
// ═══════════════════════════════════════════════════════════════════════════

const kRefPacks = 5, kRefDays = 2;

/// Mon code, calculé comme sur le serveur (rc__ref_code)
String myRefCode() {
  final p = Game.i.pid;
  return p.length < 6 ? '' : 'PT-${p.substring(0, 6).toUpperCase()}';
}

/// Message à afficher selon la réponse du serveur à un code entré
String refResultText(String? res, Map<String, dynamic> r) => switch (res) {
      'ok' => t('🤝 C\'est noté ! Ouvre $kRefPacks paquets et reviens jouer un autre jour : ton parrain et toi recevrez chacun un paquet premium.',
          '🤝 Done! Open $kRefPacks packs and come back another day: you and your sponsor will each get a premium pack.'),
      'late' => t('Le code parrain se met pendant la première semaine seulement', 'Sponsor codes can only be entered during your first week'),
      'already' => t('Tu as déjà un parrain', 'You already have a sponsor'),
      'self' => t('Tu ne peux pas être ton propre parrain (ni celui de ton parrain)', 'You can\'t sponsor yourself (or your own sponsor)'),
      'full' => t('Ce joueur a déjà 10 filleuls', 'This player already has 10 referrals'),
      _ => t('Code inconnu', 'Unknown code'),
    };

/// Petit message après avoir entré un code
void refToast(String? res, Map<String, dynamic> r) => toast(refResultText(res, r));

class ReferralPage extends StatefulWidget {
  const ReferralPage({super.key});
  @override
  State<ReferralPage> createState() => _ReferralPageState();
}

class _ReferralPageState extends State<ReferralPage> {
  Map<String, dynamic>? data;
  bool error = false, busy = false;
  final code = TextEditingController();

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await RcServer.refInfo();
      if (mounted) {
        setState(() {
          data = r;
          error = false;
        });
      }
    } catch (_) {
      if (mounted && data == null) setState(() => error = true);
    }
  }

  Future<void> _enter() async {
    final c = code.text.trim();
    if (c.isEmpty || busy) return;
    setState(() => busy = true);
    try {
      final r = await RcServer.refSet(c);
      final res = r['res'] as String?;
      if (res == 'ok') RcAudio.sfx('powerup');
      toast(refResultText(res, r));
      if (mounted) setState(() => data = r);
      Notifs.i.refresh();
    } catch (e) {
      toast(errText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaxWidth(
      child: Scaffold(
        appBar: AppBar(title: Text(t('Parrainage', 'Referral'))),
        body: data == null
            ? Center(
                child: error
                    ? Text(t('Pas de connexion au serveur', 'No connection to the server'), style: const TextStyle(color: Colors.white54))
                    : const CircularProgressIndicator(color: kGold))
            : RefreshIndicator(onRefresh: load, child: _body()),
      ),
    );
  }

  Widget _body() {
    final d = data!;
    final my = d['code'] as String? ?? myRefCode();
    final kids = [for (final k in (d['kids'] as List? ?? const [])) Map<String, dynamic>.from(k as Map)];
    final max = (d['max'] as num? ?? 10).toInt();
    final sponsor = d['sponsor'] is Map ? Map<String, dynamic>.from(d['sponsor'] as Map) : null;
    const pink = Color(0xFFFF8AD8);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
      // mon code
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4A1F5E), Color(0xFF1D2350)]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: pink, width: 1.5),
        ),
        child: Column(children: [
          const Text('🤝', style: TextStyle(fontSize: 38)),
          Text(t('Invite tes amis', 'Invite your friends'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              Clipboard.setData(ClipboardData(text: my));
              toast(t('Code copié', 'Code copied'));
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(my, style: pixelStyle(size: 15, color: const Color(0xFFFAC775))),
                const SizedBox(width: 10),
                const Icon(Icons.copy, size: 16, color: Colors.white54),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: pink, foregroundColor: const Color(0xFF2A0020)),
              icon: const Icon(Icons.share, size: 18),
              label: Text(t('Partager le jeu avec mon code', 'Share the game with my code'), style: const TextStyle(fontWeight: FontWeight.w900)),
              onPressed: shareGame,
            ),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(14)),
        child: Text(
          t('1. Ton ami installe le jeu et entre ton code (pendant sa première semaine).\n'
              '2. Quand il a ouvert $kRefPacks paquets (gratuits compris) et joué $kRefDays jours différents, vous recevez chacun un paquet premium 🎁 dans le stock.\n'
              'Jusqu\'à $max filleuls.',
              '1. Your friend installs the game and enters your code (during their first week).\n'
              '2. Once they have opened $kRefPacks packs (free ones count) and played on $kRefDays different days, you each get a premium pack 🎁 in your stock.\n'
              'Up to $max referrals.'),
          style: const TextStyle(fontSize: 13.5, height: 1.5),
        ),
      ),
      const SizedBox(height: 18),
      Text(t('Mes filleuls · ${kids.length}/$max', 'My referrals · ${kids.length}/$max'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 6),
      if (kids.isEmpty)
        Text(t('Personne pour l\'instant : partage ton code !', 'Nobody yet: share your code!'), style: const TextStyle(color: Colors.white38, fontSize: 13)),
      for (final k in kids) _kid(k),
      const SizedBox(height: 18),
      if (sponsor != null) ...[
        Text(t('Mon parrain', 'My sponsor'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 6),
        _row(
          (sponsor['avatar'] as num? ?? 0).toInt(),
          sponsor['name'] as String? ?? '?',
          d['paid'] == true
              ? Text(t('✓ Paquet reçu', '✓ Pack received'), style: const TextStyle(color: Color(0xFF5DCAA5), fontWeight: FontWeight.w800, fontSize: 12))
              : _progress((d['packs'] as num? ?? 0).toInt(), (d['days'] as num? ?? 0).toInt()),
          pid: sponsor['pid'] as String?,
        ),
      ] else if (d['can_enter'] == true) ...[
        Text(t('Tu as un code ?', 'Got a code?'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        Text(t('Pendant ta première semaine seulement', 'During your first week only'), style: const TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: code,
              enabled: !busy,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: t('Code de ton parrain (PT-…)', 'Your sponsor\'s code (PT-…)'),
                isDense: true,
                filled: true,
                fillColor: const Color(0x33000000),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onSubmitted: (_) => _enter(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
            onPressed: busy ? null : _enter,
            child: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(t('Valider', 'OK'), style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ]),
      ],
    ]);
  }

  Widget _progress(int packs, int days) => Text(
        t('${packs.clamp(0, kRefPacks)}/$kRefPacks paquets · ${days.clamp(0, kRefDays)}/$kRefDays jours',
            '${packs.clamp(0, kRefPacks)}/$kRefPacks packs · ${days.clamp(0, kRefDays)}/$kRefDays days'),
        textAlign: TextAlign.right,
        style: const TextStyle(color: Colors.white60, fontSize: 12),
      );

  Widget _kid(Map<String, dynamic> k) => _row(
        (k['avatar'] as num? ?? 0).toInt(),
        k['name'] as String? ?? '?',
        k['paid'] == true
            ? Text(t('✓ Paquet reçu', '✓ Pack received'), style: const TextStyle(color: Color(0xFF5DCAA5), fontWeight: FontWeight.w800, fontSize: 12))
            : _progress((k['packs'] as num? ?? 0).toInt(), (k['days'] as num? ?? 0).toInt()),
        pid: k['pid'] as String?,
      );

  Widget _row(int avatar, String name, Widget right, {String? pid}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: kPanel,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: pid == null ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerProfilePage(pid: pid))),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(children: [
                avatarWidget(avatar, size: 32),
                const SizedBox(width: 10),
                Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                right,
              ]),
            ),
          ),
        ),
      );
}

/// Case du panneau latéral, sous « Partager »
class ReferralMenuTile extends StatelessWidget {
  final bool compact;
  final VoidCallback? beforeOpen;
  const ReferralMenuTile({super.key, this.compact = false, this.beforeOpen});

  @override
  Widget build(BuildContext context) {
    const violet = Color(0xFFB08CFF);
    void go() {
      final nav = Navigator.of(context);
      beforeOpen?.call();
      nav.push(MaterialPageRoute(builder: (_) => const ReferralPage()));
    }

    if (compact) {
      return Tooltip(
        message: t('Parrainage', 'Referral'),
        child: InkWell(
          onTap: go,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [
              const Text('🤝', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 2),
              Text(t('Parrainage', 'Referral'), style: const TextStyle(fontSize: 10.5, color: Colors.white60)),
            ]),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: violet.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: go,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: violet.withOpacity(0.6))),
            child: Row(children: [
              const Text('🤝', style: TextStyle(fontSize: 17)),
              const SizedBox(width: 10),
              Expanded(child: Text(t('Parrainage', 'Referral'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ]),
          ),
        ),
      ),
    );
  }
}
