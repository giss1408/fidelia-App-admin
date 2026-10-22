import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_repository.dart';
import '../core/providers.dart';
import '../ui/theme.dart';

/// Phone + password sign-in for the Fidelia team.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _hidden = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_phone.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Saisissez votre numéro et votre mot de passe.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref.read(sessionProvider.notifier).signIn(phone: _phone.text.trim(), password: _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = switch (result) {
        SignedIn() => null,
        SignInRejected(:final message) => message,
        SignInUnavailable(:final message) => message,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: FideliaColors.headerGradient,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
            ),
            padding: EdgeInsets.fromLTRB(28, top + 44, 28, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fidelia Admin', style: serifStyle(42, color: Colors.white)),
                const SizedBox(height: 8),
                Text('Réservé à l’équipe Fidelia',
                    style: TextStyle(color: Colors.white.withOpacity(0.88), fontSize: 15.5)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Numéro de téléphone', prefixIcon: Icon(Icons.phone_outlined)),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _password,
                  obscureText: _hidden,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _hidden ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
                      icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _hidden = !_hidden),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, key: const Key('form-error'), style: const TextStyle(color: FideliaColors.danger, fontSize: 15)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Text('Se connecter'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
