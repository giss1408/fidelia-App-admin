import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/accounts/frozen_accounts_api.dart';
import '../core/net/api_exception.dart';
import '../core/providers.dart';
import 'relative_age.dart';
import 'account_lookup_screen.dart';
import 'step_up.dart';

final frozenAccountsApiProvider = Provider<FrozenAccountsApi?>((ref) {
  final client = ref.watch(authServiceClientProvider);
  return client == null ? null : FrozenAccountsApi(client);
});

final frozenAccountsProvider = FutureProvider.autoDispose<List<FrozenAccount>>((ref) async {
  final api = ref.watch(frozenAccountsApiProvider);
  return api == null ? const [] : api.list();
});

/// « Comptes gelés »: an account is frozen when someone said « ce n'était pas moi » about a number change, or when an admin switched it off.
/// It stays shut until the team has phoned the person and checked it is her; then it is given back here, with a written note.
class FrozenAccountsScreen extends ConsumerStatefulWidget {
  const FrozenAccountsScreen({super.key});

  @override
  ConsumerState<FrozenAccountsScreen> createState() => _FrozenAccountsScreenState();
}

class _FrozenAccountsScreenState extends ConsumerState<FrozenAccountsScreen> {
  bool _busy = false;

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _enable(FrozenAccount a) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Réactiver ce compte ?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Vous avez appelé la personne et vérifié que c’est bien elle. Le compte fonctionne de nouveau. Votre note est conservée dans l’historique.'),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setLocal(() {}),
              decoration: const InputDecoration(labelText: 'Note d’appel', hintText: 'Appelée à 10 h, voix reconnue, confirme sa demande'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            TextButton(
              key: const Key('confirm-enable'),
              onPressed: note.text.trim().length >= 10 ? () => Navigator.pop(context, true) : null,
              child: const Text('Réactiver'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || _busy || !mounted) return;
    setState(() => _busy = true);
    try {
      await withStepUp(context, ref, () => ref.read(frozenAccountsApiProvider)!.enable(a.id, note.text));
    } on ApiException catch (e) {
      _say(frozenErrorMessage(e));
    } catch (_) {
      _say('Une erreur est survenue. Réessayez.');
    } finally {
      ref.invalidate(frozenAccountsProvider);
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _reason(String r) => switch (r) {
        'not_me' => 'Gelé : « ce n’était pas moi » sur un changement de numéro',
        'disabled' => 'Désactivé par l’équipe',
        _ => 'Raison inconnue',
      };

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(frozenAccountsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Comptes gelés'), actions: [
        IconButton(
          key: const Key('lookup'),
          tooltip: 'Suspendre un compte',
          icon: const Icon(Icons.person_off_outlined),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountLookupScreen())),
        ),
      ]),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(frozenAccountsProvider.future).then((_) {}, onError: (_) {}),
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(padding: const EdgeInsets.all(24), children: [
            Text(e is ApiException ? frozenErrorMessage(e) : 'Chargement impossible. Tirez pour réessayer.', key: const Key('frozen-load-error')),
          ]),
          data: (items) => items.isEmpty
              ? ListView(padding: const EdgeInsets.all(24), children: const [Text('Aucun compte gelé.', key: Key('frozen-empty'))])
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final a in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          key: Key('frozen-${a.id}'),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(a.displayName ?? 'Client Fidelia', style: Theme.of(context).textTheme.titleMedium),
                              if (a.phoneMasked != null) Text(a.phoneMasked!),
                              const SizedBox(height: 4),
                              Text(_reason(a.reason), style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (a.since != null) Text('Depuis ${relativeAge(a.since!, DateTime.now())}', style: Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 8),
                              OutlinedButton(key: Key('enable-${a.id}'), onPressed: _busy ? null : () => _enable(a), child: const Text('Réactiver après appel')),
                            ]),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
