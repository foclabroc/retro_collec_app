import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show consolidateHttpClientResponseBytes, kIsWeb;
import 'package:flutter/painting.dart';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Catalogue des cartes : catalog.json + images, hébergés sur GitHub Pages
// (dépôt foclabroc/retro_collec_assets, généré par retro_collec_export.py).
// Les images sont téléchargées UNE fois par console (packs/<console>.zip) et
// gardées dans le stockage interne de l'appli ; seuls les packs modifiés
// (empreinte « hash » différente) sont retéléchargés.
// Version web : rien n'est téléchargé d'avance, chaque image est lue en ligne
// (cache du navigateur) directement sur GitHub Pages.
// ═══════════════════════════════════════════════════════════════════════════

const kAssetsBase = 'https://foclabroc.github.io/retro_collec_assets/';

// (hors de RcCard : dans la classe, « num » désigne le champ et non le type)
int _int(dynamic v) => (v as num).toInt();

class RcCard {
  final String id, sys, title, dev, pub, genre, img, desc, genreEn, descEn;
  final String? shot;
  final int num, rarity;
  final int? year;
  const RcCard({
    required this.id,
    required this.sys,
    required this.num,
    required this.title,
    required this.year,
    required this.dev,
    required this.pub,
    required this.genre,
    required this.rarity,
    required this.img,
    required this.shot,
    required this.desc,
    this.genreEn = '',
    this.descEn = '',
  });

  /// Genre et description dans la langue du téléphone (français par défaut).
  String get genreL => !rcFrench && genreEn.isNotEmpty ? genreEn : genre;
  String get descL => !rcFrench && descEn.isNotEmpty ? descEn : desc;

  factory RcCard.fromJson(Map<String, dynamic> j) => RcCard(
        id: j['id'] as String,
        sys: j['s'] as String,
        num: _int(j['n']),
        title: j['t'] as String? ?? '',
        year: j['y'] == null ? null : _int(j['y']),
        dev: j['dv'] as String? ?? '',
        pub: j['p'] as String? ?? '',
        genre: j['g'] as String? ?? '',
        rarity: j['r'] == null ? 0 : _int(j['r']),
        img: j['img'] as String,
        shot: j['shot'] as String?,
        desc: j['d'] as String? ?? '',
        genreEn: j['ge'] as String? ?? '',
        descEn: j['de'] as String? ?? '',
      );
}

class RcSystem {
  final String id, name, pack, hash, shotsPack, shotsHash;
  final int count, size, shotsSize;
  const RcSystem(this.id, this.name, this.count, this.pack, this.hash, this.size, this.shotsPack, this.shotsHash,
      this.shotsSize);

  factory RcSystem.fromJson(Map<String, dynamic> j) => RcSystem(
        j['id'] as String,
        j['name'] as String,
        (j['count'] as num).toInt(),
        j['pack'] as String,
        j['hash'] as String,
        (j['size'] as num? ?? 0).toInt(),
        j['shots_pack'] as String? ?? '',
        j['shots_hash'] as String? ?? '',
        (j['shots_size'] as num? ?? 0).toInt(),
      );

  /// Nom court pour le haut des cartes.
  String get short => switch (id) {
        'mastersystem' => 'Master System',
        'megadrive' => 'Mega Drive',
        'snes' => 'Super Nintendo',
        'n64' => 'Nintendo 64',
        'psx' => 'PlayStation',
        'gba' => 'GB Advance',
        'gbc' => 'GB Color',
        'ps2' => 'PlayStation 2',
        'gamecube' => 'GameCube',
        'gamegear' => 'Game Gear',
        _ => name,
      };
}

class Catalog {
  Catalog._();

  static String version = '';
  static List<RcSystem> systems = [];
  static Map<String, RcCard> cards = {};
  static Map<String, List<RcCard>> bySys = {};
  static late String dir; // dossier local des images

