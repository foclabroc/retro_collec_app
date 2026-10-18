import 'dart:async';

import 'package:flutter/material.dart';

import 'audio.dart';
import 'catalog.dart';
import 'game.dart';
import 'main.dart';
import 'push.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Notifications dans l'appli : échanges reçus en attente et cartes vendues.
// Vérifiées toutes les 45 s tant que l'appli est ouverte, et au retour dans l'appli.
// Pastilles sur les onglets Échanges et Marché + message « carte vendue ».
// ═══════════════════════════════════════════════════════════════════════════

class Notifs extends ChangeNotifier {
  Notifs._();
  static final Notifs i = Notifs._();

  int trades = 0; // propositions reçues en attente
  bool wheel = false; // tour de roue disponible
  bool canGift = false; // il reste des cadeaux à offrir aujourd'hui
  int giftsLeft = 0; // cadeaux encore à offrir aujourd'hui (3 par jour)
  int lots = 0; // paquets du lot encore à ouvrir
  int week = 0; // défis de la semaine à récupérer
  bool lotFree = false; // samedi : lot de 5 paquets gratuit
  int gifts = 0; // paquets cadeaux reçus à ouvrir
  String giftFrom = '';
  int chat = 0; // messages non lus
  bool mention = false; // quelqu'un t'a cité (@pseudo)
  int chatLast = 0; // dernier message (pour rafraîchir l'écran Messages)
  int _lastMention = -1;
  bool chatOpen = false; // écran Messages affiché : pas de pastille
  int _lastGifts = -1;
  List<Map<String, dynamic>> sales = []; // ventes pas encore vues
  final _announced = <int>{};
  int _lastTrades = -1; // -1 : premier passage (pas de message)
  Timer? _timer;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => refresh());
    refresh();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> refresh() async {
    try {
      final r = await RcServer.notifs();
      final t0 = (r['trades'] as num? ?? 0).toInt();
      final s = [for (final x in (r['sales'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
      // nouvelles ventes : un seul message pour toutes
      final fresh = s.where((x) => _announced.add((x['id'] as num).toInt())).toList();
      if (fresh.isNotEmpty) {
        final total = fresh.fold<int>(0, (a, x) => a + (x['price'] as num).toInt());
        if (fresh.length == 1) {
          final c = Catalog.cards[fresh.first['card']];
          final who = fresh.first['buyer'] ?? '?';
          toast(t('💰 ${c?.title ?? 'Carte'} vendue à $who : +$total pièces', '💰 ${c?.title ?? 'Card'} sold to $who: +$total coins'), color: const Color(0xFF0F6E56));
        } else {
          toast(t('💰 ${fresh.length} cartes vendues : +$total pièces', '💰 ${fresh.length} cards sold: +$total coins'), color: const Color(0xFF0F6E56));
        }
        RcAudio.sfx('coin');
        Game.i.sync(); // solde de pièces à jour
      }
      if (_lastTrades >= 0 && t0 > _lastTrades) {
        toast(t('🔄 Nouvelle proposition d\'échange !', '🔄 New trade offer!'), color: const Color(0xFF3C3489));
      }
      final g0 = (r['gifts'] as num? ?? 0).toInt();
      if (_lastGifts >= 0 && g0 > _lastGifts) {
        toast(t('🎁 ${r['gift_from'] ?? '?'} t\'a offert un paquet !', '🎁 ${r['gift_from'] ?? '?'} gave you a pack!'), color: const Color(0xFF854F0B));
      }
      final m0 = (r['mention'] as num? ?? 0).toInt();
      if (!chatOpen && _lastMention >= 0 && m0 > _lastMention && m0 > 0) {
        toast(t('💬 On t\'a mentionné dans les messages', '💬 You were mentioned in the messages'), color: const Color(0xFF3C3489));
      }
      _lastMention = m0;
      mention = !chatOpen && m0 > 0;
      chat = chatOpen ? 0 : (r['chat'] as num? ?? 0).toInt();
      chatLast = (r['chat_last'] as num? ?? 0).toInt();
      _lastGifts = g0;
      gifts = g0;
      giftFrom = r['gift_from'] as String? ?? '';
      wheel = r['wheel'] == true;
      canGift = r['can_gift'] == true;
      giftsLeft = (r['gifts_left'] as num? ?? (canGift ? 1 : 0)).toInt().clamp(0, 3);
      lots = (r['lots'] as num? ?? 0).toInt();
      week = (r['week'] as num? ?? 0).toInt();
      lotFree = r['lot_free'] == true;
      _lastTrades = t0;
      trades = t0;
      sales = s;
      notifyListeners();
      PushWatch.seen(r); // pas de notification Android pour ce qui vient d'être vu
    } catch (_) {
      // hors ligne : on réessaiera
    }
  }

  /// Messages lus (écran Messages ouvert)
  void chatRead() {
    if (chat == 0 && !mention) return;
    chat = 0;
    mention = false;
    notifyListeners();
  }

  /// Nombre total de notifications (pastille du bouton menu)
  int get total => trades + sales.length + chat + gifts + (wheel ? 1 : 0) + (mention ? 1 : 0);

  /// Les ventes ont été vues (ouverture du Marché)
  Future<void> salesSeen() async {
    if (sales.isEmpty) return;
    sales = [];
    notifyListeners();
    try {
      await RcServer.marketSeen();
    } catch (_) {}
  }
}

/// Pastille avec un nombre sur une icône d'onglet
Widget countBadge(int n, Widget child) => Badge(
      isLabelVisible: n > 0,
      backgroundColor: const Color(0xFFE24B4A),
      label: Text(n > 9 ? '9+' : '$n', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
      child: child,
    );
