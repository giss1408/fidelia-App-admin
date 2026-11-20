import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/accounts/relay_queue_api.dart';
import '../core/net/api_exception.dart';
import '../core/providers.dart';
import '../ui/theme.dart';
import 'relative_age.dart';
import 'step_up.dart';
import 'whatsapp.dart';

final relayQueueApiProvider = Provider<RelayQueueApi?>((ref) {
  final client = ref.watch(authServiceClientProvider);
  return client == null ? null : RelayQueueApi(client);
});

final relayQueueProvider = FutureProvider.autoDispose<List<RelayItem>>((ref) async {
  final api = ref.watch(relayQueueApiProvider);
  return api == null ? const [] : api.pending();
});

/// « Codes à envoyer »: new sign-ups wait for an activation code, and people who forgot their password wait for a temporary one. The team
/// sends each by WhatsApp from its own phone (the button opens the message, already written) and the person types it in the app.
/// A number that is not on WhatsApp is refused, which frees it for a new sign-up.
class RelayQueueScreen extends ConsumerStatefulWidget {
  const RelayQueueScreen({super.key});

  @override
  ConsumerState<RelayQueueScreen> createState() => _RelayQueueScreenState();
}

class _RelayQueueScreenState extends ConsumerState<RelayQueueScreen> {
  bool _busy = false;

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await withStepUp(context, ref, action);
    } on ApiException catch (e) {
      _say(relayErrorMessage(e));
    } catch (_) {
      _say('Une erreur est survenue. Réessayez.');
    } finally {
      ref.invalidate(relayQueueProvider);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send(RelayItem item) => _act(() async {
        final uri = await ref.read(relayQueueApiProvider)!.send(item.id);
        var opened = false;
        try {
          opened = await ref.read(whatsappLauncherProvider)(uri);
        } catch (_) {
          opened = false;
        }
        if (!opened) _say("WhatsApp n'a pas pu s'ouvrir.");
      });

  Future<void> _reject(RelayItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Refuser ce numéro ?'),
        content: const Text('À faire si le numéro n’est pas sur WhatsApp ou ne répond pas. Il est libéré : la personne pourra s’inscrire à nouveau avec le bon numéro.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(
            key: const Key('confirm-reject'),
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: FideliaColors.danger),
            child: const Text('Refuser'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _act(() => ref.read(relayQueueApiProvider)!.reject(item.id));
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(relayQueueProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Codes à envoyer')),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(relayQueueProvider.future).then((_) {}, onError: (_) {}),
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(padding: const EdgeInsets.all(24), children: [
            Text(e is ApiException ? relayErrorMessage(e) : 'Chargement impossible. Tirez pour réessayer.', key: const Key('relay-load-error')),
          ]),
          data: (items) => items.isEmpty
              ? ListView(padding: const EdgeInsets.all(24), children: const [Text('Rien à envoyer.', key: Key('relay-empty'))])
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final i in items)
                      Padding(padding: const EdgeInsets.only(bottom: 12), child: _Card(item: i, busy: _busy, onSend: _send, onReject: _reject)),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.item, required this.busy, required this.onSend, required this.onReject});

  final RelayItem item;
  final bool busy;
  final Future<void> Function(RelayItem) onSend;
  final Future<void> Function(RelayItem) onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activation = item.isActivation;
    return Card(
      key: Key('relay-${item.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.displayName ?? (activation ? 'Nouvelle inscription' : 'Mot de passe oublié'), style: theme.textTheme.titleMedium),
          if (item.phoneMasked != null) Text(item.phoneMasked!),
          const SizedBox(height: 4),
          Text(
            activation
                ? (item.sent ? 'Code d’activation envoyé, pas encore saisi' : 'Code d’activation à envoyer')
                : 'Mot de passe temporaire à envoyer',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text('Demandé ${relativeAge(item.createdAt, DateTime.now())}', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: Key('send-${item.id}'),
            onPressed: busy ? null : () => onSend(item),
            icon: const Icon(Icons.send_rounded),
            label: Text(item.sent ? 'Renvoyer (WhatsApp)' : 'Envoyer (WhatsApp)'),
          ),
          if (activation) ...[
            const SizedBox(height: 8),
            TextButton(
              key: Key('reject-${item.id}'),
              onPressed: busy ? null : () => onReject(item),
              style: TextButton.styleFrom(foregroundColor: FideliaColors.danger),
              child: const Text('Numéro pas sur WhatsApp : refuser'),
            ),
          ],
        ]),
      ),
    );
  }
}