  static bool get loaded => cards.isNotEmpty;
  static RcSystem? system(String id) {
    for (final s in systems) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Version web : adresse en ligne, avec l'empreinte du pack pour suivre les mises à jour
  static String _url(String path, String sys) => '$kAssetsBase$path?h=${system(sys)?.hash ?? version}';

  /// Jaquette de la carte (fichier local sur Android, image en ligne sur le web)
  static ImageProvider image(RcCard c) =>
      kIsWeb ? NetworkImage(_url(c.img, c.sys)) : FileImage(File('$dir/${c.img}')) as ImageProvider;

  /// Capture d'écran du jeu, ou null si absente (pas encore téléchargée sur Android)
  static ImageProvider? shot(RcCard c) {
    final s = c.shot;
    if (s == null) return null;
    if (kIsWeb) return NetworkImage(_url(s, c.sys));
    final f = File('$dir/$s');
    return f.existsSync() ? FileImage(f) : null;
  }

  static bool hasShot(RcCard c) => kIsWeb ? c.shot != null : shot(c) != null;

  static Future<void> _init() async {
    if (kIsWeb) return;
    final base = await getApplicationSupportDirectory();
    dir = '${base.path}/rc';
    await Directory(dir).create(recursive: true);
  }

  static void _parse(String txt) {
    final j = jsonDecode(txt) as Map<String, dynamic>;
    version = j['version']?.toString() ?? '';
    systems = [for (final s in j['systems'] as List) RcSystem.fromJson(Map<String, dynamic>.from(s as Map))];
    final list = [for (final c in j['cards'] as List) RcCard.fromJson(Map<String, dynamic>.from(c as Map))];
    cards = {for (final c in list) c.id: c};
    bySys = {};
    for (final c in list) {
      (bySys[c.sys] ??= []).add(c);
    }
    for (final l in bySys.values) {
      l.sort((a, b) => a.num.compareTo(b.num));
    }
  }

  /// Charge le catalogue déjà téléchargé. Faux si rien en local (premier lancement).
  static Future<bool> loadLocal() async {
    if (kIsWeb) return false; // web : catalogue relu en ligne à chaque lancement
    await _init();
    final f = File('$dir/catalog.json');
    if (!await f.exists()) return false;
    try {
      _parse(await f.readAsString());
      // toutes les jaquettes doivent être là (sinon téléchargement incomplet)
      final prefs = await SharedPreferences.getInstance();
      for (final s in systems) {
        if (prefs.getString('rc_pack_${s.id}') != s.hash) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<int>> _get(String url, {void Function(int got, int total)? progress}) async {
    if (kIsWeb) {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 40));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode} $url');
      return r.bodyBytes;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode} $url');
      return await consolidateHttpClientResponseBytes(res,
          onBytesReceived: progress == null ? null : (got, total) => progress(got, total ?? -1));
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _extract(List<int> zip) async {
    final archive = ZipDecoder().decodeBytes(zip);
    for (final f in archive) {
      if (!f.isFile) continue;
      final out = File('$dir/${f.name}');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(f.content as List<int>, flush: false);
    }
  }

  /// Met le catalogue à jour : télécharge catalog.json puis les packs de jaquettes
  /// modifiés. [progress] reçoit (fraction 0..1, texte). Lève une exception hors ligne.
  static Future<void> update({void Function(double, String)? progress}) async {
    await _init();
    final prefs = await SharedPreferences.getInstance();
    // web : même adresse que le préchargement de index.html (téléchargé en parallèle du moteur Flutter,
    // puis gardé en cache par le navigateur et revalidé par GitHub Pages)
    final txt = utf8.decode(await _get(kIsWeb ? '${kAssetsBase}catalog.json' : '${kAssetsBase}catalog.json?t=${DateTime.now().millisecondsSinceEpoch}'));
    if (kIsWeb) {
      progress?.call(0.5, '');
      _parse(txt);
      progress?.call(1, '');
      return;
    }
    final j = jsonDecode(txt) as Map<String, dynamic>;
    final remote = [for (final s in j['systems'] as List) RcSystem.fromJson(Map<String, dynamic>.from(s as Map))];
    final todo = [for (final s in remote) if (prefs.getString('rc_pack_${s.id}') != s.hash) s];
    final totalBytes = todo.fold<int>(0, (a, s) => a + (s.size > 0 ? s.size : 1));
    var doneBytes = 0;
    for (final s in todo) {
      final bytes = await _get('$kAssetsBase${s.pack}?h=${s.hash}', progress: (got, _) {
        progress?.call(totalBytes == 0 ? 1 : (doneBytes + got) / totalBytes, s.name);
      });
      await _extract(bytes);
      await prefs.setString('rc_pack_${s.id}', s.hash);
      doneBytes += s.size > 0 ? s.size : 1;
    }
    await File('$dir/catalog.json').writeAsString(txt);
    _parse(txt);
    progress?.call(1, '');
  }

  /// Captures d'écran (fiches des jeux) : téléchargées en arrière-plan, sans bloquer le jeu.
  static Future<void> updateShots() async {
    if (kIsWeb) return; // web : captures lues en ligne
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final s in systems) {
        if (s.shotsPack.isEmpty || prefs.getString('rc_shots_${s.id}') == s.shotsHash) continue;
        final bytes = await _get('$kAssetsBase${s.shotsPack}?h=${s.shotsHash}');
        await _extract(bytes);
        await prefs.setString('rc_shots_${s.id}', s.shotsHash);
      }
    } catch (_) {
      // réessayé au prochain lancement
    }
  }

  /// Vérifie si le catalogue en ligne a changé ; vrai si une mise à jour a été appliquée.
  /// Hors ligne : ne fait rien (on garde le catalogue local).
  static Future<bool> refreshInBackground({void Function(double, String)? progress}) async {
    try {
      final txt = utf8.decode(await _get('${kAssetsBase}catalog.json?t=${DateTime.now().millisecondsSinceEpoch}')
          .timeout(const Duration(seconds: 20)));
      final v = (jsonDecode(txt) as Map)['version']?.toString() ?? '';
      if (v == version) return false;
      await update(progress: progress);
      return true;
    } catch (_) {
      return false;
    }
  }
}
