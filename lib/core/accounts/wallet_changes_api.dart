import '../net/api_client.dart';
import '../net/api_exception.dart';
import 'models.dart';

/// One step of a wallet change's trail. The actor is already masked by the server; nothing here holds a code or a full number.
class WalletEvent {
  const WalletEvent({required this.at, required this.actor, required this.action, this.detail});

  factory WalletEvent.fromJson(Map<String, Object?> json) => WalletEvent(
        at: parseServerTime(json['at']! as String),
        actor: json['actor_masked'] as String? ?? '',
        action: json['action']! as String,
        detail: json['detail'] as String?,
      );

  final DateTime at;
  final String actor;
  final String action;
  final String? detail;
}

/// A merchant's request to change where the shop's customer payments are paid out (`GET /api/admin/wallet-changes`).
class WalletChangeItem {
  const WalletChangeItem({
    required this.id,
    required this.status,
    required this.shop,
    required this.provider,
    required this.newAccountMasked,
    required this.currentAccountMasked,
    required this.merchantPhoneMasked,
    required this.requestedAt,
    required this.codeSent,
    required this.activatesAt,
    required this.callNote,
    required this.events,
  });

  factory WalletChangeItem.fromJson(Map<String, Object?> json) => WalletChangeItem(
        id: json['id']! as int,
        status: json['status']! as String,
        shop: json['shop']! as String,
        provider: json['provider']! as String,
        newAccountMasked: json['account_masked']! as String,
        currentAccountMasked: json['current_account_masked'] as String?,
        merchantPhoneMasked: json['merchant_phone_masked'] as String?,
        requestedAt: parseServerTime(json['requested_at']! as String),
        codeSent: json['code_sent'] == true,
        activatesAt: json['activates_at'] is String ? parseServerTime(json['activates_at']! as String) : null,
        callNote: json['call_note'] as String?,
        events: [for (final e in (json['events'] as List? ?? const [])) WalletEvent.fromJson((e! as Map).cast<String, Object?>())],
      );

  final int id;

  /// pending_confirmation | confirmed_waiting | frozen | active | rejected | cancelled
  final String status;
  final String shop;
  final String provider;
  final String newAccountMasked;
  final String? currentAccountMasked;
  final String? merchantPhoneMasked;
  final DateTime requestedAt;
  final bool codeSent;
  final DateTime? activatesAt;
  final String? callNote;
  final List<WalletEvent> events;

  bool get isFrozen => status == 'frozen';
  bool get isOpen => status == 'pending_confirmation' || status == 'confirmed_waiting' || status == 'frozen';
}

/// Client for `/api/admin/wallet-changes`. Needs an admin signed in through the auth service with a recent authenticator code:
/// the server answers 403 `auth_login_required` / `step_up_required` otherwise. Never logs phones or send URLs.
class WalletChangesApi {
  WalletChangesApi(this._client);

  final ApiClient _client;

  static const _base = '/api/admin/wallet-changes';

  Future<List<WalletChangeItem>> open() async {
    final rows = await _client.getJsonList(_base, query: {'status': 'open'});
    return [for (final r in rows) WalletChangeItem.fromJson(r! as Map<String, Object?>)];
  }

  /// A new code, and the WhatsApp link to the MERCHANT'S login number with the message written. The link carries the code:
  /// hand it to the launcher, never log it.
  Future<Uri> sendCode(int id) async {
    final json = await _client.postJson('$_base/$id/send-code');
    final url = json['url'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const MalformedResponseException('Réponse inattendue du serveur. Réessayez.');
    }
    return uri;
  }

  /// After a phone call: the new wallet starts now. The written note is mandatory (10 characters at least) and is kept in the trail.
  Future<void> activateNow(int id, String callNote) async {
    await _client.postJson('$_base/$id/activate-now', body: {'call_note': callNote.trim()});
  }

  Future<void> reject(int id, {String? reason}) async {
    await _client.postJson('$_base/$id/reject', body: {'reason': (reason ?? '').trim().isEmpty ? null : reason!.trim()});
  }
}

/// What a refusal means for the admin, in words.
String walletChangeErrorMessage(ApiException e) {
  if (e is ClientErrorException && e.detail is String) {
    return switch (e.detail! as String) {
      'auth_login_required' => 'Cette action demande une connexion avec mot de passe et code d’authentification.',
      'step_up_required' => 'Entrez à nouveau votre code d’authentification pour continuer.',
      'frozen_review' => 'Changement gelé (« ce n’était pas moi ») : appelez le commerçant, puis rejetez ou laissez-le refaire une demande.',
      'call_note_required' => 'Notez l’appel (10 caractères au moins).',
      'change_closed' => 'Cette demande est déjà traitée.',
      'shop_has_no_merchant' => 'Ce commerce n’a pas de commerçant relié.',
      'sso_session_ended' => 'Votre session a été fermée. Reconnectez-vous.',
      'sso_unavailable' => 'Service momentanément indisponible. Réessayez plus tard.',
      final other => other,
    };
  }
  return e.message;
}
