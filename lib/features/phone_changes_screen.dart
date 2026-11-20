import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/accounts/phone_changes_api.dart';
import '../core/net/api_exception.dart';
import '../core/providers.dart';
import '../ui/theme.dart';
import 'relative_age.dart';
import 'step_up.dart';
import 'whatsapp.dart';

final phoneChangesApiProvider = Provider<PhoneChangesApi?>((ref) {
  final client = ref.watch(authServiceClientProvider);
  return client == null ? null : PhoneChangesApi(client);
});

final phoneChangesProvider = FutureProvider.autoDispose<List<PhoneChangeItem>>((ref) async {
  final api = ref.watch(phoneChangesApiProvider);
  return api == null ? const [] : api.open();
});

/// « Changements de numéro »: a person moving her account to another number goes through the team. The code for the NEW number and the
/// warning for the OLD one are WhatsApp messages sent from here; the change takes effect after a security delay (24 h), unless an admin
/// phoned her on the old number and makes it effective at once with a written note; « ce n'était pas moi » cancels it and freezes the account.
class PhoneChangesScreen extends ConsumerStatefulWidget {
  const PhoneChangesScreen({super.key});

  @override
  ConsumerState<PhoneChangesScreen> createState() => _PhoneChangesScreenState();
}

class _PhoneChangesScreenState extends ConsumerState<PhoneChangesScreen> {
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
      _say(phoneChangeErrorMessage(e));
    } catch (_) {
      _say('Une erreur est survenue. Réessayez.');
    } finally {
      ref.invalidate(phoneChangesProvider);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send(PhoneRelay relay) => _act(() async {
        final uri = await ref.read(phoneChangesApiProvider)!.sendRelay(relay.id);
        var opened = false;
        try {
          opened = await ref.read(whatsappLauncherProvider)(uri);
        } catch (_) {
          opened = false;
        }
        if (!opened) _say("WhatsApp n'a pas pu s'ouvrir.");
      });

  Future<void> _activate(PhoneChangeItem c) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Changer le numéro maintenant ?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Vous avez appelé la personne sur son ANCIEN numéro et elle confirme. Le changement prend effet tout de suite et ses '
                'sessions se ferment. Votre note est conservée dans l’historique.'),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setLocal(() {}),
              decoration: const InputDecoration(labelText: 'Note d’appel', hintText: 'Appelée à 10 h sur l’ancien numéro, voix reconnue'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            TextButton(
              key: const Key('confirm-activate'),
              onPressed: note.text.trim().length >= 10 ? () => Navigator.pop(context, true) : null,
              child: const Text('Changer maintenant'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _act(() => ref.read(phoneChangesApiProvider)!.activateNow(c.id, note.text));
  }

  Future<void> _notMe(PhoneChangeItem c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('« Ce n’était pas moi » ?'),
        content: const Text('La demande est annulée (ou l’ancien numéro est remis), le compte est GELÉ et toutes ses sessions se ferment. '
            'Appelez la personne, puis réactivez le compte dans les outils d’administration.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(
            key: const Key('confirm-not-me'),
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: FideliaColors.danger),
            child: const Text('Geler le compte'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _act(() => ref.read(phoneChangesApiProvider)!.notMe(c.id));
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(phoneChangesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Changements de numéro')),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(phoneChangesProvider.future).then((_) {}, onError: (_) {}),
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(padding: const EdgeInsets.all(24), children: [
            Text(e is ApiException ? phoneChangeErrorMessage(e) : 'Chargement impossible. Tirez pour réessayer.', key: const Key('phone-load-error')),
          ]),
          data: (items) => items.isEmpty
              ? ListView(padding: const EdgeInsets.all(24), children: const [Text('Aucun changement de numéro en cours.', key: Key('phone-empty'))])
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final c in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _Card(item: c, busy: _busy, onSend: _send, onActivate: _activate, onNotMe: _notMe),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.item, required this.busy, required this.onSend, required this.onActivate, required this.onNotMe});

  final PhoneChangeItem item;
  final bool busy;
  final Future<void> Function(PhoneRelay) onSend;
  final Future<void> Function(PhoneChangeItem) onActivate;
  final Future<void> Function(PhoneChangeItem) onNotMe;

  static String _hm(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';

  String get _status => switch (item.status) {
        'requested' => item.code == null
            ? 'Demande en cours'
            : item.code!.sent
                ? 'Code envoyé au nouveau numéro, en attente de saisie'
                : 'Code à envoyer au nouveau numéro',
        'scheduled' => 'Code saisi. Prend effet ${item.effectiveAt == null ? 'bientôt' : 'le ${_hm(item.effectiveAt!.toLocal())}'}',
        'done' => 'Changement effectué : avis à envoyer à l’ancien numéro',
        _ => item.status,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: Key('phone-change-${item.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.displayName ?? 'Client Fidelia', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('${item.oldPhoneMasked ?? 'ancien numéro'}  →  ${item.newPhoneMasked}'),
          const SizedBox(height: 4),
          Text(_status, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('Demandé ${relativeAge(item.createdAt, DateTime.now())}', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          if (item.code != null)
            FilledButton.icon(
              key: Key('send-code-${item.id}'),
              onPressed: busy ? null : () => onSend(item.code!),
              icon: const Icon(Icons.send_rounded),
              label: Text(item.code!.sent ? 'Renvoyer le code (WhatsApp)' : 'Envoyer le code au nouveau numéro'),
            ),
          if (item.alert != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: Key('send-alert-${item.id}'),
              onPressed: busy ? null : () => onSend(item.alert!),
              icon: const Icon(Icons.warning_amber_rounded),
              label: const Text('Prévenir l’ancien numéro'),
            ),
          ],
          if (item.notice != null)
            FilledButton.icon(
              key: Key('send-notice-${item.id}'),
              onPressed: busy ? null : () => onSend(item.notice!),
              icon: const Icon(Icons.send_rounded),
              label: const Text('Envoyer l’avis à l’ancien numéro'),
            ),
          if (item.status == 'scheduled') ...[
            const SizedBox(height: 8),
            OutlinedButton(key: Key('activate-${item.id}'), onPressed: busy ? null : () => onActivate(item), child: const Text('Changer maintenant (après appel)')),
          ],
          if (item.canStop) ...[
            const SizedBox(height: 8),
            TextButton(
              key: Key('not-me-${item.id}'),
              onPressed: busy ? null : () => onNotMe(item),
              style: TextButton.styleFrom(foregroundColor: FideliaColors.danger),
              child: const Text('« Ce n’était pas moi »'),
            ),
          ],
        ]),
      ),
    );
  }
}
