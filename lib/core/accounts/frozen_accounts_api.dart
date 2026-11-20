import '../net/api_client.dart';
import '../net/api_exception.dart';

class FrozenAccount {
  const FrozenAccount({required this.id, required this.displayName, required this.phoneMasked, required this.reason, required this.since});

  factory FrozenAccount.fromJson(Map<String, Object?> j) => FrozenAccount(
        id: j['id']! as String,
        displayName: j['display_name'] as String?,
        phoneMasked: j['phone_masked'] as String?,
        reason: j['reason'] as String? ?? 'unknown',
        since: j['since'] == null ? null : DateTime.parse(j['since']! as String),
      );

  final String id;
  final String? displayName;
  final String? phoneMasked;

  /// `not_me` (« ce n'était pas moi » on a number change), `disabled` (switched off by an admin) or `unknown`.
  final String reason;
  final DateTime? since;
}

/// One account found by number: enough to be sure it is the right person before switching it off.
class AccountHit {
  const AccountHit({required this.id, required this.displayName, required this.phoneMasked, required this.status, required this.roles});

  factory AccountHit.fromJson(Map<String, Object?> j) => AccountHit(
        id: j['id']! as String,
        displayName: j['display_name'] as String?,
        phoneMasked: j['phone_masked'] as String?,
        status: j['status']! as String,
        roles: [for (final m in (j['memberships'] as List? ?? const [])) '${(m as Map)['product']}:${m['role']}'],
      );

  final String id;
  final String? displayName;
  final String? phoneMasked;

  /// active, disabled, pending_activation...
  final String status;
  final List<String> roles;

  bool get isActive => status == 'active';
}

/// Client for the auth service's frozen accounts (`/v1/admin/frozen-users`, `/v1/admin/users/{id}/enable`). A product's own admins see and
/// give back their product's people only. Never logs phones.
class FrozenAccountsApi {
  FrozenAccountsApi(this._client);

  final ApiClient _client;

  Future<List<FrozenAccount>> list() async {
    final rows = await _client.getJsonList('/v1/admin/frozen-users');
    return [for (final r in rows) FrozenAccount.fromJson(r! as Map<String, Object?>)];
  }

  /// Finds an account of this product by its number. Throws a 404 `user_not_found` for anyone else's.
  Future<AccountHit> search(String phone) async {
    final json = await _client.getJson('/v1/admin/users/search', query: {'phone': phone.replaceAll(RegExp(r'\s+'), '')});
    return AccountHit.fromJson(json);
  }

  /// Switches the account off and ends its sessions. The note (10 characters at least: why, who asked) is kept in the trail.
  Future<void> disable(String id, String note) async {
    await _client.postJson('/v1/admin/users/$id/disable', body: {'note': note.trim()});
  }

  /// After a phone call: the account works again. The note (10 characters at least: who was called, what was checked) is kept in the trail.
  Future<void> enable(String id, String note) async {
    await _client.postJson('/v1/admin/users/$id/enable', body: {'note': note.trim()});
  }
}

String frozenErrorMessage(ApiException e) {
  if (e is ClientErrorException && e.detail is String) {
    return switch (e.detail! as String) {
      'step_up_required' => 'Entrez à nouveau votre mot de passe et votre code d’authentification.',
      'admin_only' => 'Action réservée aux administrateurs connectés avec leur code d’authentification.',
      'note_required' => 'Notez l’appel (10 caractères au moins).',
      'super_admin_only' => 'Seul un super administrateur peut réactiver un compte de l’équipe.',
      'auth_admin_only' => 'Ce compte relève de l’administration de la plateforme.',
      'user_not_found' => 'Aucun compte avec ce numéro.',
      'cannot_disable_self' => 'Vous ne pouvez pas suspendre votre propre compte.',
      'invalid_phone' => 'Numéro invalide.',
      'erased_account' => 'Ce compte a été supprimé : il ne peut pas être réactivé.',
      final other => other,
    };
  }
  return e.message;
}
