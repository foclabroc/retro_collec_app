import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio.dart';
import 'catalog.dart';
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

// Finitions : 0 normale, 1 brillante, 2 dorée
String finishName(int f) => [t('Normale', 'Normal'), t('Brillante', 'Holo'), t('Dorée', 'Gold')][f.clamp(0, 2)];

// Mêmes valeurs que le SQL (rc__recycle_value, rc__craft_cost, rc__pack_price)
int recycleValue(int r, int f) => const [5, 15, 50, 150, 500][r] * const [1, 3, 10][f];
int craftCost(int r) => const [50, 150, 500, 1500, 5000][r];
const kPackPrice = {'free': 0, 'mixte': 100, 'console': 150, 'premium': 400, 'mystery': 120, 'gift': 0};

const kGold = Color(0xFFEF9F27);
const kBg = Color(0xFF0A1033); // bleu nuit (thème rétro)
const kPanel = Color(0xD9141B45); // panneaux semi-transparents sur le fond animé
const kPanel2 = Color(0xFF26306B);

/// Avatars (icône + couleur)
const kAvatars = <(IconData, Color)>[
  (Icons.sports_esports, Color(0xFFEF9F27)),
  (Icons.videogame_asset, Color(0xFF378ADD)),
  (Icons.rocket_launch, Color(0xFFD85A30)),
  (Icons.pets, Color(0xFF639922)),
  (Icons.bolt, Color(0xFFFAC775)),
  (Icons.castle, Color(0xFF9C8CFF)),
  (Icons.catching_pokemon, Color(0xFFE24B4A)),
  (Icons.star, Color(0xFF1D9E75)),
];

Widget avatarWidget(int a, {double size = 40}) {
  final (icon, color) = kAvatars[a % kAvatars.length];
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color.withOpacity(0.18), shape: BoxShape.circle, border: Border.all(color: color, width: 2)),
    child: Icon(icon, color: color, size: size * 0.55),
  );
}

/// Objet possédé : une carte dans une finition
class Owned {
  final String card;
  final int finish, qty;
  const Owned(this.card, this.finish, this.qty);
}

/// Liste [[carte, finition, qté], …] → map carte → [qté normale, brillante, dorée]
Map<String, List<int>> parseOwned(dynamic raw) {
  final out = <String, List<int>>{};
  if (raw is! List) return out;
  for (final e in raw) {
    if (e is! List || e.length < 3) continue;
    final q = out[e[0] as String] ??= [0, 0, 0];
    q[(e[1] as num).toInt().clamp(0, 2)] = (e[2] as num).toInt();
  }
  return out;
}

class Game extends ChangeNotifier {
  Game._();
  static final Game i = Game._();

  bool ready = false;
  String pid = '', name = '', showcase = '';
  int avatar = 0, coins = 0, score = 0, cards = 0, packs = 0, pity = 0, streak = 0;
  bool free = false;
  Map<String, dynamic> missions = {};
  Set<String> milestones = {};
  Map<String, List<int>> owned = {};

  /// Événements à afficher (bonus de connexion, missions, paliers…)
  final events = StreamController<Map<String, dynamic>>.broadcast();

  int qty(String card, [int? finish]) {
    final q = owned[card];
    if (q == null) return 0;
    return finish == null ? q[0] + q[1] + q[2] : q[finish];
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

  int get dupesValue {
    var v = 0;
    owned.forEach((id, q) {
      final c = Catalog.cards[id];
      if (c == null) return;
      for (var f = 0; f < 3; f++) {
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
    coins = (r['coins'] as num? ?? coins).toInt();
    pity = (r['pity'] as num? ?? pity).toInt();
    score = (r['score'] as num? ?? score).toInt();
    if (kind == 'free') free = false;
    packs++;
    for (final c in (r['cards'] as List? ?? const [])) {
      final q = owned[c['c'] as String] ??= [0, 0, 0];
      q[(c['f'] as num).toInt()]++;
    }
    notifyListeners();
    return r;
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

  Future<void> craft(String card) async {
    final r = await RcServer.craft(card);
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
      'déjà ouvert aujourd\'hui' => t('Paquet gratuit déjà ouvert aujourd\'hui', 'Free pack already opened today'),
      'dernier exemplaire' => t('Tu dois garder au moins un exemplaire', 'You must keep at least one copy'),
      'trop de lots' => t('12 lots maximum en vente', '12 listings maximum'),
      'carte non possédée' => t('Carte non possédée', 'Card not owned'),
      'trop d\'échanges en attente' => t('Trop d\'échanges en attente', 'Too many pending trades'),
      'tu ne possèdes pas ces cartes' => t('Tu ne possèdes plus ces cartes', 'You no longer own these cards'),
      'code invalide' => t('Code invalide : il faut 32 caractères (0-9, A-F)', 'Invalid code: 32 characters needed (0-9, A-F)'),
      'code inconnu' => t('Aucun profil avec ce code', 'No profile with this code'),
      'déjà tourné aujourd\'hui' => t('Roue déjà tournée aujourd\'hui', 'Wheel already spun today'),
      'cadeau déjà offert' => t('Tu as déjà offert un paquet aujourd\'hui', 'You already gave a pack today'),
      'pas à toi-même' => t('Tu ne peux pas t\'offrir un paquet', 'You can\'t give yourself a pack'),
      'trop de cadeaux' => t('Ce joueur a déjà 5 paquets cadeaux à ouvrir', 'This player already has 5 gift packs to open'),
      'aucun cadeau' => t('Aucun paquet cadeau', 'No gift pack'),
      'attends un peu' => t('Attends quelques secondes avant d\'écrire à nouveau', 'Wait a few seconds before writing again'),
      'chat interdit' => t('Tu ne peux plus écrire dans les messages', 'You can no longer write messages'),
      'message trop long' => t('Message trop long (120 caractères max)', 'Message too long (120 characters max)'),
      'message vide' => t('Message vide', 'Empty message'),
      'identifiants incorrects' => t('Pseudo ou mot de passe incorrect', 'Wrong name or password'),
      'trop de tentatives' => t('Trop d\'essais : réessaie dans 15 minutes', 'Too many attempts: try again in 15 minutes'),
      _ => e.message,
    };
  }
  return e.toString();
}
