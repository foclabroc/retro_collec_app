import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account.dart';
import 'audio.dart';
import 'cards.dart';
import 'game.dart';
import 'retro_theme.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Premier lancement : choix du pseudo et de l'avatar, ou restauration d'un
// profil existant avec son code de sauvegarde. Le profil n'est créé sur le
// serveur qu'à la validation (pas de profil fantôme).
// ═══════════════════════════════════════════════════════════════════════════

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final ctl = TextEditingController(), pass = TextEditingController();
  int avatar = 0;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    ctl.dispose();
    pass.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = ctl.text.trim();
    if (name.length < 3) {
      setState(() => error = t('3 caractères minimum', '3 characters minimum'));
      return;
    }
    if (pass.text.isNotEmpty && pass.text.length < 6) {
      setState(() => error = t('Mot de passe : 6 caractères minimum', 'Password: 6 characters minimum'));
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!await RcServer.nameFree(name)) {
        setState(() => error = t('Ce pseudo est déjà pris', 'This name is already taken'));
      } else {
        await Game.i.refresh(); // crée le profil
        await Game.i.setProfile(newName: name, newAvatar: avatar);
        if (pass.text.isNotEmpty) {
          try {
            await RcServer.setPassword(pass.text);
          } catch (_) {} // pourra être fait plus tard dans Profil
        }
        RcAudio.sfx('powerup');
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
    } catch (e) {
      setState(() => error = errText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _restore() async {
    final n = await showAccountLogin(context);
    if (n == null || !mounted) return;
    RcAudio.sfx('powerup');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(children: [
                Text('PIXEL', style: pixelStyle(size: 26)),
                const SizedBox(height: 6),
                Text('TRADE', style: pixelStyle(size: 26, color: const Color(0xFF3DD9FF))),
                const SizedBox(height: 20),
                const SizedBox(width: 90, child: CardBack()),
                const SizedBox(height: 24),
                Text(t('BIENVENUE !', 'WELCOME!'), style: pixelStyle(size: 13)),
                const SizedBox(height: 8),
                Text(t('Choisis ton pseudo et ton avatar', 'Choose your name and avatar'),
                    style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kPanel,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kGold.withOpacity(0.6), width: 1.5),
                  ),
                  child: Column(children: [
                    TextField(
                      controller: ctl,
                      maxLength: 16,
                      enabled: !busy,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      decoration: InputDecoration(
                        hintText: t('Ton pseudo', 'Your name'),
                        counterText: '',
                        filled: true,
                        fillColor: const Color(0x33000000),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: pass,
                      enabled: !busy,
                      obscureText: true,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: t('Mot de passe (conseillé)', 'Password (recommended)'),
                        helperText: t('Pour retrouver ton compte sur un autre téléphone', 'To get your account back on another phone'),
                        helperStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                        filled: true,
                        fillColor: const Color(0x33000000),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      onSubmitted: (_) => _create(),
                    ),
                    const SizedBox(height: 16),
                    Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
                      for (var i = 0; i < kAvatars.length; i++)
                        GestureDetector(
                          onTap: busy ? null : () => setState(() => avatar = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: avatar == i ? kGold : Colors.transparent, width: 2.5),
                              boxShadow: avatar == i ? [BoxShadow(color: kGold.withOpacity(0.5), blurRadius: 10)] : null,
                            ),
                            child: avatarWidget(i, size: 46),
                          ),
                        ),
                    ]),
                  ]),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF8A80), fontWeight: FontWeight.w700)),
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: kGold,
                      foregroundColor: const Color(0xFF2A1800),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: busy ? null : _create,
                    child: busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Text(t("C'EST PARTI !", "LET'S GO!"), style: pixelStyle(size: 12, color: const Color(0xFF2A1800), shadow: false)),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: busy ? null : _restore,
                  icon: const Icon(Icons.login, color: kGold, size: 18),
                  label: Text(t("J'ai déjà un compte", 'I already have an account'),
                      style: const TextStyle(color: Colors.white70)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
