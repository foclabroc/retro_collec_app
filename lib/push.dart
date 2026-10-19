import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide Constraints;
import 'package:flutter/services.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'catalog.dart';
import 'game.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Notifications Android, même appli fermée : environ toutes les 15 min (minimum
// imposé par Android), le téléphone interroge rc_notifs et prévient :
//   🎁 paquet cadeau reçu · 💰 carte vendue · 🔄 proposition d'échange
//   💬 mention dans les messages · 🃏 paquet gratuit du jour (une fois par jour,
//   à partir de 9 h) · 🎉 lot gratuit du samedi
// Quand l'appli est ouverte, Notifs (notifs.dart) met à jour le même état :
// rien n'est notifié deux fois.
// ═══════════════════════════════════════════════════════════════════════════

const _kTask = 'rc_push_watch';
const _kStateKey = 'rc_push_state';
const _kEnabledKey = 'rc_push';
const _kLastKey = 'rc_push_last';
const _kDuelInv = 'rc_push_duel_inv';
const _kDuelTurn = 'rc_push_duel_turn';
const _kAskedKey = 'rc_push_battery_asked';
const _sys = MethodChannel('com.foclabroc.retro_collec/system');

/// Point d'entrée de la tâche de fond (isolat séparé).
@pragma('vm:entry-point')
void pushWatchDispatcher() {
  Workmanager().executeTask((task, input) async {
    DartPluginRegistrant.ensureInitialized();
    try {
      // repère de la dernière vérification (affiché dans les réglages)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLastKey, DateTime.now().millisecondsSinceEpoch);
      await loadLang();
      if (await PushWatch.enabled()) await PushWatch.check(notify: true);
    } catch (_) {}
    return true;
  });
}

