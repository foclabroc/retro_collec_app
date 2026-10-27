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
// reconnexion automatique (1 s → 15 s). Le relais envoie 'hello' dès l'abonnement
// (preuve que la chaîne marche) et tient lui-même la présence « en ligne ».
// ═══════════════════════════════════════════════════════════════════════════

class LiveLink {
  LiveLink._();
  static final i = LiveLink._();

  final _events = StreamController<Map<String, dynamic>>.broadcast();

  /// Événements de duel reçus : {game, gid, status}.
  Stream<Map<String, dynamic>> get events => _events.stream;

  final _other = StreamController<Map<String, dynamic>>.broadcast();

  /// Autres événements (1.0.18) : {'ev': nom, …contenu}. Pas de données de jeu dedans,
  /// l'écran relit par les RPC habituelles (voir live_events.dart) :
  ///  · canal du joueur, 'me' {k} : trade / sale / gift / prog / react
  ///  · canal commun rc_all : chat, feed, market, config, online, duels, mail, events, player {pid}
  Stream<Map<String, dynamic>> get other => _other.stream;

  static const _all = 'realtime:rc_all';

  /// Partie regardée (spectateur) : son canal, rejoint en plus (et à chaque reconnexion)
  String? _watch;

  /// Duel Rétro Jump que je joue : canal de la partie (positions de l'adversaire, j'y envoie les miennes)
  String? _play;

  final _pos = StreamController<Map<String, dynamic>>.broadcast();

  /// Positions des joueurs d'un duel Rétro Jump ('rjpos', ≈ 10 par seconde) sur le canal
  /// de la partie jouée ou regardée : {s: camp, t: ms depuis le départ, x, h, r, sc, d}
  Stream<Map<String, dynamic>> get positions => _pos.stream;

  /// Jouer un duel Rétro Jump : rejoint le canal de la partie (sans être compté spectateur)
  void play(String game, int id) {
    unplay();
    _play = 'realtime:${watchTopicOf(game, id)}';
    if (_ch != null) _send(_play!, 'phx_join', _cfg);
  }

  void unplay() {
    final w = _play;
    _play = null;
    if (w != null && _ch != null) _send(w, 'phx_leave', {});
  }

  /// Ma position aux autres abonnés du canal de la partie (relayée sans passer par la base)
  void sendPos(Map<String, dynamic> p) {
    final topic = _play;
    if (topic == null || !_joined) return;
    try {
      _ch?.sink.add(jsonEncode({
        'topic': topic,
        'event': 'broadcast',
        'payload': {'type': 'broadcast', 'event': 'rjpos', 'payload': p},
        'ref': null,
      }));
    } catch (_) {}
  }

  static String watchTopicOf(String game, int id) =>
      'rc_${sha256.convert(utf8.encode('watch|$game|$id')).toString().substring(0, 24)}';

  static const _cfg = {
    'config': {
      'broadcast': {'ack': false, 'self': false},
      'presence': {'key': ''},
      'postgres_changes': [],
      'private': false,
    },
  };

  /// Regarder une partie : ses coups arrivent dans [events] comme ceux de mes duels.
  void watch(String game, int id) {
    unwatch();
    _watch = 'realtime:${watchTopicOf(game, id)}';
    if (_ch != null) _send(_watch!, 'phx_join', _cfg);
  }

  void unwatch() {
    final w = _watch;
    _watch = null;
    if (w != null && _ch != null) _send(w, 'phx_leave', {});
  }

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
      _send(_topic!, 'phx_join', _cfg); // ref 1 : mon canal (le relais le reconnaît comme celui du joueur)
      _send(_all, 'phx_join', _cfg); // ref 2 : canal commun
      if (_watch != null) _send(_watch!, 'phx_join', _cfg); // partie regardée
      if (_play != null) _send(_play!, 'phx_join', _cfg); // duel Rétro Jump en cours
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
    final topic = m['topic'];
    if (topic != _topic && topic != _all && topic != _watch && topic != _play) return;
    if (ev == 'phx_reply' && p is Map && m['ref'] == '1') {
      // réponse à l'abonnement à mon canal (premier message envoyé sur cette connexion)
      _joined = p['status'] == 'ok';
      if (_joined) _fails = 0;
    } else if (ev == 'broadcast' && p is Map && p['event'] == 'rjpos' && p['payload'] is Map) {
      if (topic == _play || topic == _watch) _pos.add(Map<String, dynamic>.from(p['payload'] as Map));
    } else if (ev == 'broadcast' && p is Map && p['event'] == 'duel' && p['payload'] is Map) {
      _proven = true;
      _events.add(Map<String, dynamic>.from(p['payload'] as Map));
    } else if (ev == 'broadcast' && p is Map && p['event'] is String) {
      _proven = true;
      _other.add({...(p['payload'] is Map ? Map<String, dynamic>.from(p['payload'] as Map) : const <String, dynamic>{}), 'ev': p['event']});
    } else if (topic == _topic && (ev == 'phx_error' || ev == 'phx_close')) {
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
    final int s = _fails < 5 ? 1 << (_fails - 1) : 15; // 1, 2, 4, 8 puis 15 s
    _retry?.cancel();
    _retry = Timer(Duration(seconds: s), start);
  }
}
