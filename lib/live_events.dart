import 'dart:async';

import 'chat.dart';
import 'feed.dart';
import 'live_link.dart';
import 'main.dart';
import 'market.dart';
import 'neighbors.dart';
import 'notifs.dart';
import 'trades.dart';
import 'duel_watch.dart';
import 'update_check.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Temps réel partout (1.0.18) : le serveur prévient (LiveLink.other), l'écran
// concerné se recharge tout de suite par ses RPC habituelles.
//  · 'me'     : échange reçu / répondu, carte vendue, paquet offert → notifications
//  · 'chat'   : nouveau message → écran Messages ouvert, sinon pastille
//  · 'feed'   : nouvelle actu → onglet Actu s'il est affiché
//  · 'market' : la Bourse a bougé → onglet Bourse s'il est affiché
//  · 'config' : réglages admin (bandeau, prix, maintenance, version minimale)
//  · 'online' : un joueur arrive → compteur En ligne, salle d'arcade affichée
// Chaque événement est regroupé (rafales) puis traité une fois.
// Les minuteries restent en secours, ralenties quand LiveLink.connected.
// ═══════════════════════════════════════════════════════════════════════════

class LiveEvents {
  LiveEvents._();
  static StreamSubscription? _sub;
  static final _wait = <String, Timer>{};

  static void start() {
    _sub ??= LiveLink.i.other.listen((ev) {
      _wait[ev]?.cancel();
      _wait[ev] = Timer(Duration(milliseconds: ev == 'chat' ? 300 : 1200), () => _run(ev));
    });
  }

  static int get _tab => HomeShellState.current?.tab ?? -1;

  static void _run(String ev) {
    switch (ev) {
      case 'me':
        Notifs.i.refresh();
        TradesScreenState.current?.load();
      case 'chat':
        final m = MessagesScreenState.current;
        if (m != null && Notifs.i.chatOpen) {
          m.load();
        } else {
          Notifs.i.refresh();
        }
      case 'feed':
        if (_tab == 6) FeedScreenState.current?.load();
      case 'market':
        if (_tab == 3) MarketGroupsState.current?.load();
      case 'config':
        updateGateKey.currentState?.recheck();
      case 'online':
        DuelWatch.i.refresh();
        if (_tab == 5) NeighborsScreenState.current?.load();
    }
  }
}
