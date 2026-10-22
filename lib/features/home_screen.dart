import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/net/api_exception.dart';
import '../ui/theme.dart';
import 'checks_screen.dart';

/// « À traiter »: the three request lists with their counts.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const _keys = {
    ChecksList.verify: Key('card-verify'),
    ChecksList.forgot: Key('card-forgot'),
    ChecksList.team: Key('card-team'),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(checksProvider);
    Future<void> refresh() async {
      ref.invalidate(checksProvider);
      try {
        await ref.read(checksProvider.future);
      } catch (_) {}
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
