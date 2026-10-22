import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_repository.dart';
import '../core/providers.dart';
import '../ui/theme.dart';

const passwordRuleText = '8 caractères minimum, pas seulement des chiffres';

/// At least 8 characters and not only digits. The server stays the authority.
bool isAcceptablePassword(String value) => value.length >= 8 && !RegExp(r'^\d+$').hasMatch(value);

/// Choosing a password. [forced] is the first-sign-in case (temporary
/// password): no back, no current password, a sign-out escape. Otherwise it
/// is the normal change from Compte, which asks for the current password.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key, required this.forced});

  final bool forced;

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _hidden = true;
  bool _busy = false;
  String? _ruleError;
  String? _matchError;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final ruleError = isAcceptablePassword(_new.text) ? null : passwordRuleText;
    final matchError = _new.text == _confirm.text ? null : 'Les deux mots de passe sont différents';
    final currentMissing = !widget.forced && _current.text.isEmpty;
    setState(() {
      _ruleError = ruleError;
      _matchError = ruleError == null ? matchError : null;
      _error = currentMissing ? 'Saisissez votre mot de passe actuel.' : null;
    });
    if (ruleError != null || matchError != null || currentMissing) return;

    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).changePassword(
            current: widget.forced ? null : _current.text,
            newPassword: _new.text,
          );
      if (!mounted) return;
      // Forced: the gate swaps this screen for home. Otherwise go back.
      if (!widget.forced) Navigator.of(context).pop(true);
    } on AccountActionException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  Widget _field(TextEditingController controller, String label, {String? error, TextInputAction? action, bool toggle = false}) {
    return TextField(
      controller: controller,
      obscureText: _hidden,
      textInputAction: action ?? TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        errorText: error,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: toggle
            ? IconButton(
                tooltip: _hidden ? 'Afficher les mots de passe' : 'Masquer les mots de passe',
                icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hidden = !_hidden),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.forced ? 'Choisissez votre mot de passe' : 'Changer le mot de passe';
    return PopScope(
      canPop: !widget.forced,
      child: Scaffold(
        appBar: AppBar(automaticallyImplyLeading: !widget.forced, title: Text(title)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            if (widget.forced)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text('Votre mot de passe était temporaire. Choisissez-en un qui n’est qu’à vous.'),
              ),
            if (!widget.forced) ...[
              _field(_current, 'Mot de passe actuel'),
              const SizedBox(height: 14),
            ],
            _field(_new, 'Nouveau mot de passe', error: _ruleError, toggle: true),
            const SizedBox(height: 6),
            const Text(passwordRuleText, style: TextStyle(color: FideliaColors.muted, fontSize: 14)),
            const SizedBox(height: 14),
            _field(_confirm, 'Confirmez le mot de passe', error: _matchError, action: TextInputAction.done),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, key: const Key('form-error'), style: const TextStyle(color: FideliaColors.danger, fontSize: 15)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('Enregistrer'),
            ),
            if (widget.forced)
              TextButton(
                onPressed: _busy ? null : () => ref.read(sessionProvider.notifier).signOut(),
                child: const Text('Se déconnecter'),
              ),
          ],
        ),
      ),
    );
  }
}
