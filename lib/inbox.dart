import 'package:flutter/material.dart';

import 'audio.dart';
import 'game.dart';
import 'notifs.dart';
import 'rewards.dart';
import 'server.dart';

// ─────────────────────────────────────────────────────────────────────────────
// À l'ouverture du jeu : messages de l'admin (annonces, cadeaux) puis sondage.
// ─────────────────────────────────────────────────────────────────────────────

bool _inboxBusy = false;

Future<void> showInbox(BuildContext context) async {
  if (_inboxBusy) return;
  _inboxBusy = true;
  try {
    List<Map<String, dynamic>> mails = const [];
    try {
      mails = await RcServer.mailList();
    } catch (_) {}
    var gotSomething = false;
    for (final m in mails) {
      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (ctx) => _MailDialog(mail: m),
      );
      if (ok == true) gotSomething = true;
    }
    if (gotSomething) await Game.i.sync();
    Map<String, dynamic>? poll;
    try {
      poll = await RcServer.pollCurrent();
    } catch (_) {}
    if (poll != null && context.mounted) {
      final p = poll;
      await showDialog<void>(context: context, useRootNavigator: true, builder: (ctx) => _PollDialog(poll: p));
    }
  } finally {
    _inboxBusy = false;
  }
}

int _n(dynamic v) => (v as num?)?.toInt() ?? 0;

class _MailDialog extends StatefulWidget {
  final Map<String, dynamic> mail;
  const _MailDialog({required this.mail});
  @override
  State<_MailDialog> createState() => _MailDialogState();
}

class _MailDialogState extends State<_MailDialog> {
  bool busy = false;
  String? error;

  Map<String, dynamic> get m => widget.mail;
  /// Récompense complète : anciens champs (pièces, pixels, paquets premium) + « reward »
  Map<String, dynamic> get rw => rewardAdd(rewardOf(m), {'packs': {'premium': _n(m['packs'])}});
  bool get gift => rewardAny(rw);

  Future<void> _ok() async {
    setState(() => busy = true);
    try {
      await RcServer.mailRead(_n(m['id']));
      if (gift) RcAudio.sfx('coin');
      if (rewardHasPacks(rw)) Notifs.i.refresh();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = errText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = (m['body'] as String? ?? '').trim();
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: kBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: kGold, width: 1.5)),
        title: Column(children: [
          Text(gift ? '🎁' : '📢', style: const TextStyle(fontSize: 40)),
          const SizedBox(height: 6),
          Text(m['title']?.toString() ?? '', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (body.isNotEmpty) Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.35)),
          if (gift) ...[
            const SizedBox(height: 14),
            Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
              for (final p in rewardParts(rw)) _chip('+$p'),
            ]),
            if (rewardHasPacks(rw))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(t('Les paquets arrivent dans tes cadeaux.', 'Packs go to your gifts.'),
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ),
          ],
          if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
          const SizedBox(height: 6),
          Text('— Pixel Trade', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11.5)),
        ]),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: busy ? null : _ok,
            style: ElevatedButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
            child: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(gift ? t('Récupérer', 'Collect') : 'OK', style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Widget _chip(String s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: kGold.withOpacity(0.18), borderRadius: BorderRadius.circular(20), border: Border.all(color: kGold)),
        child: Text(s, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFFFD08A))),
      );
}

class _PollDialog extends StatefulWidget {
  final Map<String, dynamic> poll;
  const _PollDialog({required this.poll});
  @override
  State<_PollDialog> createState() => _PollDialogState();
}

class _PollDialogState extends State<_PollDialog> {
  int? chosen;
  Map<String, dynamic>? results;
  bool busy = false;
  String? error;

  List<String> get options => [for (final o in (widget.poll['options'] as List? ?? const [])) o.toString()];

  Future<void> _vote(int i) async {
    setState(() {
      busy = true;
      chosen = i;
    });
    try {
      final r = await RcServer.pollVote(_n(widget.poll['id']), i);
      if (mounted) setState(() => results = r);
    } catch (e) {
      if (mounted) setState(() => error = errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = results;
    final votes = [for (final v in (r?['votes'] as List? ?? const [])) _n(v)];
    final total = r == null ? 0 : _n(r['total']);
    return AlertDialog(
      backgroundColor: kBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: kGold, width: 1.5)),
      title: Column(children: [
        const Text('📊', style: TextStyle(fontSize: 36)),
        const SizedBox(height: 4),
        Text(t('Sondage', 'Poll'), style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(widget.poll['question']?.toString() ?? '', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, o) in options.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: r == null
                ? OutlinedButton(
                    onPressed: busy ? null : () => _vote(i),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: chosen == i ? kGold : Colors.white24, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(o, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                  )
                : _bar(o, i < votes.length ? votes[i] : 0, total, i == chosen),
          ),
        if (r != null)
          Text(t('$total vote${total > 1 ? 's' : ''} · merci !', '$total vote${total > 1 ? 's' : ''} · thanks!'),
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        if (error != null) Text(error!, style: const TextStyle(color: Colors.redAccent)),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(r == null ? t('Plus tard', 'Later') : t('Fermer', 'Close')),
        ),
      ],
    );
  }

  Widget _bar(String label, int n, int total, bool mine) {
    final f = total == 0 ? 0.0 : n / total;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: mine ? kGold : Colors.transparent, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        FractionallySizedBox(widthFactor: f, heightFactor: 1, child: Container(color: kGold.withOpacity(0.35))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))),
            Text('${(f * 100).round()} %', style: const TextStyle(fontWeight: FontWeight.w900)),
          ]),
        ),
      ]),
    );
  }
}
