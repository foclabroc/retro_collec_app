import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'library.dart';
import 'audio.dart';
import 'cards.dart';
import 'defis.dart';
import 'catalog.dart';
import 'inbox.dart';
import 'game.dart';
import 'bonus.dart';
import 'games_room.dart';
import 'guide.dart';
import 'chat.dart';
import 'duel_watch.dart';
import 'events.dart';
import 'feed.dart';
import 'layout.dart';
import 'bourse.dart';
import 'neighbors.dart';
import 'share.dart';
import 'notifs.dart';
import 'push.dart';
import 'packs.dart';
import 'parrainage.dart';
import 'retro_theme.dart';
import 'server.dart';
import 'title_screen.dart';
import 'update_check.dart';
import 'welcome.dart';
import 'whats_new.dart';
import 'rewards.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PIXEL TRADE — collection multijoueur de boîtes de jeux rétro, by foclabroc
// Langue : français si le téléphone est en français, anglais sinon.
// ═══════════════════════════════════════════════════════════════════════════

final rcMessenger = GlobalKey<ScaffoldMessengerState>();
final rcNav = GlobalKey<NavigatorState>();

/// Vrai pendant l'ouverture d'un paquet : le glissé du bord ne doit pas la fermer
int rcEdgeMenuBlocked = 0; // nombre d'écrans d'ouverture de paquet affichés

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // téléphone : toujours en portrait ; tablette : peut tourner (mode tablette en paysage)
  detectTablet();
  await loadLayoutMode();
  await applyOrientation();
  rcLayoutMode.addListener(_rebuildAll);
  await loadLang();
  await RcAudio.loadPrefs();
  await Tilt.loadPrefs();
  await loadTheme();
  rcThemeIndex.addListener(_rebuildAll);
  runApp(const RetroCollecApp());
}

/// Thème d'interface changé : tous les écrans sont redessinés (sans revenir à l'écran titre)
void _rebuildAll() {
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
}

class RetroCollecApp extends StatelessWidget {
  const RetroCollecApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Changement de langue : toute l'appli est reconstruite (retour à l'écran titre)
    return ValueListenableBuilder<int>(
      valueListenable: rcLangChanged,
      builder: (context, v, _) => MaterialApp(
      key: ValueKey('lang$v'),
      title: 'Pixel Trade',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rcMessenger,
      navigatorKey: rcNav,
      // Fond animé rétro derrière tous les écrans.
      // Android 15 (bord à bord) : rien ne passe sous la barre des boutons Android.
      // Web : la souris peut aussi faire défiler en glissant (listes, carrousels)
      scrollBehavior: const MaterialScrollBehavior().copyWith(dragDevices: {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      }),
      builder: (context, child) => _WebFrame(
        child: Stack(children: [
          const Positioned.fill(child: RetroBackground()),
          Positioned.fill(child: SafeArea(top: false, left: false, right: false, child: child ?? const SizedBox())),
          // bord gauche : glisser vers la droite ouvre le menu, depuis n'importe quel écran
          const Positioned(left: 0, top: 0, bottom: 0, width: 22, child: _EdgeMenuSwipe()),
        ]),
      ),
      theme: retroTheme(),
      home: UpdateGate(french: rcFrench, child: const StartScreen()),
      ),
    );
  }
}

/// Version web sur grand écran (PC, tablette en paysage) : l'appli reste au format
/// téléphone, centrée, sur le fond rétro. Sur mobile et sur Android : rien ne change.
class _WebFrame extends StatelessWidget {
  final Widget child;
  const _WebFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;
    final mq = MediaQuery.of(context);
    final size = mq.size;
    if (size.width <= 560 || size.width >= 900) return child; // ≥ 900 : mode tablette plein écran
    final h = size.height;
    final w = math.min(460.0, math.max(360.0, h * 0.52));
    return Stack(children: [
      const Positioned.fill(child: RetroBackground()),
      Positioned.fill(child: ColoredBox(color: Colors.black.withOpacity(0.35))),
      Center(
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            border: Border.symmetric(vertical: BorderSide(color: kGold.withOpacity(0.5), width: 2)),
            boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 40)],
          ),
          child: ClipRect(
            child: MediaQuery(data: mq.copyWith(size: Size(w, h)), child: child),
          ),
        ),
      ),
    ]);
  }
}

/// Bande invisible sur le bord gauche : un glissé vers la droite referme les écrans
/// ouverts par-dessus (album, fiche, profil…) et ouvre le menu latéral.
class _EdgeMenuSwipe extends StatefulWidget {
  const _EdgeMenuSwipe();
  @override
  State<_EdgeMenuSwipe> createState() => _EdgeMenuSwipeState();
}

