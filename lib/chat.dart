import 'dart:async';

import 'package:flutter/material.dart';

import 'admin.dart';
import 'audio.dart';
import 'game.dart';
import 'live_link.dart';
import 'main.dart';
import 'notifs.dart';
import 'profile.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Messages : chat public entre joueurs (comme Rétro Jump).
//  · rafraîchi toutes les 8 s tant que l'écran est affiché
//  · filtre de mots, liens et numéros masqués côté serveur
//  · appui long sur un message = signaler ; toucher un pseudo = sa fiche
//  · @pseudo : suggestions en tapant @, mention en doré, notification
//  · @tous (admin seulement, vérifié par le serveur) : mention de tous les joueurs
// ═══════════════════════════════════════════════════════════════════════════

const kChatMax = 120;

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});
  @override
  State<MessagesScreen> createState() => MessagesScreenState();
}

class MessagesScreenState extends State<MessagesScreen> {
  static MessagesScreenState? current;
  final msgs = <Map<String, dynamic>>[];
  final _ctl = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  Timer? _timer;
  bool _loaded = false, _sending = false;
  String? _error;
  List<String> _names = []; // pseudos connus (suggestions @)
  List<String> _suggest = [];

  int get _last => msgs.isEmpty ? 0 : (msgs.last['id'] as num).toInt();

