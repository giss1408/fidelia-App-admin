import '../net/api_client.dart';
import '../net/api_exception.dart';

/// A relay message that can still be sent for a number change: the code for the NEW number, the warning for the OLD number, or the
/// notice for the OLD number once the change took effect.
class PhoneRelay {
  const PhoneRelay({required this.id, required this.sent});
  final int id;
  final bool sent;
}

class PhoneChangeItem {
  const PhoneChangeItem({
    required this.id,
    required this.status,
    required this.displayName,
    required this.newPhoneMasked,
    required this.oldPhoneMasked,
    required this.createdAt,
    required this.effectiveAt,
    required this.code,
    required this.alert,
    required this.notice,
  });

  factory PhoneChangeItem.fromJson(Map<String, Object?> j) {
    final relays = (j['relays'] as Map?)?.cast<String, Object?>() ?? const {};
    PhoneRelay? relay(String k) {
      final r = relays[k];
      if (r is! Map) return null;
      return PhoneRelay(id: r['id']! as int, sent: r['status'] == 'sent');
    }

    return PhoneChangeItem(
      id: j['id']! as int,
      status: j['status']! as String,
      displayName: j['display_name'] as String?,
      newPhoneMasked: j['new_phone_masked']! as String,
      oldPhoneMasked: j['old_phone_masked'] as String?,
      createdAt: DateTime.parse(j['created_at']! as String),
      effectiveAt: j['effective_at'] == null ? null : DateTime.parse(j['effective_at']! as String),
      code: relay('code'),
      alert: relay('alert'),
      notice: relay('notice'),
    );
  }

  final int id;

  /// requested (waiting for the code), scheduled (waiting for the security delay), done (a notice is still to send).
  final String status;
  final String? displayName;
  final String newPhoneMasked;
  final String? oldPhoneMasked;
  final DateTime createdAt;
  final DateTime? effectiveAt;
  final PhoneRelay? code;
  final PhoneRelay? alert;
  final PhoneRelay? notice;

  bool get canStop => status == 'requested' || status == 'scheduled';
}

/// Client for the auth service's number-change review (`/v1/admin/phone-changes`, `/v1/admin/relay`): a product's own admins see and act
/// on their product's requests only. Never logs phones or send links (they carry codes).
class PhoneChangesApi {
  PhoneChangesApi(this._client);

  final ApiClient _client;

  Future<List<PhoneChangeItem>> open() async {
    final rows = await _client.getJsonList('/v1/admin/phone-changes', query: {'status': 'open'});
    return [for (final r in rows) PhoneChangeItem.fromJson(r! as Map<String, Object?>)];
  }

  /// A WhatsApp link with the message written (code, warning or notice). Hand it to the launcher, never log it.
  Future<Uri> sendRelay(int relayId) async {
    final json = await _client.postJson('/v1/admin/relay/$relayId/send');
    final url = json['url'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const MalformedResponseException('Réponse inattendue du serveur. Réessayez.');
    }
    return uri;
  }

  /// After a phone call on the OLD number: the change takes effect now. The note (10 characters at least) is kept in the trail.
  Future<void> activateNow(int id, String note) async {
    await _client.postJson('/v1/admin/phone-changes/$id/activate-now', body: {'note': note.trim()});
  }

  /// « Ce n'était pas moi »: cancels the change (or puts the old number back), freezes the account, ends its sessions.
  Future<void> notMe(int id) async {
    await _client.postJson('/v1/admin/phone-changes/$id/not-me');
  }
}

String phoneChangeErrorMessage(ApiException e) {
  if (e is ClientErrorException && e.detail is String) {
    return switch (e.detail! as String) {
      'step_up_required' => 'Entrez à nouveau votre mot de passe et votre code d’authentification.',
      'admin_only' => 'Action réservée aux administrateurs connectés avec leur code d’authentification.',
      'request_closed' => 'Ce message n’est plus d’actualité (changement déjà traité).',
      'nothing_to_activate' || 'nothing_to_cancel' => 'Ce changement est déjà traité.',
      'phone_change_not_found' || 'request_not_found' => 'Demande introuvable.',
      'old_phone_taken' => 'L’ancien numéro a été pris entre-temps : à régler à la main.',
      'phone_taken' => 'Le nouveau numéro a déjà un compte.',
      'product_unavailable' => 'Un service est indisponible. Le compte est quand même gelé ; réessayez dans quelques minutes.',
      'note_required' => 'Notez l’appel (10 caractères au moins).',
      final other => other,
    };
  }
  return e.message;
}
