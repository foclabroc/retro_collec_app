import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PIXEL TRADE — serveur maison (PostgreSQL + PostgREST + relais rc-realtime
// derrière Caddy, voir selfhost/). Rétro Jump reste sur Supabase.
// Tout est décidé côté serveur (pièces, tirages, collection) : l'appli appelle
// les fonctions SQL rc_* avec une signature (même sel que le SQL).
// ═══════════════════════════════════════════════════════════════════════════

const kRcUrl = 'https://api.foclabroc.duckdns.org';
const kRcKey = 'sb_publishable_M1Rdee-lSEzCfq81zjYq5Q_NgJ0a35z';
const _salt = 'rc-collec#7b2e-foc'; // identique au SQL (rc__sig)
const _kDeviceKey = 'rc_device';

/// Erreur renvoyée par le serveur (message lisible : « pas assez de pièces »…)
/// ou hors ligne ([offline] = true) : pas de réseau, ou serveur joignable mais
/// service arrêté (502 / 503 / 504 de Caddy → message « serveur indisponible »).
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

  static final _http = http.Client();

  static Future<dynamic> _rpc(String fn, Map<String, dynamic> body) async {
    try {
      final res = await _http
          .post(
            Uri.parse('$kRcUrl/rest/v1/rpc/$fn'),
            headers: {
              'apikey': kRcKey,
              if (kRcKey.startsWith('eyJ')) 'Authorization': 'Bearer $kRcKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 502 || res.statusCode == 503 || res.statusCode == 504) {
        throw const RcError('serveur indisponible', offline: true);
      }
      final txt = utf8.decode(res.bodyBytes);
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
    }
  }

  static Map<String, dynamic> _map(dynamic r) => r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  static List<Map<String, dynamic>> _list(dynamic r) =>
      r is List ? [for (final x in r) if (x is Map) Map<String, dynamic>.from(x)] : <Map<String, dynamic>>[];

  // ── Joueur ──────────────────────────────────────────────────────────────
  /// État complet : pid, name, avatar, coins, score, cards, packs, pity, streak,
  /// free, showcase, missions, milestones, owned [[carte, finition, qté]], events.
  /// [have] : empreinte de la collection déjà connue (elle n'est renvoyée que si elle a changé)
  static Future<Map<String, dynamic>> me({String? have}) async {
    final d = await deviceId();
    return _map(await _rpc('rc_me', {'p_device': d, 'p_sig': _sig('$d|me'), if (have != null) 'p_have': have}));
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

  /// Achat avec choix du booster : le serveur tire 6 paquets et attend le choix (rc_pick).
  /// Renvoie {choose: 6, kind, sys, resumed, coins, lots, gifts} ; resumed = achat précédent pas encore choisi.
  static Future<Map<String, dynamic>> openChoice(String kind, [String? sys]) async {
    final d = await deviceId();
    return _map(await _rpc('rc_open_choice', {
      'p_device': d,
      'p_kind': kind,
      'p_sys': sys,
      'p_sig': _sig('$d|open6|$kind|${sys ?? ''}'),
    }));
  }

  /// Choix du booster (0 à 5). Renvoie comme [open] + choice, missed {c,f,r,n,b}.
  static Future<Map<String, dynamic>> pick(int choice) async {
    final d = await deviceId();
    return _map(await _rpc('rc_pick', {'p_device': d, 'p_choice': choice, 'p_sig': _sig('$d|pick|$choice')}));
  }

  /// Achat en attente de choix (appli fermée avant de choisir), ou null.
  static Future<Map<String, dynamic>?> pending() async {
    final d = await deviceId();
    final r = await _rpc('rc_pending_get', {'p_device': d, 'p_sig': _sig('$d|pending')});
    return r == null ? null : _map(r);
  }

  // ── Spectateurs (duels en direct des autres) ───────────────────────────
  /// Duels en direct en cours : [{game: c4|bs, id, phase, moves, p1: {pid, name, avatar}, p2}]
  static Future<List<Map<String, dynamic>>> liveGames() async => _list(await _rpc('rc_live_games', {}));

  // ── Tournois (tournament.dart) ─────────────────────────────────────────
  /// À venir, en cours, finis depuis moins de 7 jours (résumés)
  static Future<List<Map<String, dynamic>>> tourList() async {
    final d = await deviceId();
    return _list(await _rpc('rc_tour_list', {'p_device': d}));
  }

  /// Un tournoi complet : joueurs, matchs (arbre)
  static Future<Map<String, dynamic>> tourGet(int id) async {
    final d = await deviceId();
    return _map(await _rpc('rc_tour_get', {'p_id': id, 'p_device': d}));
  }

  static Future<Map<String, dynamic>> tourJoin(int id) async {
    final d = await deviceId();
    return _map(await _rpc('rc_tour_join', {'p_device': d, 'p_id': id, 'p_sig': _sig('$d|tjoin|$id')}));
  }

  static Future<Map<String, dynamic>> tourLeave(int id) async {
    final d = await deviceId();
    return _map(await _rpc('rc_tour_leave', {'p_device': d, 'p_id': id, 'p_sig': _sig('$d|tleave|$id')}));
  }

  /// « Je suis là » pour mon match → mon match ({status, gid…} + match)
  static Future<Map<String, dynamic>> tourReady(int mid) async {
    final d = await deviceId();
    return _map(await _rpc('rc_tour_ready', {'p_device': d, 'p_mid': mid, 'p_sig': _sig('$d|tready|$mid')}));
  }

  // ── Spectateurs d'une partie en direct (watchers.dart) ─────────────────
  /// Je regarde (à refaire toutes les 20 s) → spectateurs [{pid, name, avatar}]
  static Future<List<Map<String, dynamic>>> watchJoin(String game, int id) async {
    final d = await deviceId();
    final r = _map(await _rpc('rc_watch_join', {'p_device': d, 'p_game': game, 'p_id': id, 'p_sig': _sig('$d|wjoin|$game|$id')}));
    return _list(r['list']);
  }

  static Future<void> watchLeave(String game, int id) async {
    final d = await deviceId();
    await _rpc('rc_watch_leave', {'p_device': d, 'p_game': game, 'p_id': id, 'p_sig': _sig('$d|wleave|$game|$id')});
  }

  /// Spectateurs d'une partie (pour les joueurs)
  static Future<List<Map<String, dynamic>>> watchers(String game, int id) async =>
      _list(await _rpc('rc_watchers', {'p_game': game, 'p_id': id}));

  static Future<void> watchReact(String game, int id, String e) async {
    final d = await deviceId();
    await _rpc('rc_watch_react', {'p_device': d, 'p_game': game, 'p_id': id, 'p_e': e, 'p_sig': _sig('$d|wreact|$game|$id|$e')});
  }

  /// Une partie vue en spectateur (vue du joueur 1, rien de secret)
  static Future<Map<String, dynamic>> c4Watch(int id) async => _map(await _rpc('rc_c4_watch', {'p_id': id}));
  static Future<Map<String, dynamic>> bsWatch(int id) async => _map(await _rpc('rc_bs_watch', {'p_id': id}));

  // ── 4 en ligne (rc_c4_*) ───────────────────────────────────────────────
  /// Joueurs en ligne à défier en direct : [{pid, name, avatar, score, busy}]
  static Future<List<Map<String, dynamic>>> c4Online() async {
    final d = await deviceId();
    return _list(await _rpc('rc_c4_online', {'p_device': d}));
  }

  /// Mes parties (invitations, en cours, terminées récemment)
  static Future<List<Map<String, dynamic>>> c4List() async {
    final d = await deviceId();
    return _list(await _rpc('rc_c4_list', {'p_device': d}));
  }

  static Future<Map<String, dynamic>> c4State(int id) async {
    final d = await deviceId();
    return _map(await _rpc('rc_c4_state', {'p_device': d, 'p_id': id}));
  }

  /// mode : live (1 min par coup) ou turn (24 h par coup)
  static Future<Map<String, dynamic>> c4Invite(String pid, String mode) async {
    final d = await deviceId();
    return _map(await _rpc('rc_c4_invite', {'p_device': d, 'p_pid': pid, 'p_mode': mode, 'p_sig': _sig('$d|c4inv|$pid|$mode')}));
  }

  /// Accepter / refuser une invitation (ou annuler la sienne)
  static Future<Map<String, dynamic>> c4Answer(int id, bool accept) async {
    final d = await deviceId();
    return _map(await _rpc('rc_c4_answer', {'p_device': d, 'p_id': id, 'p_accept': accept, 'p_sig': _sig('$d|c4ans|$id|${accept ? 1 : 0}')}));
  }

  static Future<Map<String, dynamic>> c4Play(int id, int col) async {
    final d = await deviceId();
    return _map(await _rpc('rc_c4_play', {'p_device': d, 'p_id': id, 'p_col': col, 'p_sig': _sig('$d|c4play|$id|$col')}));
  }

  /// Réaction pendant une partie : 👍 😮 😂 🔥 👏
  static Future<void> c4Emote(int id, String emo) async {
    final d = await deviceId();
    await _rpc('rc_c4_emote', {'p_device': d, 'p_id': id, 'p_emo': emo, 'p_sig': _sig('$d|c4emo|$id|$emo')});
  }

  /// Mes statistiques : {wins, losses, draws, streak, net}
  static Future<Map<String, dynamic>> c4Stats() async {
    final d = await deviceId();
    return _map(await _rpc('rc_c4_stats', {'p_device': d}));
  }

  /// Meilleurs joueurs de la semaine : [{pid, name, avatar, wins, online}]
  static Future<List<Map<String, dynamic>>> c4Top() async => _list(await _rpc('rc_c4_top', {}));

  static Future<Map<String, dynamic>> c4Resign(int id) async {
    final d = await deviceId();
    return _map(await _rpc('rc_c4_resign', {'p_device': d, 'p_id': id, 'p_sig': _sig('$d|c4resign|$id')}));
  }

  /// Défis reçus : {live: [défis en direct], invites, turns, last_from}. bg = vérification appli fermée.
  static Future<Map<String, dynamic>> duelPing({bool bg = false}) async {
    final d = await deviceId();
    return _map(await _rpc('rc_duel_ping', {'p_device': d, 'p_bg': bg}));
  }

  // ── Console Wars, bataille navale (rc_bs_*) ────────────────────────────
  static Future<List<Map<String, dynamic>>> bsOnline() async {
    final d = await deviceId();
    return _list(await _rpc('rc_bs_online', {'p_device': d}));
  }

  static Future<List<Map<String, dynamic>>> bsList() async {
    final d = await deviceId();
    return _list(await _rpc('rc_bs_list', {'p_device': d}));
  }

  static Future<Map<String, dynamic>> bsState(int id) async {
    final d = await deviceId();
    return _map(await _rpc('rc_bs_state', {'p_device': d, 'p_id': id}));
  }

  static Future<Map<String, dynamic>> bsInvite(String pid, String mode) async {
    final d = await deviceId();
    return _map(await _rpc('rc_bs_invite', {'p_device': d, 'p_pid': pid, 'p_mode': mode, 'p_sig': _sig('$d|bsinv|$pid|$mode')}));
  }

  static Future<Map<String, dynamic>> bsAnswer(int id, bool accept) async {
    final d = await deviceId();
    return _map(await _rpc('rc_bs_answer', {'p_device': d, 'p_id': id, 'p_accept': accept, 'p_sig': _sig('$d|bsans|$id|${accept ? 1 : 0}')}));
  }

  /// Flotte : [{k, r, c, h}] (neo 5, ps 4, md 3, nes 3, gb 2 cases)
  static Future<Map<String, dynamic>> bsPlace(int id, List<Map<String, dynamic>> fleet) async {
    final d = await deviceId();
    return _map(await _rpc('rc_bs_place', {'p_device': d, 'p_id': id, 'p_fleet': fleet, 'p_sig': _sig('$d|bsplace|$id')}));
  }

  static Future<Map<String, dynamic>> bsShoot(int id, int cell) async {
    final d = await deviceId();
    return _map(await _rpc('rc_bs_shoot', {'p_device': d, 'p_id': id, 'p_cell': cell, 'p_sig': _sig('$d|bsshoot|$id|$cell')}));
  }

  static Future<Map<String, dynamic>> bsResign(int id) async {
    final d = await deviceId();
    return _map(await _rpc('rc_bs_resign', {'p_device': d, 'p_id': id, 'p_sig': _sig('$d|bsresign|$id')}));
  }

  static Future<void> bsEmote(int id, String emo) async {
    final d = await deviceId();
    await _rpc('rc_bs_emote', {'p_device': d, 'p_id': id, 'p_emo': emo, 'p_sig': _sig('$d|bsemo|$id|$emo')});
  }

  static Future<Map<String, dynamic>> bsStats() async {
    final d = await deviceId();
    return _map(await _rpc('rc_bs_stats', {'p_device': d}));
  }

  static Future<List<Map<String, dynamic>>> bsTop() async => _list(await _rpc('rc_bs_top', {}));

  // ── Événements (table rc_events, gérée dans Supabase) ──────────────────
  static Future<List<Map<String, dynamic>>> events() async {
    final d = await deviceId();
    return _list(await _rpc('rc_events_list', {'p_device': d}));
  }

  /// Récompense d'un événement : {coins, pixels, gain_coins, gain_pixels}
  static Future<Map<String, dynamic>> eventClaim(int id) async {
    final d = await deviceId();
    return _map(await _rpc('rc_event_claim', {'p_device': d, 'p_id': id, 'p_sig': _sig('$d|event|$id')}));
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

  /// Cartes de récompense à ranger : [{id, c, f, r, from, at, n}]
  static Future<List<Map<String, dynamic>>> stockList() async {
    final d = await deviceId();
    return _list(await _rpc('rc_stock_list', {'p_device': d, 'p_sig': _sig('$d|stock')}));
  }

  /// Range une carte du stock (ou toutes si [id] est null) dans la collection : {cards, events, coins, pixels, score, left}
  static Future<Map<String, dynamic>> stockTake([int? id]) async {
    final d = await deviceId();
    return _map(await _rpc('rc_stock_take', {'p_device': d, 'p_id': id, 'p_sig': _sig('$d|stocktake|${id ?? 0}')}));
  }

  /// Offre un paquet à un joueur (3 par jour, un par joueur)
  static Future<void> gift(String toPid) async {
    final d = await deviceId();
    await _rpc('rc_gift', {'p_device': d, 'p_to_pid': toPid, 'p_sig': _sig('$d|gift|$toPid')});
  }

  // ── Fil d'actualité ─────────────────────────────────────────────────────
  /// 100 dernières nouvelles (plus récentes d'abord) : {id, at, kind, card, f, sys, n, pid, name, avatar,
  /// rx: [👏, 🔥, 😮], me: ma réaction ou -1}
  static Future<List<Map<String, dynamic>>> feed([int after = 0]) async {
    final d = await deviceId();
    return _list(await _rpc('rc_feed_list3', {'p_device': d, 'p_after': after}));
  }

  /// Réagir à une nouvelle (0 👏, 1 🔥, 2 😮 ; la même réaction l'enlève) : {rx, me}
  static Future<Map<String, dynamic>> feedReact(int id, int emo) async {
    final d = await deviceId();
    return _map(await _rpc('rc_feed_react', {'p_device': d, 'p_id': id, 'p_emo': emo, 'p_sig': _sig('$d|react|$id|$emo')}));
  }

  /// Les réactions à mes nouvelles ont été vues
  static Future<void> reactsSeen() async {
    final d = await deviceId();
    await _rpc('rc_reacts_seen', {'p_device': d, 'p_sig': _sig('$d|rseen')});
  }

  // ── Parrainage ──────────────────────────────────────────────────────────
  /// {code, can_enter, sponsor {name, pid, avatar}, paid, packs, days, max, kids [{name, pid, avatar, packs, days, paid}]}
  static Future<Map<String, dynamic>> refInfo() async {
    final d = await deviceId();
    return _map(await _rpc('rc_ref_info', {'p_device': d, 'p_sig': _sig('$d|ref')}));
  }

  /// Entrer le code de son parrain : l'état + {res: ok | late | already | self | unknown | full}
  static Future<Map<String, dynamic>> refSet(String code) async {
    final d = await deviceId();
    return _map(await _rpc('rc_ref_set', {'p_device': d, 'p_code': code, 'p_sig': _sig('$d|refset|$code')}));
  }

  // ── Messages des duels ──────────────────────────────────────────────────
  /// Petit mot joint à mon défi (game : 'c4' ou 'bs')
  static Future<void> duelMsg(String game, int id, String msg) async {
    final d = await deviceId();
    await _rpc('rc_duel_msg', {'p_device': d, 'p_game': game, 'p_id': id, 'p_msg': msg, 'p_sig': _sig('$d|dmsg|$game|$id|$msg')});
  }

  /// Réponse rapide à un défi reçu
  static Future<void> duelReply(String game, int id, String msg) async {
    final d = await deviceId();
    await _rpc('rc_duel_reply', {'p_device': d, 'p_game': game, 'p_id': id, 'p_msg': msg, 'p_sig': _sig('$d|dreply|$game|$id|$msg')});
  }

  // ── Défis de la semaine ─────────────────────────────────────────────────
  /// {goals, rewards, prog, claim (bits : défis 0..5, coffre 6), chest, ends, coins, pixels, gifts}
  static Future<Map<String, dynamic>> week() async {
    final d = await deviceId();
    return _map(await _rpc('rc_week', {'p_device': d, 'p_sig': _sig('$d|week')}));
  }

  /// Cadeau de passage de version (une fois par joueur et par version) : {coins} donnés (0 si déjà reçu)
  /// Envoie aussi l'appareil (« 1.0.21|android », « 1.0.21|web ») : version vue dans l'admin.
  static Future<Map<String, dynamic>> upgradeGift(String ver) async {
    final d = await deviceId();
    final v = '$ver|${kIsWeb ? 'web' : defaultTargetPlatform.name}';
    return _map(await _rpc('rc_upgrade_gift', {'p_device': d, 'p_ver': v, 'p_sig': _sig('$d|upgrade|$v')}));
  }

  /// Trophées : {list: [{k, n, got, t: [bronze, argent, or]}], show, ready}
  static Future<Map<String, dynamic>> trophies() async {
    final d = await deviceId();
    return _map(await _rpc('rc_trophies', {'p_device': d, 'p_sig': _sig('$d|trophies')}));
  }

  /// Récupère le palier suivant d'un trophée : l'état mis à jour + {coins, pixels, gain, px, tier}
  static Future<Map<String, dynamic>> trophyClaim(String kind) async {
    final d = await deviceId();
    return _map(await _rpc('rc_trophy_claim', {'p_device': d, 'p_kind': kind, 'p_sig': _sig('$d|tclaim|$kind')}));
  }

  /// Vitrine de 3 trophées (« wins,,cards ») : l'état mis à jour
  static Future<Map<String, dynamic>> trophyShow(String list) async {
    final d = await deviceId();
    return _map(await _rpc('rc_trophy_show', {'p_device': d, 'p_list': list, 'p_sig': _sig('$d|tshow|$list')}));
  }

  /// Récupère un défi (1..6) ou le coffre (7) : l'état mis à jour + {gain}
  static Future<Map<String, dynamic>> weekClaim(int i) async {
    final d = await deviceId();
    return _map(await _rpc('rc_week_claim', {'p_device': d, 'p_i': i, 'p_sig': _sig('$d|wclaim|$i')}));
  }

  // ── Gamedle (jeu du jour) ───────────────────────────────────────────────
  /// {day, card, guesses, won, solvers, players, coins}
  static Future<Map<String, dynamic>> gamedleState() async {
    final d = await deviceId();
    return _map(await _rpc('rc_gamedle_state', {'p_device': d}));
  }

  /// Une proposition : l'état mis à jour + {ok, reward, answer}
  static Future<Map<String, dynamic>> gamedleGuess(String card) async {
    final d = await deviceId();
    return _map(await _rpc('rc_gamedle_guess', {'p_device': d, 'p_card': card, 'p_sig': _sig('$d|gamedle|$card')}));
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

  /// Achat groupé : [(carte, finition, prix max)] → {bought:[{card,f,n,price}], skipped:[{card,f,why}], events, coins}
  static Future<Map<String, dynamic>> marketBuyMany(List<(String, int, int)> items) async {
    final d = await deviceId();
    final s = items.map((x) => '${x.$1}:${x.$2}:${x.$3}').join(',');
    return _map(await _rpc('rc_market_buy_many', {'p_device': d, 'p_items': s, 'p_sig': _sig('$d|buymany|$s')}));
  }

  /// Marché groupé : [{card, finish, lots, min_price, last_at}]
  /// Toutes les cartes en vente (une ligne par carte et finition) avec le prix moyen sur 30 jours
  static Future<List<Map<String, dynamic>>> marketBrowse() async {
    final d = await deviceId();
    return _list(await _rpc('rc_market_browse', {'p_device': d}));
  }

  static Future<List<Map<String, dynamic>>> marketGroups({String? sys, bool missing = false}) async {
    final d = await deviceId();
    return _list(await _rpc('rc_market_groups', {'p_device': d, 'p_sys': sys, 'p_missing': missing}));
  }

  /// Joueurs qui ont cette carte en double : [{pid, name, avatar, qty}]
  /// Mes cartes manquantes que les voisins ont en double : {cards, players: [{pid, name, avatar, online, n, cards: [[id, qty]]}]}
  static Future<Map<String, dynamic>> missingFinder() async {
    final d = await deviceId();
    return _map(await _rpc('rc_missing_finder', {'p_device': d, 'p_sig': _sig('$d|missing')}));
  }

  static Future<List<Map<String, dynamic>>> cardOwners(String card) async {
    final d = await deviceId();
    return _list(await _rpc('rc_card_owners', {'p_device': d, 'p_card': card}));
  }

  /// Historique : [{kind: sold|bought|trade_in|trade_out, card, finish, price, other_name, other_pid, give, want, status, at}]
  /// Historique par pages : {rows, more, earned, spent, trades}
  static Future<Map<String, dynamic>> historyPage(int offset) async {
    final d = await deviceId();
    final r = await _rpc('rc_history_page', {'p_device': d, 'p_offset': offset});
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

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

  /// Ma borne dans la salle d'arcade (avec mon rang), si je ne suis pas dans les 100 premiers
  static Future<Map<String, dynamic>?> myFloor() async {
    final d = await deviceId();
    final r = await _rpc('rc_my_floor', {'p_device': d});
    return r == null ? null : _map(r);
  }

  /// {pid, name, avatar, score, cards, packs, showcase, since, owned}
  static Future<Map<String, dynamic>?> profile(String pid) async {
    final r = await _rpc('rc_profile', {'p_pid': pid});
    return r == null ? null : _map(r);
  }

  // ── Admin (réservé aux comptes de rc_admins, vérifié par le serveur) ──────
  static Future<dynamic> _admin(String fn, String payload, [Map<String, dynamic> extra = const {}]) async {
    final d = await deviceId();
    return _rpc(fn, {'p_device': d, 'p_sig': _sig('$d|admin|$payload'), ...extra});
  }

  /// Version minimale exigée (publique) : {min_version}
  static Future<Map<String, dynamic>> appConfig() async => _map(await _rpc('rc_app_config', {}));

  static Future<bool> adminCheck() async {
    try {
      return (await _admin('rc_admin_check', 'check')) == true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> adminAccounts([String q = '']) async =>
      _list(await _admin('rc_admin_accounts', 'accounts|$q', {'p_query': q}));

  static Future<Map<String, dynamic>> adminPlayer(String pid) async =>
      _map(await _admin('rc_admin_player', 'player|$pid', {'p_pid': pid}));

  static Future<List<Map<String, dynamic>>> adminLinks() async => _list(await _admin('rc_admin_links', 'links'));

  static Future<Map<String, dynamic>> adminStats() async => _map(await _admin('rc_admin_stats', 'stats'));

  static Future<List<Map<String, dynamic>>> adminChat() async => _list(await _admin('rc_admin_chat', 'chat'));

  /// act : hide, show, ban (24 h), unban
  static Future<bool> adminChatAct(int id, String act) async =>
      (await _admin('rc_admin_chat_act', 'chatact|$id|$act', {'p_id': id, 'p_act': act})) == true;

  static Future<Map<String, dynamic>> adminSetConfig(String key, String value) async =>
      _map(await _admin('rc_admin_set_config', 'config|$key|$value', {'p_key': key, 'p_value': value}));

  /// Réglages en direct : valeurs envoyées en JSON (ex. {"saga":3.2,"mixte":100})
  static Future<Map<String, dynamic>> adminSetLive(Map<String, num> values) async {
    final v = jsonEncode(values);
    return _map(await _admin('rc_admin_set_live', 'live|$v', {'p_values': v}));
  }

  static Future<bool> adminBlock(String pid, bool on) async =>
      (await _admin('rc_admin_block', 'block|$pid|${on ? 1 : 0}', {'p_pid': pid, 'p_on': on})) == true;

  /// 'ok' ou 'taken'
  static Future<String> adminRename(String pid, String name) async =>
      (await _admin('rc_admin_rename', 'rename|$pid|$name', {'p_pid': pid, 'p_name': name}))?.toString() ?? 'ok';

  static Future<List<Map<String, dynamic>>> adminMarket([String q = '']) async =>
      _list(await _admin('rc_admin_market', 'market|$q', {'p_query': q}));

  static Future<bool> adminMarketRemove(int id) async =>
      (await _admin('rc_admin_market_remove', 'mremove|$id', {'p_id': id})) == true;

  /// pid vide = tous les joueurs
  static Future<void> adminMail(String pid, String title, String body, int coins, int pixels, int packs) async {
    await _admin('rc_admin_mail', 'mail|$pid|$title|$coins|$pixels|$packs', {
      'p_pid': pid,
      'p_title': title,
      'p_body': body,
      'p_coins': coins,
      'p_pixels': pixels,
      'p_packs': packs,
    });
  }

  static Future<List<Map<String, dynamic>>> adminMails() async => _list(await _admin('rc_admin_mails', 'mails'));

  static Future<void> adminMailDelete(int id) async => _admin('rc_admin_mail_delete', 'maildel|$id', {'p_id': id});

  static Future<List<Map<String, dynamic>>> adminPolls() async => _list(await _admin('rc_admin_polls', 'polls'));

  /// options : une réponse par ligne (2 à 4)
  static Future<void> adminPollNew(String question, String options, int days) async {
    await _admin('rc_admin_poll_new', 'pollnew|$question|$options|$days', {'p_question': question, 'p_options': options, 'p_days': days});
  }

  static Future<void> adminPollClose(int id) async => _admin('rc_admin_poll_close', 'pollclose|$id', {'p_id': id});

  static Future<List<Map<String, dynamic>>> adminEvents() async => _list(await _admin('rc_admin_events', 'events'));

  /// id null : nouvel événement
  static Future<void> adminEventSave(int? id, Map<String, dynamic> data) async {
    final v = jsonEncode(data);
    await _admin('rc_admin_event_save', 'evsave|${id ?? 0}|$v', {'p_id': id, 'p_data': v});
  }

  /// Créer (id absent) ou modifier un tournoi encore ouvert → id
  static Future<int> adminTourSave(Map<String, dynamic> data) async {
    final v = jsonEncode(data);
    return ((await _admin('rc_admin_tour_save', 'toursave|$v', {'p_data': v})) as num).toInt();
  }

  static Future<void> adminTourCancel(int id) async => _admin('rc_admin_tour_cancel', 'tourcancel|$id', {'p_id': id});

  static Future<void> adminEventActive(int id, bool on) async =>
      _admin('rc_admin_event_active', 'evactive|$id|${on ? 1 : 0}', {'p_id': id, 'p_on': on});

  /// Courrier avec récompense enrichie. target : all, active7, new7, inactive7 ou pid:<pid>
  static Future<void> adminMail2(String target, String title, String body, Map<String, dynamic> reward) async {
    final r = jsonEncode(reward);
    await _admin('rc_admin_mail2', 'mail2|$target|$title|$r', {'p_target': target, 'p_title': title, 'p_body': body, 'p_reward': r});
  }

  /// Listes des stats : active7, today, new7, packs, sales, duels
  static Future<List<Map<String, dynamic>>> adminStatList(String kind) async =>
      _list(await _admin('rc_admin_stat_list', 'statlist|$kind', {'p_kind': kind}));

  /// Qui possède une carte, combien en circulent, dernières ventes
  static Future<Map<String, dynamic>> adminCard(String card) async => _map(await _admin('rc_admin_card', 'card|$card', {'p_card': card}));

  /// Journal des actions admin (200 dernières)
  static Future<List<Map<String, dynamic>>> adminLog() async => _list(await _admin('rc_admin_log_list', 'log'));

  /// Activité des joueurs (80 lignes) : groupe ('' = tout), bout de pseudo, avant la ligne n° before (0 = début)
  /// Journal de tous les joueurs (150 lignes, plus récentes d'abord) ; [before] = `at` de la dernière ligne reçue, '' = début.
  static Future<List<Map<String, dynamic>>> adminFeed(String before) async =>
      _list(await _admin('rc_admin_feed', 'feed|$before', {'p_before': before}));

  static Future<List<Map<String, dynamic>>> adminActivity(String group, String who, int before) async =>
      _list(await _admin('rc_admin_activity', 'act|$group|$who|$before', {'p_group': group, 'p_who': who, 'p_before': before}));

  // ── Courrier de l'admin et sondage (à l'ouverture du jeu) ────────────────
  static Future<List<Map<String, dynamic>>> mailList() async {
    final d = await deviceId();
    return _list(await _rpc('rc_mail_list', {'p_device': d, 'p_sig': _sig('$d|mail')}));
  }

  static Future<Map<String, dynamic>> mailRead(int id) async {
    final d = await deviceId();
    return _map(await _rpc('rc_mail_read', {'p_device': d, 'p_id': id, 'p_sig': _sig('$d|mailread|$id')}));
  }

  static Future<Map<String, dynamic>?> pollCurrent() async {
    final d = await deviceId();
    final r = await _rpc('rc_poll_current', {'p_device': d, 'p_sig': _sig('$d|poll')});
    return r is Map ? _map(r) : null;
  }

  static Future<Map<String, dynamic>> pollVote(int id, int choice) async {
    final d = await deviceId();
    return _map(await _rpc('rc_poll_vote', {'p_device': d, 'p_id': id, 'p_choice': choice, 'p_sig': _sig('$d|vote|$id|$choice')}));
  }
}
