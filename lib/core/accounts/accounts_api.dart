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
    final url = json['url'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const MalformedResponseException('Réponse inattendue du serveur. Réessayez.');
    }
    return uri;
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
    final id = json['check_id'];
    if (id is! int) {
      throw const MalformedResponseException('Réponse inattendue du serveur. Réessayez.');
    }
    return id;
  }

  /// Deletes the account: the person is erased, shops keep their records
  /// anonymously. A shop owner is refused (409): remove the shop first.
  Future<void> deleteUser(int userId) async {
    await _client.delete('$_base/users/$userId');
  }

  /// Shops matching [query], or null when this admin is not the super admin.
  Future<List<AdminShop>?> shops(String query) async {
    try {
      final rows = await _client.getJsonList('$_base/shops', query: {if (query.trim().isNotEmpty) 'q': query.trim()});
      return [for (final row in rows) AdminShop.fromJson(row! as Map<String, Object?>)];
    } on ClientErrorException catch (e) {
      if (e.statusCode == 403) return null;
      rethrow;
    }
  }

  /// Removes the shop with all its data, and the logins only it needed.
  /// [confirmName] is the shop's name typed again. Returns rows removed.
  Future<int> deleteShop(int shopId, String confirmName) async {
    final json = await _client.deleteJson('$_base/shops/$shopId', body: {'confirm_name': confirmName});
    final deleted = json['deleted'];
    return deleted is Map ? deleted.values.whereType<int>().fold<int>(0, (a, b) => a + b) : 0;
  }

  /// The shared test logins, or null when this admin may not manage them: not
  /// the super admin (403), or a production API, which has none (404).
  Future<List<TestAccount>?> testAccounts() async {
    try {
      final rows = await _client.getJsonList('$_base/test-accounts');
      return [for (final row in rows) TestAccount.fromJson(row! as Map<String, Object?>)];
    } on ClientErrorException catch (e) {
      if (e.statusCode == 403 || e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// One password for every shared test login. Their open sessions end; the
  /// super admin's own login is left alone.
  Future<void> setTestPassword(String password) async {
    await _client.putJson('$_base/test-accounts/password', body: {'password': password});
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
