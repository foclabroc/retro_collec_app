import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'library.dart';
import 'audio.dart';
import 'cards.dart';
import 'catalog.dart';
import 'game.dart';
import 'bonus.dart';
import 'chat.dart';
import 'market.dart';
import 'neighbors.dart';
import 'notifs.dart';
import 'packs.dart';
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

// ─── Écran principal : 7 rubriques dans un panneau latéral gauche ───────────────────────────────────────────
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
    // En arrière-plan : captures d'écran des fiches (le catalogue est vérifié à l'écran titre)
    Future(() => Catalog.updateShots());
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

  void openMenu() => scaffoldKey.currentState?.openDrawer();

  void _select(int i) {
    final was = tab;
    setState(() => tab = i);
    if (was == 5 && i != 5) MessagesScreenState.current?.active(false);
    if (i == 3) TradesScreenState.current?.load();
    if (i == 4) MarketScreenState.current?.opened();
    if (i == 5) MessagesScreenState.current?.active(true);
    if (i == 6) NeighborsScreenState.current?.load();
    if (i == 2 || i == 6) Notifs.i.refresh();
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
      child: Scaffold(
        key: scaffoldKey,
        drawerEdgeDragWidth: 28,
        drawer: _menu(),
        onDrawerChanged: (open) {
          if (open) Notifs.i.refresh();
        },
        body: SafeArea(
          child: IndexedStack(index: tab, children: const [
            LibraryScreen(),
            PacksScreen(),
            BonusScreen(),
            TradesScreen(),
            MarketScreen(),
            MessagesScreen(),
            NeighborsScreen(),
          ]),
        ),
      ),
    );
  }

  /// Panneau latéral gauche : profil en haut, puis tous les onglets avec leurs pastilles
  Widget _menu() {
    return Drawer(
      backgroundColor: const Color(0xF20A1033),
      width: 270,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([Game.i, Notifs.i]),
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
                      _select(i);
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
                        CoinChip(g.coins),
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
                      dot: g.free, count: n.gifts, hint: g.free ? t('Paquet gratuit dispo !', 'Free pack ready!') : null),
                  item(2, 'bonus', t('Bonus', 'Bonus'), dot: n.wheel, hint: t('Roue et quiz', 'Wheel and quiz')),
                  item(3, 'trades', t('Échanges', 'Trades'), count: n.trades),
                  item(4, 'market', t('Marché', 'Market'), count: n.sales.length),
                  item(5, 'messages', t('Messages', 'Messages'),
                      count: n.chat, dot: n.mention, hint: n.mention ? t('On t\'a mentionné', 'You were mentioned') : null),
                  item(6, 'neighbors', t('Voisinage', 'Neighbors'), hint: n.canGift ? t('Cadeau du jour à offrir', 'Daily gift to give') : null),
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
