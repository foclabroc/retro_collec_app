import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

// Version web : musique de fond avec un élément <audio> du navigateur.
// (Les navigateurs n'autorisent le son qu'après une première touche : l'écran titre s'en charge.)

web.HTMLAudioElement? _audio;
int? _index;
bool _wanted = false;
int _errors = 0; // lecteurs recréés après une erreur (au plus 3, pour ne pas boucler)

// .ogg (Chrome, Firefox, Android) ; .mp3 pour Safari / iPhone qui ne lisent pas l'ogg.
// Les mp3 sont dans web/music/ : ils ne sont pas ajoutés à l'APK.
final bool _ogg = web.HTMLAudioElement().canPlayType('audio/ogg; codecs="vorbis"').isNotEmpty;

String _src(int i) => _ogg ? 'assets/assets/music/collec_music_${i + 1}.ogg' : 'music/collec_music_${i + 1}.mp3';

void webMusic(String method, Map<String, dynamic>? args) {
  try {
    switch (method) {
      case 'musicStart':
        final i = ((args?['track'] as num?) ?? 0).toInt().clamp(0, 7);
        _wanted = true;
        if (_audio != null && _index == i) {
          _audio!.play();
          return;
        }
        _audio?.pause();
        _index = i;
        _audio = _newAudio(i);
        _audio!.play();
      case 'musicStop':
        _wanted = false;
        _audio?.pause();
        _audio = null;
        _index = null;
      case 'musicPause':
        _audio?.pause();
      case 'musicResume':
        if (_wanted) _audio?.play();
      default:
        _playSfx(method == 'sfx' ? (args?['name'] as String? ?? '') : method);
    }
  } catch (_) {}
}

/// Lecteur de musique en boucle. « loop » ne suffit pas toujours sur le web : quand le
/// fichier vient du cache de l'appli (service worker), certains navigateurs ne savent pas
/// revenir au début. On relance donc nous-mêmes à la fin du morceau, et on recrée le
/// lecteur s'il tombe en erreur.
web.HTMLAudioElement _newAudio(int i) {
  final a = web.HTMLAudioElement()
    ..src = _src(i)
    ..loop = true
    ..volume = 0.45;
  a.addEventListener(
      'ended',
      ((web.Event _) {
        if (!_wanted || _audio != a) return;
        _errors = 0;
        try {
          a.currentTime = 0;
          a.play();
        } catch (_) {}
      }).toJS);
  a.addEventListener(
      'error',
      ((web.Event _) {
        if (!_wanted || _audio != a || _index == null || _errors >= 3) return;
        _errors++;
        // lecteur cassé : on en recrée un sur le même morceau
        final n = _newAudio(_index!);
        _audio = n;
        n.play();
      }).toJS);
  return a;
}

// ── Effets sonores : mêmes sons que la version Android (MainActivity.kt), générés
// en Dart puis joués avec l'audio du navigateur (Web Audio). Rien n'est téléchargé.

web.AudioContext? _ctx;
final _buffers = <String, web.AudioBuffer>{};

void _playSfx(String name) {
  try {
    final ctx = _ctx ??= web.AudioContext();
    if (ctx.state == 'suspended') ctx.resume();
    var buf = _buffers[name];
    if (buf == null) {
      final gen = _sounds[name];
      if (gen == null) return;
      final (rate, data) = gen();
      if (data.isEmpty) return;
      buf = ctx.createBuffer(1, data.length, rate.toDouble());
      buf.copyToChannel(data.toJS, 0);
      _buffers[name] = buf;
    }
    final src = ctx.createBufferSource()..buffer = buf;
    src.connect(ctx.destination);
    src.start();
  } catch (_) {}
}

const _kQuiz = 44100, _kChip = 22050;
const _sine = 0, _square = 1, _triangle = 2, _noise = 3;
final _rnd = Random(12345);

double _midi(int n) => 440.0 * pow(2, (n - 69) / 12.0);

