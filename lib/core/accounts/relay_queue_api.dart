import '../net/api_client.dart';
import '../net/api_exception.dart';

/// A WhatsApp message the team has to send from its own phone: the activation code of a new sign-up, or a temporary password for
/// someone who forgot hers.
class RelayItem {
  const RelayItem({required this.id, required this.purpose, required this.status, required this.displayName, required this.phoneMasked, required this.createdAt});

  factory RelayItem.fromJson(Map<String, Object?> j) => RelayItem(
        id: j['id']! as int,
        purpose: j['purpose']! as String,
        status: j['status']! as String,
        displayName: j['display_name'] as String?,
        phoneMasked: j['phone_masked'] as String?,
        createdAt: DateTime.parse(j['created_at']! as String),
      );

  final int id;

  /// `activation` or `password_reset` (the number-change messages have their own screen).
  final String purpose;

  /// `open` (to send) or `sent` (sent once, the person has not typed it yet: it can be sent again).
  final String status;
  final String? displayName;
  final String? phoneMasked;
  final DateTime createdAt;

  bool get isActivation => purpose == 'activation';
  bool get sent => status == 'sent';
}

/// Client for the auth service's relay queue (`/v1/admin/relay-queue`, `/v1/admin/relay/{id}/send|reject`): a product's own admins see
/// and send their product's messages only. Never logs phones or links (they carry codes and passwords).
class RelayQueueApi {
  RelayQueueApi(this._client);

  final ApiClient _client;

  static const purposes = {'activation', 'password_reset'};

  Future<List<RelayItem>> pending() async {
    final rows = await _client.getJsonList('/v1/admin/relay-queue', query: {'status': 'pending'});
    return [
      for (final r in rows)
        if (purposes.contains((r! as Map)['purpose'])) RelayItem.fromJson(r as Map<String, Object?>),
    ];
  }

  /// A NEW code (or temporary password) and the WhatsApp link with the message written. Hand it to the launcher, never log it.
  Future<Uri> send(int id) async {
    final json = await _client.postJson('/v1/admin/relay/$id/send');
    final url = json['url'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const MalformedResponseException('Réponse inattendue du serveur. Réessayez.');
    }
    return uri;
  }

  /// The number is not on WhatsApp, or wrong: release it so the person can sign up again with the right one (activation only).
  Future<void> reject(int id) async {
    await _client.postJson('/v1/admin/relay/$id/reject');
  }
}

String relayErrorMessage(ApiException e) {
  if (e is ClientErrorException && e.detail is String) {
    return switch (e.detail! as String) {
      'step_up_required' => 'Entrez à nouveau votre mot de passe et votre code d’authentification.',
      'admin_only' => 'Action réservée aux administrateurs connectés avec leur code d’authentification.',
      'request_closed' || 'already_active' || 'not_active' => 'Cette demande est déjà traitée.',
      'request_not_found' => 'Demande introuvable.',
      'relay_not_allowed_for_privileged' => 'Les comptes de l’équipe ne passent pas par WhatsApp : voir un super administrateur.',
      'cannot_reject' => 'Cette demande ne peut pas être refusée.',
      final other => other,
    };
  }
  return e.message;
}
