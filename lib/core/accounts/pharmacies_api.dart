import '../net/api_client.dart';

/// Abidjan time is UTC. The server stores duties without a zone, so the app
/// reads and sends them as UTC, whatever zone the admin's phone is in.
DateTime _abidjan(String value) => DateTime.parse(value.endsWith('Z') || value.contains('+') ? value : '${value}Z').toUtc();

/// One on-duty ("de garde") period.
class PharmacyDuty {
  const PharmacyDuty({required this.id, required this.startsAt, required this.endsAt});

  factory PharmacyDuty.fromJson(Map<String, Object?> json) => PharmacyDuty(
        id: json['id']! as int,
        startsAt: _abidjan(json['starts_at']! as String),
        endsAt: _abidjan(json['ends_at']! as String),
      );

  final int id;
  final DateTime startsAt;
  final DateTime endsAt;
}

/// A pharmacy with its duties that have not ended yet.
class AdminPharmacy {
  const AdminPharmacy({required this.id, required this.name, required this.commune, this.address, this.duties = const []});

  factory AdminPharmacy.fromJson(Map<String, Object?> json) => AdminPharmacy(
        id: json['id']! as int,
        name: json['name']! as String,
        commune: json['commune']! as String,
        address: json['address'] as String?,
        duties: [for (final d in json['duties']! as List<Object?>) PharmacyDuty.fromJson(d! as Map<String, Object?>)],
      );

  final int id;
  final String name;
  final String commune;
  final String? address;
  final List<PharmacyDuty> duties;
}

/// Client for the weekly on-duty rotation, entered from the official list.
class PharmaciesApi {
  PharmaciesApi(this._client);

  final ApiClient _client;

  Future<List<AdminPharmacy>> pharmacies({String? commune}) async {
    final rows = await _client.getJsonList('/api/admin/pharmacies', query: {
      if (commune != null && commune.trim().isNotEmpty) 'commune': commune.trim(),
    });
    return [for (final row in rows) AdminPharmacy.fromJson(row! as Map<String, Object?>)];
  }

  /// [startsAt] and [endsAt] are UTC (Abidjan time).
  Future<void> addDuty(int pharmacyId, DateTime startsAt, DateTime endsAt) async {
    await _client.postJson('/api/admin/pharmacies/$pharmacyId/duties', body: {
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
    });
  }

  Future<void> deleteDuty(int dutyId) async {
    await _client.delete('/api/admin/duties/$dutyId');
  }
}
