import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/accounts/wallet_changes_api.dart';
import '../core/net/api_exception.dart';
import '../core/providers.dart';
import '../ui/theme.dart';
import 'relative_age.dart';
import 'whatsapp.dart';

const _providerNames = {'wave': 'Wave', 'orange': 'Orange Money', 'mtn': 'MTN MoMo', 'moov': 'Moov Money'};

const _actionNames = {
  'requested': 'Demande',
  'code_sent': 'Code envoyé',
  'confirmed': 'Code saisi',
  'frozen_not_me': 'Gelé : « ce n’était pas moi »',
  'activated_auto': 'Activé (après 24 h)',
  'activated_first_wallet': 'Activé (premier portefeuille)',
  'activated_admin_call': 'Activé après appel',
  'rejected': 'Rejeté',
  'cancelled': 'Annulé par le commerçant',
};

final walletChangesProvider = FutureProvider.autoDispose<List<WalletChangeItem>>((ref) => ref.watch(walletChangesApiProvider).open());

/// « Changements de portefeuille »: where a shop's customer payments are paid out is the shop's money, so each change goes
/// through the team: send the merchant a code on WhatsApp, or phone him and activate at once with a written note. A change the
/// merchant disowned (« ce n'était pas moi ») is frozen and can only be rejected here.
class WalletChangesScreen extends ConsumerStatefulWidget {
  const WalletChangesScreen({super.key});

  @override
  ConsumerState<WalletChangesScreen> createState() => _WalletChangesScreenState();
}

class _WalletChangesScreenState extends ConsumerState<WalletChangesScreen> {
  bool _busy = false;

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// One action, its failure explained, and always a refresh afterwards.
  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      _say(walletChangeErrorMessage(e));
    } catch (_) {
      _say('Une erreur est survenue. Réessayez.');
    } finally {
      ref.invalidate(walletChangesProvider);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send(WalletChangeItem c) => _act(() async {
        final uri = await ref.read(walletChangesApiProvider).sendCode(c.id);
        var opened = false;
        try {
          opened = await ref.read(whatsappLauncherProvider)(uri);
        } catch (_) {
          opened = false;
        }
        if (!opened) _say("WhatsApp n'a pas pu s'ouvrir.");
      });

  Future<void> _activate(WalletChangeItem c) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Activer ${c.shop} maintenant ?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Vous avez appelé le commerçant et vérifié que c’est bien lui. Le nouveau portefeuille démarre tout de suite, sans code ni attente. '
                'Votre note est conservée dans l’historique.'),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setLocal(() {}),
              decoration: const InputDecoration(labelText: 'Note d’appel', hintText: 'Appelé à 10 h, voix reconnue, connaît le nouveau numéro'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            TextButton(
              key: const Key('confirm-activate'),
              onPressed: note.text.trim().length >= 10 ? () => Navigator.pop(context, true) : null,
              child: const Text('Activer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _act(() => ref.read(walletChangesApiProvider).activateNow(c.id, note.text));
  }

  Future<void> _reject(WalletChangeItem c) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rejeter la demande de ${c.shop} ?'),
        content: TextField(controller: reason, decoration: const InputDecoration(labelText: 'Motif (facultatif)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Rejeter')),
        ],
      ),
    );
    if (ok != true) return;
    await _act(() => ref.read(walletChangesApiProvider).reject(c.id, reason: reason.text));
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(walletChangesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Changements de portefeuille')),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(walletChangesProvider.future).then((_) {}, onError: (_) {}),
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(padding: const EdgeInsets.all(24), children: [
            Text(e is ApiException ? walletChangeErrorMessage(e) : 'Chargement impossible. Tirez pour réessayer.', key: const Key('wallet-load-error')),
          ]),
          data: (items) => items.isEmpty
              ? ListView(padding: const EdgeInsets.all(24), children: const [Text('Aucune demande en cours.', key: Key('wallet-empty'))])
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // frozen first: someone says it is not them
                    for (final c in [...items]..sort((a, b) => (b.isFrozen ? 1 : 0) - (a.isFrozen ? 1 : 0)))
                      Padding(padding: const EdgeInsets.only(bottom: 12), child: _ChangeCard(item: c, busy: _busy, onSend: _send, onActivate: _activate, onReject: _reject)),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ChangeCard extends StatelessWidget {
  const _ChangeCard({required this.item, required this.busy, required this.onSend, required this.onActivate, required this.onReject});

  final WalletChangeItem item;
  final bool busy;
  final Future<void> Function(WalletChangeItem) onSend;
  final Future<void> Function(WalletChangeItem) onActivate;
  final Future<void> Function(WalletChangeItem) onReject;

  String get _status => switch (item.status) {
        'pending_confirmation' => item.codeSent ? 'Code envoyé, en attente de saisie' : 'Code à envoyer',
        'confirmed_waiting' => 'Confirmé, active ${item.activatesAt == null ? 'bientôt' : 'à ${_hm(item.activatesAt!.toLocal())}'}',
        'frozen' => 'GELÉ : le commerçant dit que ce n’est pas lui',
        _ => item.status,
      };

  static String _hm(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final frozen = item.isFrozen;
    return Card(
      key: Key('wallet-change-${item.id}'),
      color: frozen ? FideliaColors.danger.withOpacity(0.08) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.shop, style: theme.textTheme.titleMedium),
          if (item.merchantPhoneMasked != null) Text('Commerçant : ${item.merchantPhoneMasked}', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Text('${item.currentAccountMasked ?? 'aucun portefeuille'}  →  ${_providerNames[item.provider] ?? item.provider} ${item.newAccountMasked}'),
          const SizedBox(height: 4),
          Text(_status, style: TextStyle(fontWeight: FontWeight.w600, color: frozen ? FideliaColors.danger : null)),
          Text('Demandé ${relativeAge(item.requestedAt, DateTime.now())}', style: theme.textTheme.bodySmall),
          if (item.events.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Historique', style: TextStyle(fontSize: 14)),
              children: [
                for (final e in item.events)
                  ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(_actionNames[e.action] ?? e.action), subtitle: Text('${e.actor} · ${relativeAge(e.at, DateTime.now())}${e.detail == null ? '' : ' · ${e.detail}'}')),
              ],
            ),
          const SizedBox(height: 8),
          if (frozen)
            const Text('Appelez le commerçant pour vérifier, puis rejetez la demande. Il pourra en refaire une.')
          else ...[
            FilledButton.icon(
              key: Key('send-${item.id}'),
              onPressed: busy ? null : () => onSend(item),
              icon: const Icon(Icons.send_rounded),
              label: Text(item.codeSent ? 'Renvoyer le code (WhatsApp)' : 'Envoyer le code (WhatsApp)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(key: Key('activate-${item.id}'), onPressed: busy ? null : () => onActivate(item), child: const Text('Activer après appel')),
          ],
          const SizedBox(height: 8),
          TextButton(key: Key('reject-${item.id}'), onPressed: busy ? null : () => onReject(item), child: const Text('Rejeter')),
        ]),
      ),
    );
  }
}
