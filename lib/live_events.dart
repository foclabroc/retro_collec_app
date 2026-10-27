import 'dart:async';

import 'package:flutter/foundation.dart';

import 'cab_games.dart';
import 'chat.dart';
import 'connect4.dart';
import 'defis.dart';
import 'duel_watch.dart';
import 'events.dart';
import 'feed.dart';
import 'game.dart';
import 'inbox.dart';
import 'live_link.dart';
import 'main.dart';
import 'market.dart';
import 'neighbors.dart';
import 'notifs.dart';
import 'tournament.dart';
import 'trades.dart';
import 'update_check.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Temps réel partout (1.0.18) : le serveur prévient (LiveLink.other), l'écran
// concerné se recharge tout de suite par ses RPC habituelles.
//  · 'me' {k}  : trade / sale / gift → notifications (+ échanges) ;
//                prog → défis de la semaine, trophées ; react → pastille Actu
//  · 'chat'    : nouveau message → écran Messages ouvert, sinon pastille
//  · 'feed'    : nouvelle actu → onglet Actu s'il est affiché
//  · 'market'  : la Bourse a bougé → onglet Bourse s'il est affiché
//  · 'config'  : réglages admin (bandeau, prix, maintenance, version minimale)
//  · 'online' {pid} : un joueur arrive ou part → compteur, liste En ligne, salle d'arcade,
//                salons et parties (pastille en ligne), profil de ce joueur s'il est ouvert
//  · 'duels'   : un duel en direct commence / finit → listes « À regarder », salle
//  · 'mail'    : courrier ou sondage de l'admin → affiché tout de suite (après une partie)
//  · 'events'  : événements modifiés → liste + prix / promos
//  · 'player' {pid} : profil ou collection d'un joueur changé → pages ouvertes de ce joueur
//  · 'tour'    : un tournoi a bougé → pages des tournois (Tours.ping) + mon match (DuelWatch)
// Traitement quasi immédiat : seules les rafales d'un même tour (≈ 80 ms) sont regroupées.
// Les minuteries restent en secours, ralenties quand LiveLink.connected.
// ═══════════════════════════════════════════════════════════════════════════

class LiveEvents {
  LiveEvents._();
  static StreamSubscription? _sub;
  static final _wait = <String, Timer>{};

  /// Un joueur est arrivé / parti, ou un duel en direct a commencé / fini
  static final online = ValueNotifier<int>(0);

  /// Mes défis de la semaine ou trophées ont avancé
  static final prog = ValueNotifier<int>(0);

  /// Profil ou collection d'un joueur changé (pid)
  static final _player = StreamController<String>.broadcast();
  static Stream<String> get player => _player.stream;

  static void start() {
    _sub ??= LiveLink.i.other.listen((m) {
      final ev = m['ev'] as String? ?? '';
      if (ev == 'hello') return; // le relais confirme l'abonnement
      final pid = m['pid'] as String?;
      if ((ev == 'player' || ev == 'online') && pid != null) _later('player:$pid', 80, () => _player.add(pid));
      if (ev == 'player') return;
      if (ev == 'me' && m['k'] == 'cabrec') {
        // quelqu'un a battu le record de ma borne
        final g = kCabGames[m['game']];
        toast(t('🏆 ${m['name']} a battu le record de ta borne${g == null ? '' : ' sur ${g.fr}'} : ${m['score']}',
            '🏆 ${m['name']} beat your cabinet\'s record${g == null ? '' : ' on ${g.en}'}: ${m['score']}'));
        return;
      }
      final key = ev == 'me' ? 'me:${m['k']}' : ev;
      _later(key, ev == 'chat' ? 0 : 80, () => _run(ev, m['k'] as String?));
    });
  }

  static void _later(String key, int ms, void Function() f) {
    _wait[key]?.cancel();
    _wait[key] = Timer(Duration(milliseconds: ms), () {
      _wait.remove(key);
      f();
    });
  }

  static int get _tab => HomeShellState.current?.tab ?? -1;

  static void _run(String ev, String? k) {
    switch (ev) {
      case 'me':
        Notifs.i.refresh();
        if (k == 'trade' || k == 'sale' || k == 'gift') Game.i.sync(); // collection, consoles, pièces à jour tout de suite
        if (k == 'trade') TradesScreenState.current?.load();
        if (k == 'react' && _tab == 6) FeedScreenState.current?.load();
        if (k == 'prog') {
          DefisScreenState.current?.load();
          prog.value++;
        }
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
        online.value++;
        if (_tab == 5) NeighborsScreenState.current?.load();
      case 'duels':
        if (LiveGames.i.watched) LiveGames.i.refresh();
        online.value++;
        if (_tab == 5) NeighborsScreenState.current?.load();
      case 'mail':
        _inbox();
      case 'cab':
        if (_tab == 5) NeighborsScreenState.current?.load(); // record ou jeu d'une borne changé
      case 'tour':
        Tours.ping.value++;
        DuelWatch.i.refresh();
      case 'events':
        Events.i.refresh();
        updateGateKey.currentState?.recheck(); // promos, prix
    }
  }

  /// Courrier / sondage : tout de suite, sauf pendant une partie (on réessaie toutes les 5 s)
  static void _inbox([int tries = 0]) {
    final ctx = HomeShellState.current?.context;
    if (ctx == null || !ctx.mounted || tries > 180) return;
    if (DuelWatch.i.inGame > 0) {
      _later('mail', 5000, () => _inbox(tries + 1));
      return;
    }
    showInbox(ctx);
  }
}
