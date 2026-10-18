import 'dart:math' show Random;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio.dart';
import 'catalog.dart';
import 'retro_theme.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// État du joueur (copie locale de ce que renvoie le serveur) + réglages communs
// ═══════════════════════════════════════════════════════════════════════════

/// Langue : réglage 'auto' (langue du téléphone), 'fr' ou 'en'.
bool rcFrench = true;
String rcLang = 'auto';
String t(String fr, String en) => rcFrench ? fr : en;

/// Incrémenté à chaque changement de langue : l'appli se reconstruit entièrement.
final rcLangChanged = ValueNotifier<int>(0);

void _applyLang() {
  final phoneFr = WidgetsBinding.instance.platformDispatcher.locale.languageCode.toLowerCase() == 'fr';
  rcFrench = rcLang == 'fr' || (rcLang == 'auto' && phoneFr);
}

Future<void> loadLang() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('rc_lang') ?? 'auto';
    rcLang = const ['auto', 'fr', 'en'].contains(v) ? v : 'auto';
  } catch (_) {}
  _applyLang();
}

Future<void> setLang(String lang) async {
  rcLang = lang;
  _applyLang();
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rc_lang', lang);
  } catch (_) {}
  rcLangChanged.value++;
}

// Raretés : 0 commune … 4 légendaire
const kRarityColor = [Color(0xFF888780), Color(0xFF639922), Color(0xFF378ADD), Color(0xFF9C8CFF), Color(0xFFEF9F27)];
const kRarityDark = [Color(0xFF444441), Color(0xFF173404), Color(0xFF042C53), Color(0xFF26215C), Color(0xFF412402)];
const kRarityLight = [Color(0xFFD3D1C7), Color(0xFFC0DD97), Color(0xFFB5D4F4), Color(0xFFCECBF6), Color(0xFFFAC775)];
String rarityName(int r) => [
      t('Commune', 'Common'),
      t('Peu commune', 'Uncommon'),
      t('Rare', 'Rare'),
      t('Épique', 'Epic'),
      t('Légendaire', 'Legendary'),
    ][r.clamp(0, 4)];

// Finitions : 0 normale, 1 brillante, 2 dorée, 3 full art (épiques et légendaires)
const kFinishes = 4;
String finishName(int f) => [t('Normale', 'Normal'), t('Brillante', 'Holo'), t('Dorée', 'Gold'), t('Full art', 'Full art')][f.clamp(0, 3)];

/// Nombre total d'exemplaires (toutes finitions)
int qSum(List<int> q) => q.fold(0, (a, b) => a + b);

/// Meilleure finition possédée (full art > dorée > brillante > normale)
int bestFinish(List<int>? q) {
  if (q == null) return 0;
  for (var f = q.length - 1; f > 0; f--) {
    if (q[f] > 0) return f;
  }
  return 0;
}

// Mêmes valeurs que le SQL (rc__recycle_value, rc__craft_cost, rc__pack_price)
int recycleValue(int r, int f) => const [5, 15, 50, 150, 500][r] * const [1, 3, 10, 30][f];
int craftCost(int r) => const [50, 150, 500, 1500, 5000][r];
/// Boosters spéciaux payés en pixels (1 pixel par booster ouvert)
const kSpecialPrice = {'star': 15, 'sconsole': 25, 'gold': 40};
const kPackPrice = {'free': 0, 'mixte': 100, 'console': 150, 'premium': 400, 'mystery': 120, 'gift': 0, 'lot': 0};
const kLotPrice = 500; // lot de 5 paquets mixtes (gratuit le samedi)

const kGold = Color(0xFFEF9F27);
// Couleurs de fond selon le thème d'interface choisi (retro_theme.dart)
Color get kBg => rcTheme.bg; // fond des feuilles et dialogues
Color get kPanel => rcTheme.panel; // panneaux semi-transparents sur le fond animé
Color get kPanel2 => rcTheme.panel2;

/// Avatars : 18 personnages pixel art (assets/avatars/avatar_NN.webp).
/// La couleur sert de liseré autour de l'avatar.
const kAvatars = <Color>[
  Color(0xFF378ADD), Color(0xFF639922), Color(0xFF3E6FC2), Color(0xFF5A6378), Color(0xFFED93B1), Color(0xFFD9483B),
  Color(0xFF2E2E38), Color(0xFF8A8F9C), Color(0xFFB0B4BE), Color(0xFFE8863A), Color(0xFF4E9A4A), Color(0xFF6E9A2E),
  Color(0xFF3BA7E8), Color(0xFF4F6B4A), Color(0xFF7B55C7), Color(0xFF9C5FD0), Color(0xFFC8735A), Color(0xFF8A5A3B),
];

