import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/accounts/pharmacies_api.dart';
import '../core/net/api_exception.dart';
import '../core/providers.dart';
import '../ui/theme.dart';

final pharmaciesApiProvider = Provider<PharmaciesApi>((ref) => PharmaciesApi(ref.watch(apiClientProvider)));

final pharmaciesProvider = FutureProvider.autoDispose.family<List<AdminPharmacy>, String>(
  (ref, commune) => ref.watch(pharmaciesApiProvider).pharmacies(commune: commune),
);

const _days = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'];
String _two(int n) => n.toString().padLeft(2, '0');

/// « sam 05/01 08:00 », in Abidjan time (UTC).
String dutyMoment(DateTime t) {
  final u = t.toUtc();
  return '${_days[u.weekday - 1]} ${_two(u.day)}/${_two(u.month)} ${_two(u.hour)}:${_two(u.minute)}';
}

/// « Gardes »: the pharmacies and their on-duty periods. The admin copies the
/// official weekly rotation in; customers see it in « Pharmacies de garde ».
class DutiesScreen extends ConsumerStatefulWidget {
  const DutiesScreen({super.key});

  @override
  ConsumerState<DutiesScreen> createState() => _DutiesScreenState();
}

class _DutiesScreenState extends ConsumerState<DutiesScreen> {
  final _search = TextEditingController();
  String _commune = '';
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

  Future<void> _run(Future<void> Function() call, String done) async {
    setState(() => _busy = true);
    try {
      await call();
      ref.invalidate(pharmaciesProvider);
      _say(done);
    } on ApiException catch (e) {
      _say(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Dates, then the hour the duty changes (08:00 by default). The end is
  /// the same hour on the last day.
  Future<void> _add(AdminPharmacy pharmacy) async {
    final today = DateTime.now().toUtc();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: DateTime(today.year + 1, today.month, today.day),
      initialDateRange: DateTimeRange(
        start: DateTime(today.year, today.month, today.day),
        end: DateTime(today.year, today.month, today.day + 7),
      ),
      helpText: 'Garde de ${pharmacy.name}',
      saveText: 'Suivant',
    );
    if (range == null || !mounted) return;
    final hour = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
      helpText: 'Heure de relève (heure d’Abidjan)',
    );
    if (hour == null || !mounted) return;
    final start = DateTime.utc(range.start.year, range.start.month, range.start.day, hour.hour, hour.minute);
    final end = DateTime.utc(range.end.year, range.end.month, range.end.day, hour.hour, hour.minute);
    if (!end.isAfter(start)) {
      _say('La fin doit être après le début.');
      return;
    }
    await _run(() => ref.read(pharmaciesApiProvider).addDuty(pharmacy.id, start, end), 'Garde ajoutée');
  }

  Future<void> _delete(AdminPharmacy pharmacy, PharmacyDuty duty) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retirer cette garde ?'),
        content: Text('${pharmacy.name}\ndu ${dutyMoment(duty.startsAt)} au ${dutyMoment(duty.endsAt)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: FideliaColors.danger),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() => ref.read(pharmaciesApiProvider).deleteDuty(duty.id), 'Garde retirée');
  }

  @override
  Widget build(BuildContext context) {
    final pharmacies = ref.watch(pharmaciesProvider(_commune));
    final theme = Theme.of(context);
    final now = DateTime.now().toUtc();
    return Scaffold(
      appBar: AppBar(title: const Text('Pharmacies de garde')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(pharmaciesProvider(_commune).future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (value) => setState(() => _commune = value.trim()),
              decoration: const InputDecoration(labelText: 'Commune', prefixIcon: Icon(Icons.search)),
            ),
            const SizedBox(height: 8),
            Text('Heures d’Abidjan.', style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            ...switch (pharmacies) {
              AsyncData(:final value) when value.isEmpty => [const Center(child: Text('Aucune pharmacie'))],
              AsyncData(:final value) => [
                  for (final pharmacy in value)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(pharmacy.name, style: theme.textTheme.titleMedium),
                            Text([pharmacy.commune, if (pharmacy.address != null) pharmacy.address!].join(' · '),
                                style: theme.textTheme.bodySmall),
                            for (final duty in pharmacy.duties)
                              Row(
                                children: [
                                  Icon(
                                    Icons.local_pharmacy_outlined,
                                    size: 18,
                                    color: duty.startsAt.isAfter(now) ? FideliaColors.muted : FideliaColors.orangeDeep,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text('${dutyMoment(duty.startsAt)} → ${dutyMoment(duty.endsAt)}')),
                                  IconButton(
                                    tooltip: 'Retirer cette garde',
                                    icon: const Icon(Icons.delete_outline, color: FideliaColors.danger),
                                    onPressed: _busy ? null : () => _delete(pharmacy, duty),
                                  ),
                                ],
                              ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: _busy ? null : () => _add(pharmacy),
                                icon: const Icon(Icons.add),
                                label: const Text('Ajouter une garde'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              AsyncError(:final error) => [Text(error is ApiException ? error.message : 'Chargement impossible. Tirez pour réessayer.')],
              _ => [const Center(child: CircularProgressIndicator())],
            },
          ],
        ),
      ),
    );
  }
}
