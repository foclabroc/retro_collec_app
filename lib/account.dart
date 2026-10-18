import 'package:flutter/material.dart';

import 'game.dart';
import 'server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Compte : connexion (pseudo + mot de passe, ou code de sauvegarde) et
// définition du mot de passe.
// ═══════════════════════════════════════════════════════════════════════════

/// Fenêtre de connexion à un compte existant. Renvoie le pseudo si réussi.
Future<String?> showAccountLogin(BuildContext context, {bool replacing = false, bool withCode = false}) =>
    showDialog<String>(context: context, builder: (_) => _LoginDialog(replacing: replacing, withCode: withCode));

class _LoginDialog extends StatefulWidget {
  final bool replacing, withCode;
  const _LoginDialog({required this.replacing, this.withCode = false});
  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  final name = TextEditingController(), pass = TextEditingController(), code = TextEditingController();
  late bool withCode = widget.withCode;
  bool busy = false, hide = true;
  String? error;

  @override
  void dispose() {
    name.dispose();
    pass.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final n = withCode ? await RcServer.restore(code.text) : await RcServer.login(name.text, pass.text);
      await Game.i.refresh();
      if (mounted) Navigator.pop(context, n);
      return;
    } catch (e) {
      if (mounted) setState(() => error = errText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('Retrouver mon compte', 'Get my account back')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.replacing)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(t('Le profil actuel de ce téléphone sera remplacé.', 'This phone\'s current profile will be replaced.'),
                  style: const TextStyle(fontSize: 12, color: Color(0xFFF09595))),
            ),
          if (!withCode) ...[
            TextField(
              controller: name,
              enabled: !busy,
              maxLength: 16,
              decoration: InputDecoration(labelText: t('Pseudo', 'Name'), counterText: '', prefixIcon: const Icon(Icons.person)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pass,
              enabled: !busy,
              obscureText: hide,
              decoration: InputDecoration(
                labelText: t('Mot de passe', 'Password'),
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(icon: Icon(hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => hide = !hide)),
              ),
              onSubmitted: (_) => _go(),
            ),
          ] else
            TextField(
              controller: code,
              enabled: !busy,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(labelText: t('Code de sauvegarde', 'Backup code'), hintText: 'XXXX-XXXX-…', prefixIcon: const Icon(Icons.key)),
              onSubmitted: (_) => _go(),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(error!, style: const TextStyle(color: Color(0xFFFF8A80), fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: busy ? null : () => setState(() {
                withCode = !withCode;
                error = null;
              }),
              child: Text(withCode ? t('Utiliser pseudo + mot de passe', 'Use name + password') : t('Utiliser un code de sauvegarde', 'Use a backup code'),
                  style: const TextStyle(fontSize: 12)),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: Text(t('Annuler', 'Cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
          onPressed: busy ? null : _go,
          child: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(t('Se connecter', 'Log in'), style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

/// Définir ou changer le mot de passe. Renvoie true si enregistré.
Future<bool> showSetPassword(BuildContext context, {bool change = false}) async =>
    await showDialog<bool>(context: context, builder: (_) => _PasswordDialog(change: change)) == true;

class _PasswordDialog extends StatefulWidget {
  final bool change;
  const _PasswordDialog({required this.change});
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final p1 = TextEditingController(), p2 = TextEditingController();
  bool busy = false, hide = true;
  String? error;

  @override
  void dispose() {
    p1.dispose();
    p2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (p1.text.length < 6) {
      setState(() => error = t('6 caractères minimum', '6 characters minimum'));
      return;
    }
    if (p1.text != p2.text) {
      setState(() => error = t('Les deux mots de passe sont différents', 'Passwords do not match'));
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await RcServer.setPassword(p1.text);
      if (mounted) Navigator.pop(context, true);
      return;
    } catch (e) {
      if (mounted) setState(() => error = errText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.change ? t('Changer le mot de passe', 'Change password') : t('Protéger mon compte', 'Protect my account')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            t('Sur un nouveau téléphone, tu pourras retrouver ton compte avec ton pseudo « ${Game.i.name} » et ce mot de passe.',
                'On a new phone, you can get your account back with your name "${Game.i.name}" and this password.'),
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: p1,
            enabled: !busy,
            obscureText: hide,
            decoration: InputDecoration(
              labelText: t('Mot de passe', 'Password'),
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(icon: Icon(hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => hide = !hide)),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: p2,
            enabled: !busy,
            obscureText: hide,
            decoration: InputDecoration(labelText: t('Confirmer', 'Confirm'), prefixIcon: const Icon(Icons.lock_outline)),
            onSubmitted: (_) => _save(),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(error!, style: const TextStyle(color: Color(0xFFFF8A80), fontWeight: FontWeight.w700, fontSize: 13)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context, false), child: Text(t('Annuler', 'Cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF2A1800)),
          onPressed: busy ? null : _save,
          child: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(t('Enregistrer', 'Save'), style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}
