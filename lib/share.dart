import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game.dart';
import 'main.dart';

// ═══════════════════════════════════════════════════════════════════════════
// « Partager ce jeu à tes amis » (panneau latéral) : le lien du dernier APK
// (page de la dernière version sur GitHub) et la version web de test.
// Android : fenêtre de partage du téléphone ; web : copié dans le presse-papiers.
// ═══════════════════════════════════════════════════════════════════════════

const kApkLatestUrl = 'https://github.com/foclabroc/retro_collec_app/releases/latest';
const kWebUrl = 'https://foclabroc.github.io/retro_collec_app/';
const _sys = MethodChannel('com.foclabroc.retro_collec/system');

String shareGameText() {
  final me = Game.i.name.isEmpty ? '' : t('\nMon pseudo : ${Game.i.name}', '\nMy name: ${Game.i.name}');
  return t(
    '🎮 Viens jouer à Pixel Trade, le jeu de collection de cartes de jeux rétro !$me\n\n'
        '📱 Android (APK, dernière version) : $kApkLatestUrl\n'
        '🌐 Version web (test, sans installer) : $kWebUrl',
    '🎮 Come play Pixel Trade, the retro game card collecting game!$me\n\n'
        '📱 Android (APK, latest version): $kApkLatestUrl\n'
        '🌐 Web version (test, no install): $kWebUrl',
  );
}

Future<void> shareGame() async {
  final text = shareGameText();
  if (!kIsWeb) {
    try {
      final ok = await _sys.invokeMethod<bool>('share', {'text': text, 'title': t('Partager Pixel Trade', 'Share Pixel Trade')});
      if (ok == true) return;
    } catch (_) {
      // ancienne version du code natif : on copie le texte
    }
  }
  await Clipboard.setData(ClipboardData(text: text));
  toast(t('Lien copié : colle-le dans un message à tes amis', 'Link copied: paste it in a message to your friends'));
}

/// Case du panneau latéral
class ShareMenuTile extends StatelessWidget {
  final bool compact; // barre latérale étroite (tablette)
  final VoidCallback? beforeOpen;
  const ShareMenuTile({super.key, this.compact = false, this.beforeOpen});

  @override
  Widget build(BuildContext context) {
    const pink = Color(0xFFFF8AD8);
    void go() {
      beforeOpen?.call();
      shareGame();
    }

    if (compact) {
      return Tooltip(
        message: t('Partager ce jeu à tes amis', 'Share this game with your friends'),
        child: InkWell(
          onTap: go,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [
              const Icon(Icons.share, color: pink, size: 20),
              const SizedBox(height: 2),
              Text(t('Partager', 'Share'), style: const TextStyle(fontSize: 10.5, color: Colors.white60)),
            ]),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: pink.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: go,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: pink.withOpacity(0.6))),
            child: Row(children: [
              const Icon(Icons.share, color: pink, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('Partager ce jeu à tes amis', 'Share this game with your friends'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  Text(t('Lien de l\'APK et de la version web', 'APK and web version links'), style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ]),
          ),
        ),
      ),
    );
  }
}