Float32List _cat(List<Float32List> parts) {
  final out = Float32List(parts.fold(0, (a, p) => a + p.length));
  var o = 0;
  for (final p in parts) {
    out.setAll(o, p);
    o += p.length;
  }
  return out;
}

Float32List _mix(Float32List a, Float32List b) {
  final out = Float32List(max(a.length, b.length));
  for (var i = 0; i < out.length; i++) {
    out[i] = (i < a.length ? a[i] : 0.0) + (i < b.length ? b[i] : 0.0);
  }
  return out;
}

Float32List _gap(int ms, [int rate = _kChip]) => Float32List(rate * ms ~/ 1000);

// Sons du quiz (sinus avec attaque 5 ms et relâche 20 ms)
Float32List _s(double freq, int ms, [double amp = 0.6]) {
  final n = _kQuiz * ms ~/ 1000;
  final a = (_kQuiz * 0.005).toInt(), r = (_kQuiz * 0.020).toInt();
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    final env = i < a ? i / a : (i > n - r ? (n - i) / r : 1.0);
    out[i] = sin(2 * pi * freq * i / _kQuiz) * amp * env;
  }
  return out;
}

Float32List _wrong() {
  final n = (_kQuiz * 0.25).toInt();
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    final freq = 220.0 - 480.0 * (i / n);
    final raw = sin(2 * pi * freq * i / _kQuiz);
    final c = raw > 0.6 ? 0.6 + (raw - 0.6) * 0.3 : (raw < -0.6 ? -0.6 + (raw + 0.6) * 0.3 : raw);
    out[i] = c * 0.65 * (n - i) / n;
  }
  return out;
}

// Synthé « chiptune » : note avec glissando de f0 à f1, enveloppe courte
Float32List _tone(double f0, double f1, int ms, double amp, int wave, {double duty = 0.5, double decay = 3.0, double vibrato = 0}) {
  final n = _kChip * ms ~/ 1000;
  final out = Float32List(n);
  final attack = max(1, (_kChip * 0.003).toInt());
  var phase = 0.0, noise = 0.0;
  for (var i = 0; i < n; i++) {
    final p = i / n;
    var f = f0 + (f1 - f0) * p;
    if (vibrato > 0) f *= 1.0 + 0.04 * sin(2 * pi * vibrato * i / _kChip);
    phase += f / _kChip;
    final ph = phase - phase.floorToDouble();
    final double v;
    switch (wave) {
      case _square:
        v = ph < duty ? 1.0 : -1.0;
      case _triangle:
        v = 4.0 * (ph - 0.5).abs() - 1.0;
      case _noise:
        if (ph < f / _kChip) noise = _rnd.nextDouble() * 2 - 1;
        v = noise;
      default:
        v = sin(2 * pi * ph);
    }
    final env = (i < attack ? i / attack : 1.0) * exp(-decay * p) * (1.0 - p * p * p);
    out[i] = (v * amp * env).clamp(-1.0, 1.0).toDouble();
  }
  return out;
}

Float32List _arp(List<int> notes, int ms, double amp, int wave, [double duty = 0.25]) =>
    _cat([for (final m in notes) _tone(_midi(m), _midi(m), ms, amp, wave, duty: duty, decay: 1.5)]);