class _EdgeMenuSwipeState extends State<_EdgeMenuSwipe> {
  double dx = 0;
  bool done = false;

  void _open() {
    final shell = HomeShellState.current;
    if (shell == null || rcEdgeMenuBlocked > 0) return; // écran titre, bienvenue, ouverture de paquet : pas de menu
    rcNav.currentState?.popUntil((r) => r.isFirst);
    WidgetsBinding.instance.addPostFrameCallback((_) => HomeShellState.current?.openMenu());
  }

  @override
  Widget build(BuildContext context) {
    if (isWide(context)) return const SizedBox.shrink(); // menu déjà visible à gauche
    return _build(context);
  }

  Widget _build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) {
          dx = 0;
          done = false;
        },
        onHorizontalDragUpdate: (d) {
          dx += d.delta.dx;
          if (!done && dx > 36) {
            done = true;
            _open();
          }
        },
      );
}

void toast(String msg, {Color? color}) {
  rcMessenger.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, duration: const Duration(seconds: 3)));
}

// ─── Écran titre : chargement (catalogue + serveur), avancement du joueur,
//     « touche l'écran pour jouer », numéro de version en bas ──────────────
class StartScreen extends StatefulWidget {
  const StartScreen({super.key});
  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> with TickerProviderStateMixin {
  double progress = 0;
  bool ready = false, done = false;
  DateTime? _lastBack;
  String step = '';
  String? error;
  late final AnimationController blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  // Web : le navigateur n'autorise le son qu'après une première touche
  bool _soundOn = !kIsWeb;
  int _c4Turn = 0, _gifts = 0;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // La musique d'accueil démarre dès l'écran titre (sur le web, à la première touche)
    if (!kIsWeb) RcAudio.musicStart(RcAudio.homeTrack);
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !done) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  /// Nouvelles du panneau joueur : parties de 4 en ligne où c'est ton tour, cadeaux reçus
  Future<void> _loadNews() async {
    try {
      final r = await Future.wait([RcServer.c4List(), RcServer.notifs().then((v) => [v])]);
      if (!mounted) return;
      setState(() {
        _c4Turn = r[0].where((g) => g['status'] == 'playing' && g['turn'] == g['side']).length;
        _gifts = ((r[1].first['gifts'] as num?) ?? 0).toInt();
      });
    } catch (_) {}
  }

  void _unlockSound() {
    _soundOn = true;
    if (RcAudio.musicEnabled) RcAudio.musicStart(RcAudio.homeTrack);
    setState(() {});
  }

  void _toggleSound() {
    HapticFeedback.selectionClick();
    if (!_soundOn) {
      if (!RcAudio.soundOn) RcAudio.setSound(true);
      _unlockSound();
      return;
    }
    RcAudio.setSound(!RcAudio.soundOn);
    setState(() {});
  }

  void _tap() {
    if (!_soundOn && RcAudio.soundOn) {
      _unlockSound();
      return;
    }
    _play();
  }

