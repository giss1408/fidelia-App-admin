import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/accounts/accounts_api.dart';
import '../core/accounts/models.dart';
import '../core/net/api_exception.dart';
import '../core/providers.dart';
import '../ui/theme.dart';
import 'relative_age.dart';
import 'whatsapp.dart';

/// The three lists the team works through.
enum ChecksList {
  verify('Numéros à vérifier'),
  forgot('Mots de passe oubliés'),
  team('Identifiants commerçant');

  const ChecksList(this.title);

  final String title;
}

/// All open requests, split into the three lists, oldest first.
class ChecksData {
  const ChecksData(this._lists);

  final Map<ChecksList, List<AccountCheck>> _lists;

  List<AccountCheck> of(ChecksList list) => _lists[list] ?? const [];
}

final checksProvider = FutureProvider.autoDispose<ChecksData>((ref) async {
  final api = ref.watch(accountsApiProvider);
  final results = await Future.wait([
    api.checks('verify_number'),
    api.checks('change_number'),
    api.checks('reset_password'),
  ]);
  int oldestFirst(AccountCheck a, AccountCheck b) => a.createdAt.compareTo(b.createdAt);
  final verify = [...results[0], ...results[1]]..sort(oldestFirst);
  final forgot = results[2].where((c) => !c.teamCreated).toList()..sort(oldestFirst);
  final team = results[2].where((c) => c.teamCreated).toList()..sort(oldestFirst);
  return ChecksData({ChecksList.verify: verify, ChecksList.forgot: forgot, ChecksList.team: team});
});

class ChecksScreen extends ConsumerStatefulWidget {
  const ChecksScreen({super.key, required this.list});

  final ChecksList list;

  @override
  ConsumerState<ChecksScreen> createState() => _ChecksScreenState();
}

class _ChecksScreenState extends ConsumerState<ChecksScreen> {
  bool _busy = false;

  Future<void> _refresh() async {
    ref.invalidate(checksProvider);
    try {
      await ref.read(checksProvider.future);
    } catch (_) {
      // The list shows its own error state.
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs one action, reports its failure, and always refreshes afterwards.
  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on AlreadyHandled catch (e) {
      _say(e.message);
    } on ApiException catch (e) {
      _say(e.message);
    } finally {
      await _refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send(AccountCheck check) => _act(() async {
        final uri = await ref.read(accountsApiProvider).send(check.id);
        var opened = false;
        try {
          opened = await ref.read(whatsappLauncherProvider)(uri);
        } catch (_) {
          opened = false;
        }
        if (!opened) _say("WhatsApp n'a pas pu s'ouvrir.");
      });

  Future<void> _refuse(AccountCheck check) async {
    final reset = check.kind == 'reset_password';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Refuser cette demande ?'),
        content: Text(reset
            ? 'La demande sera close.'
            : "La personne verra que son numéro n'a pas pu être vérifié et pourra le corriger."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Refuser')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _act(() => ref.read(accountsApiProvider).refuse(check.id));
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(checksProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.list.title)),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: data.when(
          loading: () => _scrollable(const [Center(child: CircularProgressIndicator())]),
          error: (e, _) => _scrollable([
            Center(child: Text(e is ApiException ? e.message : 'Chargement impossible. Tirez pour réessayer.')),
          ]),
          data: (d) {
            final items = d.of(widget.list);
            if (items.isEmpty) return _scrollable([const Center(child: Text('Rien à traiter'))]);
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _CheckCard(
                key: ValueKey(items[i].id),
                check: items[i],
                busy: _busy,
                onSend: () => _send(items[i]),
                onRefuse: () => _refuse(items[i]),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _scrollable(List<Widget> children) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: children,
      );
}

class _CheckCard extends StatelessWidget {
  const _CheckCard({super.key, required this.check, required this.busy, required this.onSend, required this.onRefuse});

  final AccountCheck check;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onRefuse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reset = check.kind == 'reset_password';
    final resend = check.sentAt != null;
    final what = reset ? 'un mot de passe temporaire' : 'le code';
    final label = resend
        ? (reset ? 'Renvoyer un mot de passe temporaire sur WhatsApp' : 'Renvoyer le code sur WhatsApp')
        : 'Envoyer $what sur WhatsApp';
    return Card(
      key: key,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Chip(label: Text(check.app == 'merchant' ? 'Fidelia Pro' : 'Fidelia')),
                if (check.kind == 'change_number') ...[
                  const SizedBox(width: 8),
                  Text('Nouveau numéro', style: theme.textTheme.labelSmall),
                ],
                const Spacer(),
                Text(relativeAge(check.createdAt, DateTime.now().toUtc()), style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(check.phoneMasked, style: theme.textTheme.titleLarge),
            if (resend) ...[
              const SizedBox(height: 4),
              Text(reset ? 'Mot de passe déjà envoyé' : 'Code déjà envoyé',
                  style: theme.textTheme.bodySmall?.copyWith(color: FideliaColors.success)),
            ],
            const SizedBox(height: 12),
            FilledButton(onPressed: busy ? null : onSend, child: Text(label, textAlign: TextAlign.center)),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: busy ? null : onRefuse, child: const Text('Refuser')),
          ],
        ),
      ),
    );
  }
}
