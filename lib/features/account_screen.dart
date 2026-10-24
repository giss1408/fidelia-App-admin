import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'change_password_screen.dart';
import 'shops_screen.dart';
import 'test_accounts_screen.dart';

/// « Compte »: the admin's own password and sign-out, and for the super admin
/// the shared test logins.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  void _say(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _changePassword(BuildContext context) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const ChangePasswordScreen(forced: false)),
    );
    if (changed == true && context.mounted) _say(context, 'Mot de passe changé');
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmer')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(sessionProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final username = ref.watch(sessionProvider).username;
    return Scaffold(
      appBar: AppBar(title: const Text('Compte')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (username != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(username, style: Theme.of(context).textTheme.titleLarge),
            ),
          FilledButton(onPressed: () => _changePassword(context), child: const Text('Changer mon mot de passe')),
          // Only the super admin gets these lists; anyone else, nothing to show.
          if (ref.watch(shopsProvider('')).valueOrNull != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ShopsScreen())),
              child: const Text('Commerces'),
            ),
          ],
          if (ref.watch(testAccountsProvider).valueOrNull != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TestAccountsScreen())),
              child: const Text('Comptes de test'),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton(onPressed: () => _signOut(context, ref), child: const Text('Se déconnecter')),
        ],
      ),
    );
  }
}
