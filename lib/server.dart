import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// RÉTRO COLLEC — serveur Supabase (même projet que Rétro Jump, tables rc_*)
// Tout est décidé côté serveur (pièces, tirages, collection) : l'appli appelle
// les fonctions SQL rc_* avec une signature (même sel que le SQL).
// ═══════════════════════════════════════════════════════════════════════════

const kRcUrl = 'https://wwyxfcdubdnwokeanigk.supabase.co';
const kRcKey = 'sb_publishable_M1Rdee-lSEzCfq81zjYq5Q_NgJ0a35z';
const _salt = 'rc-collec#7b2e-foc'; // identique au SQL (rc__sig)
const _kDeviceKey = 'rc_device';

/// Erreur renvoyée par le serveur (message lisible : « pas assez de pièces »…)
/// ou hors ligne ([offline] = true).
class RcError implements Exception {
  final String message;
  final bool offline;
  const RcError(this.message, {this.offline = false});
  @override
  String toString() => message;
}

class RcServer {
  RcServer._();

  static String? _device;

  /// Identifiant secret du téléphone (32 caractères), créé au premier lancement.
  static Future<String> deviceId() async {
    if (_device != null) return _device!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kDeviceKey);
    if (id == null || id.length != 32) {
      final r = Random.secure();
      id = List.generate(32, (_) => '0123456789abcdef'[r.nextInt(16)]).join();
      await prefs.setString(_kDeviceKey, id);
    }
    return _device = id;
  }

  /// Identifiant public correspondant à un identifiant secret.
  static String pidOf(String device) => sha256.convert(utf8.encode(device)).toString().substring(0, 16);

  /// Code de sauvegarde lisible : 8 groupes de 4 caractères.
  static Future<String> backupCode() async {
    final d = await deviceId();
    return [for (var i = 0; i < 32; i += 4) d.substring(i, i + 4)].join('-').toUpperCase();
  }

  /// Restaure un profil à partir de son code de sauvegarde.
  /// Renvoie le pseudo du profil retrouvé, ou lève RcError si le code est invalide ou inconnu.
  static Future<String> restore(String code) async {
    final id = code.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
    if (id.length != 32) throw const RcError('code invalide');
    final p = await profile(pidOf(id));
    if (p == null) throw const RcError('code inconnu');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDeviceKey, id);
    _device = id;
    return p['name'] as String? ?? '?';
  }

  static String _sig(String s) => sha256.convert(utf8.encode('$_salt|$s')).toString();

  static Future<dynamic> _rpc(String fn, Map<String, dynamic> body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.openUrl('POST', Uri.parse('$kRcUrl/rest/v1/rpc/$fn')).timeout(const Duration(seconds: 10));
      req.headers.set('apikey', kRcKey);
      if (kRcKey.startsWith('eyJ')) req.headers.set('Authorization', 'Bearer $kRcKey');
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(body)));
      final res = await req.close().timeout(const Duration(seconds: 15));
      final txt = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
      if (res.statusCode >= 300) {
        var msg = 'HTTP ${res.statusCode}';
        try {
          final j = jsonDecode(txt);
          if (j is Map && j['message'] is String) msg = j['message'] as String;
        } catch (_) {}
        throw RcError(msg);
      }
      return txt.isEmpty ? null : jsonDecode(txt);
    } on RcError {
      rethrow;
    } catch (_) {
      throw const RcError('hors ligne', offline: true);
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, dynamic> _map(dynamic r) => r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  static List<Map<String, dynamic>> _list(dynamic r) =>
      r is List ? [for (final x in r) if (x is Map) Map<String, dynamic>.from(x)] : <Map<String, dynamic>>[];

  // ── Joueur ──────────────────────────────────────────────────────────────
  /// État complet : pid, name, avatar, coins, score, cards, packs, pity, streak,
  /// free, showcase, missions, milestones, owned [[carte, finition, qté]], events.
  static Future<Map<String, dynamic>> me() async {
    final d = await deviceId();
    return _map(await _rpc('rc_me', {'p_device': d, 'p_sig': _sig('$d|me')}));
  }

  /// 'ok', 'taken' (pseudo pris) ou 'showcase' (carte de vitrine non possédée).
  static Future<String> setProfile(String name, int avatar, String showcase) async {
    final d = await deviceId();
    final r = await _rpc('rc_set_profile', {
      'p_device': d,
      'p_name': name,
      'p_avatar': avatar,
      'p_showcase': showcase,
      'p_sig': _sig('$d|profile|$name|$avatar|$showcase'),
    });
    return (r as String?) ?? 'ok';
  }

  // ── Paquets ─────────────────────────────────────────────────────────────
  /// kind : free, mixte, console (sys obligatoire), premium.
  /// Renvoie {cards:[{c,f,r,n}], coins, pity, score, events}.
  static Future<Map<String, dynamic>> open(String kind, [String? sys]) async {
    final d = await deviceId();
    return _map(await _rpc('rc_open', {
      'p_device': d,
      'p_kind': kind,
      'p_sys': sys,
      'p_sig': _sig('$d|open|$kind|${sys ?? ''}'),
    }));
  }

  // ── Recyclage / fabrication ─────────────────────────────────────────────
  static Future<Map<String, dynamic>> recycle(String card, int finish, int qty) async {
    final d = await deviceId();
    return _map(await _rpc('rc_recycle', {
      'p_device': d,
      'p_card': card,
      'p_finish': finish,
      'p_qty': qty,
      'p_sig': _sig('$d|recycle|$card|$finish|$qty'),
    }));
  }

  static Future<Map<String, dynamic>> recycleDupes() async {
    final d = await deviceId();
    return _map(await _rpc('rc_recycle_dupes', {'p_device': d, 'p_sig': _sig('$d|dupes')}));
  }

  static Future<Map<String, dynamic>> craft(String card) async {
    final d = await deviceId();
    return _map(await _rpc('rc_craft', {'p_device': d, 'p_card': card, 'p_sig': _sig('$d|craft|$card')}));
  }

  // ── Marché ──────────────────────────────────────────────────────────────
  /// [{id, card, finish, price, seller, seller_pid, created_at}]
  static Future<List<Map<String, dynamic>>> marketList({String? sys, String? card, bool missing = false}) async {
    final d = await deviceId();
    return _list(await _rpc('rc_market_list', {'p_device': d, 'p_sys': sys, 'p_card': card, 'p_missing': missing}));
  }

  /// [{id, card, finish, price, sold, buyer, created_at, sold_at}]
  static Future<List<Map<String, dynamic>>> marketMine() async {
    final d = await deviceId();
    return _list(await _rpc('rc_market_mine', {'p_device': d}));
  }

  static Future<int> marketAdd(String card, int finish, int price) async {
    final d = await deviceId();
    final r = await _rpc('rc_market_add', {
      'p_device': d,
      'p_card': card,
      'p_finish': finish,
      'p_price': price,
      'p_sig': _sig('$d|sell|$card|$finish|$price'),
    });
    return (r as num).toInt();
  }

  static Future<bool> marketCancel(int id) async {
    final d = await deviceId();
    return (await _rpc('rc_market_cancel', {'p_device': d, 'p_id': id, 'p_sig': _sig('$d|cancel|$id')})) == true;
  }

  /// {card, f, n, coins, events} ou null si le lot vient d'être vendu.
  static Future<Map<String, dynamic>?> marketBuy(int id) async {
    final d = await deviceId();
    final r = await _rpc('rc_market_buy', {'p_device': d, 'p_id': id, 'p_sig': _sig('$d|buy|$id')});
    return r == null ? null : _map(r);
  }

  // ── Échanges ────────────────────────────────────────────────────────────
  /// give / want : 'carte:finition,…'
  static Future<int> tradeOffer(String toPid, String give, String want) async {
    final d = await deviceId();
    final r = await _rpc('rc_trade_offer', {
      'p_device': d,
      'p_to_pid': toPid,
      'p_give': give,
      'p_want': want,
      'p_sig': _sig('$d|offer|$toPid|$give|$want'),
    });
    return (r as num).toInt();
  }

  /// [{id, incoming, other_name, other_pid, give, want, status, created_at, done_at}]
  static Future<List<Map<String, dynamic>>> trades() async {
    final d = await deviceId();
    return _list(await _rpc('rc_trades', {'p_device': d}));
  }

  /// {status: accepted | refused | failed, events}
  static Future<Map<String, dynamic>> tradeAnswer(int id, bool accept) async {
    final d = await deviceId();
    return _map(await _rpc('rc_trade_answer', {
      'p_device': d,
      'p_id': id,
      'p_accept': accept,
      'p_sig': _sig('$d|answer|$id|$accept'),
    }));
  }

  static Future<bool> tradeCancel(int id) async {
    final d = await deviceId();
    return (await _rpc('rc_trade_cancel', {'p_device': d, 'p_id': id, 'p_sig': _sig('$d|tcancel|$id')})) == true;
  }

  // ── Joueurs ─────────────────────────────────────────────────────────────
  /// [{pid, name, avatar, score, cards, showcase}]
  static Future<List<Map<String, dynamic>>> board() async => _list(await _rpc('rc_board', {}));

  /// (rang, total)
  static Future<(int, int)> rank() async {
    final d = await deviceId();
    final rows = _list(await _rpc('rc_rank', {'p_device': d}));
    if (rows.isEmpty) return (0, 0);
    return ((rows.first['rank'] as num? ?? 0).toInt(), (rows.first['total'] as num? ?? 0).toInt());
  }

  static Future<List<Map<String, dynamic>>> find(String query) async => _list(await _rpc('rc_find', {'p_query': query}));

  /// {pid, name, avatar, score, cards, packs, showcase, since, owned}
  static Future<Map<String, dynamic>?> profile(String pid) async {
    final r = await _rpc('rc_profile', {'p_pid': pid});
    return r == null ? null : _map(r);
  }
}
