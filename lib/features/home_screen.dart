import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/net/api_exception.dart';
import '../ui/theme.dart';
import 'account_screen.dart';
import 'checks_screen.dart';
import 'duties_screen.dart';
import 'users_screen.dart';
import 'frozen_accounts_screen.dart';
import 'phone_changes_screen.dart';
import 'relay_queue_screen.dart';
import 'wallet_changes_screen.dart';

/// The signed-in shell: « À traiter », « Utilisateurs », « Gardes » and « Compte ».
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  // « Gardes » loads only once opened: most sessions are about requests.
  bool _dutiesOpened = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [const TodoTab(), const UsersScreen(), if (_dutiesOpened) const DutiesScreen() else const SizedBox(), const AccountScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() {
          _index = i;
          _dutiesOpened |= i == 2;
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.inbox_outlined), selectedIcon: Icon(Icons.inbox), label: 'À traiter'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Utilisateurs'),
          NavigationDestination(icon: Icon(Icons.local_pharmacy_outlined), selectedIcon: Icon(Icons.local_pharmacy), label: 'Gardes'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Compte'),
        ],
      ),
    );
  }
}

/// « À traiter »: the three request lists with their counts.
class TodoTab extends ConsumerWidget {
  const TodoTab({super.key});

  static const _keys = {
    ChecksList.verify: Key('card-verify'),
    ChecksList.forgot: Key('card-forgot'),
    ChecksList.team: Key('card-team'),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(checksProvider);
    Future<void> refresh() async {
      final error = await refreshChecks(ref);
      if (error != null && context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error)));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('À traiter')),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (data.hasError && !data.hasValue)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  data.error is ApiException
                      ? (data.error! as ApiException).message
                      : 'Chargement impossible. Tirez pour réessayer.',
                ),
              ),
            // Wallet changes: where a shop's money is paid out. A change the merchant disowned shows first inside.
            _CountCard(
              key: const Key('card-wallet'),
              title: 'Changements de portefeuille',
              count: ref.watch(walletChangesProvider).valueOrNull?.length,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WalletChangesScreen())),
            ),
            const SizedBox(height: 12),
            // Activation codes and temporary passwords (auth mode only: the process lives in the auth service).
            if (ref.watch(relayQueueApiProvider) != null) ...[
              _CountCard(
                key: const Key('card-relay'),
                title: 'Codes à envoyer',
                count: ref.watch(relayQueueProvider).valueOrNull?.length,
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RelayQueueScreen())),
              ),
              const SizedBox(height: 12),
            ],
            // Frozen accounts (auth mode only).
            if (ref.watch(frozenAccountsApiProvider) != null) ...[
              _CountCard(
                key: const Key('card-frozen'),
                title: 'Comptes gelés',
                count: ref.watch(frozenAccountsProvider).valueOrNull?.length,
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FrozenAccountsScreen())),
              ),
              const SizedBox(height: 12),
            ],
            // Number changes (auth mode only: the process lives in the auth service).
            if (ref.watch(phoneChangesApiProvider) != null) ...[
              _CountCard(
                key: const Key('card-phone'),
                title: 'Changements de numéro',
                count: ref.watch(phoneChangesProvider).valueOrNull?.length,
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PhoneChangesScreen())),
              ),
              const SizedBox(height: 12),
            ],
            for (final list in ChecksList.values) ...[
              _CountCard(
                key: _keys[list],
                title: list.title,
                count: data.valueOrNull?.of(list).length,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => ChecksScreen(list: list)),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({super.key, required this.title, required this.count, required this.onTap});

  final String title;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              Text(count?.toString() ?? '–', style: serifStyle(34, color: FideliaColors.orangeDeep)),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: FideliaColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