Widget avatarWidget(int a, {double size = 40}) {
  final i = a.abs() % kAvatars.length;
  final color = kAvatars[i];
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFF14204F),
      shape: BoxShape.circle,
      border: Border.all(color: color, width: size >= 40 ? 2 : 1.5),
    ),
    child: ClipOval(
      child: Image.asset(
        'assets/avatars/avatar_${i.toString().padLeft(2, '0')}.webp',
        fit: BoxFit.cover,
        filterQuality: FilterQuality.none, // pixel art net
        errorBuilder: (_, __, ___) => Icon(Icons.person, color: color, size: size * 0.55),
      ),
    ),
  );
}

/// Objet possédé : une carte dans une finition
class Owned {
  final String card;
  final int finish, qty;
  const Owned(this.card, this.finish, this.qty);
}

/// Liste [[carte, finition, qté], …] → map carte → [qté normale, brillante, dorée, full art]
Map<String, List<int>> parseOwned(dynamic raw) {
  final out = <String, List<int>>{};
  if (raw is! List) return out;
  for (final e in raw) {
    if (e is! List || e.length < 3) continue;
    final q = out[e[0] as String] ??= [0, 0, 0, 0];
    q[(e[1] as num).toInt().clamp(0, 3)] = (e[2] as num).toInt();
  }
  return out;
}

class Game extends ChangeNotifier {
  Game._();
  static final Game i = Game._();

  bool ready = false;
  String pid = '', name = '', showcase = '';
  String house = ''; // maison du Voisinage (chargée avec le Voisinage)
  int avatar = 0, coins = 0, score = 0, cards = 0, packs = 0, pity = 0, streak = 0;
  bool free = false;
  int pixels = 0; // 1 par booster ouvert, échangeables contre des boosters spéciaux
  DateTime? freeAt; // prochain paquet gratuit (toutes les 6 h) ; null = inconnu (ancien serveur : minuit)
  Map<String, dynamic> missions = {};
  Set<String> milestones = {};
  Map<String, List<int>> owned = {};

  /// Événements à afficher (bonus de connexion, missions, paliers…)
  final events = StreamController<Map<String, dynamic>>.broadcast();

  int qty(String card, [int? finish]) {
    final q = owned[card];
    if (q == null) return 0;
    return finish == null ? qSum(q) : q[finish];
  }

  bool has(String card) => qty(card) > 0;

  int ownedIn(String sys) => (Catalog.bySys[sys] ?? const []).where((c) => has(c.id)).length;

  int get dupes {
    var n = 0;
    for (final q in owned.values) {
      for (final x in q) {
        if (x > 1) n += x - 1;
      }
    }
    return n;
  }

  /// Cartes dont on peut fusionner des exemplaires (5 normales ou 3 brillantes)
  int get fusable => owned.values.where((q) => q[0] >= 5 || q[1] >= 3).length;

  /// Exemplaires brillants et dorés
  int get holoCount => owned.values.fold(0, (a, q) => a + q[1]);
  int get goldCount => owned.values.fold(0, (a, q) => a + q[2]);
  int get fullArtCount => owned.values.fold(0, (a, q) => a + q[3]);

  // ── Dernières cartes obtenues (mémorisées sur le téléphone) ──
  final recent = <(String, int)>[];
  bool _recentLoaded = false;

