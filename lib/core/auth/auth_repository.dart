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
  AuthRepository({required ApiClient client, required TokenStore tokenStore, ApiClient? authClient})
      : _client = client,
        _tokenStore = tokenStore,
        _auth = authClient;

  /// Talks to the platform auth service (SSO) when set: sign-in (with the authenticator code), renewal, sign-out, password change and
  /// step-up go there; fidelia only receives the access token the service issued. Null = fidelia's own sign-in.
  final ApiClient? _auth;

  bool get authMode => _auth != null;

  /// The temporary password just typed, in memory only, so the forced "new password" step can send it as the current one.
  String? _signInPassword;

  /// `admin`, or `super_admin` (the auth service's name for the founder role: fidelia treats it as an admin).
  static bool isAdminRole(String role) => role == appRole || role == 'super_admin';

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
    if (token != null && token.isNotEmpty && !isAdminRole(jwtRole(token))) {
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
  Future<SignInResult> signIn({required String phone, required String password, String? totp}) async {
    if (_auth != null) return _authSignIn(phone, password, totp);
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
      if (token is String && token.isNotEmpty && !isAdminRole(jwtRole(token))) {
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
      final body = await (_auth ?? _client).postJson(
        _auth != null ? '/v1/refresh' : '/api/auth/refresh',
        body: {'refresh_token': refreshToken},
        authenticated: false,
      );
      final access = body['access_token'];
      if (access is String && !isAdminRole(jwtRole(access))) {
        await _tokenStore.clear();
        return false;
      }
      return _store(body, username: await currentUsername());
    } on ClientErrorException {
      return false;
    }
  }

  Future<SignInResult> _authSignIn(String phone, String password, String? totp) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    try {
      final body = await _auth!.postJson(
        '/v1/login',
        body: {
          'phone': phone.replaceAll(RegExp(r'\s+'), ''),
          'password': password,
          'product': 'fidelia',
          'app': appRole,
          if (totp != null && totp.trim().isNotEmpty) 'totp': totp.trim(),
        },
        authenticated: false,
      );
      final token = body['access_token'];
      if (token is String && token.isNotEmpty && !isAdminRole(jwtRole(token))) return const SignInRejected(_notAdmin);
      if (!await _store(body, username: maskPhone(digits))) return const SignInUnavailable(_unusable);
      _signInPassword = body['must_change_password'] == true ? password : null;
      return SignedIn(mustChangePassword: await mustChangePassword());
    } on ClientErrorException catch (error) {
      return SignInRejected(switch (error.detail) {
        'invalid_credentials' => 'Numéro ou mot de passe incorrect.',
        'invalid_totp' => 'Code d’authentification incorrect, manquant ou déjà utilisé.',
        'totp_not_set_up' => 'Ce compte n’a pas encore d’application d’authentification : voir un super administrateur.',
        'not_activated' => "Ce compte n'est pas encore activé.",
        'account_blocked' => 'Ce compte est suspendu.',
        'no_access_to_app' => _notAdmin,
        'login_locked' => 'Trop d’essais. Réessayez dans 15 minutes.',
        'temp_password_expired' => 'Le mot de passe temporaire a expiré : demandez-en un nouveau à un super administrateur.',
        'rate_limited' => 'Trop de tentatives. Réessayez dans quelques minutes.',
        final String other => other,
        _ => error.message,
      });
    } on ApiException catch (error) {
      return SignInUnavailable(error.message);
    }
  }

  /// "07 •• •• 03 04" from the digits typed.
  static String maskPhone(String digits) {
    final d = digits.length > 10 ? digits.substring(digits.length - 10) : digits;
    return d.length < 10 ? '•• •• ••' : '${d.substring(0, 2)} •• •• ${d.substring(6, 8)} ${d.substring(8, 10)}';
  }

  /// Re-proves password AND authenticator code at the auth service and keeps the fresh access token it returns (same session, fresh
  /// proof). Fidelia's admin actions (roles, suspensions, wallet changes) ask for this within 5 minutes.
  Future<void> stepUp({required String password, required String totp}) async {
    final auth = _auth;
    if (auth == null) throw const AccountActionException('Connexion par mot de passe requise.');
    try {
      final body = await auth.postJson('/v1/step-up', body: {'password': password, 'totp': totp.trim()}, unauthorizedEndsSession: false);
      final access = body['access_token'];
      final refresh = await _tokenStore.readRefreshToken();
      if (access is! String || access.isEmpty || refresh == null) throw const AccountActionException(_unusable);
      await _tokenStore.save(token: access, refreshToken: refresh, username: await currentUsername() ?? '');
    } on ClientErrorException catch (error) {
      throw AccountActionException(switch (error.detail) {
        'invalid_credentials' => 'Mot de passe incorrect.',
        'invalid_totp' => 'Code d’authentification incorrect ou déjà utilisé : attendez le code suivant.',
        'login_locked' => 'Trop d’essais. Réessayez dans 15 minutes.',
        _ => error.message,
      });
    } on ApiException catch (error) {
      throw AccountActionException(error.message);
    }
  }

  Future<bool> _store(Map<String, Object?> body, {String? username}) async {
    final access = body['access_token'];
    final refresh = body['refresh_token'];
    if (access is! String || access.isEmpty || refresh is! String || refresh.isEmpty) return false;
    await _tokenStore.save(
      token: access,
      refreshToken: refresh,
      username: body['phone_masked'] as String? ?? username ?? '',
    );
    return true;
  }

  /// Sets a new password. [current] is omitted right after signing in with a
  /// temporary password. On success the server's new token pair replaces the
  /// stored one, which no longer carries the `pc` claim.
  Future<void> changePassword({String? current, required String newPassword}) async {
    final auth = _auth;
    if (auth != null) {
      final currentPassword = current ?? _signInPassword;
      if (currentPassword == null) throw const AccountActionException('Saisissez votre mot de passe actuel.');
      try {
        await auth.postJson('/v1/password/change', body: {'current_password': currentPassword, 'new_password': newPassword}, unauthorizedEndsSession: false);
      } on ClientErrorException catch (error) {
        throw AccountActionException(error.detail == 'invalid_credentials' ? 'Mot de passe actuel incorrect.' : error.message);
      } on ApiException catch (error) {
        throw AccountActionException(error.message);
      }
      _signInPassword = null;
      // Nothing to store from the change itself: renew, which issues a token without the "must change" mark.
      if (!await refresh()) throw const AccountActionException(_unusable);
      return;
    }
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
    _signInPassword = null;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await (_auth ?? _client).postJson(_auth != null ? '/v1/logout' : '/api/auth/logout', body: {'refresh_token': refreshToken}, authenticated: false);
      } on ApiException {
        // Best effort; the local wipe below is what matters on this device.
      }
    }
    await _tokenStore.clear();
  }
}