  @override
  void dispose() {
    blink.dispose();
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      error = null;
      step = t('Chargement…', 'Loading…');
    });
    // profil déjà créé : le serveur est interrogé pendant que le catalogue se charge (au lieu d'après)
    Future<void>? me;
    if (await RcServer.hasProfile()) {
      me = Game.i.refresh();
      me.catchError((_) {}); // l'erreur éventuelle est relue plus bas
    }
    try {
      if (!await Catalog.loadLocal()) {
        setState(() => step = t('Téléchargement des cartes…', 'Downloading cards…'));
        await Catalog.update(progress: (p, s) {
          if (mounted) {
            setState(() {
              progress = p;
              if (s.isNotEmpty) step = t('Téléchargement des cartes : $s', 'Downloading cards: $s');
            });
          }
        });
      } else {
        // catalogue déjà là : on vérifie s'il a changé (nouvelles cartes, textes, traductions)
        setState(() => step = t('Recherche de nouvelles cartes…', 'Checking for new cards…'));
        await Catalog.refreshInBackground(progress: (p, s) {
          if (mounted) {
            setState(() {
              progress = p;
              if (s.isNotEmpty) step = t('Mise à jour des cartes : $s', 'Updating cards: $s');
            });
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = t('Impossible de télécharger les cartes.\nVérifie ta connexion.', 'Could not download the cards.\nCheck your connection.'));
      return;
    }
    // Premier lancement : pseudo + avatar (ou code de sauvegarde) avant de créer le profil
    if (!await RcServer.hasProfile()) {
      if (!mounted) return;
      setState(() => step = '');
      await Navigator.of(context).push(PageRouteBuilder(
        pageBuilder: (_, __, ___) => const WelcomePage(),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ));
      if (!mounted) return;
      if (Game.i.ready) {
        setState(() => ready = true);
        return;
      }
    }
    try {
      setState(() => step = t('Connexion au serveur…', 'Connecting…'));
      if (me != null) {
        try {
          await me;
        } catch (_) {
          await Game.i.refresh(); // nouvel essai (réseau qui revient, réessai après une erreur)
        }
      } else {
        await Game.i.refresh();
      }
    } catch (e) {
      if (mounted) setState(() => error = errText(e));
      return;
    }
    if (mounted) setState(() => ready = true);
    _loadNews();
  }

  void _play() {
    if (!ready) return;
    RcAudio.sfx('continue');
    HapticFeedback.mediumImpact();
    // On reste sous UpdateGate (vérification des mises à jour) : l'accueil remplace l'écran titre
    setState(() => done = true);
  }

  static String _inText(DateTime at) {
    final d = at.difference(DateTime.now());
    if (d.isNegative) return '0 min';
    return d.inHours > 0 ? '${d.inHours} h ${(d.inMinutes % 60).toString().padLeft(2, '0')}' : '${d.inMinutes} min';
  }

  Widget _news(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: c.withOpacity(0.14), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 11.5)),
      );

  @override
  Widget build(BuildContext context) {
    if (done) {
      return HomeShell(onBackToTitle: () {
        setState(() => done = false); // la musique continue sur l'écran titre
        _loadNews();
      });
    }
    final g = Game.i;
    final total = Catalog.cards.length;
    // Écran titre : appuyer 2 fois sur retour pour quitter
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBack != null && now.difference(_lastBack!) < const Duration(seconds: 2)) {
          SystemNavigator.pop();
        } else {
          _lastBack = now;
          toast(t('Appuie encore sur retour pour quitter', 'Press back again to quit'));
        }
      },
      child: Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tap,
        child: Stack(children: [
        const Positioned.fill(child: TitleSky()),
        SafeArea(
          // pleine largeur : tout reste centré même quand seuls de petits éléments sont affichés
          child: SizedBox(
            width: double.infinity,
            child: Column(children: [
            const Spacer(flex: 2),
            const TitleFan(),
            const SizedBox(height: 18),
            const TitleLogo(),
            const SizedBox(height: 10),
            Text(t('Collection de jeux rétro', 'Retro game collection'), style: const TextStyle(color: Colors.white60, letterSpacing: 1)),
            const Spacer(),
            if (error != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              ),
              const SizedBox(height: 14),
              ElevatedButton(onPressed: _start, child: Text(t('Réessayer', 'Retry'))),
            ] else if (!ready) ...[
              SizedBox(
                width: 240,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: progress > 0 && progress < 1 ? progress : null, minHeight: 6, color: kGold, backgroundColor: kPanel2),
                ),
              ),
              const SizedBox(height: 12),
              Text(step, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
            ] else ...[
              // avancement du joueur
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 28),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kPanel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF3550B8), width: 2),
                ),
                child: Column(children: [
                  Row(children: [
                    avatarWidget(g.avatar, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(g.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        Text(t('Score ${g.score} · ${g.packs} paquets', 'Score ${g.score} · ${g.packs} packs'),
                            style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      CoinChip(g.coins),
                      const SizedBox(height: 4),
                      PixelChip(g.pixels),
                    ]),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Text(t('Collection', 'Collection'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    const Spacer(),
                    Text('${g.cards} / $total · ${total == 0 ? 0 : (g.cards * 100 / total).floor()} %',
                        style: const TextStyle(color: kGold, fontWeight: FontWeight.w800, fontSize: 12)),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: total == 0 ? 0 : g.cards / total, minHeight: 7, color: kGold, backgroundColor: kPanel2),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      if (g.free)
                        _news('🎁 ' + t('Paquet gratuit prêt', 'Free pack ready'), const Color(0xFF5DCAA5))
                      else if (g.freeAt != null)
                        _news('🎁 ' + t('Gratuit dans ${_inText(g.freeAt!)}', 'Free in ${_inText(g.freeAt!)}'), Colors.white70),
                      if (_c4Turn > 0) _news('⚔ ' + t('4 en ligne : à toi', 'Connect 4: your turn'), const Color(0xFFFF8A95)),
                      if (_gifts > 0) _news(t('$_gifts cadeau${_gifts > 1 ? 'x' : ''}', '$_gifts gift${_gifts > 1 ? 's' : ''}'), const Color(0xFFFFD166)),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 26),
              FadeTransition(
                opacity: blink,
                child: Text(
                    !_soundOn && RcAudio.soundOn ? t('▶ TOUCHE POUR LE SON', '▶ TAP FOR SOUND') : t('▶ TOUCHE POUR JOUER', '▶ TAP TO PLAY'),
                    textAlign: TextAlign.center,
                    style: pixelStyle(size: 11, color: Colors.white)),
              ),
            ],
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text('v$kRetroCollecVersion · by foclabroc', style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ),
          ]),
          ),
        ),
        // son : coupe ou remet la musique (sur le web, la première touche l'active)
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _SoundButton(on: _soundOn && RcAudio.soundOn, needsTap: !_soundOn && RcAudio.soundOn, onTap: _toggleSound),
            ),
          ),
        ),
        ]),
      ),
    ),
    );
  }
}

