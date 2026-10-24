import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/accounts/models.dart';
import '../core/net/api_exception.dart';
import '../core/providers.dart';
import '../ui/theme.dart';

/// The shops, or null when this admin is not the super admin.
final shopsProvider = FutureProvider.autoDispose.family<List<AdminShop>?, String>(
  (ref, query) => ref.watch(accountsApiProvider).shops(query),
);

/// « Commerces », for the super admin: clear test or pilot shops, each with
/// everything attached, before going live.
class ShopsScreen extends ConsumerStatefulWidget {
  const ShopsScreen({super.key});

  @override
  ConsumerState<ShopsScreen> createState() => _ShopsScreenState();
}

class _ShopsScreenState extends ConsumerState<ShopsScreen> {
  final _search = TextEditingController();
  String _query = '';
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _delete(AdminShop shop) async {
    final typed = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('Supprimer « ${shop.name} » ?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Le commerce et tout ce qui s’y rattache sont effacés, sans retour : ventes, paiements, points, '
                'offres, photos, caissiers. Les comptes du gérant et des caissiers aussi, s’ils n’ont pas d’autre commerce.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: typed,
                autofocus: true,
                onChanged: (_) => setDialog(() {}),
                decoration: const InputDecoration(labelText: 'Tapez le nom du commerce pour confirmer'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            TextButton(
              onPressed: typed.text.trim() == shop.name ? () => Navigator.pop(context, true) : null,
              style: TextButton.styleFrom(foregroundColor: FideliaColors.danger),
              child: const Text('Supprimer'),
            ),
          ],
        ),
      ),
    );
    final name = typed.text.trim();
    typed.dispose();
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final rows = await ref.read(accountsApiProvider).deleteShop(shop.id, name);
      ref.invalidate(shopsProvider);
      _say('« ${shop.name} » supprimé ($rows éléments)');
    } on ApiException catch (e) {
      _say(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shops = ref.watch(shopsProvider(_query));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Commerces')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (value) => setState(() => _query = value.trim()),
            decoration: const InputDecoration(labelText: 'Nom ou commune', prefixIcon: Icon(Icons.search)),
          ),
          const SizedBox(height: 12),
          ...switch (shops) {
            AsyncData(:final value?) when value.isEmpty => [const Center(child: Text('Aucun commerce'))],
            AsyncData(:final value?) => [
                for (final shop in value)
                  Card(
                    child: ListTile(
                      title: Text(shop.name),
                      subtitle: Text([
                        shop.commune,
                        if (shop.ownerMasked != null) shop.ownerMasked!,
                        if (shop.isSample) 'exemple',
                      ].join(' · ')),
                      trailing: IconButton(
                        tooltip: 'Supprimer ce commerce',
                        icon: const Icon(Icons.delete_outline, color: FideliaColors.danger),
                        onPressed: _busy ? null : () => _delete(shop),
                      ),
                    ),
                  ),
              ],
            AsyncData() => [const Text('Réservé au super admin.')],
            AsyncError(:final error) => [Text(error is ApiException ? error.message : 'Chargement impossible.', style: theme.textTheme.bodyMedium)],
            _ => [const Center(child: CircularProgressIndicator())],
          },
        ],
      ),
    );
  }
}
