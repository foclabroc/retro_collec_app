import 'package:web/web.dart' as web;

// Version web : musique de fond avec un élément <audio> du navigateur.
// (Les navigateurs n'autorisent le son qu'après une première touche : l'écran titre s'en charge.)

web.HTMLAudioElement? _audio;
int? _index;
bool _wanted = false;

String _src(int i) => 'assets/assets/music/collec_music_${i + 1}.ogg';

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
        _audio = web.HTMLAudioElement()
          ..src = _src(i)
          ..loop = true
          ..volume = 0.45;
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
    }
  } catch (_) {}
}