  @override
  void initState() {
    super.initState();
    current = this;
    _ctl.addListener(_onType);
    checkAdmin(); // @tous proposé seulement à l'admin
    RcServer.board().then((r) {
      _names = {..._names, for (final p in r) p['name'] as String? ?? ''}.where((n) => n.isNotEmpty).toList();
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    Notifs.i.chatOpen = false;
    if (current == this) current = null;
    _ctl.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Écran affiché ou quitté (appelé par le menu)
  void active(bool on) {
    Notifs.i.chatOpen = on;
    _timer?.cancel();
    if (on) {
      Notifs.i.chatRead();
      load();
      var n = 0; // temps réel branché : secours toutes les 40 s au lieu de 8 s
      _timer = Timer.periodic(const Duration(seconds: 8), (_) {
        if (!LiveLink.i.connected || (n++) % 5 == 0) load();
      });
    } else {
      _focus.unfocus();
    }
  }

  Future<void> load() async {
    try {
      final r0 = await RcServer.chatList(_last);
      if (!mounted) return;
      // deux chargements en même temps (envoi + temps réel) : on ne garde que les messages pas encore affichés
      final after = _last;
      final r = [for (final m in r0) if ((m['id'] as num? ?? 0).toInt() > after) m];
      final atBottom = !_scroll.hasClients || _scroll.position.pixels >= _scroll.position.maxScrollExtent - 60;
      setState(() {
        msgs.addAll(r);
        if (msgs.length > 200) msgs.removeRange(0, msgs.length - 200);
        for (final m in r) {
          final n = m['name'] as String? ?? '';
          if (n.isNotEmpty && !_names.contains(n)) _names.add(n);
        }
        _loaded = true;
        _error = null;
      });
      Notifs.i.chatRead();
      if (r.isNotEmpty && (atBottom || r.any((m) => m['me'] == true))) _toBottom();
    } catch (e) {
      if (mounted && !_loaded) setState(() => _error = errText(e));
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  // Suggestions @pseudo : mot en cours commençant par @
  void _onType() {
    final txt = _ctl.text;
    final pos = _ctl.selection.baseOffset < 0 ? txt.length : _ctl.selection.baseOffset;
    final before = txt.substring(0, pos.clamp(0, txt.length));
    final m = RegExp(r'@(\S*)$').firstMatch(before);
    final typed = m == null ? '' : nameKey(m.group(1)!);
    final next = m == null
        ? <String>[]
        : [
            if (rcIsAdmin.value && 'tous'.startsWith(typed)) 'tous', // @tous : tout le monde (admin)
            ..._names.where((n) => n != Game.i.name && nameKey(n).startsWith(typed)).take(5),
          ];
    if (next.join('|') != _suggest.join('|')) setState(() => _suggest = next);
  }

  void _pick(String name) {
    final txt = _ctl.text;
    final pos = _ctl.selection.baseOffset < 0 ? txt.length : _ctl.selection.baseOffset;
    final before = txt.substring(0, pos);
    final start = before.lastIndexOf('@');
    final insert = '@${nameKey(name)} ';
    final out = txt.substring(0, start) + insert + txt.substring(pos);
    _ctl.value = TextEditingValue(text: out, selection: TextSelection.collapsed(offset: start + insert.length));
    setState(() => _suggest = []);
  }

  void mention(String name) {
    _ctl.text = '${_ctl.text.isEmpty || _ctl.text.endsWith(' ') ? _ctl.text : '${_ctl.text} '}@${nameKey(name)} ';
    _ctl.selection = TextSelection.collapsed(offset: _ctl.text.length);
    _focus.requestFocus();
  }

  Future<void> _send() async {
    final m = _ctl.text.trim();
    if (m.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await RcServer.chatSend(m);
      _ctl.clear();
      RcAudio.sfx('coin');
      await load();
      _toBottom();
    } catch (e) {
      toast(errText(e));
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _report(Map<String, dynamic> m) async {
    if (m['me'] == true) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Signaler ce message ?', 'Report this message?')),
        content: Text(t('Il sera masqué pour toi tout de suite, et pour tout le monde s\'il est signalé 3 fois.',
            'It will be hidden for you right away, and for everyone if reported 3 times.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Annuler', 'Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE24B4A)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Signaler', 'Report')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await RcServer.chatReport((m['id'] as num).toInt());
      setState(() => msgs.remove(m));
      toast(t('Message signalé, merci', 'Message reported, thanks'));
    } catch (e) {
      toast(errText(e));
    }
  }

  static const _nameColors = [
    Color(0xFF85B7EB), Color(0xFFED93B1), Color(0xFF9FE1CB), Color(0xFFFAC775),
    Color(0xFFB4A9FF), Color(0xFFF0997B), Color(0xFFC0DD97), Color(0xFF8FD3FF),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TabHeader(t('Messages', 'Messages'), icon: 'messages'),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
        child: Text(t('Sois sympa : appui long sur un message pour le signaler', 'Be nice: long-press a message to report it'),
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ),
      Expanded(child: _list()),
      if (_suggest.isNotEmpty)
        Container(
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final n in _suggest)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ActionChip(label: Text('@$n'), onPressed: () => _pick(n), backgroundColor: kPanel2),
              ),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _ctl,
              focusNode: _focus,
              maxLength: kChatMax,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: t('Écris un message… (@ pour citer)', 'Write a message… (@ to mention)'),
                counterText: '',
                isDense: true,
                filled: true,
                fillColor: const Color(0x33000000),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2A1800)))
                : const Icon(Icons.send),
          ),
        ]),
      ),
    ]);
  }

  Widget _list() {
    if (_error != null) {
      return Center(child: TextButton(onPressed: load, child: Text('$_error\n${t('Réessayer', 'Retry')}', textAlign: TextAlign.center)));
    }
    if (!_loaded) return const Center(child: CircularProgressIndicator(color: kGold));
    if (msgs.isEmpty) {
      return Center(child: Text(t('Aucun message : lance la discussion !', 'No messages yet: start the conversation!'), style: const TextStyle(color: Colors.white38)));
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      itemCount: msgs.length,
      itemBuilder: (_, i) {
        final m = msgs[i];
        final prev = i > 0 ? msgs[i - 1] : null;
        final at = DateTime.tryParse(m['at'] as String? ?? '')?.toLocal();
        final prevAt = DateTime.tryParse(prev?['at'] as String? ?? '')?.toLocal();
        final newDay = at != null && (prevAt == null || prevAt.day != at.day || prevAt.month != at.month);
        return Column(children: [
          if (newDay) _dayLabel(at),
          _bubble(m, at, sameAuthor: !newDay && prev?['pid'] == m['pid']),
        ]);
      },
    );
  }

  Widget _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    final txt = diff == 0
        ? t('Aujourd\'hui', 'Today')
        : diff == 1
            ? t('Hier', 'Yesterday')
            : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(txt, style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _bubble(Map<String, dynamic> m, DateTime? at, {bool sameAuthor = false}) {
    // largeur réelle de la liste (et pas de l'écran : en grand écran le chat n'occupe qu'une partie)
    return LayoutBuilder(builder: (context, box) => _bubbleIn(m, at, sameAuthor, box.maxWidth * (m['me'] == true ? 0.8 : 0.72)));
  }

  Widget _bubbleIn(Map<String, dynamic> m, DateTime? at, bool sameAuthor, double maxW) {
    final me = m['me'] == true;
    final name = m['name'] as String? ?? '?';
    final pid = m['pid'] as String? ?? '';
    final msg = m['msg'] as String? ?? '';
    final myKey = '@${nameKey(Game.i.name)}';
    final flat = msg.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}@]', unicode: true), '');
    final citesMe = !me && (flat.contains(myKey) || RegExp(r'@tous\b').hasMatch(msg.toLowerCase()));
    final nameColor = me ? kGold : _nameColors[pid.hashCode.abs() % _nameColors.length];
    final time = at == null ? '' : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

    final bubble = GestureDetector(
      onLongPress: () => _report(m),
      child: Container(
        constraints: BoxConstraints(maxWidth: maxW),
        padding: const EdgeInsets.fromLTRB(11, 7, 11, 6),
        decoration: BoxDecoration(
          color: me ? const Color(0xFF5A3A08) : kPanel,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(me ? 14 : 4),
            bottomRight: Radius.circular(me ? 4 : 14),
          ),
          border: Border.all(color: citesMe ? kGold : (me ? kGold.withOpacity(0.5) : Colors.white10), width: citesMe ? 1.6 : 1),
        ),
        child: IntrinsicWidth(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (!me && !sameAuthor)
            GestureDetector(
              onTap: pid.isEmpty ? null : () => _openPlayer(pid, name),
              child: Text(name, style: TextStyle(color: nameColor, fontWeight: FontWeight.w800, fontSize: 12.5)),
            ),
          _richMsg(msg),
          Align(
            alignment: Alignment.bottomRight,
            child: Text(time, style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ),
        ])),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: sameAuthor ? 2 : 6),
      child: Row(
        mainAxisAlignment: me ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!me)
            SizedBox(
              width: 38,
              child: sameAuthor
                  ? null
                  : GestureDetector(
                      onTap: pid.isEmpty ? null : () => _openPlayer(pid, name),
                      child: avatarWidget((m['avatar'] as num? ?? 0).toInt(), size: 32),
                    ),
            ),
          Flexible(child: bubble),
        ],
      ),
    );
  }

  /// Texte avec les @mentions colorées (la mienne en doré)
  Widget _richMsg(String msg) {
    final myKey = nameKey(Game.i.name);
    final spans = <TextSpan>[];
    msg.splitMapJoin(
      RegExp(r'@\S+'),
      onMatch: (mm) {
        final tag = mm.group(0)!;
        final mine = nameKey(tag.substring(1)) == myKey || nameKey(tag.substring(1)) == 'tous';
        spans.add(TextSpan(text: tag, style: TextStyle(color: mine ? kGold : const Color(0xFF8FD3FF), fontWeight: FontWeight.w800)));
        return '';
      },
      onNonMatch: (s) {
        spans.add(TextSpan(text: s));
        return '';
      },
    );
    return Text.rich(TextSpan(style: const TextStyle(color: Colors.white, fontSize: 14), children: spans));
  }

  void _openPlayer(String pid, String name) {
    if (pid == Game.i.pid) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: kBg,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.person),
            title: Text(t('Voir le profil de $name', 'View $name\'s profile')),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerProfilePage(pid: pid)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.alternate_email),
            title: Text(t('Mentionner', 'Mention')),
            onTap: () {
              Navigator.pop(ctx);
              mention(name);
            },
          ),
        ]),
      ),
    );
  }
}
