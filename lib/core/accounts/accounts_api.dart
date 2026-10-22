import '../net/api_client.dart';
import '../net/api_exception.dart';
import 'models.dart';

/// The request was already sent or refused (HTTP 409), or the account is
/// suspended. Refresh the list instead of retrying.
class AlreadyHandled implements Exception {
  const AlreadyHandled([this.message = 'Cette demande est déjà traitée.']);

  final String message;

  @override
  String toString() => 'AlreadyHandled';
}

/// Client for `/api/admin/accounts`. Never logs phones or send URLs.
class AccountsApi {
  AccountsApi(this._client);

  final ApiClient _client;

  static const _base = '/api/admin/accounts';

  Future<List<AccountCheck>> checks(String kind) async {
    final rows = await _client.getJsonList('$_base/checks', query: {'kind': kind});
    return [for (final row in rows) AccountCheck.fromJson(row! as Map<String, Object?>)];
  }

  /// Marks the check as sent and returns the WhatsApp link to open. The link
  /// carries the code or password: hand it to the launcher, never log it.
  Future<Uri> send(int id) async {
    final json = await _handled(() => _client.postJson('$_base/checks/$id/send'));
    return Uri.parse(json['url']! as String);
  }

  Future<void> refuse(int id) async {
    await _handled(() => _client.postJson('$_base/checks/$id/refuse'));
  }

  /// Looks an account up by phone as typed. Null when none exists.
  Future<AdminUserView?> findUser(String phone) async {
    try {
      final json = await _client.getJson('$_base/users', query: {
        'phone': phone.replaceAll(RegExp(r'\s+'), ''),
        'country_code': 'CI',
      });
      return AdminUserView.fromJson(json);
    } on ClientErrorException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<void> suspend(int userId) async {
    await _client.postJson('$_base/users/$userId/suspend');
  }

  Future<void> restore(int userId) async {
    await _client.postJson('$_base/users/$userId/restore');
  }

  Future<void> signOut(int userId) async {
    await _client.postJson('$_base/users/$userId/sign-out');
  }

  /// Opens a reset_password check; returns its id.
  Future<int> resetPassword(int userId) async {
    final json = await _client.postJson('$_base/users/$userId/reset-password');
    return json['check_id']! as int;
  }

  Future<T> _handled<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ClientErrorException catch (e) {
      if (e.statusCode == 409) throw AlreadyHandled(e.message);
      rethrow;
    }
  }
}