// ─── Écran principal : 6 rubriques dans un panneau latéral gauche ───────────────────────────────────────────
class HomeShell extends StatefulWidget {
  final VoidCallback? onBackToTitle; // retour Android depuis l'onglet Collection
  const HomeShell({super.key, this.onBackToTitle});
  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  static HomeShellState? current;
  int tab = 0;
  StreamSubscription? _evSub;
  final _queue = <Map<String, dynamic>>[];
  bool _showing = false;

  void goTo(int i) => _select(i);

  bool _away = false; // appli en arrière-plan / onglet caché (vérifications coupées)

  void _openEvents() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EventsPage()));

  @override
  void initState() {
    super.initState();
    current = this;
    WidgetsBinding.instance.addObserver(this);
    _evSub = Game.i.events.stream.listen(_onEvent);
    for (final e in Game.i.drainPending()) {
      _onEvent(e);
    }
    RcAudio.musicStart(RcAudio.homeTrack);
    Notifs.i.start();
    DuelWatch.i.start(); // défis reçus (4 en ligne, Console Wars)
    PushWatch.start(); // notifications Android, même appli fermée
    // En arrière-plan : captures d'écran des fiches (le catalogue est vérifié à l'écran titre)
    Future(() => Catalog.updateShots());
    // Nouveautés de la version (jusqu'à « Ne plus afficher ») puis cadeaux uniques du serveur
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) await maybeShowWhatsNew(context);
      if (mounted) await PushWatch.maybeAskBattery(context);
      await Game.i.claimRewards();
      if (mounted) await _upgradeGift();
      Events.i.refresh();
      if (mounted) await showInbox(context); // annonces / cadeaux de l'admin, puis sondage
      // booster payé mais pas encore choisi (appli fermée pendant le choix) : on reprend
      final p = await Game.i.pendingChoice();
      if (p != null && mounted) await showPackOpening(context, p, (p['kind'] as String?) ?? 'mixte');
    });
  }

  /// Cadeau de mise à jour (1.0.16 : 500 pièces ; 1.0.18 : 600 pièces, 8 pixels, 1 booster premium),
  /// versé une seule fois par le serveur. `reward` = même JSON que les récompenses (rewards.dart).
  Future<void> _upgradeGift() async {
    try {
      final r = await RcServer.upgradeGift(kRetroCollecVersion);
      final rw = r['reward'] ?? {'coins': r['coins'] ?? 0};
      final txt = rewardText(rw, icons: false);
      if (txt.isEmpty || !mounted) return;
      final pack = rewardHasPacks(rw);
      await Game.i.refresh();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(px(t('CADEAU', 'GIFT')), style: pixelStyle(size: 14)),
          content: Text(t('Mise à jour $kRetroCollecVersion : $txt offerts. Merci de jouer à Pixel Trade !'
                  '${pack ? '\n\nLe booster t\'attend dans Paquets → Cadeaux reçus.' : ''}',
              'Update $kRetroCollecVersion: $txt for you. Thanks for playing Pixel Trade!'
                  '${pack ? '\n\nYour pack is waiting in Packs → Gifts received.' : ''}')),
          actions: [ElevatedButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Merci !', 'Thanks!')))],
        ),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _evSub?.cancel();
    Notifs.i.stop();
    DuelWatch.i.stop();
    if (current == this) current = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour dans l'appli : nouveau jour → bonus et paquet gratuit
    if (state == AppLifecycleState.resumed) {
      if (!_away) return; // simple perte de focus (fenêtre web) : rien n'a été coupé
      _away = false;
      Game.i.sync();
      Notifs.i.start(); // relance les vérifications (et en fait une tout de suite)
      Events.i.refresh();
      DuelWatch.i.start();
      showInbox(context);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      // appli en arrière-plan ou onglet web caché : plus aucune requête régulière
      _away = true;
      DuelWatch.i.stop();
      Notifs.i.stop();
    }
  }

  void _onEvent(Map<String, dynamic> e) {
    _queue.add(e);
    if (!_showing) _next();
  }

  Future<void> _next() async {
    if (_queue.isEmpty) {
      _showing = false;
      return;
    }
    _showing = true;
    final e = _queue.removeAt(0);
    final coins = (e['coins'] as num? ?? 0).toInt();
    String msg;
    switch (e['type']) {
      case 'welcome':
        msg = t('Bienvenue dans Pixel Trade ! $coins pièces offertes', 'Welcome to Pixel Trade! $coins free coins');
      case 'login':
        final s = (e['streak'] as num? ?? 1).toInt();
        msg = t('Connexion jour $s : +$coins pièces', 'Day $s login: +$coins coins');
      case 'reward':
        msg = t('🎁 Cadeau : +$coins pièces offertes !', '🎁 Gift: +$coins free coins!');
      case 'milestone':
        final sys = Catalog.system(e['sys'] as String? ?? '')?.name ?? e['sys'];
        final saga = sagaOfSys(e['sys'] as String?);
        msg = saga != null
            ? (e['step'] == 100
                ? t('🌈 Saga ${saga.name} complète : +$coins pièces et +2 pixels !', '🌈 ${saga.name} saga complete: +$coins coins and +2 pixels!')
                : t('Saga ${saga.name} à moitié : +$coins pièces !', '${saga.name} saga half done: +$coins coins!'))
            : t('Série $sys à ${e['step']} % : +$coins pièces !', '$sys set at ${e['step']}%: +$coins coins!');
      default:
        msg = '';
    }
    if (msg.isNotEmpty) {
      RcAudio.sfx('coin');
      toast(msg, color: const Color(0xFF412402));
      await Future.delayed(const Duration(milliseconds: 2600));
    }
    _next();
  }

  final scaffoldKey = GlobalKey<ScaffoldState>();

  void openMenu() {
    final st = scaffoldKey.currentState;
    if (st != null && !st.isDrawerOpen) st.openDrawer();
  }

  void _select(int i) {
    final was = tab;
    setState(() => tab = i);
    if (was == 4 && i != 4) MessagesScreenState.current?.active(false);
    if (i == 3) BourseScreenState.current?.opened();
    if (i == 4) MessagesScreenState.current?.active(true);
    if (i == 5) NeighborsScreenState.current?.load();
    if (i == 6) {
      FeedScreenState.current?.load();
      if (Notifs.i.reacts > 0) RcServer.reactsSeen().then((_) => Notifs.i.refresh()).catchError((_) {});
    }
    if (i == 7) DefisScreenState.current?.load();
    if (i == 8) GamesRoomScreenState.current?.load();
    if (i == 2 || i == 5) Notifs.i.refresh();
    if (i == 1) PacksScreenState.reloadPending();
  }


  @override
  Widget build(BuildContext context) {
    // Bouton retour Android : menu ouvert → fermé ; autre onglet → Collection ; Collection → écran titre
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final st = scaffoldKey.currentState;
        if (st != null && st.hasDrawer) {
          // téléphone : « fin de course » du retour, il ouvre / ferme le panneau latéral à chaque appui
          if (st.isDrawerOpen) {
            st.closeDrawer();
          } else {
            st.openDrawer();
          }
        } else if (tab != 0) {
          _select(0); // mode large (menu toujours visible) : retour vers la Collection
        } else {
          widget.onBackToTitle?.call();
        }
      },
      child: Builder(builder: (context) {
        // Mode large (tablette en paysage, PC) : menu toujours visible à gauche, pas de tiroir
        final wide = isWide(context);
        final stack = IndexedStack(key: _stackKey, index: tab, children: const [
          LibraryScreen(),
          MaxWidth(child: PacksScreen()),
          MaxWidth(child: BonusScreen()),
          BourseScreen(),
          MaxWidth(child: MessagesScreen()),
          NeighborsScreen(),
          MaxWidth(child: FeedScreen()),
          MaxWidth(child: DefisScreen()),
          MaxWidth(child: GamesRoomScreen()),
        ]);
        return Scaffold(
          key: scaffoldKey,
          drawerEdgeDragWidth: wide ? 0 : 28,
          drawer: wide ? null : _menu(),
          onDrawerChanged: (open) {
            if (open) Notifs.i.refresh();
          },
          body: SafeArea(
            child: Column(children: [
              const _InfoBanner(), // bandeau d'info (page admin)
              Expanded(child: wide ? Row(children: [_rail(), Expanded(child: stack)]) : stack),
            ]),
          ),
        );
      }),
    );
  }

  final _stackKey = GlobalKey(); // garde l'état des onglets quand on passe du mode téléphone au mode large

  /// Mode large : colonne d'icônes toujours visible (mêmes rubriques et pastilles que le menu)
  Widget _rail() {
    return ListenableBuilder(
      listenable: Listenable.merge([Game.i, Notifs.i, Events.i, DuelWatch.i]),
      builder: (context, _) {
        final g = Game.i, n = Notifs.i;
        Widget item(int i, String icon, String label, {int count = 0, bool dot = false}) {
          final sel = tab == i;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Material(
              color: sel ? kGold.withOpacity(0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  if (i < 0) {
                    _openEvents();
                  } else {
                    _select(i);
                  }
                },
                child: SizedBox(
                  width: 84,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Column(children: [
                      Badge(
                        isLabelVisible: count > 0 || dot,
                        label: count > 0 ? Text(count > 99 ? '99+' : '$count') : null,
                        smallSize: 9,
                        backgroundColor: const Color(0xFFE24B4A),
                        child: TabIcon(icon, selected: sel),
                      ),
                      const SizedBox(height: 4),
                      Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10.5, fontWeight: sel ? FontWeight.w800 : FontWeight.w600, color: sel ? kGold : Colors.white70)),
                    ]),
                  ),
                ),
              ),
            ),
          );
        }

        return Container(
          width: 96,
          decoration: BoxDecoration(
            color: kBg.withOpacity(0.72),
            border: const Border(right: BorderSide(color: Colors.white12)),
          ),
          child: Column(children: [
            const SizedBox(height: 12),
            Tooltip(
              message: t('Mon profil et réglages', 'My profile and settings'),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyProfilePage())),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: kGold),
                  child: Badge(
                    isLabelVisible: n.trophies > 0,
                    label: Text(n.trophies > 99 ? '99+' : '${n.trophies}'),
                    child: avatarWidget(g.avatar, size: 50),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                child: Column(children: [
                  item(0, 'collection', t('Collection', 'Collection')),
                  item(1, 'packs', t('Paquets', 'Packs'), dot: g.free || n.lotFree, count: n.gifts + n.lots),
                  item(7, 'defis', t('Défis', 'Challenges'), count: n.week),
                  item(2, 'bonus', t('Bonus', 'Bonus'), dot: n.wheel),
                  item(8, 'games', t('Salle de jeux', 'Game room'), count: DuelWatch.i.badge),
                  item(3, 'market', t('Bourse', 'Exchange'), count: n.trades + n.sales.length),
                  item(4, 'messages', t('Messages', 'Messages'), count: n.chat, dot: n.mention),
                  item(5, 'neighbors', t('Voisinage', 'Neighbors')),
                  item(6, 'news', t('Actualités', 'News'), count: n.reacts),
                  item(-1, 'events', t('Événements', 'Events'), count: Events.i.unseen),
                ]),
              ),
            ),
            const OnlineMenuTile(compact: true),
            const ReferralMenuTile(compact: true),
            const GuideMenuTile(compact: true),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('v$kRetroCollecVersion', style: const TextStyle(color: Colors.white30, fontSize: 10)),
            ),
          ]),
        );
      },
    );
  }

  /// Panneau latéral gauche : profil en haut, puis tous les onglets avec leurs pastilles
  Widget _menu() {
    return Drawer(
      backgroundColor: kBg.withOpacity(0.95),
      width: 270,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([Game.i, Notifs.i, Events.i, DuelWatch.i]),
          builder: (context, _) {
            final g = Game.i, n = Notifs.i;
            Widget item(int i, String icon, String label, {int count = 0, bool dot = false, String? hint}) {
              final sel = tab == i;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
                child: Material(
                  color: sel ? kGold.withOpacity(0.16) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.of(context).pop();
                      if (i < 0) {
                        _openEvents();
                      } else {
                        _select(i);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: sel ? kGold.withOpacity(0.7) : Colors.transparent),
                      ),
                      child: Row(children: [
                        TabIcon(icon, selected: sel),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: sel ? kGold : Colors.white)),
                            if (hint != null) Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFFFB86B), fontSize: 11, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                        if (count > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: const Color(0xFFE24B4A), borderRadius: BorderRadius.circular(10)),
                            child: Text(count > 99 ? '99+' : '$count', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                          )
                        else if (dot)
                          Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFE24B4A), shape: BoxShape.circle)),
                      ]),
                    ),
                  ),
                ),
              );
            }

            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // en-tête : mon profil
              InkWell(
                onTap: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.push(MaterialPageRoute(builder: (_) => const MyProfilePage()));
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
                  child: Row(children: [
                    Badge(
                      isLabelVisible: n.trophies > 0,
                      label: Text(n.trophies > 99 ? '99+' : '${n.trophies}'),
                      child: avatarWidget(g.avatar, size: 42),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 4),
                        Row(mainAxisSize: MainAxisSize.min, children: [CoinChip(g.coins), const SizedBox(width: 6), PixelChip(g.pixels)]),
                      ]),
                    ),
                    const Icon(Icons.settings, color: Colors.white54, size: 20),
                  ]),
                ),
              ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Divider(color: Colors.white12, height: 1)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(padding: EdgeInsets.zero, children: [
                  item(0, 'collection', t('Collection', 'Collection')),
                  item(1, 'packs', t('Paquets', 'Packs'),
                      dot: g.free || n.lotFree, count: n.gifts + n.lots,
                      hint: n.lotFree
                          ? t('Lot de 5 paquets gratuit !', 'Free 5-pack bundle!')
                          : g.free
                              ? t('Paquet gratuit dispo !', 'Free pack ready!')
                              : null),
                  item(7, 'defis', t('Défis de la semaine', 'Weekly challenges'),
                      count: n.week, hint: n.week > 0 ? t('Récompense à récupérer !', 'Reward to claim!') : null),
                  item(2, 'bonus', t('Bonus', 'Bonus'), dot: n.wheel),
                  item(8, 'games', t('Salle de jeux', 'Game room'),
                      count: DuelWatch.i.badge,
                      hint: DuelWatch.i.invites > 0
                          ? t('⚔ ${DuelWatch.i.lastFrom ?? 'Un joueur'} te défie', '⚔ ${DuelWatch.i.lastFrom ?? 'A player'} challenges you')
                          : DuelWatch.i.turns > 0
                              ? t('🎮 À toi de jouer (${DuelWatch.i.turns})', '🎮 Your turn (${DuelWatch.i.turns})')
                              : null),
                  item(3, 'market', t('Bourse', 'Exchange'),
                      count: n.trades + n.sales.length),
                  item(4, 'messages', t('Messages', 'Messages'),
                      count: n.chat, dot: n.mention, hint: n.mention ? t('On t\'a mentionné', 'You were mentioned') : null),
                  item(5, 'neighbors', t('Voisinage', 'Neighbors'), hint: n.canGift ? t('${n.giftsLeft} cadeau(x) à offrir', '${n.giftsLeft} gift(s) to give') : null),
                  item(6, 'news', t('Actualités', 'News'),
                      count: n.reacts,
                      hint: n.reacts > 0
                          ? t('${n.reacts} réaction(s) à tes exploits', '${n.reacts} reaction(s) to your feats')
                          : null),
                  item(-1, 'events', t('Événements', 'Events'),
                      count: Events.i.unseen, hint: Events.i.unseen > 0 ? t('Nouveau !', 'New!') : null),
                ]),
              ),
              OnlineMenuTile(beforeOpen: () => Navigator.of(context).maybePop()),
              ReferralMenuTile(beforeOpen: () => Navigator.of(context).maybePop()),
              GuideMenuTile(beforeOpen: () => Navigator.of(context).maybePop()),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
                child: Text('Pixel Trade v$kRetroCollecVersion', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white30, fontSize: 10.5)),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

