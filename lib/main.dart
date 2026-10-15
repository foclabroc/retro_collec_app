import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'library.dart';
import 'audio.dart';
import 'cards.dart';
import 'catalog.dart';
import 'game.dart';
import 'market.dart';
import 'packs.dart';
import 'profile.dart';
import 'trades.dart';
import 'retro_theme.dart';
import 'server.dart';
import 'update_check.dart';
import 'welcome.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PIXEL TRADE — collection multijoueur de boîtes de jeux rétro, by foclabroc
// Langue : français si le téléphone est en français, anglais sinon.
// ═══════════════════════════════════════════════════════════════════════════

final rcMessenger = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  await loadLang();
  await RcAudio.loadPrefs();
  await Tilt.loadPrefs();
  runApp(const RetroCollecApp());
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
      // Fond animé rétro derrière tous les écrans.
      // Android 15 (bord à bord) : rien ne passe sous la barre des boutons Android.
      builder: (context, child) => Stack(children: [
        const Positioned.fill(child: RetroBackground()),
        Positioned.fill(child: SafeArea(top: false, left: false, right: false, child: child ?? const SizedBox())),
      ]),
      theme: retroTheme(),
      home: UpdateGate(french: rcFrench, child: const StartScreen()),
      ),
    );
  }
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
  late final AnimationController float = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    blink.dispose();
    float.dispose();
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
  }

  void _play() {
    if (!ready) return;
    RcAudio.sfx('continue');
    HapticFeedback.mediumImpact();
    // On reste sous UpdateGate (vérification des mises à jour) : l'accueil remplace l'écran titre
    setState(() => done = true);
  }

  @override
  Widget build(BuildContext context) {
    if (done) {
      return HomeShell(onBackToTitle: () {
        RcAudio.musicStop();
        setState(() => done = false);
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
        onTap: _play,
        child: SafeArea(
          // pleine largeur : tout reste centré même quand seuls de petits éléments sont affichés
          child: SizedBox(
            width: double.infinity,
            child: Column(children: [
            const Spacer(flex: 2),
            // carte qui flotte
            AnimatedBuilder(
              animation: float,
              builder: (_, child) => Transform.translate(
                offset: Offset(0, -8 + 16 * Curves.easeInOut.transform(float.value)),
                child: Transform.rotate(angle: -0.06 + 0.12 * Curves.easeInOut.transform(float.value), child: child),
              ),
              child: const SizedBox(width: 150, child: CardBack(aura: kGold, glow: 0.7)),
            ),
            const SizedBox(height: 30),
            Text('PIXEL', style: pixelStyle(size: 30)),
            const SizedBox(height: 8),
            Text('TRADE', style: pixelStyle(size: 30, color: const Color(0xFF3DD9FF))),
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
                  child: LinearProgressIndicator(value: progress > 0 && progress < 1 ? progress : null, minHeight: 6, color: kGold, backgroundColor: const Color(0xFF26306B)),
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
                    CoinChip(g.coins),
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
                    child: LinearProgressIndicator(value: total == 0 ? 0 : g.cards / total, minHeight: 7, color: kGold, backgroundColor: const Color(0xFF26306B)),
                  ),
                  if (g.free) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      const Icon(Icons.card_giftcard, color: Color(0xFF5DCAA5), size: 18),
                      const SizedBox(width: 6),
                      Text(t('Ton paquet du jour t\'attend !', 'Your daily pack is waiting!'),
                          style: const TextStyle(color: Color(0xFF5DCAA5), fontWeight: FontWeight.w700)),
                    ]),
                  ],
                ]),
              ),
              const SizedBox(height: 26),
              FadeTransition(
                opacity: blink,
                child: Text(t('TOUCHE L\'ÉCRAN POUR JOUER', 'TAP THE SCREEN TO PLAY'), textAlign: TextAlign.center, style: pixelStyle(size: 11, color: Colors.white)),
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
      ),
    ),
    );
  }
}

// ─── Écran principal : 5 onglets ───────────────────────────────────────────
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

  void goTo(int i) => setState(() => tab = i);

  @override
  void initState() {
    super.initState();
    current = this;
    WidgetsBinding.instance.addObserver(this);
    _evSub = Game.i.events.stream.listen(_onEvent);
    for (final e in Game.i.drainPending()) {
      _onEvent(e);
    }
    RcAudio.musicStart(1);
    // En arrière-plan : captures d'écran des fiches (le catalogue est vérifié à l'écran titre)
    Future(() => Catalog.updateShots());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _evSub?.cancel();
    if (current == this) current = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour dans l'appli : nouveau jour → bonus et paquet gratuit
    if (state == AppLifecycleState.resumed) Game.i.sync();
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

  @override
  Widget build(BuildContext context) {
    // Bouton retour Android : autre onglet → Collection ; Collection → écran titre (l'appli ne se ferme pas)
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (tab != 0) {
          setState(() => tab = 0);
        } else {
          widget.onBackToTitle?.call();
        }
      },
      child: ListenableBuilder(
      listenable: Game.i,
      builder: (context, _) => Scaffold(
        body: SafeArea(
          child: IndexedStack(index: tab, children: const [
            LibraryScreen(),
            PacksScreen(),
            TradesScreen(),
            MarketScreen(),
            ProfileScreen(),
          ]),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: [
            NavigationDestination(icon: const TabIcon('collection'), selectedIcon: const TabIcon('collection', selected: true), label: t('Collection', 'Collection')),
            NavigationDestination(
              icon: Badge(isLabelVisible: Game.i.free, child: const TabIcon('packs')),
              selectedIcon: Badge(isLabelVisible: Game.i.free, child: const TabIcon('packs', selected: true)),
              label: t('Paquets', 'Packs'),
            ),
            NavigationDestination(icon: const TabIcon('trades'), selectedIcon: const TabIcon('trades', selected: true), label: t('Échanges', 'Trades')),
            NavigationDestination(icon: const TabIcon('market'), selectedIcon: const TabIcon('market', selected: true), label: t('Marché', 'Market')),
            NavigationDestination(icon: const TabIcon('profile'), selectedIcon: const TabIcon('profile', selected: true), label: t('Profil', 'Profile')),
          ],
        ),
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
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Row(children: [
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: pixelStyle(size: 15))),
          ...actions,
          const SizedBox(width: 6),
          ListenableBuilder(listenable: Game.i, builder: (_, __) => CoinChip(Game.i.coins)),
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