  Future<void> loadRecent() async {
    if (_recentLoaded) return;
    _recentLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final x in prefs.getStringList('rc_recent') ?? const <String>[]) {
        final p = x.split(':');
        if (p.length == 2) recent.add((p[0], int.tryParse(p[1]) ?? 0));
      }
      notifyListeners();
    } catch (_) {}
  }

  void addRecent(String card, int f) {
    recent.removeWhere((e) => e.$1 == card && e.$2 == f);
    recent.insert(0, (card, f));
    if (recent.length > 12) recent.removeRange(12, recent.length);
    SharedPreferences.getInstance().then((p) => p.setStringList('rc_recent', [for (final (c, f) in recent) '$c:$f'])).catchError((_) => true);
  }

  int get dupesValue {
    var v = 0;
    owned.forEach((id, q) {
      final c = Catalog.cards[id];
      if (c == null) return;
      for (var f = 0; f < kFinishes; f++) {
        if (q[f] > 1) v += recycleValue(c.rarity, f) * (q[f] - 1);
      }
    });
    return v;
  }

  List<(String, int)> get showcaseItems => parseItems(showcase);

  void _apply(Map<String, dynamic> m) {
    pid = m['pid'] as String? ?? pid;
    name = m['name'] as String? ?? name;
    avatar = (m['avatar'] as num? ?? avatar).toInt();
    coins = (m['coins'] as num? ?? coins).toInt();
    score = (m['score'] as num? ?? score).toInt();
    cards = (m['cards'] as num? ?? cards).toInt();
    packs = (m['packs'] as num? ?? packs).toInt();
    pity = (m['pity'] as num? ?? pity).toInt();
    streak = (m['streak'] as num? ?? streak).toInt();
    free = m['free'] as bool? ?? free;
    pixels = (m['pixels'] as num? ?? pixels).toInt();
    final fi = (m['free_in'] as num?)?.toInt();
    freeAt = fi == null || free ? null : DateTime.now().add(Duration(seconds: fi));
    showcase = m['showcase'] as String? ?? showcase;
    if (m['missions'] is Map) missions = Map<String, dynamic>.from(m['missions'] as Map);
    if (m['milestones'] is List) {
      milestones = {for (final x in m['milestones'] as List) if (x is List) '${x[0]}:${x[1]}'};
    }
    if (m.containsKey('owned')) owned = parseOwned(m['owned']);
  }

  final _pending = <Map<String, dynamic>>[]; // événements reçus avant l'écran principal (écran titre)

  void emit(dynamic evs) {
    if (evs is! List) return;
    for (final e in evs) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      if (events.hasListener) {
        events.add(m);
      } else {
        _pending.add(m);
      }
    }
  }

  /// Événements en attente (bonus de connexion…), à afficher en arrivant sur l'écran principal.
  List<Map<String, dynamic>> drainPending() {
    final l = List<Map<String, dynamic>>.from(_pending);
    _pending.clear();
    return l;
  }

  /// Recharge tout depuis le serveur. Lève RcError hors ligne.
  Future<void> refresh() async {
    final m = await RcServer.me();
    _apply(m);
    ready = true;
    notifyListeners();
    emit(m['events']);
  }

  /// Rafraîchit sans lever d'erreur (après une action).
  Future<void> sync() async {
    try {
      await refresh();
    } catch (_) {}
  }

  Future<Map<String, dynamic>> openPack(String kind, [String? sys]) async {
    final r = await RcServer.open(kind, sys);
    if (kind == 'free') free = false;
    _applyPack(r);
    return r;
  }

  bool _choiceOk = true; // faux si le serveur n'a pas encore patch_choix_booster.sql

  /// Achat avec choix parmi 6 boosters : renvoie {choose: 6, kind, sys, resumed…},
  /// ou directement les cartes (comme [openPack]) si le serveur n'est pas à jour.
  Future<Map<String, dynamic>> openChoice(String kind, [String? sys]) async {
    if (_choiceOk) {
      try {
        final r = await RcServer.openChoice(kind, sys);
        coins = (r['coins'] as num? ?? coins).toInt();
        pixels = (r['pixels'] as num? ?? pixels).toInt();
        if (kind == 'free' && r['resumed'] != true) {
          free = false;
          freeAt = DateTime.now().add(const Duration(hours: 6));
        }
        notifyListeners();
        return autoPickGift(r);
      } on RcError catch (e) {
        if (!'$e'.contains('Could not find the function')) rethrow;
        _choiceOk = false;
      }
    }
    return openPack(kind, sys);
  }

  /// Paquet cadeau : pas de choix, un booster de couleur au hasard.
  Future<Map<String, dynamic>> autoPickGift(Map<String, dynamic> r) async {
    if (r['choose'] != null && r['cards'] == null && r['kind'] == 'gift') return pickPack(Random().nextInt(6));
    return r;
  }

  /// Booster choisi (0 à 5) : ses cartes arrivent dans la collection.
  Future<Map<String, dynamic>> pickPack(int choice) async {
    final r = await RcServer.pick(choice);
    _applyPack(r);
    return r;
  }

  /// Achat payé mais booster pas encore choisi (appli fermée entre les deux), ou null.
  Future<Map<String, dynamic>?> pendingChoice() async {
    if (!_choiceOk) return null;
    try {
      return await RcServer.pending();
    } catch (_) {
      return null;
    }
  }

  void _applyPack(Map<String, dynamic> r) {
    coins = (r['coins'] as num? ?? coins).toInt();
    pixels = (r['pixels'] as num? ?? pixels).toInt();
    pity = (r['pity'] as num? ?? pity).toInt();
    score = (r['score'] as num? ?? score).toInt();
    packs++;
    for (final c in (r['cards'] as List? ?? const [])) {
      final q = owned[c['c'] as String] ??= [0, 0, 0, 0];
      q[(c['f'] as num).toInt()]++;
    }
    // les meilleures cartes du paquet en tête des « dernières cartes »
    final got = [for (final c in (r['cards'] as List? ?? const [])) (c['c'] as String, (c['f'] as num).toInt(), (c['r'] as num? ?? 0).toInt())]
      ..sort((a, b) => (a.$3 * 4 + a.$2).compareTo(b.$3 * 4 + b.$2));
    for (final (c, f, _) in got) {
      addRecent(c, f);
    }
    notifyListeners();
  }

  Future<int> recycle(String card, int finish, int n) async {
    final r = await RcServer.recycle(card, finish, n);
    await sync();
    emit(r['events']);
    return (r['gain'] as num? ?? 0).toInt();
  }

  Future<(int, int)> recycleDupes() async {
    final r = await RcServer.recycleDupes();
    await sync();
    emit(r['events']);
    return ((r['count'] as num? ?? 0).toInt(), (r['gain'] as num? ?? 0).toInt());
  }

  /// Met à jour pièces et pixels après une récompense
  void setWallet(Map<String, dynamic> r) {
    coins = (r['coins'] as num? ?? coins).toInt();
    pixels = (r['pixels'] as num? ?? pixels).toInt();
    notifyListeners();
  }

  /// Verse les cadeaux uniques du serveur (sans erreur si hors ligne ou patch SQL absent)
  Future<void> claimRewards() async {
    try {
      final r = await RcServer.claim();
      if (r['coins'] != null) coins = (r['coins'] as num).toInt();
      notifyListeners();
      emit(r['events']);
    } catch (_) {}
  }

  /// Fusion d'exemplaires en une finition supérieure ; renvoie la nouvelle finition
  Future<int> fuse(String card, int finish) async {
    final r = await RcServer.fuse(card, finish);
    addRecent(card, finish + 1);
    await sync();
    emit(r['events']);
    return (r['f'] as num? ?? finish + 1).toInt();
  }

  Future<void> craft(String card) async {
    final r = await RcServer.craft(card);
    addRecent(card, 0);
    await sync();
    emit(r['events']);
  }

  Future<void> setProfile({String? newName, int? newAvatar, String? newShowcase}) async {
    final res = await RcServer.setProfile(newName ?? name, newAvatar ?? avatar, newShowcase ?? showcase);
    if (res == 'taken') throw RcError(t('Ce pseudo est déjà pris', 'This name is already taken'));
    if (res == 'showcase') throw RcError(t('Carte de vitrine non possédée', 'Showcase card not owned'));
    name = newName ?? name;
    avatar = newAvatar ?? avatar;
    showcase = newShowcase ?? showcase;
    notifyListeners();
  }

  void setCoins(int c) {
    coins = c;
    notifyListeners();
  }

  void playSound(int rarity) {
    RcAudio.sfx(const ['jump', 'coin', 'tier', 'continue', 'powerup'][rarity.clamp(0, 4)]);
  }
}