/// En-tête commun des onglets : titre + pièces
class TabHeader extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final String? icon; // icône de l'onglet (assets/tabs/<icon>.png) dans une pastille lumineuse
  const TabHeader(this.title, {super.key, this.actions = const [], this.icon});
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(HomeShellState.current != null && Scaffold.maybeOf(context)?.hasDrawer == true ? 4 : 16, 12, 8, 8),
        child: Row(children: [
          if (Scaffold.maybeOf(context)?.hasDrawer == true)
            ListenableBuilder(
              listenable: Listenable.merge([Game.i, Notifs.i, DuelWatch.i]),
              builder: (_, __) => IconButton(
                tooltip: t('Menu', 'Menu'),
                onPressed: () => HomeShellState.current?.openMenu(),
                icon: Badge(
                  isLabelVisible: Notifs.i.total > 0 || Game.i.free || DuelWatch.i.badge > 0,
                  backgroundColor: const Color(0xFFE24B4A),
                  smallSize: 9,
                  child: const Icon(Icons.menu, size: 28),
                ),
              ),
            ),
          // icône de l'onglet dans une pastille de la couleur du thème
          // (seulement si l'écran est assez large : le titre garde une taille lisible)
          if (icon != null && title.isNotEmpty && MediaQuery.sizeOf(context).width >= 380)
            Container(
              width: 34,
              height: 34,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color.lerp(rcTheme.accent, Colors.black, 0.45)!, Color.lerp(rcTheme.accent, Colors.black, 0.8)!],
                ),
                border: Border.all(color: rcTheme.accent, width: 1.5),
                boxShadow: [BoxShadow(color: rcTheme.accent.withOpacity(0.45), blurRadius: 12)],
              ),
              child: Padding(padding: const EdgeInsets.all(5), child: Image.asset('assets/tabs/$icon.png', filterQuality: FilterQuality.medium)),
            ),
          // titre en majuscules pixel, souligné de la couleur du thème ; il rétrécit si la place
          // manque, les pièces et les pixels gardent toujours leur taille
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: IntrinsicWidth(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  Text(px(title.toUpperCase()),
                      maxLines: 1,
                      style: pixelStyle(size: 12.5, color: Colors.white).copyWith(
                        letterSpacing: 1,
                        shadows: [Shadow(color: rcTheme.accent.withOpacity(0.7), blurRadius: 8), const Shadow(color: Colors.black, offset: Offset(0, 2))],
                      )),
                  if (title.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: LinearGradient(colors: [rcTheme.accent, rcTheme.accent.withOpacity(0)]),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ),
          ...actions,
          const SizedBox(width: 6),
          // pixels (boosters spéciaux) et pièces
          ListenableBuilder(
            listenable: Game.i,
            builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(onTap: () => _goPacks(context, pixels: true), child: PixelChip(Game.i.pixels)),
              const SizedBox(width: 6),
              GestureDetector(onTap: () => _goPacks(context, pixels: false), child: CoinChip(Game.i.coins)),
            ]),
          ),
          const SizedBox(width: 8),
        ]),
      );
}

