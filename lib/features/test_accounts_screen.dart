import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/accounts/models.dart';
import '../core/net/api_exception.dart';
import '../core/providers.dart';
import '../ui/theme.dart';
import 'change_password_screen.dart' show isAcceptablePassword, passwordRuleText;

/// The shared test logins, or null when this admin may not manage them.
final testAccountsProvider = FutureProvider.autoDispose<List<TestAccount>?>((ref) => ref.watch(accountsApiProvider).testAccounts());

const _roles = {
  'customer': 'Client',
  'merchant': 'Commerçant',
  'cashier': 'Caissier',
  'agent': 'Agent terrain',
  'admin': 'Admin',
};

/// « Comptes de test », for the super admin: the shared test numbers and one
/// password for all of them, in place of FIDELIA_SEED_PASSWORD on Render.
class TestAccountsScreen extends ConsumerStatefulWidget {
  const TestAccountsScreen({super.key});

  @override
  ConsumerState<TestAccountsScreen> createState() => _TestAccountsScreenState();
}

class _TestAccountsScreenState extends ConsumerState<TestAccountsScreen> {
  final _password = TextEditingController();
  bool _hidden = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (!isAcceptablePassword(_password.text)) {
      setState(() => _error = passwordRuleText);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountsApiProvider).setTestPassword(_password.text);
      if (!mounted) return;
      _password.clear();
      ref.invalidate(testAccountsProvider);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mot de passe des comptes de test enregistré')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(testAccountsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Comptes de test')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Les numéros partagés pour tester les apps. Un seul mot de passe pour tous ; '
            'les remplacer déconnecte ceux qui les utilisent. Votre propre compte ne change pas.',
          ),
          const SizedBox(height: 16),
          ...switch (accounts) {
            AsyncData(:final value?) => [
                for (final a in value)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(a.hasPassword ? Icons.lock_outline : Icons.lock_open_outlined),
                    title: Text(a.phoneMasked),
                    subtitle: Text('${_roles[a.role] ?? a.role}${a.hasPassword ? '' : ' · sans mot de passe'}'),
                  ),
              ],
            AsyncError(:final error) => [Text('$error', style: const TextStyle(color: FideliaColors.danger))],
            _ => [const Center(child: CircularProgressIndicator())],
          },
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            enabled: !_busy,
            obscureText: _hidden,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'Nouveau mot de passe des comptes de test',
              helperText: passwordRuleText,
              errorText: _error,
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _hidden ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
                icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}
