import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PIXEL TRADE — serveur Supabase (même projet que Rétro Jump, tables rc_*)
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

  /// Vrai si ce téléphone a déjà un profil (identifiant créé ou restauré).
  static Future<bool> hasProfile() async {
    if (_device != null) return true;
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_kDeviceKey) ?? '').length == 32;
  }

  /// Pseudo disponible ?
  static Future<bool> nameFree(String name) async => (await _rpc('rc_name_free', {'p_name': name})) == true;

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
    await _adopt(id);
    return p['name'] as String? ?? '?';
  }

  /// Connexion pseudo + mot de passe. Renvoie le pseudo du compte.
  static Future<String> login(String name, String password) async {
    final r = await _rpc('rc_login', {'p_name': name.trim(), 'p_hash': _passHash(password)});
    if (r is! String || r.length != 32) throw const RcError('identifiants incorrects');
    final p = await profile(pidOf(r));
    await _adopt(r);
    return p?['name'] as String? ?? name.trim();
  }

  /// Définit ou change le mot de passe du compte de ce téléphone.
  static Future<void> setPassword(String password) async {
    final d = await deviceId();
    final h = _passHash(password);
    await _rpc('rc_set_password', {'p_device': d, 'p_hash': h, 'p_sig': _sig('$d|password|$h')});
  }

  static Future<bool> hasPassword() async {
    if (!await hasProfile()) return false;
    return (await _rpc('rc_has_password', {'p_device': await deviceId()})) == true;
  }

  static String _passHash(String password) => sha256.convert(utf8.encode('pt-pass#41c9|$password')).toString();

  /// Remplace le profil de ce téléphone (le profil vierge éventuel est supprimé).
  static Future<void> _adopt(String id) async {
    final old = await hasProfile() ? await deviceId() : id;
    if (old != id) {
      try {
        await _rpc('rc_forget', {'p_device': old, 'p_sig': _sig('$old|forget')});
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDeviceKey, id);
    _device = id;
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

  /// Fusion : 5 normales → 1 brillante (finish 0), 3 brillantes → 1 dorée (finish 1)
  static Future<Map<String, dynamic>> fuse(String card, int finish) async {
    final d = await deviceId();
    return _map(await _rpc('rc_fuse', {'p_device': d, 'p_card': card, 'p_finish': finish, 'p_sig': _sig('$d|fuse|$card|$finish')}));
  }

  /// Cadeaux uniques pas encore reçus (ex. 800 pièces de la v1.0.3) : {events, coins}
  static Future<Map<String, dynamic>> claim() async {
    final d = await deviceId();
    return _map(await _rpc('rc_claim', {'p_device': d, 'p_sig': _sig('$d|claim')}));
  }

  // ── Bonus ───────────────────────────────────────────────────────────────
  /// Roue de la fortune : {seg, gain, card:{c,f,r,n}|null, coins, events}
  static Future<Map<String, dynamic>> wheel() async {
    final d = await deviceId();
    return _map(await _rpc('rc_wheel', {'p_device': d, 'p_sig': _sig('$d|wheel')}));
  }

  /// Lot de 5 paquets mixtes (500 pièces, gratuit le samedi) : {free, lots, coins}
  static Future<Map<String, dynamic>> buyLot() async {
    final d = await deviceId();
    return _map(await _rpc('rc_buy_lot', {'p_device': d, 'p_sig': _sig('$d|lot')}));
  }

  /// Cadeaux reçus pas encore ouverts : [{id, name, pid, avatar, at}]
  static Future<List<Map<String, dynamic>>> giftsList() async {
    final d = await deviceId();
    return _list(await _rpc('rc_gifts_list', {'p_device': d}));
  }

  /// Offre un paquet à un joueur (3 par jour, un par joueur)
  static Future<void> gift(String toPid) async {
    final d = await deviceId();
    await _rpc('rc_gift', {'p_device': d, 'p_to_pid': toPid, 'p_sig': _sig('$d|gift|$toPid')});
  }

  // ── Quiz rétro ──────────────────────────────────────────────────────────
  /// Pièces encore gagnables aujourd'hui (0 à 100).
  static Future<int> quizStatus() async {
    final d = await deviceId();
    return ((await _rpc('rc_quiz_status', {'p_device': d})) as num? ?? 0).toInt();
  }

  /// Fin de partie : {gain, left, coins}
  static Future<Map<String, dynamic>> quizClaim(int correct) async {
    final d = await deviceId();
    return _map(await _rpc('rc_quiz_claim', {'p_device': d, 'p_correct': correct, 'p_sig': _sig('$d|quiz|$correct')}));
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

  /// Marché groupé : [{card, finish, lots, min_price, last_at}]
  static Future<List<Map<String, dynamic>>> marketGroups({String? sys, bool missing = false}) async {
    final d = await deviceId();
    return _list(await _rpc('rc_market_groups', {'p_device': d, 'p_sys': sys, 'p_missing': missing}));
  }

  /// Joueurs qui ont cette carte en double : [{pid, name, avatar, qty}]
  static Future<List<Map<String, dynamic>>> cardOwners(String card) async {
    final d = await deviceId();
    return _list(await _rpc('rc_card_owners', {'p_device': d, 'p_card': card}));
  }

  /// Historique : [{kind: sold|bought|trade_in|trade_out, card, finish, price, other_name, other_pid, give, want, status, at}]
  static Future<List<Map<String, dynamic>>> history() async {
    final d = await deviceId();
    return _list(await _rpc('rc_history', {'p_device': d}));
  }

  /// Prix de référence : {avg, sold, min, open} (null si aucune donnée)
  static Future<Map<String, dynamic>> marketPrice(String card, int finish) async =>
      _map(await _rpc('rc_market_price', {'p_card': card, 'p_finish': finish}));

  /// Notifications : {trades: nb d'échanges reçus en attente, sales: [{id, card, f, price, buyer}]}
  static Future<Map<String, dynamic>> notifs() async {
    final d = await deviceId();
    return _map(await _rpc('rc_notifs', {'p_device': d}));
  }

  /// « Mes ventes » consulté
  static Future<void> marketSeen() async {
    final d = await deviceId();
    await _rpc('rc_market_seen', {'p_device': d, 'p_sig': _sig('$d|seen')});
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

  // ── Messages ────────────────────────────────────────────────────────────
  /// [{id, pid, name, avatar, msg, at, me}] après [after] (80 derniers max)
  static Future<List<Map<String, dynamic>>> chatList(int after) async {
    final d = await deviceId();
    return _list(await _rpc('rc_chat_list', {'p_device': d, 'p_after': after}));
  }

  static Future<void> chatSend(String msg) async {
    final d = await deviceId();
    await _rpc('rc_chat_send', {'p_device': d, 'p_msg': msg, 'p_sig': _sig('$d|chat|$msg')});
  }

  static Future<void> chatReport(int id) async {
    final d = await deviceId();
    await _rpc('rc_chat_report', {'p_device': d, 'p_id': id, 'p_sig': _sig('$d|report|$id')});
  }

  /// Maison du Voisinage : 'style.murs.toit.déco'
  static Future<void> setHouse(String house) async {
    final d = await deviceId();
    await _rpc('rc_set_house', {'p_device': d, 'p_house': house, 'p_sig': _sig('$d|house|$house')});
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