/// Bandeau d'info réglé depuis la page admin (texte défilant si trop long), jusqu'à sa date de fin
class _InfoBanner extends StatelessWidget {
  const _InfoBanner();
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Map<String, dynamic>?>(
        valueListenable: rcBanner,
        builder: (context, b, _) {
          final until = DateTime.tryParse(b?['until']?.toString() ?? '');
          if (b == null || (until != null && until.isBefore(DateTime.now()))) return const SizedBox.shrink();
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [kGold.withOpacity(0.28), kGold.withOpacity(0.12)]),
              border: const Border(bottom: BorderSide(color: kGold, width: 1)),
            ),
            child: Row(children: [
              const Text('📢', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(b['text']?.toString() ?? '',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFFFFE2A8))),
              ),
            ]),
          );
        },
      );
}

/// Clic sur les pixels ou les pièces d'un bandeau : onglet Paquets, puis sous-menu Pixels ou boutique
void _goPacks(BuildContext context, {required bool pixels}) {
  final shell = HomeShellState.current;
  if (shell == null) return;
  Navigator.of(context).popUntil((r) => r.isFirst); // page ouverte par-dessus (mon profil) : on la ferme
  shell.goTo(1);
  WidgetsBinding.instance.addPostFrameCallback((_) => pixels ? PacksScreenState.openPixels() : PacksScreenState.showShop());
}

