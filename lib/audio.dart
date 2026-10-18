import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'web_audio_stub.dart' if (dart.library.js_interop) 'web_audio_web.dart';

/// Service audio léger pour le Quiz.
/// Utilise un MethodChannel vers AudioTrack Android natif.
/// Aucune dépendance externe requise.
class RcAudio {
  RcAudio._();

  static const _ch = MethodChannel('com.foclabroc.retro_collec/audio');

  /// Bruitages activés (réglage mémorisé, indépendant de la musique)
  static bool _enabled = true;
  static const _kSfxKey = 'rc_sfx';

  static bool get enabled => _enabled;
  static set enabled(bool v) {
    _enabled = v;
    SharedPreferences.getInstance().then((p) => p.setBool(_kSfxKey, v)).catchError((_) => false);
  }

  /// Bonne réponse ✅
  static Future<void> correct() => _play('playCorrect');

  /// Mauvaise réponse ❌
  static Future<void> wrong() => _play('playWrong');

  /// Temps écoulé ⏱
  static Future<void> timeout() => _play('playTimeout');

  /// Victoire 🏆 (score >= 70%)
  static Future<void> win() => _play('playWin');

  /// Défaite 💀 (score < 50%)
  static Future<void> lose() => _play('playLose');

  /// Tick timer ⚡ (5 dernières secondes)
  static Future<void> tick() => _play('playTick');

  // ── Mini-jeux : effets et musique ─────────────────────────────────────────

  /// Effet chiptune (jump, spring, coin, stomp, powerup, shield, hurt, break,
  /// logo, tier, continue).
  static Future<void> sfx(String name) => _play('sfx', {'name': name});

  static const _kMusicKey = 'rc_music';
  static bool _music = true;
  static bool _musicLoaded = false;
  static int? _track; // musique du jeu actuellement ouvert

  /// Morceau choisi dans les réglages (index dans kTracks, même ordre que MainActivity.kt)
  static const kTracks = ['Pixel Quest', 'Block World', 'Level Up', 'Game On', 'Retro Wave', 'Lo-fi Gaming', 'Study Time', 'Game Show'];
  static const _kTrackKey = 'rc_track2'; // -1 = aléatoire (par défaut, nouvelles musiques)
  static int homeTrack = 0;

  /// « Aléatoire » : un morceau différent à chaque lancement
  static bool homeTrackRandom = true;

  static int _randomTrack(int not) {
    int i;
    do {
      i = Random().nextInt(kTracks.length);
    } while (i == not && kTracks.length > 1);
    return i;
  }

  /// [i] = -1 : aléatoire
  static Future<void> setHomeTrack(int i) async {
    homeTrackRandom = i < 0;
    homeTrack = homeTrackRandom ? _randomTrack(homeTrack) : i;
    if (_music) musicStart(homeTrack);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kTrackKey, i < 0 ? -1 : i);
      await prefs.setInt('rc_track_last', homeTrack);
    } catch (_) {}
  }

  /// Musique des mini-jeux activée (réglage mémorisé).
  static bool get musicEnabled => _music;

  /// Un seul bouton pour tout le son : musique et bruitages ensemble (mémorisé)
  static bool get soundOn => _music || _enabled;
  static Future<void> setSound(bool v) async {
    enabled = v;
    await setMusicEnabled(v);
    if (v && _track == null) musicStart(homeTrack);
  }

  static Future<void> loadPrefs() async {
    if (_musicLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _music = prefs.getBool(_kMusicKey) ?? true;
      _enabled = prefs.getBool(_kSfxKey) ?? true;
      final v = prefs.getInt(_kTrackKey) ?? -1;
      homeTrackRandom = v < 0;
      if (homeTrackRandom) {
        homeTrack = _randomTrack((prefs.getInt('rc_track_last') ?? -1));
        await prefs.setInt('rc_track_last', homeTrack);
      } else {
        homeTrack = v.clamp(0, kTracks.length - 1);
      }
      _musicLoaded = true;
    } catch (_) {}
  }

  static Future<void> setMusicEnabled(bool v) async {
    _music = v;
    _musicLoaded = true;
    if (!v) {
      _invoke('musicStop');
    } else if (_track != null) {
      musicStart(_track!);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kMusicKey, v);
    } catch (_) {}
  }

  /// Lance la musique [track] en boucle (0 = Rétro Jump, 1 = Breakout).
  static Future<void> musicStart(int track) async {
    _track = track;
    if (!_music) return;
    await _invoke('musicStart', {'track': track});
  }

  static Future<void> musicStop() {
    _track = null;
    return _invoke('musicStop');
  }
  static Future<void> musicPause() => _invoke('musicPause');
  static Future<void> musicResume() async {
    if (!_music) return;
    await _invoke('musicResume');
  }

  static Future<void> _play(String method, [Map<String, dynamic>? args]) async {
    if (!_enabled) return;
    await _invoke(method, args);
  }

  static Future<void> _invoke(String method, [Map<String, dynamic>? args]) async {
    if (kIsWeb) {
      webMusic(method, args); // web : musique (<audio>) et effets (Web Audio)
      return;
    }
    try {
      await _ch.invokeMethod(method, args);
    } catch (_) {
      // Silencieux si le canal n'est pas disponible (ex: iOS, desktop)
    }
  }
}