final Map<String, (int, Float32List) Function()> _sounds = {
  'playCorrect': () => (_kQuiz, _cat([_s(523.25, 80, 0.55), _gap(20, _kQuiz), _s(659.25, 120, 0.55)])),
  'playWrong': () => (_kQuiz, _wrong()),
  'playTimeout': () => (_kQuiz, _cat([_s(311.13, 60, 0.4), _gap(30, _kQuiz), _s(261.63, 150, 0.35)])),
  'playWin': () => (_kQuiz, _cat([_s(523.25, 100, 0.5), _gap(15, _kQuiz), _s(659.25, 100, 0.5), _gap(15, _kQuiz), _s(783.99, 100, 0.5), _gap(15, _kQuiz), _s(1046.5, 220, 0.55)])),
  'playLose': () => (_kQuiz, _cat([_s(392.00, 120, 0.45), _gap(20, _kQuiz), _s(349.23, 120, 0.45), _gap(20, _kQuiz), _s(311.13, 120, 0.45), _gap(20, _kQuiz), _s(261.63, 250, 0.40)])),
  'playTick': () => (_kQuiz, _s(880.0, 40, 0.3)),
  'jump': () => (_kChip, _tone(330, 660, 90, 0.22, _square, duty: 0.25, decay: 4)),
  'spring': () => (_kChip, _tone(180, 820, 300, 0.35, _triangle, decay: 2, vibrato: 28)),
  'coin': () => (_kChip, _cat([_tone(_midi(83), _midi(83), 55, 0.25, _square, decay: 0.5), _tone(_midi(88), _midi(88), 170, 0.25, _square, decay: 3)])),
  'stomp': () => (_kChip, _mix(_tone(700, 140, 130, 0.30, _square, decay: 3), _tone(3000, 800, 90, 0.18, _noise, decay: 5))),
  'boost': () => (_kChip, _mix(_tone(110, 880, 700, 0.24, _square, duty: 0.25, decay: 1), _tone(600, 3500, 700, 0.12, _noise, decay: 0.8))),
  'powerup': () => (_kChip, _arp([60, 64, 67, 72, 76, 79, 84, 88], 45, 0.25, _square)),
  'shield': () => (_kChip, _cat([_tone(500, 1400, 160, 0.28, _triangle, decay: 1.5), _tone(_midi(88), _midi(88), 120, 0.2, _triangle, decay: 3)])),
  'hurt': () => (_kChip, _mix(_tone(400, 120, 220, 0.30, _square, duty: 0.125, decay: 2.5), _tone(2000, 300, 160, 0.20, _noise, decay: 4))),
  'break': () => (_kChip, _mix(_tone(1800, 400, 160, 0.30, _noise, decay: 4), _tone(220, 90, 120, 0.18, _square, decay: 4))),
  'logo': () => (_kChip, _arp([79, 84, 88, 91], 70, 0.22, _triangle)),
  'tier': () => (_kChip, _cat([_arp([67, 72, 76], 90, 0.22, _square, 0.5), _tone(_midi(79), _midi(79), 260, 0.24, _square, decay: 2)])),
  'continue': () => (_kChip, _cat([_arp([60, 67, 72, 76, 79], 70, 0.24, _square, 0.5), _gap(20), _tone(_midi(84), _midi(84), 260, 0.24, _square, decay: 2)])),
  'alarm': () => (
        _kChip,
        _mix(
          _cat([_tone(620, 620, 150, 0.45, _square, decay: 0.5), _gap(70), _tone(620, 620, 150, 0.45, _square, decay: 0.5), _gap(70), _tone(520, 520, 240, 0.45, _square, decay: 0.7)]),
          _cat([_tone(310, 310, 150, 0.35, _triangle, decay: 0.5), _gap(70), _tone(310, 310, 150, 0.35, _triangle, decay: 0.5), _gap(70), _tone(260, 260, 240, 0.35, _triangle, decay: 0.7)]),
        )
      ),
  'missile': () => (_kChip, _mix(_tone(1800, 500, 420, 0.16, _triangle, decay: 1.5), _tone(4000, 1500, 420, 0.10, _noise, decay: 1.5))),
  'zap': () => (_kChip, _mix(_tone(90, 70, 480, 0.30, _square, decay: 1.2, vibrato: 60), _tone(5000, 2000, 480, 0.16, _noise, decay: 1.5))),
  'explode': () => (_kChip, _mix(_tone(2500, 120, 650, 0.32, _noise, decay: 1.8), _tone(140, 45, 650, 0.30, _square, decay: 2))),
};

/// Recharge la page en contournant le cache (nouvelle version du jeu).
void webReload() {
  final l = web.window.location;
  l.href = '${l.origin}${l.pathname}?v=${DateTime.now().millisecondsSinceEpoch}';
}
