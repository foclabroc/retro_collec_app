import 'package:flutter/material.dart';

import 'game.dart';
import 'main.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Messages des duels (4 en ligne, Console Wars) : petit mot joint à un défi ou à
// une revanche, réponse rapide de l'invité, phrases rapides en partie.
// Les textes écrits sont filtrés côté serveur comme le chat (patch_duels_messages.sql).
// ═══════════════════════════════════════════════════════════════════════════

const kDuelMsgMax = 60;

List<String> get kDuelPhrases => [
      t('Une petite partie ? 🎮', 'Up for a game? 🎮'),
      t('Prépare-toi à perdre 😏', 'Get ready to lose 😏'),
      t('Revanche ! 🔥', 'Rematch! 🔥'),
      t('Bonne chance 🍀', 'Good luck 🍀'),
      t('Je t\'attends 😎', 'I\'m waiting 😎'),
    ];

List<String> get kReplyPhrases => [
      t('J\'arrive ! 👍', 'Coming! 👍'),
      t('Dans 5 minutes ⏳', 'In 5 minutes ⏳'),
      t('Pas maintenant 🙏', 'Not now 🙏'),
      t('Demain ? 📅', 'Tomorrow? 📅'),
    ];

/// Phrases rapides en partie (la liste est aussi vérifiée par le serveur : ne pas traduire)
const kGamePhrases = ['Bien joué !', 'Oups 😅', 'GG 🤝', 'Pas mal !'];

/// Une réaction est-elle une phrase (et pas un simple emoji) ?
bool isPhrase(String e) => e.runes.length > 2;

/// Bulle de texte blanche (message reçu)
class SayBubble extends StatelessWidget {
  final String text;
  final String? caption; // petite ligne sous la bulle (« Lulu a répondu »)
  const SayBubble(this.text, {super.key, this.caption});
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        CustomPaint(painter: _TipPainter(), size: const Size(16, 8)),
        Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))],
          ),
          child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF151515), fontWeight: FontWeight.w900, fontSize: 15)),
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(caption!, style: const TextStyle(color: Colors.white54, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ),
      ]);
}

class _TipPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawPath(
        Path()
          ..moveTo(s.width / 2, 0)
          ..lineTo(s.width, s.height)
          ..lineTo(0, s.height)
          ..close(),
        Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Petite ligne « 💬 message » dans une carte du salon
class SayLine extends StatelessWidget {
  final String text;
  final String? who;
  const SayLine(this.text, {super.key, this.who});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: Text('💬 ${who == null ? '' : '$who : '}$text',
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF151515), fontWeight: FontWeight.w800, fontSize: 12)),
        ),
      );
}

/// Fenêtre pour écrire un petit texte (60 caractères)
Future<String?> writeDuelText(BuildContext context, String title) async {
  final ctl = TextEditingController();
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        maxLength: kDuelMsgMax,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: t('Ton message…', 'Your message…')),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Annuler', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: Text(t('Envoyer', 'Send'))),
      ],
    ),
  );
  ctl.dispose();
  return r == null || r.isEmpty ? null : r;
}

/// Avant d'envoyer un défi ou une revanche : un petit mot (facultatif).
/// Renvoie null si on annule, '' pour envoyer sans message, sinon le texte.
Future<String?> pickDuelMessage(BuildContext context, String title) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kBg.withOpacity(0.98),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _MsgSheet(title: title),
  );
}

class _MsgSheet extends StatefulWidget {
  final String title;
  const _MsgSheet({required this.title});
  @override
  State<_MsgSheet> createState() => _MsgSheetState();
}

class _MsgSheetState extends State<_MsgSheet> {
  final ctl = TextEditingController();

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cur = ctl.text.trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 10),
          Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          Text(t('Ajoute un petit mot (facultatif)', 'Add a short message (optional)'), style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in kDuelPhrases)
              ChoiceChip(
                label: Text(p, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                selected: cur == p,
                selectedColor: kGold.withOpacity(0.35),
                onSelected: (_) => setState(() {
                  ctl.text = p;
                  ctl.selection = TextSelection.collapsed(offset: p.length);
                }),
              ),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: ctl,
            maxLength: kDuelMsgMax,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: t('✏️ Écris ton message…', '✏️ Write your message…'),
              filled: true,
              fillColor: const Color(0x33000000),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800), padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () => Navigator.pop(context, cur),
            child: Text(t('Envoyer le défi', 'Send the challenge'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: Text(t('Envoyer sans message', 'Send without a message'), style: const TextStyle(color: Colors.white60)),
          ),
        ]),
      ),
    );
  }
}

