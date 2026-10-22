import 'dart:typed_data';

/// Android : les jaquettes sont des fichiers locaux (rien à faire ici).
Future<Uint8List?> webCachedBytes(String url) async => null;

/// Android : rien à nettoyer.
Future<void> webPruneImages(bool Function(String url) keep) async {}
