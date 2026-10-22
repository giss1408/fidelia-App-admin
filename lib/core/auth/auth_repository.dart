import 'dart:async';

import '../net/api_client.dart';
import '../net/api_exception.dart';
import 'token_store.dart';

/// An account action failed; [message] is the server's French sentence, ready
/// to show.
class AccountActionException implements Exception {
  const AccountActionException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Outcome of a sign-in attempt, as something the UI can render directly.
sealed class SignInResult {
  const SignInResult();
}

class SignedIn extends SignInResult {
  const SignedIn({required this.mustChangePassword});

  /// The account signed in with a temporary password and must choose its own
  /// before anything else.
  final bool mustChangePassword;
}

/// The server said no: wrong credentials, locked, suspended, no password yet.
class SignInRejected extends SignInResult {
  const SignInRejected(this.message);
  final String message;
}

/// The server could not be reached, or it failed. Retrying may work.
class SignInUnavailable extends SignInResult {
  const SignInUnavailable(this.message);
  final String message;
}

/// Sign-in with phone number + password, session renewal, sign-out.
///
/// Only an `admin` session is accepted; any other role is treated as no
/// session at all.
class AuthRepository {
  AuthRepository({required ApiClient client, required TokenStore tokenStore})
      : _client = client,
        _tokenStore = tokenStore;

  static const appRole = 'admin';
  static const _unusable = 'La réponse du serveur est inutilisable';
  static const _notAdmin = "Ce compte n'a pas accès à Fidelia Admin.";
  static const _noPassword =
      "Ce compte n'a pas encore de mot de passe. Demandez-en un à l'équipe Fidelia.";

  final ApiClient _client;
  final TokenStore _tokenStore;

  /// The refresh in flight, shared by every caller. Refresh tokens are single
  /// use and the server treats a second use as theft, so two concurrent
  /// refreshes with the same token would sign the user out.
  Completer<bool>? _refreshing;

  /// Whether this device holds an admin session: a live access token, or a
  /// refresh token that can mint one. A session of another role is wiped.
  Future<bool> hasValidSession() async {
    final token = await _tokenStore.readToken();
    if (token != null && token.isNotEmpty && jwtRole(token) != appRole) {
      await _tokenStore.clear();
      return false;
    }
    if (token != null && token.isNotEmpty && !isTokenExpired(token)) return true;
    final refresh = await _tokenStore.readRefreshToken();
    if (refresh != null && refresh.isNotEmpty) return true;
    await _tokenStore.clear();
    return false;
  }

  Future<String?> currentUsername() => _tokenStore.readUsername();

  /// Whether the stored access token carries the `pc` claim.
  Future<bool> mustChangePassword() async {
    final token = await _tokenStore.readToken();
    return token != null && token.isNotEmpty && jwtMustChangePassword(token);
  }

  /// [phone] may be typed in national form ("07 01 02 03 04"); spaces are
  /// dropped and the server normalises the rest.
  Future<SignInResult> signIn({required String phone, required String password}) async {
    try {
      final body = await _client.postJson(
        '/api/auth/login',
        body: {
          'phone': phone.replaceAll(RegExp(r'\s+'), ''),
          'country_code': 'CI',
          'password': password,
          'app': appRole,
        },
        authenticated: false,
      );
      final token = body['access_token'];
      if (token is String && token.isNotEmpty && jwtRole(token) != appRole) {
        return const SignInRejected(_notAdmin);
      }
      if (!await _store(body)) return const SignInUnavailable(_unusable);
      return SignedIn(mustChangePassword: await mustChangePassword());
    } on ClientErrorException catch (error) {
      if (error.statusCode == 409 && error.detail == 'password_not_set') {
        return const SignInRejected(_noPassword);
      }
      return SignInRejected(error.message);
    } on ApiException catch (error) {
      return SignInUnavailable(error.message);
    }
  }

  /// Renews the access token. True when a new one is stored; false when the
  /// server refused the refresh token (the session is over). Throws
  /// [NetworkException] or [ServerErrorException] when the server could not
  /// say, so being offline never signs anyone out.
  Future<bool> refresh() {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight.future;
    final completer = _refreshing = Completer<bool>();
    _doRefresh().then(completer.complete, onError: completer.completeError).whenComplete(() => _refreshing = null);
    return completer.future;
  }

  Future<bool> _doRefresh() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final body = await _client.postJson(
        '/api/auth/refresh',
        body: {'refresh_token': refreshToken},
        authenticated: false,
      );
      final access = body['access_token'];
      if (access is String && jwtRole(access) != appRole) {
        await _tokenStore.clear();
        return false;
      }
      return _store(body);
    } on ClientErrorException {
      return false;
    }
  }

  Future<bool> _store(Map<String, Object?> body) async {
    final access = body['access_token'];
    final refresh = body['refresh_token'];
    if (access is! String || access.isEmpty || refresh is! String || refresh.isEmpty) return false;
    await _tokenStore.save(
      token: access,
      refreshToken: refresh,
      username: body['phone_masked'] as String? ?? '',
    );
    return true;
  }

  /// Sets a new password. [current] is omitted right after signing in with a
  /// temporary password. On success the server's new token pair replaces the
  /// stored one, which no longer carries the `pc` claim.
  Future<void> changePassword({String? current, required String newPassword}) async {
    try {
      final body = await _client.postJson(
        '/api/auth/password',
        body: {if (current != null) 'current': current, 'new': newPassword},
        // A wrong current password is a 401 that must not end the session.
        unauthorizedEndsSession: false,
      );
      if (!await _store(body)) throw const AccountActionException(_unusable);
    } on ClientErrorException catch (error) {
      throw AccountActionException(error.message);
    } on ApiException catch (error) {
      throw AccountActionException(error.message);
    }
  }

  /// Ends the session: revoked on the server when reachable, always wiped
  /// here.
  Future<void> signOut() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await _client.postJson('/api/auth/logout', body: {'refresh_token': refreshToken}, authenticated: false);
      } on ApiException {
        // Best effort; the local wipe below is what matters on this device.
      }
    }
    await _tokenStore.clear();
  }
}
