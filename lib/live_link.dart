import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Realtime (Supabase Broadcast) : le serveur prévient l'appli dès qu'un duel
// qui me concerne change (défi reçu, réponse, coup joué, fin de partie…).
//  · un canal public par joueur, nommé à partir du device SECRET
//    (rc__rt_topic côté SQL : 'rc_' + sha256('rt|' + device)[0..24]) ;
//    jamais à partir du pid, qui est public.
//  · message reçu : {game: 'c4' | 'bs', gid, status} → les écrans concernés
//    rechargent tout de suite (DuelWatch, salon, page de partie).
//  · [connected] vrai seulement quand l'abonnement est accepté ET qu'un message a
//    déjà été reçu (preuve que la chaîne marche) : les écrans passent alors en
//    polling lent de secours, sinon ils gardent le rythme normal.
// Protocole Phoenix (vsn 1.0.0) : phx_join, heartbeat toutes les 25 s,
// reconnexion automatique (2 s → 30 s).
// ═══════════════════════════════════════════════════════════════════════════

class LiveLink {
  LiveLink._();
  static final i = LiveLink._();

  final _events = StreamController<Map<String, dynamic>>.broadcast();

  /// Événements de duel reçus : {game, gid, status}.
  Stream<Map<String, dynamic>> get events => _events.stream;

  bool _joined = false, _proven = false;

  /// Realtime branché et prouvé (au moins un message reçu dans cette session).
  bool get connected => _joined && _proven;

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _beat, _retry;
  bool _wanted = false;
  int _ref = 0, _fails = 0;
  String? _topic;

  static String topicOf(String device) =>
      'rc_${sha256.convert(utf8.encode('rt|$device')).toString().substring(0, 24)}';

  /// Ouvre la connexion (sans effet si déjà ouverte).
  Future<void> start() async {
    _wanted = true;
    if (_ch != null) return;
    _retry?.cancel();
    try {
      _topic = 'realtime:${topicOf(await RcServer.deviceId())}';
      final ws = kRcUrl.replaceFirst('https://', 'wss://');
      final ch = WebSocketChannel.connect(Uri.parse('$ws/realtime/v1/websocket?apikey=$kRcKey&vsn=1.0.0'));
      _ch = ch;
      _sub = ch.stream.listen(_onMsg, onError: (_) => _drop(), onDone: _drop, cancelOnError: true);
      _send(_topic!, 'phx_join', {
        'config': {
          'broadcast': {'ack': false, 'self': false},
          'presence': {'key': ''},
          'postgres_changes': [],
          'private': false,
        },
      });
      _beat?.cancel();
      _beat = Timer.periodic(const Duration(seconds: 25), (_) => _send('phoenix', 'heartbeat', {}));
    } catch (_) {
      _drop();
    }
  }

  /// Ferme la connexion (appli en arrière-plan).
  void stop() {
    _wanted = false;
    _retry?.cancel();
    _close();
  }

  void _send(String topic, String event, Map<String, dynamic> payload) {
    try {
      _ref++;
      _ch?.sink.add(jsonEncode({'topic': topic, 'event': event, 'payload': payload, 'ref': '$_ref', 'join_ref': '1'}));
    } catch (_) {}
  }

  void _onMsg(dynamic raw) {
    Map<String, dynamic> m;
    try {
      m = Map<String, dynamic>.from(jsonDecode(raw as String) as Map);
    } catch (_) {
      return;
    }
    final ev = m['event'];
    final p = m['payload'];
    if (m['topic'] != _topic) return;
    if (ev == 'phx_reply' && p is Map && m['ref'] == '1') {
      // réponse à l'abonnement (premier message envoyé sur cette connexion)
      _joined = p['status'] == 'ok';
      if (_joined) _fails = 0;
    } else if (ev == 'broadcast' && p is Map && p['event'] == 'duel' && p['payload'] is Map) {
      _proven = true;
      _events.add(Map<String, dynamic>.from(p['payload'] as Map));
    } else if (ev == 'phx_error' || ev == 'phx_close') {
      _drop();
    }
  }

  void _close() {
    _joined = false;
    _beat?.cancel();
    _sub?.cancel();
    _sub = null;
    try {
      _ch?.sink.close();
    } catch (_) {}
    _ch = null;
    _ref = 0;
  }

  void _drop() {
    _close();
    if (!_wanted) return;
    _fails++;
    final int s = _fails < 5 ? 2 << (_fails - 1) : 30; // 2, 4, 8, 16 puis 30 s
    _retry?.cancel();
    _retry = Timer(Duration(seconds: s), start);
  }
}