/// Icône d'onglet colorée (assets/tabs/<nom>.png) : estompée si l'onglet n'est pas sélectionné.
class TabIcon extends StatelessWidget {
  final String name;
  final bool selected;
  const TabIcon(this.name, {super.key, this.selected = false});
  @override
  Widget build(BuildContext context) => AnimatedScale(
        scale: selected ? 1.18 : 1,
        duration: const Duration(milliseconds: 180),
        child: Opacity(
          opacity: selected ? 1 : 0.6,
          child: Image.asset('assets/tabs/$name.png', width: 30, height: 30, filterQuality: FilterQuality.medium),
        ),
      );
}

/// Bouton son de l'écran titre (il pulse sur le web tant que le son n'est pas activé)
class _SoundButton extends StatefulWidget {
  final bool on, needsTap;
  final VoidCallback onTap;
  const _SoundButton({required this.on, required this.needsTap, required this.onTap});
  @override
  State<_SoundButton> createState() => _SoundButtonState();
}

class _SoundButtonState extends State<_SoundButton> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const neon = Color(0xFFFF4FD8);
    final label = widget.needsTap ? t('Activer le son', 'Turn sound on') : (widget.on ? t('Son', 'Sound') : t('Coupé', 'Muted'));
    return AnimatedBuilder(
      animation: c,
      builder: (_, child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [if (widget.needsTap) BoxShadow(color: neon.withOpacity(0.35 * (1 - c.value)), spreadRadius: 6 * c.value)],
        ),
        child: child,
      ),
      child: Material(
        color: const Color(0xB30A0E32),
        shape: StadiumBorder(side: BorderSide(color: widget.needsTap ? neon : Colors.white24, width: 1.5)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(widget.on ? Icons.volume_up : Icons.volume_off, size: 17, color: Colors.white),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }
}