class PushWatch {
  static final _notif = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Dernière vérification faite appli fermée (null : jamais)
  static Future<DateTime?> lastRun() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final v = prefs.getInt(_kLastKey);
      return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
    } catch (_) {
      return null;
    }
  }

  /// L'appli échappe-t-elle à l'économie de batterie ?
  static Future<bool> batteryFree() async {
    if (kIsWeb) return true;
    try {
      return await _sys.invokeMethod<bool>('batteryFree') ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> askBattery() async {
    try {
      await _sys.invokeMethod('askBattery');
    } catch (_) {}
  }

  static Future<void> openAutostart() async {
    try {
      await _sys.invokeMethod('autostart');
    } catch (_) {}
  }

  static Future<String> brand() async {
    try {
      return (await _sys.invokeMethod<String>('brand') ?? '').toLowerCase();
    } catch (_) {
      return '';
    }
  }

  /// Une seule fois : si Android endort l'appli, on explique comment recevoir les notifications
  static Future<void> maybeAskBattery(BuildContext context) async {
    if (kIsWeb || !await enabled()) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kAskedKey) ?? false) return;
      if (await batteryFree()) return;
      await prefs.setBool(_kAskedKey, true);
      if (context.mounted) await showReliableDialog(context);
    } catch (_) {}
  }

  /// Les 2 réglages Android qui empêchent les notifications appli fermée
  static Future<void> showReliableDialog(BuildContext context) async {
    final free = await batteryFree();
    final b = await brand();
    final oem = ['xiaomi', 'redmi', 'poco', 'oppo', 'realme', 'oneplus', 'vivo', 'huawei', 'honor', 'samsung'].any(b.contains);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('🔔 Notifications appli fermée', '🔔 Notifications when closed')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('Android endort les applis fermées pour économiser la batterie : Pixel Trade ne peut alors plus vérifier les cadeaux, ventes et échanges.',
              'Android puts closed apps to sleep to save battery: Pixel Trade then can no longer check for gifts, sales and trades.')),
          const SizedBox(height: 12),
          Text(t('1. Batterie : choisis « Aucune restriction » (ou « Ne pas optimiser »)', '1. Battery: choose "Unrestricted" (or "Don\'t optimize")'),
              style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          if (free)
            Text(t('✓ Déjà fait', '✓ Already done'), style: const TextStyle(color: Color(0xFF5DCAA5), fontWeight: FontWeight.w800))
          else
            FilledButton(onPressed: askBattery, child: Text(t('Ouvrir le réglage', 'Open the setting'))),
          if (oem) ...[
            const SizedBox(height: 12),
            Text(t('2. Démarrage automatique : active Pixel Trade (téléphones Xiaomi, Oppo, Realme, Huawei, Samsung…)',
                    '2. Autostart: turn Pixel Trade on (Xiaomi, Oppo, Realme, Huawei, Samsung phones…)'),
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            OutlinedButton(onPressed: openAutostart, child: Text(t('Ouvrir le réglage', 'Open the setting'))),
          ],
          const SizedBox(height: 10),
          Text(t('Ensuite, une vérification est faite environ toutes les 15 minutes (Android peut l\'espacer quand le téléphone dort).',
                  'Then a check runs about every 15 minutes (Android may space it out while the phone sleeps).'),
              style: const TextStyle(fontSize: 12, color: Colors.white60)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  static Future<bool> enabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kEnabledKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Au lancement de l'appli : autorisation et tâche périodique.
  static Future<void> start() async {
    if (kIsWeb) return; // pas de notifications Android sur le web
    try {
      await Workmanager().initialize(pushWatchDispatcher);
      if (!await enabled()) return;
      await _init();
      await _notif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      await _register();
    } catch (_) {}
  }

  static Future<void> _register() => Workmanager().registerPeriodicTask(
        _kTask,
        _kTask,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
      );

  /// Réglage « Notifications » du profil
  static Future<void> setEnabled(bool v) async {
    if (kIsWeb) return; // pas de notifications Android sur le web
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabledKey, v);
      if (v) {
        await _init();
        await _notif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
        await _register();
      } else {
        await Workmanager().cancelByUniqueName(_kTask);
      }
    } catch (_) {}
  }

  static Future<void> _init() async {
    if (_ready) return;
    await _notif.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_notify')),
    );
    _ready = true;
  }

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  static Future<Map<String, dynamic>> _load(SharedPreferences prefs) async {
    try {
      return Map<String, dynamic>.from(jsonDecode(prefs.getString(_kStateKey) ?? '') as Map);
    } catch (_) {
      return {};
    }
  }

  static int _maxSale(Map<String, dynamic> r) {
    var m = 0;
    for (final x in (r['sales'] as List? ?? const [])) {
      if (x is Map) m = (x['id'] as num? ?? 0).toInt() > m ? (x['id'] as num).toInt() : m;
    }
    return m;
  }

  static int _i(dynamic v) => (v as num? ?? 0).toInt();

  /// Paquet gratuit pas encore signalé : chaque paquet (toutes les 6 h) est repéré par free_at
  /// (heure du paquet précédent) ; ancien serveur sans free_at : une fois par jour.
  static bool _freeNew(Map r, Map old) =>
      r.containsKey('free_at') ? '${_i(r['free_at'])}' != '${old['freeAt']}' : old['freeDay'] != _today();

  /// Appli ouverte : défis et tours déjà signalés dans l'appli (pas de notification ensuite)
  static Future<void> seenDuels(int invites, int turns) async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kDuelInv, invites);
      await prefs.setInt(_kDuelTurn, turns);
    } catch (_) {}
  }

  /// Appli ouverte : tout ce que l'appli vient d'afficher est « vu ».
  static Future<void> seen(Map<String, dynamic> r) async {
    if (kIsWeb) return; // pas de notifications Android sur le web
    try {
      final prefs = await SharedPreferences.getInstance();
      final old = await _load(prefs);
      await prefs.setString(
        _kStateKey,
        jsonEncode({
          'trades': _i(r['trades']),
          'sale': _maxSale(r) > _i(old['sale']) ? _maxSale(r) : _i(old['sale']),
          'gift': _i(r['gift_last']),
          'mention': _i(r['mention']) > _i(old['mention']) ? _i(r['mention']) : _i(old['mention']),
          'freeDay': _today(), // l'appli a été ouverte aujourd'hui : pas de rappel
          'freeAt': r['free'] == true ? _i(r['free_at']) : old['freeAt'], // paquet gratuit vu dans l'appli : pas de rappel
          'lotDay': r['lot_free'] == true ? _today() : old['lotDay'],
        }),
      );
    } catch (_) {}
  }

  /// Tâche de fond : compare l'état du serveur au dernier état connu et notifie.
  static Future<void> check({required bool notify}) async {
    if (kIsWeb) return; // pas de notifications Android sur le web
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // l'appli a pu écrire entre-temps
    if (!await RcServer.hasProfile()) return;
    final r = await RcServer.notifs();
    final old = await _load(prefs);
    final first = old.isEmpty;
    final today = _today();
    final msgs = <(int, String, String)>[]; // (id, titre, texte)

    if (!first && notify) {
      // échanges reçus
      final tr = _i(r['trades']);
      if (tr > _i(old['trades'])) {
        msgs.add((1, t('🔄 Proposition d\'échange', '🔄 Trade offer'),
            tr == 1 ? t('Un joueur te propose un échange', 'A player sent you a trade offer') : t('$tr échanges t\'attendent', '$tr trade offers are waiting')));
      }
      // ventes
      final fresh = [
        for (final x in (r['sales'] as List? ?? const []))
          if (x is Map && _i(x['id']) > _i(old['sale'])) x
      ];
      if (fresh.isNotEmpty) {
        final total = fresh.fold<int>(0, (a, x) => a + _i(x['price']));
        String body;
        if (fresh.length == 1) {
          try {
            if (Catalog.cards.isEmpty) await Catalog.loadLocal();
          } catch (_) {}
          final c = Catalog.cards[fresh.first['card']];
          body = t('${c?.title ?? 'Ta carte'} vendue à ${fresh.first['buyer'] ?? '?'} : +$total pièces',
              '${c?.title ?? 'Your card'} sold to ${fresh.first['buyer'] ?? '?'}: +$total coins');
        } else {
          body = t('${fresh.length} cartes vendues : +$total pièces', '${fresh.length} cards sold: +$total coins');
        }
        msgs.add((2, t('💰 Carte vendue', '💰 Card sold'), body));
      }
      // cadeaux
      if (_i(r['gift_last']) > _i(old['gift'])) {
        msgs.add((3, t('🎁 Paquet cadeau', '🎁 Gift pack'),
            t('${r['gift_from'] ?? 'Un voisin'} t\'a offert un paquet de 5 cartes', '${r['gift_from'] ?? 'A neighbor'} gave you a 5-card pack')));
      }
      // mention
      if (_i(r['mention']) > _i(old['mention'])) {
        msgs.add((4, t('💬 Messages', '💬 Messages'), t('Quelqu\'un t\'a mentionné dans les messages', 'Someone mentioned you in the messages')));
      }
      // lot gratuit du samedi (une fois)
      if (r['lot_free'] == true && old['lotDay'] != today) {
        msgs.add((5, t('🎉 C\'est samedi !', '🎉 It\'s Saturday!'), t('Ton lot de 5 paquets mixtes est gratuit aujourd\'hui', 'Your 5 mixed packs bundle is free today')));
      } else if (r['free'] == true && _freeNew(r, old) && DateTime.now().hour >= 9 && DateTime.now().hour < 22) {
        // paquet gratuit (toutes les 6 h ; une fois par paquet, de 9 h à 22 h, si l'appli n'a pas été ouverte)
        msgs.add((6, t('🃏 Paquet gratuit', '🃏 Free pack'),
            r['wheel'] == true
                ? t('Ton paquet gratuit et la roue de la fortune t\'attendent', 'Your free pack and the wheel of fortune are waiting')
                : t('Ton paquet gratuit t\'attend', 'Your free pack is waiting')));
      }
    }

    await prefs.setString(
      _kStateKey,
      jsonEncode({
        'trades': _i(r['trades']),
        'sale': _maxSale(r) > _i(old['sale']) ? _maxSale(r) : _i(old['sale']),
        'gift': _i(r['gift_last']),
        'mention': _i(r['mention']) > _i(old['mention']) ? _i(r['mention']) : _i(old['mention']),
        'freeDay': msgs.any((m) => m.$1 == 6) || first ? today : old['freeDay'],
        'freeAt': msgs.any((m) => m.$1 == 6) || (first && r['free'] == true) ? _i(r['free_at']) : old['freeAt'],
        'lotDay': msgs.any((m) => m.$1 == 5) || (first && r['lot_free'] == true) ? today : old['lotDay'],
      }),
    );

    // défis : invitation tour par tour reçue, partie où c'est mon tour
    try {
      final d = await RcServer.duelPing(bg: true);
      final inv = _i(d['invites']), trn = _i(d['turns']);
      final oldInv = _i(prefs.getInt(_kDuelInv)), oldTrn = _i(prefs.getInt(_kDuelTurn));
      if (notify && !first) {
        if (inv > oldInv) {
          msgs.add((7, t('⚔ ${d['last_from'] ?? 'Un joueur'} te défie !', '⚔ ${d['last_from'] ?? 'A player'} challenges you!'),
              t('Une partie tour par tour t\'attend dans Bonus / Jeux (gratuit)', 'A turn-based game is waiting in Bonus / Games (free)')));
        }
        if (trn > oldTrn) {
          msgs.add((8, t('🎮 À toi de jouer', '🎮 Your turn'),
              trn == 1 ? t('Ton adversaire a joué : à toi !', 'Your opponent played: your turn!') : t('$trn parties t\'attendent', '$trn games are waiting for you')));
        }
      }
      await prefs.setInt(_kDuelInv, inv);
      await prefs.setInt(_kDuelTurn, trn);
    } catch (_) {}

    if (msgs.isEmpty) return;
    await _init();
    for (final (id, title, body) in msgs) {
      await _notif.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'pixel_trade',
            'Pixel Trade',
            channelDescription: t('Cadeaux, ventes, échanges et paquets gratuits', 'Gifts, sales, trades and free packs'),
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_stat_notify', // silhouette blanche (barre d'état)
            color: const Color(0xFFEF9F27),
            largeIcon: const DrawableResourceAndroidBitmap('ic_notif_large'), // l'icône du jeu en couleur
            styleInformation: BigTextStyleInformation(body),
          ),
        ),
      );
    }
  }
}
