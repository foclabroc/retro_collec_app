import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

// Version web : jaquettes et captures gardées dans le Cache Storage du navigateur.
// GitHub Pages ne garde les fichiers que 10 min en cache : ensuite le navigateur redemande
// chaque image au serveur (une requête par carte). Ici, une image déjà vue est relue
// directement sur l'appareil, sans réseau. Les adresses portent l'empreinte du pack
// de la console (?h=…) : une image modifiée a une autre adresse.

const _kCache = 'rc-img-v1';
Future<web.Cache>? _open;
bool _off = false; // Cache Storage indisponible (navigation privée, vieux navigateur) : réseau seul

Future<web.Cache> _cache() => _open ??= web.window.caches.open(_kCache).toDart;

/// Octets de l'image : depuis le cache, sinon téléchargée puis rangée. null = utiliser le réseau normal.
Future<Uint8List?> webCachedBytes(String url) async {
  if (_off) return null;
  try {
    final c = await _cache();
    final hit = await c.match(url.toJS).toDart;
    if (hit != null) {
      final buf = await (hit as web.Response).arrayBuffer().toDart;
      return buf.toDart.asUint8List();
    }
    final r = await web.window.fetch(url.toJS).toDart;
    if (!r.ok) return null;
    try {
      await c.put(url.toJS, r.clone()).toDart;
    } catch (_) {} // cache plein : on affiche quand même
    final buf = await r.arrayBuffer().toDart;
    return buf.toDart.asUint8List();
  } catch (_) {
    _off = true;
    return null;
  }
}

/// Supprime les images d'anciennes versions des packs (keep = false).
Future<void> webPruneImages(bool Function(String url) keep) async {
  if (_off) return;
  try {
    final c = await _cache();
    final keys = (await c.keys().toDart).toDart;
    for (final req in keys) {
      if (!keep(req.url)) await c.delete(req.url.toJS).toDart;
    }
  } catch (_) {}
}
