import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/accounts/models.dart';
import '../core/net/api_exception.dart';
import '../core/providers.dart';
import '../ui/theme.dart';
import 'checks_screen.dart';
import 'relative_age.dart';

const _roleNames = {
  'customer': 'Client',
  'merchant': 'Commerçant',
  'cashier': 'Caissier',
  'agent': 'Agent',
  'admin': 'Admin',
};

const _genericError = 'Une erreur est survenue. Réessayez.';

/// « Utilisateurs »: find an account by phone and act on it.
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  final _phone = TextEditingController();
  String _searched = '';
  AdminUserView? _user;
  bool _notFound = false;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _load(String phone) async {
    final user = await ref.read(accountsApiProvider).findUser(phone);
    if (!mounted) return;
    setState(() {
      _user = user;
      _notFound = user == null;
    });
  }

  Future<void> _search() async {
    final phone = _phone.text.trim();
    if (_busy || phone.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _user = null;
      _notFound = false;
    });
    try {
      await _load(phone);
      _searched = phone;
    } on ApiException catch (e) {
      _say(e.message);
    } catch (_) {
      _say(_genericError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _act(
    String question,
    Future<void> Function(int id) action,
    String done, {
    bool refreshChecksAfter = false,
  }) async {
    final user = _user;
    if (user == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(question),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmer')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await action(user.id);
      if (refreshChecksAfter) ref.invalidate(checksProvider);
      _say(done);
      await _load(_searched);
    } on ApiException catch (e) {
      _say(e.message);
    } catch (_) {
      _say(_genericError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.read(accountsApiProvider);
    final user = _user;
    return Scaffold(
      appBar: AppBar(title: const Text('Utilisateurs')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.search,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))],
            onSubmitted: (_) => _search(),
            decoration: const InputDecoration(labelText: 'Numéro de téléphone', prefixIcon: Icon(Icons.phone_outlined)),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : _search, child: const Text('Rechercher')),
          const SizedBox(height: 16),
          if (_notFound) const Center(child: Text('Aucun compte pour ce numéro')),
          if (user != null)
            _UserCard(
              user: user,
              busy: _busy,
              onSuspend: () => _act('Suspendre ce compte ?', api.suspend, 'Compte suspendu'),
              onRestore: () => _act('Réactiver ce compte ?', api.restore, 'Compte réactivé'),
              onSignOut: () => _act('Fermer toutes les sessions ?', api.signOut, 'Sessions fermées'),
              onDelete: () => _act(
                'Supprimer ce compte ? Le numéro et ses points sont effacés, sans retour.',
                api.deleteUser,
                'Compte supprimé',
              ),
              onReset: () => _act(
                'Réinitialiser le mot de passe ?',
                api.resetPassword,
                'Demande créée : envoyez le mot de passe depuis « Mots de passe oubliés »',
                refreshChecksAfter: true,
              ),
            ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.busy,
    required this.onSuspend,
    required this.onRestore,
    required this.onSignOut,
    required this.onReset,
    required this.onDelete,
  });

  final AdminUserView user;
  final bool busy;
  final VoidCallback onSuspend;
  final VoidCallback onRestore;
  final VoidCallback onSignOut;
  final VoidCallback onReset;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = user.roles.map((r) => _roleNames[r] ?? r).join(', ');
    final last = user.lastLoginAt;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(user.phoneMasked, style: theme.textTheme.titleLarge),
            if (roles.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(roles, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                Chip(label: Text(user.verified ? 'Vérifié' : 'Non vérifié')),
                if (user.disabled)
                  Chip(label: const Text('Suspendu'), backgroundColor: FideliaColors.danger.withOpacity(0.15)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              last == null
                  ? 'Jamais connecté'
                  : 'Dernière connexion : ${relativeAge(last, DateTime.now().toUtc())}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (user.disabled)
              FilledButton(onPressed: busy ? null : onRestore, child: const Text('Réactiver'))
            else
              OutlinedButton(onPressed: busy ? null : onSuspend, child: const Text('Suspendre')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: busy ? null : onSignOut, child: const Text('Déconnecter partout')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: busy ? null : onReset, child: const Text('Réinitialiser le mot de passe')),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: busy ? null : onDelete,
              style: OutlinedButton.styleFrom(foregroundColor: FideliaColors.danger),
              child: const Text('Supprimer le compte'),
            ),
          ],
        ),
      ),
    );
  }
}
