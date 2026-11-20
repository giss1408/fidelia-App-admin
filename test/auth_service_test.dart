import 'dart:convert';

import 'package:fidelia_admin/core/auth/auth_repository.dart';
import 'package:fidelia_admin/core/auth/token_store.dart';
import 'package:fidelia_admin/core/net/api_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The admin app signing in through the platform auth service (FIDELIA_AUTH_BASE): phone + password + authenticator code at
/// `/v1/login`, and fidelia only ever receives the access token the service issued. Stand-ins for both servers, no network.
String _jwt(Map<String, Object?> claims) {
  String part(Object v) => base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  return '${part({'alg': 'EdDSA'})}.${part(claims)}.sig';
}

final _exp = DateTime.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch ~/ 1000;
String _access({String role = 'admin', bool mcp = false}) => _jwt({'sub': 'u', 'role': role, 'exp': _exp, if (mcp) 'mcp': true});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TokenStore store;
  late List<http.Request> authSent;
  late List<http.Request> fideliaSent;
  late http.Response Function(http.Request) authReply;
  late AuthRepository repo;

  http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    store = TokenStore();
    authSent = [];
    fideliaSent = [];
    authReply = (_) => json({'access_token': _access(), 'refresh_token': 'refresh-1', 'must_change_password': false});
    ApiClient client(List<http.Request> log, http.Response Function(http.Request) reply, String base) => ApiClient(
          inner: MockClient((r) async {
            log.add(r);
            return reply(r);
          }),
          tokenProvider: () async => store.readToken(),
          baseUrl: base,
        );
    repo = AuthRepository(
      client: client(fideliaSent, (_) => json({'detail': 'fidelia must not be called for auth'}, 500), 'https://api.test.invalid'),
      authClient: client(authSent, (r) => authReply(r), 'https://auth.test.invalid'),
      tokenStore: store,
    );
  });

  test('sign-in sends phone, password and the authenticator code to auth with product fidelia and app admin', () async {
    final r = await repo.signIn(phone: '07 01 02 03 04', password: 'pw-secret-1', totp: ' 123456 ');
    expect(r, isA<SignedIn>());
    expect(authSent.single.url.path, '/v1/login');
    expect(jsonDecode(authSent.single.body), {'phone': '0701020304', 'password': 'pw-secret-1', 'product': 'fidelia', 'app': 'admin', 'totp': '123456'});
    expect(await repo.currentUsername(), '07 •• •• 03 04');
    expect(fideliaSent, isEmpty);
  });

  test('a super admin of the auth service is an admin here; a shop or customer token is refused and stores nothing', () async {
    authReply = (_) => json({'access_token': _access(role: 'super_admin'), 'refresh_token': 'r', 'must_change_password': false});
    expect(await repo.signIn(phone: '0701020304', password: 'x', totp: '123456'), isA<SignedIn>());
    await store.clear();
    authReply = (_) => json({'access_token': _access(role: 'merchant'), 'refresh_token': 'r', 'must_change_password': false});
    final r = await repo.signIn(phone: '0701020304', password: 'x', totp: '123456');
    expect(r, isA<SignInRejected>());
    expect(await store.readToken(), isNull);
  });

  test('without a code the field is simply not sent (the server will ask for it)', () async {
    await repo.signIn(phone: '0701020304', password: 'pw-secret-1');
    expect(jsonDecode(authSent.single.body).containsKey('totp'), isFalse);
  });

  test('refusals are explained, including the code', () async {
    final cases = {
      'invalid_credentials': 'Numéro ou mot de passe incorrect.',
      'invalid_totp': 'Code d’authentification incorrect, manquant ou déjà utilisé.',
      'login_locked': 'Trop d’essais. Réessayez dans 15 minutes.',
      'account_blocked': 'Ce compte est suspendu.',
    };
    for (final e in cases.entries) {
      authReply = (_) => json({'detail': e.key}, e.key == 'account_blocked' ? 403 : 401);
      expect(((await repo.signIn(phone: '0701020304', password: 'x', totp: '1')) as SignInRejected).message, e.value);
    }
    authReply = (_) => json({'detail': 'no_access_to_app'}, 403);
    expect(((await repo.signIn(phone: '0701020304', password: 'x')) as SignInRejected).message, contains('pas accès'));
  });

  test('a temporary password: forced change with the password just typed, then a renewed token without the mark', () async {
    authReply = (r) => r.url.path == '/v1/login'
        ? json({'access_token': _access(mcp: true), 'refresh_token': 'refresh-1', 'must_change_password': true})
        : r.url.path == '/v1/password/change'
            ? http.Response('', 204)
            : json({'access_token': _access(), 'refresh_token': 'refresh-2', 'must_change_password': false});
    final r = await repo.signIn(phone: '0701020304', password: 'temp-pass-1', totp: '123456');
    expect((r as SignedIn).mustChangePassword, isTrue);
    await repo.changePassword(newPassword: 'brand-new-pass-1');
    expect(authSent.map((x) => x.url.path), ['/v1/login', '/v1/password/change', '/v1/refresh']);
    expect(jsonDecode(authSent[1].body), {'current_password': 'temp-pass-1', 'new_password': 'brand-new-pass-1'});
    expect(await repo.mustChangePassword(), isFalse);
    expect(await store.readRefreshToken(), 'refresh-2');
    expect(await repo.currentUsername(), '07 •• •• 03 04');
  });

  test('renewal and sign-out use the auth service', () async {
    await repo.signIn(phone: '0701020304', password: 'pw-secret-1', totp: '123456');
    authReply = (_) => json({'access_token': _access(), 'refresh_token': 'refresh-2', 'must_change_password': false});
    expect(await repo.refresh(), isTrue);
    expect(authSent.last.url.path, '/v1/refresh');
    authReply = (_) => http.Response('', 204);
    await repo.signOut();
    expect(authSent.last.url.path, '/v1/logout');
    expect(await store.readToken(), isNull);
    expect(fideliaSent, isEmpty);
  });

  test('step-up proves password AND authenticator code, keeps the fresh token on the same session, and a wrong code changes nothing', () async {
    await repo.signIn(phone: '0701020304', password: 'pw-secret-1', totp: '123456');
    final fresh = _access();
    authReply = (_) => json({'access_token': fresh, 'amr': ['pwd', 'totp']});
    await repo.stepUp(password: 'pw-secret-1', totp: '654321');
    expect(authSent.last.url.path, '/v1/step-up');
    expect(jsonDecode(authSent.last.body), {'password': 'pw-secret-1', 'totp': '654321'});
    expect(await store.readToken(), fresh);
    expect(await store.readRefreshToken(), 'refresh-1');
    authReply = (_) => json({'detail': 'invalid_totp'}, 401);
    await expectLater(repo.stepUp(password: 'pw-secret-1', totp: '000000'), throwsA(isA<AccountActionException>().having((e) => e.message, 'message', contains('suivant'))));
    expect(await store.readToken(), fresh);
  });

  test('without an auth client the repository is exactly the legacy one', () async {
    final legacy = AuthRepository(
      client: ApiClient(
        inner: MockClient((r) async {
          fideliaSent.add(r);
          return json({'access_token': _access(), 'refresh_token': 'r', 'phone_masked': '+225 ** ** 12'});
        }),
        tokenProvider: () async => null,
        baseUrl: 'https://api.test.invalid',
      ),
      tokenStore: store,
    );
    expect(legacy.authMode, isFalse);
    await legacy.signIn(phone: '0701020304', password: 'pw');
    expect(fideliaSent.single.url.path, '/api/auth/login');
  });
}
