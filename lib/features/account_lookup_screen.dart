import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/accounts/frozen_accounts_api.dart';
import '../core/net/api_exception.dart';
import '../ui/theme.dart';
import 'frozen_accounts_screen.dart';
import 'step_up.dart';

/// « Suspendre un compte »: find the person by number, check it is the right one, and switch the account off with a written note (a stolen
/// phone, fraud, a request). Her sessions end at once; the account comes back from « Comptes gelés » after a call.
class AccountLookupScreen extends ConsumerStatefulWidget {
  const AccountLookupScreen({super.key});

  @override
  ConsumerState<AccountLookupScreen> createState() => _AccountLookupScreenState();
}

class _AccountLookupScreenState extends ConsumerState<AccountLookupScreen> {
  final _phone = TextEditingController();
  AccountHit? _hit;
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_busy || _phone.text.trim().length < 8) return;
    setState(() {
      _busy = true;
      _hit = null;
      _message = null;
    });
    try {
      final hit = await ref.read(frozenAccountsApiProvider)!.search(_phone.text);
      if (mounted) setState(() => _hit = hit);
    } on ApiException catch (e) {
      if (mounted) setState(() => _message = frozenErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable(AccountHit hit) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Suspendre ce compte ?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Toutes ses sessions se ferment tout de suite et elle ne peut plus se connecter. Vous pourrez la réactiver après un appel, depuis « Comptes gelés ». '
                'Votre note est conservée dans l’historique.'),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setLocal(() {}),
              decoration: const InputDecoration(labelText: 'Motif', hintText: 'Téléphone volé, signalé par la cliente à 9 h'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            TextButton(
              key: const Key('confirm-disable'),
              onPressed: note.text.trim().length >= 10 ? () => Navigator.pop(context, true) : null,
              style: TextButton.styleFrom(foregroundColor: FideliaColors.danger),
              child: const Text('Suspendre'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || _busy || !mounted) return;
    setState(() => _busy = true);
    try {
      await withStepUp(context, ref, () => ref.read(frozenAccountsApiProvider)!.disable(hit.id, note.text));
      ref.invalidate(frozenAccountsProvider);
      if (mounted) setState(() => _hit = null);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Compte suspendu. Il apparaît dans « Comptes gelés ».')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(frozenErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hit = _hit;
    return Scaffold(
      appBar: AppBar(title: const Text('Suspendre un compte')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        TextField(
          key: const Key('lookup-phone'),
          controller: _phone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: const InputDecoration(labelText: 'Numéro de téléphone', prefixIcon: Icon(Icons.phone_outlined)),
        ),
        const SizedBox(height: 12),
        FilledButton(key: const Key('lookup-search'), onPressed: _busy ? null : _search, child: const Text('Chercher')),
        const SizedBox(height: 16),
        if (_message != null) Text(_message!, key: const Key('lookup-message'), style: const TextStyle(color: FideliaColors.danger)),
        if (hit != null)
          Card(
            key: const Key('lookup-result'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(hit.displayName ?? 'Client Fidelia', style: Theme.of(context).textTheme.titleMedium),
                if (hit.phoneMasked != null) Text(hit.phoneMasked!),
                const SizedBox(height: 4),
                Text(hit.roles.join(' · ')),
                const SizedBox(height: 8),
                if (hit.isActive)
                  OutlinedButton(
                    key: const Key('lookup-disable'),
                    onPressed: _busy ? null : () => _disable(hit),
                    style: OutlinedButton.styleFrom(foregroundColor: FideliaColors.danger),
                    child: const Text('Suspendre ce compte'),
                  )
                else
                  const Text('Ce compte n’est pas actif : voir « Comptes gelés ».', key: Key('lookup-not-active')),
              ]),
            ),
          ),
      ]),
    );
  }
}
