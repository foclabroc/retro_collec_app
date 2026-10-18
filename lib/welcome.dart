import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account.dart';
import 'audio.dart';
import 'cards.dart';
import 'game.dart';
import 'retro_theme.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Premier lancement : écran de connexion (pseudo + mot de passe, ou code de
// sauvegarde), et « Nouveau joueur » pour créer un profil (pseudo, mot de
// passe, avatar). Le profil n'est créé sur le serveur qu'à la validation.
// ═══════════════════════════════════════════════════════════════════════════

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final ctl = TextEditingController(), pass = TextEditingController();
  final loginName = TextEditingController(), loginPass = TextEditingController();
  int avatar = 0;
  bool busy = false, creating = false, hide = true;
  String? error;

  @override
  void dispose() {
    ctl.dispose();
    pass.dispose();
    loginName.dispose();
    loginPass.dispose();
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

  Future<void> _login() async {
    if (loginName.text.trim().isEmpty || loginPass.text.isEmpty) {
      setState(() => error = t('Pseudo et mot de passe', 'Name and password'));
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await RcServer.login(loginName.text.trim(), loginPass.text);
      await Game.i.refresh();
      RcAudio.sfx('powerup');
      if (mounted) Navigator.of(context).pop(true);
      return;
    } catch (e) {
      if (mounted) setState(() => error = errText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  /// Connexion avec le code de sauvegarde (comptes sans mot de passe)
  Future<void> _restore() async {
    final n = await showAccountLogin(context, withCode: true);
    if (n == null || !mounted) return;
    RcAudio.sfx('powerup');
    Navigator.of(context).pop(true);
  }

  InputDecoration _field(String hint, IconData icon, {Widget? suffix}) => InputDecoration(
        hintText: hint,
        counterText: '',
        prefixIcon: Icon(icon, color: Colors.white54),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0x33000000),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      );

  Widget _bigButton(String label, VoidCallback? onTap, {bool outlined = false}) => SizedBox(
        width: double.infinity,
        height: 52,
        child: outlined
            ? OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF3DD9FF), width: 2),
                  backgroundColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: onTap,
                child: Text(label, style: pixelStyle(size: 11, color: const Color(0xFF3DD9FF), shadow: false)),
              )
            : FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: kGold,
                  foregroundColor: const Color(0xFF2A1800),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: onTap,
                child: busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Text(label, style: pixelStyle(size: 11, color: const Color(0xFF2A1800), shadow: false)),
              ),
      );

  Widget _errorLine() => error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF8A80), fontWeight: FontWeight.w700)),
        );

  /// Écran de départ : connexion, puis « Nouveau joueur »
  List<Widget> _loginView() => [
        Text('PIXEL', style: pixelStyle(size: 26)),
        const SizedBox(height: 6),
        Text('TRADE', style: pixelStyle(size: 26, color: const Color(0xFF3DD9FF))),
        const SizedBox(height: 20),
        const SizedBox(width: 80, child: CardBack()),
        const SizedBox(height: 22),
        Text(t('CONNEXION', 'LOG IN'), style: pixelStyle(size: 13)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kPanel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kGold.withOpacity(0.6), width: 1.5),
          ),
          child: Column(children: [
            TextField(
              controller: loginName,
              maxLength: 16,
              enabled: !busy,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              decoration: _field(t('Pseudo', 'Name'), Icons.person),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: loginPass,
              enabled: !busy,
              obscureText: hide,
              decoration: _field(t('Mot de passe', 'Password'), Icons.lock,
                  suffix: IconButton(icon: Icon(hide ? Icons.visibility : Icons.visibility_off, color: Colors.white54), onPressed: () => setState(() => hide = !hide))),
              onSubmitted: (_) => _login(),
            ),
            _errorLine(),
            const SizedBox(height: 14),
            _bigButton(t('SE CONNECTER', 'LOG IN'), busy ? null : _login),
            const SizedBox(height: 4),
            TextButton(
              onPressed: busy ? null : _restore,
              child: Text(t('Pas de mot de passe ? Code de sauvegarde', 'No password? Backup code'),
                  textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF8FD3FF), fontSize: 12.5, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        Row(children: [
          const Expanded(child: Divider(color: Colors.white24)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(t('première fois ?', 'first time?'), style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
          ),
          const Expanded(child: Divider(color: Colors.white24)),
        ]),
        const SizedBox(height: 14),
        _bigButton(
            t('NOUVEAU JOUEUR', 'NEW PLAYER'),
            busy
                ? null
                : () => setState(() {
                      creating = true;
                      error = null;
                    }),
            outlined: true),
      ];

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
              child: Column(children: !creating ? _loginView() : [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                              creating = false;
                              error = null;
                            }),
                    icon: const Icon(Icons.arrow_back, size: 18, color: Colors.white70),
                    label: Text(t('Retour à la connexion', 'Back to log in'), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800)),
                  ),
                ),
                Text('PIXEL', style: pixelStyle(size: 20)),
                const SizedBox(height: 4),
                Text('TRADE', style: pixelStyle(size: 20, color: const Color(0xFF3DD9FF))),
                const SizedBox(height: 18),
                Text(t('NOUVEAU JOUEUR', 'NEW PLAYER'), style: pixelStyle(size: 13)),
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
                _errorLine(),
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
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