/// 'carte:finition,…' → [(carte, finition)]
List<(String, int)> parseItems(String s) => [
      for (final x in s.split(','))
        if (x.trim().isNotEmpty) (x.split(':')[0], int.tryParse(x.split(':').length > 1 ? x.split(':')[1] : '0') ?? 0),
    ];

String itemsToString(List<(String, int)> items) => items.map((e) => '${e.$1}:${e.$2}').join(',');

/// Message d'erreur lisible (serveur ou hors ligne)
String errText(Object e) {
  if (e is RcError) {
    if (e.offline) return t('Pas de connexion au serveur', 'No connection to the server');
    return switch (e.message) {
      'pas assez de pièces' => t('Pas assez de pièces', 'Not enough coins'),
      'pas assez de pixels' => t('Pas assez de pixels', 'Not enough pixels'),
      'pas ton tour' => t('Ce n\'est pas ton tour', 'It\'s not your turn'),
      'colonne pleine' => t('Cette colonne est pleine', 'This column is full'),
      'partie terminée' => t('La partie est terminée', 'The game is over'),
      'joueur hors ligne' => t('Ce joueur n\'est plus en ligne', 'This player is no longer online'),
      'partie déjà en cours' => t('Vous avez déjà une partie en cours', 'You already have a game going'),
      'trop de parties' => t('Trop de parties en cours (15 max.)', 'Too many games (15 max)'),
      'invitation expirée' => t('Cette invitation a expiré', 'This invitation has expired'),
      'adversaire sans pièces' => t('Ton adversaire n\'a plus assez de pièces', 'Your opponent doesn\'t have enough coins'),
      'déjà récupéré' => t('Récompense déjà récupérée', 'Reward already claimed'),
      'événement terminé' => t('Cet événement est terminé', 'This event has ended'),
      'flotte invalide' => t('Flotte invalide', 'Invalid fleet'),
      'flotte déjà placée' => t('Ta flotte est déjà placée', 'Your fleet is already placed'),
      'case déjà visée' => t('Tu as déjà tiré sur cette case', 'You already shot this cell'),
      'pas de palier à récupérer' => t('Aucun palier à récupérer pour l\'instant', 'No step to claim yet'),
      'déjà proposé' => t('Tu as déjà proposé ce jeu', 'You already guessed this game'),
      'gamedle terminé' => t('Gamedle terminé : reviens demain !', 'Gamedle over: come back tomorrow!'),
      'pas assez d\'exemplaires' => t('Pas assez d\'exemplaires pour fusionner', 'Not enough copies to fuse'),
      'fusion impossible' => t('Fusion impossible', 'Cannot fuse'),
      'déjà ouvert aujourd\'hui' => t('Paquet gratuit déjà ouvert aujourd\'hui', 'Free pack already opened today'),
      'dernier exemplaire' => t('Tu dois garder au moins un exemplaire', 'You must keep at least one copy'),
      'trop de lots' => t('12 lots maximum en vente', '12 listings maximum'),
      'carte non possédée' => t('Carte non possédée', 'Card not owned'),
      'trop d\'échanges en attente' => t('Trop d\'échanges en attente', 'Too many pending trades'),
      'tu ne possèdes pas ces cartes' => t('Tu ne possèdes plus ces cartes', 'You no longer own these cards'),
      'code invalide' => t('Code invalide : il faut 32 caractères (0-9, A-F)', 'Invalid code: 32 characters needed (0-9, A-F)'),
      'code inconnu' => t('Aucun profil avec ce code', 'No profile with this code'),
      'déjà tourné aujourd\'hui' => t('Roue déjà tournée aujourd\'hui', 'Wheel already spun today'),
      'cadeau déjà offert' => t('Tu as déjà offert tes 3 paquets aujourd\'hui', 'You already gave your 3 packs today'),
      'déjà offert à ce joueur' => t('Tu as déjà offert un paquet à ce joueur aujourd\'hui', 'You already gave this player a pack today'),
      'aucun paquet du lot' => t('Plus de paquet dans ton lot', 'No pack left in your bundle'),
      'pas à toi-même' => t('Tu ne peux pas t\'offrir un paquet', 'You can\'t give yourself a pack'),
      'trop de cadeaux' => t('Ce joueur a déjà 10 paquets cadeaux à ouvrir', 'This player already has 10 gift packs to open'),
      'aucun cadeau' => t('Aucun paquet cadeau', 'No gift pack'),
      'attends un peu' => t('Attends quelques secondes avant d\'écrire à nouveau', 'Wait a few seconds before writing again'),
      'chat interdit' => t('Tu ne peux plus écrire dans les messages', 'You can no longer write messages'),
      'message trop long' => t('Message trop long (120 caractères max)', 'Message too long (120 characters max)'),
      'message vide' => t('Message vide', 'Empty message'),
      'style verrouillé' => t('Ce thème n\'est pas encore débloqué', 'This theme is not unlocked yet'),
      'maison invalide' => t('Thème invalide', 'Invalid theme'),
      'identifiants incorrects' => t('Pseudo ou mot de passe incorrect', 'Wrong name or password'),
      'trop de tentatives' => t('Trop d\'essais : réessaie dans 15 minutes', 'Too many attempts: try again in 15 minutes'),
      _ => e.message,
    };
  }
  return e.toString();
}
