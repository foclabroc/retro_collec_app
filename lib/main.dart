import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'library.dart';
import 'audio.dart';
import 'cards.dart';
import 'catalog.dart';
import 'game.dart';
import 'bonus.dart';
import 'chat.dart';
import 'events.dart';
import 'feed.dart';
import 'layout.dart';
import 'bourse.dart';
import 'neighbors.dart';
import 'notifs.dart';
import 'push.dart';
import 'packs.dart';
import 'retro_theme.dart';
import 'server.dart';
import 'title_screen.dart';
import 'update_check.dart';
import 'welcome.dart';
import 'whats_new.dart';

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
      if (!RcAudio.musicEnabled) RcAudio.setMusicEnabled(true);
      _unlockSound();
      return;
    }
    final v = !RcAudio.musicEnabled;
    RcAudio.setMusicEnabled(v);
    if (v) RcAudio.musicStart(RcAudio.homeTrack);
    setState(() {});
  }

  void _tap() {
    if (!_soundOn && RcAudio.musicEnabled) {
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
      await Game.i.refresh();
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
                    !_soundOn && RcAudio.musicEnabled ? t('▶ TOUCHE POUR LE SON', '▶ TAP FOR SOUND') : t('▶ TOUCHE POUR JOUER', '▶ TAP TO PLAY'),
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
              child: _SoundButton(on: _soundOn && RcAudio.musicEnabled, needsTap: !_soundOn && RcAudio.musicEnabled, onTap: _toggleSound),
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
    PushWatch.start(); // notifications Android, même appli fermée
    // En arrière-plan : captures d'écran des fiches (le catalogue est vérifié à l'écran titre)
    Future(() => Catalog.updateShots());
    // Nouveautés de la version (jusqu'à « Ne plus afficher ») puis cadeaux uniques du serveur
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) await maybeShowWhatsNew(context);
      if (mounted) await PushWatch.maybeAskBattery(context);
      await Game.i.claimRewards();
      Events.i.refresh();
      // booster payé mais pas encore choisi (appli fermée pendant le choix) : on reprend
      final p = await Game.i.pendingChoice();
      if (p != null && mounted) await showPackOpening(context, p, (p['kind'] as String?) ?? 'mixte');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _evSub?.cancel();
    Notifs.i.stop();
    if (current == this) current = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour dans l'appli : nouveau jour → bonus et paquet gratuit
    if (state == AppLifecycleState.resumed) {
      Game.i.sync();
      Notifs.i.refresh();
      Events.i.refresh();
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
      case 'mission':
        final m = switch (e['mission']) {
          'open' => t('ouvrir 2 paquets', 'open 2 packs'),
          'recycle' => t('recycler 5 doublons', 'recycle 5 duplicates'),
          _ => t('faire un échange ou un achat', 'make a trade or a purchase'),
        };
        msg = t('Mission accomplie ($m) : +$coins pièces', 'Mission complete ($m): +$coins coins');
      case 'reward':
        msg = t('🎁 Cadeau : +$coins pièces offertes !', '🎁 Gift: +$coins free coins!');
      case 'milestone':
        final sys = Catalog.system(e['sys'] as String? ?? '')?.name ?? e['sys'];
        msg = t('Série $sys à ${e['step']} % : +$coins pièces !', '$sys set at ${e['step']}%: +$coins coins!');
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
    if (i == 6) FeedScreenState.current?.load();
    if (i == 2 || i == 5) Notifs.i.refresh();
  }


  @override
  Widget build(BuildContext context) {
    // Bouton retour Android : menu ouvert → fermé ; autre onglet → Collection ; Collection → écran titre
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (scaffoldKey.currentState?.isDrawerOpen == true) {
          scaffoldKey.currentState?.closeDrawer();
        } else if (tab != 0) {
          _select(0);
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
        ]);
        return Scaffold(
          key: scaffoldKey,
          drawerEdgeDragWidth: wide ? 0 : 28,
          drawer: wide ? null : _menu(),
          onDrawerChanged: (open) {
            if (open) Notifs.i.refresh();
          },
          body: SafeArea(
            child: wide ? Row(children: [_rail(), Expanded(child: stack)]) : stack,
          ),
        );
      }),
    );
  }

  final _stackKey = GlobalKey(); // garde l'état des onglets quand on passe du mode téléphone au mode large

  /// Mode large : colonne d'icônes toujours visible (mêmes rubriques et pastilles que le menu)
  Widget _rail() {
    return ListenableBuilder(
      listenable: Listenable.merge([Game.i, Notifs.i, Events.i]),
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
                  child: avatarWidget(g.avatar, size: 50),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                child: Column(children: [
                  item(0, 'collection', t('Collection', 'Collection')),
                  item(1, 'packs', t('Paquets', 'Packs'), dot: g.free || n.lotFree, count: n.gifts + n.lots),
                  item(2, 'bonus', t('Bonus / Jeux', 'Bonus / Games'), dot: n.wheel),
                  item(3, 'market', t('Bourse', 'Exchange'), count: n.trades + n.sales.length),
                  item(4, 'messages', t('Messages', 'Messages'), count: n.chat, dot: n.mention),
                  item(5, 'neighbors', t('Voisinage', 'Neighbors')),
                  item(6, 'news', t('Actualités', 'News')),
                  item(-1, 'events', t('Événements', 'Events'), count: Events.i.unseen),
                ]),
              ),
            ),
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
          listenable: Listenable.merge([Game.i, Notifs.i, Events.i]),
          builder: (context, _) {
            final g = Game.i, n = Notifs.i;
            Widget item(int i, String icon, String label, {int count = 0, bool dot = false, String? hint}) {
              final sel = tab == i;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: sel ? kGold.withOpacity(0.7) : Colors.transparent),
                      ),
                      child: Row(children: [
                        TabIcon(icon, selected: sel),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: sel ? kGold : Colors.white)),
                            if (hint != null) Text(hint, style: const TextStyle(color: Colors.white54, fontSize: 11)),
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
                  padding: const EdgeInsets.fromLTRB(16, 18, 12, 14),
                  child: Row(children: [
                    avatarWidget(g.avatar, size: 48),
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
                  item(2, 'bonus', t('Bonus / Jeux', 'Bonus / Games'), dot: n.wheel, hint: t('Roue, Gamedle, quiz, 4 en ligne, Console Wars', 'Wheel, Gamedle, quiz, Connect 4, Console Wars')),
                  item(3, 'market', t('Bourse', 'Exchange'),
                      count: n.trades + n.sales.length, hint: t('Acheter, vendre, échanger', 'Buy, sell, trade')),
                  item(4, 'messages', t('Messages', 'Messages'),
                      count: n.chat, dot: n.mention, hint: n.mention ? t('On t\'a mentionné', 'You were mentioned') : null),
                  item(5, 'neighbors', t('Voisinage', 'Neighbors'), hint: n.canGift ? t('${n.giftsLeft} cadeau(x) à offrir', '${n.giftsLeft} gift(s) to give') : null),
                  item(6, 'news', t('Actualités', 'News'), hint: t('Les exploits des joueurs', 'What players are up to')),
                  item(-1, 'events', t('Événements', 'Events'),
                      count: Events.i.unseen, hint: Events.i.unseen > 0 ? t('Nouveau !', 'New!') : t('Fêtes, cadeaux, défis', 'Parties, gifts, challenges')),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text('Pixel Trade v$kRetroCollecVersion', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white30, fontSize: 11)),
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
  const TabHeader(this.title, {super.key, this.actions = const []});
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(HomeShellState.current != null && Scaffold.maybeOf(context)?.hasDrawer == true ? 4 : 16, 12, 8, 8),
        child: Row(children: [
          if (Scaffold.maybeOf(context)?.hasDrawer == true)
            ListenableBuilder(
              listenable: Listenable.merge([Game.i, Notifs.i]),
              builder: (_, __) => IconButton(
                tooltip: t('Menu', 'Menu'),
                onPressed: () => HomeShellState.current?.openMenu(),
                icon: Badge(
                  isLabelVisible: Notifs.i.total > 0 || Game.i.free,
                  backgroundColor: const Color(0xFFE24B4A),
                  smallSize: 9,
                  child: const Icon(Icons.menu, size: 28),
                ),
              ),
            ),
          // titre entier : la police se réduit si la place manque (pièces, pixels, boutons)
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(title, maxLines: 1, style: pixelStyle(size: 15)),
            ),
          ),
          ...actions,
          const SizedBox(width: 6),
          // pixels (boosters spéciaux) et pièces
          ListenableBuilder(
            listenable: Game.i,
            builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
              PixelChip(Game.i.pixels),
              const SizedBox(width: 6),
              CoinChip(Game.i.coins),
            ]),
          ),
          const SizedBox(width: 8),
        ]),
      );
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
