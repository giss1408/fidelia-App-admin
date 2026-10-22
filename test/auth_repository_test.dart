import 'dart:convert';

import 'package:fidelia_admin/core/auth/auth_repository.dart';
import 'package:fidelia_admin/core/auth/token_store.dart';
import 'package:fidelia_admin/core/net/api_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String jwt({String role = 'admin', bool pc = false, Duration life = const Duration(hours: 1)}) {
  String enc(Map<String, Object?> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final exp = DateTime.now().add(life).millisecondsSinceEpoch ~/ 1000;
  return '${enc({'alg': 'none'})}.${enc({'role': role, 'exp': exp, if (pc) 'pc': true})}.sig';
}

http.Response json(int status, Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

Map<String, Object?> pair({String role = 'admin', bool pc = false, String refresh = 'r1', Duration life = const Duration(hours: 1)}) => {
      'access_token': jwt(role: role, pc: pc, life: life),
      'refresh_token': refresh,
      'token_type': 'bearer',
      'expires_in': 3600,
      'role': role,
      'phone_masked': '07 •• •• 03 04',
      'verified': true,
      'must_change_password': pc,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TokenStore store;
  late List<http.Request> seen;
  late AuthRepository repo;
  late ApiClient client;
  late int unauthorized;

  void setup(Future<http.Response> Function(http.Request) handler) {
    FlutterSecureStorage.setMockInitialValues({});
    store = TokenStore();
    seen = [];
    unauthorized = 0;
    late AuthRepository r;
    client = ApiClient(
      baseUrl: 'http://test',
      inner: MockClient((req) async {
        seen.add(req);
        return handler(req);
      }),
      tokenProvider: () => store.readToken(),
      onRefresh: () => r.refresh(),
      onUnauthorized: () async {
        unauthorized++;
        await store.clear();
      },
    );
    r = repo = AuthRepository(client: client, tokenStore: store);
  }

  test('signs in an admin', () async {
    setup((_) async => json(200, pair()));
    final result = await repo.signIn(phone: '07 01 02 03 04', password: 'secret');
    expect(result, isA<SignedIn>());
    expect((result as SignedIn).mustChangePassword, isFalse);
    final body = jsonDecode(seen.single.body) as Map;
    expect(body, {'phone': '0701020304', 'country_code': 'CI', 'password': 'secret', 'app': 'admin'});
    expect(seen.single.url.path, '/api/auth/login');
    expect(await repo.hasValidSession(), isTrue);
    expect(await store.readRefreshToken(), 'r1');
  });

  test('wrong password shows the server message', () async {
    setup((_) async => json(401, {'detail': 'Numéro ou mot de passe incorrect.'}));
    final result = await repo.signIn(phone: '0701020304', password: 'x');
    expect(result, isA<SignInRejected>());
    expect((result as SignInRejected).message, 'Numéro ou mot de passe incorrect.');
    expect(await store.readToken(), isNull);
    expect(unauthorized, 0);
  });

  test('password_not_set has its own message', () async {
    setup((_) async => json(409, {'detail': 'password_not_set'}));
    final result = await repo.signIn(phone: '0701020304', password: 'x');
    expect((result as SignInRejected).message,
        "Ce compte n'a pas encore de mot de passe. Demandez-en un à l'équipe Fidelia.");
  });

  test('locked account (423) shows the server message', () async {
    setup((_) async => json(423, {'detail': 'Compte verrouillé. Réessayez plus tard.'}));
    final result = await repo.signIn(phone: '0701020304', password: 'x');
    expect((result as SignInRejected).message, 'Compte verrouillé. Réessayez plus tard.');
  });

  test('no network is unavailable, not rejected', () async {
    setup((_) async => throw http.ClientException('offline'));
    expect(await repo.signIn(phone: '0701020304', password: 'x'), isA<SignInUnavailable>());
    setup((_) async => json(503, {'detail': 'x'}));
    expect(await repo.signIn(phone: '0701020304', password: 'x'), isA<SignInUnavailable>());
  });

  test('a non-admin session is refused and not stored', () async {
    setup((_) async => json(200, pair(role: 'merchant')));
    expect(await repo.signIn(phone: '0701020304', password: 'x'), isA<SignInRejected>());
    expect(await store.readToken(), isNull);
  });

  test('a stored non-admin session counts as no session', () async {
    setup((_) async => json(204, {}));
    await store.save(token: jwt(role: 'merchant'), refreshToken: 'r', username: 'u');
    expect(await repo.hasValidSession(), isFalse);
    expect(await store.readToken(), isNull);
  });

  test('temporary password session must change it', () async {
    setup((_) async => json(200, pair(pc: true)));
    final result = await repo.signIn(phone: '0701020304', password: 'temp');
    expect((result as SignedIn).mustChangePassword, isTrue);
    expect(await repo.mustChangePassword(), isTrue);
  });

  test('change password stores the new pair and clears the flag', () async {
    setup((req) async => json(200, pair(refresh: 'r2')));
    await store.save(token: jwt(pc: true), refreshToken: 'r1', username: 'u');
    expect(await repo.mustChangePassword(), isTrue);
    await repo.changePassword(newPassword: 'nouveau-mot-de-passe');
    expect(seen.single.url.path, '/api/auth/password');
    expect(jsonDecode(seen.single.body), {'new': 'nouveau-mot-de-passe'});
    expect(seen.single.headers['Authorization'], startsWith('Bearer '));
    expect(await repo.mustChangePassword(), isFalse);
    expect(await store.readRefreshToken(), 'r2');
  });

  test('change password surfaces the server message and keeps the session', () async {
    setup((_) async => json(401, {'detail': 'Mot de passe actuel incorrect.'}));
    await store.save(token: jwt(), refreshToken: 'r1', username: 'u');
    await expectLater(
      repo.changePassword(current: 'bad', newPassword: 'new-password-1'),
      throwsA(isA<AccountActionException>().having((e) => e.message, 'message', 'Mot de passe actuel incorrect.')),
    );
    expect(seen, hasLength(1), reason: 'a wrong current password must not trigger a refresh');
    expect(unauthorized, 0);
    expect(await store.readToken(), isNotNull);
  });

  test('expired token refreshes once then retries', () async {
    var meCalls = 0;
    setup((req) async {
      if (req.url.path == '/api/auth/refresh') return json(200, pair(refresh: 'r2'));
      meCalls++;
      return meCalls == 1 ? json(401, {'detail': 'expired'}) : json(200, {'sub': 'x'});
    });
    await store.save(token: jwt(), refreshToken: 'r1', username: 'u');
    final me = await client.getJson('/api/auth/me');
    expect(me['sub'], 'x');
    expect(seen.where((r) => r.url.path == '/api/auth/refresh'), hasLength(1));
    expect(meCalls, 2);
    expect(await store.readRefreshToken(), 'r2');
  });

  test('concurrent refreshes share one request', () async {
    setup((req) async => json(200, pair(refresh: 'r2')));
    await store.save(token: jwt(), refreshToken: 'r1', username: 'u');
    final results = await Future.wait([repo.refresh(), repo.refresh()]);
    expect(results, [true, true]);
    expect(seen, hasLength(1));
  });

  test('refused refresh signs out', () async {
    setup((req) async => req.url.path == '/api/auth/refresh' ? json(401, {'detail': 'invalid'}) : json(401, {'detail': 'expired'}));
    await store.save(token: jwt(), refreshToken: 'r1', username: 'u');
    await expectLater(client.getJson('/api/auth/me'), throwsA(anything));
    expect(unauthorized, 1);
    expect(await store.readToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
    expect(await repo.hasValidSession(), isFalse);
  });

  test('sign out revokes the refresh token and wipes the store', () async {
    setup((_) async => json(204, {}));
    await store.save(token: jwt(), refreshToken: 'r1', username: 'u');
    await repo.signOut();
    expect(seen.single.url.path, '/api/auth/logout');
    expect(jsonDecode(seen.single.body), {'refresh_token': 'r1'});
    expect(await store.readToken(), isNull);
  });
}