/// Réponses rapides à un défi reçu (sans accepter ni refuser). [onSent] est appelé après l'envoi.
class ReplyChips extends StatelessWidget {
  final String game; // 'c4' ou 'bs'
  final int id;
  final String to; // nom de celui qui a lancé le défi
  final VoidCallback? onSent;
  const ReplyChips({super.key, required this.game, required this.id, required this.to, this.onSent});

  Future<void> _send(BuildContext context, String? text) async {
    if (text == null || text.isEmpty) return;
    try {
      await RcServer.duelReply(game, id, text);
      toast(t('Réponse envoyée à $to', 'Reply sent to $to'));
      onSent?.call();
    } catch (e) {
      toast(errText(e));
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
        for (final p in kReplyPhrases)
          ActionChip(
            label: Text(p, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
            visualDensity: VisualDensity.compact,
            onPressed: () => _send(context, p),
          ),
        ActionChip(
          label: Text(t('✏️ Écrire…', '✏️ Write…'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
          visualDensity: VisualDensity.compact,
          onPressed: () async => _send(context, await writeDuelText(context, t('Répondre à $to', 'Reply to $to'))),
        ),
      ]);
}

/// Grande réaction au milieu du plateau : l'emoji (ou la phrase) grossit, puis remonte en s'effaçant
class BigReaction extends StatelessWidget {
  final String emo, who;
  final int seq; // change à chaque réaction (relance l'animation)
  const BigReaction({super.key, required this.emo, required this.who, required this.seq});
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            key: ValueKey(seq),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 2600),
            builder: (_, v, __) {
              // 0 → 0.12 : apparaît en grossissant ; 0.75 → 1 : remonte et s'efface
              final scale = v < 0.12 ? Curves.easeOutBack.transform(v / 0.12) * 1.15 : (v < 0.22 ? 1.15 - (v - 0.12) * 1.5 : 1.0);
              final fade = v < 0.75 ? 1.0 : 1 - (v - 0.75) / 0.25;
              final up = v < 0.75 ? -18 * (v / 0.75) : -18 - 30 * ((v - 0.75) / 0.25);
              if (v >= 1) return const SizedBox.shrink();
              return Opacity(
                opacity: fade.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, up),
                  child: Transform.scale(
                    scale: scale.clamp(0.01, 2.0),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      isPhrase(emo)
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 14, offset: Offset(0, 6))],
                              ),
                              child: Text(emo, style: const TextStyle(color: Color(0xFF151515), fontWeight: FontWeight.w900, fontSize: 24)),
                            )
                          : Text(emo, style: const TextStyle(fontSize: 88, shadows: [Shadow(color: Colors.black54, blurRadius: 14, offset: Offset(0, 6))])),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), borderRadius: BorderRadius.circular(12)),
                        child: Text(who, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                      ),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      );
}

/// Barre des réactions en partie : 5 emojis (gros boutons) + phrases rapides
class ReactionBar extends StatelessWidget {
  final List<String> emotes;
  final void Function(String) onSend;
  const ReactionBar({super.key, required this.emotes, required this.onSend});
  @override
  Widget build(BuildContext context) => Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final e in emotes)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkResponse(
                onTap: () => onSend(e),
                radius: 28,
                child: Container(
                  width: 50,
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: kPanel, shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: 1.5)),
                  child: Text(e, style: const TextStyle(fontSize: 25)),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
          for (final p in kGamePhrases)
            ActionChip(
              label: Text(p, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
              visualDensity: VisualDensity.compact,
              onPressed: () => onSend(p),
            ),
        ]),
      ]);
}
