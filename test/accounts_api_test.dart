import 'dart:convert';

import 'package:fidelia_admin/core/accounts/accounts_api.dart';
import 'package:fidelia_admin/core/net/api_client.dart';
import 'package:fidelia_admin/core/net/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(int status, Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

void main() {
  late List<http.Request> seen;
  late AccountsApi api;

  void setup(http.Response Function(http.Request) handler) {
    seen = [];
    api = AccountsApi(ApiClient(
      baseUrl: 'http://test',
      tokenProvider: () async => 'tok',
      inner: MockClient((req) async {
        seen.add(req);
        return handler(req);
      }),
    ));
  }

  const base = '/api/admin/accounts';

  test('checks lists open checks, filtered by kind, dates read as UTC', () async {
    setup((_) => json(200, [
          {
            'id': 3,
            'kind': 'reset_password',
            'app': 'merchant',
            'phone_masked': '07 •• •• 03 04',
            'created_at': '2026-10-22T08:30:00',
            'sent_at': null,
            'team_created': true,
          },
          {
            'id': 4,
            'kind': 'reset_password',
            'app': 'customer',
            'phone_masked': '05 •• •• 01 02',
            'created_at': '2026-10-22T08:30:00+00:00',
            'sent_at': '2026-10-22T09:00:00.123456',
            'team_created': false,
          },
        ]));
    final list = await api.checks('reset_password');
    expect(seen.single.method, 'GET');
    expect(seen.single.url.path, '$base/checks');
    expect(seen.single.url.queryParameters, {'kind': 'reset_password'});
    expect(seen.single.headers['Authorization'], 'Bearer tok');
    expect(list.length, 2);
    expect(list[0].id, 3);
    expect(list[0].app, 'merchant');
    expect(list[0].phoneMasked, '07 •• •• 03 04');
    expect(list[0].createdAt, DateTime.utc(2026, 10, 22, 8, 30));
    expect(list[0].createdAt.isUtc, isTrue);
    expect(list[0].sentAt, isNull);
    expect(list[0].teamCreated, isTrue);
    expect(list[1].createdAt, DateTime.utc(2026, 10, 22, 8, 30));
    expect(list[1].sentAt!.isUtc, isTrue);
    expect(list[1].sentAt!.hour, 9);
  });

  test('send posts and returns the url as a Uri', () async {
    setup((_) => json(200, {'url': 'https://wa.me/2250700000304?text=Bonjour%20x'}));
    final uri = await api.send(7);
    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, '$base/checks/7/send');
    expect(uri.host, 'wa.me');
  });

  test('send without a usable url is a MalformedResponseException', () async {
    setup((_) => json(200, {}));
    await expectLater(api.send(7), throwsA(isA<MalformedResponseException>()));
    setup((_) => json(200, {'url': 'not a url'}));
    await expectLater(api.send(7), throwsA(isA<MalformedResponseException>()));
  });

  test('resetPassword without check_id is a MalformedResponseException', () async {
    setup((_) => json(200, {}));
    await expectLater(api.resetPassword(3), throwsA(isA<MalformedResponseException>()));
  });

  test('send and refuse map 409 to AlreadyHandled', () async {
    setup((_) => json(409, {'detail': 'Cette demande est deja traitee.'}));
    await expectLater(api.send(1), throwsA(isA<AlreadyHandled>()));
    await expectLater(api.refuse(1), throwsA(isA<AlreadyHandled>()));
  });

  test('refuse posts and accepts 204 with an empty body', () async {
    setup((_) => http.Response('', 204));
    await api.refuse(5);
    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, '$base/checks/5/refuse');
  });

  test('findUser sends the phone without spaces and country_code CI', () async {
    setup((_) => json(200, {
          'id': 9,
          'phone_masked': '07 •• •• 03 04',
          'roles': ['merchant', 'cashier'],
          'disabled': false,
          'verified': true,
          'last_login_at': '2026-10-21T10:00:00',
        }));
    final user = await api.findUser('07 00 00 03 04');
    expect(seen.single.method, 'GET');
    expect(seen.single.url.path, '$base/users');
    expect(seen.single.url.queryParameters, {'phone': '0700000304', 'country_code': 'CI'});
    expect(seen.single.url.query, contains('country_code=CI'));
    expect(user!.id, 9);
    expect(user.roles, ['merchant', 'cashier']);
    expect(user.verified, isTrue);
    expect(user.lastLoginAt, DateTime.utc(2026, 10, 21, 10));
  });

  test('findUser url-encodes a plus sign', () async {
    setup((_) => json(404, {'detail': 'Compte introuvable.'}));
    await api.findUser('+225 07 00 00 03 04');
    expect(seen.single.url.query, contains('phone=%2B2250700000304'));
  });

  test('findUser returns null on 404', () async {
    setup((_) => json(404, {'detail': 'Compte introuvable.'}));
    expect(await api.findUser('0700000304'), isNull);
  });

  test('403 surfaces as ApiException (not an admin)', () async {
    setup((_) => json(403, {'detail': 'Not allowed for this account'}));
    await expectLater(api.checks('verify_number'), throwsA(isA<ApiException>()));
    await expectLater(api.findUser('0700000304'), throwsA(isA<ClientErrorException>()));
  });

  test('suspend, restore, signOut post to their paths and accept 204', () async {
    setup((_) => http.Response('', 204));
    await api.suspend(2);
    await api.restore(2);
    await api.signOut(2);
    expect(seen.map((r) => '${r.method} ${r.url.path}'), [
      'POST $base/users/2/suspend',
      'POST $base/users/2/restore',
      'POST $base/users/2/sign-out',
    ]);
  });

  test('resetPassword returns the new check id', () async {
    setup((_) => json(200, {'check_id': 42}));
    expect(await api.resetPassword(2), 42);
    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, '$base/users/2/reset-password');
  });

  test('ApiClient accepts a 204 with an empty body on POST without a parse error', () async {
    setup((_) => http.Response('', 204));
    final client = ApiClient(
      baseUrl: 'http://test',
      tokenProvider: () async => 'tok',
      inner: MockClient((_) async => http.Response('', 204)),
    );
    expect(await client.postJson('/x'), isEmpty);
  });

  test('the test logins: listed for the super admin, null for anyone else', () async {
    setup((_) => json(200, [
          {'phone_masked': '07 •• •• 00 01', 'role': 'customer', 'has_password': true},
          {'phone_masked': '07 •• •• 00 09', 'role': 'admin', 'has_password': false},
        ]));
    final accounts = await api.testAccounts();
    expect(accounts!.map((a) => a.role), ['customer', 'admin']);
    expect(accounts.last.hasPassword, isFalse);
    expect(seen.single.url.path, '$base/test-accounts');

    for (final status in [403, 404]) {
      setup((_) => json(status, {'detail': 'Reserve au super admin.'}));
      expect(await api.testAccounts(), isNull);
    }
  });

  test('the test logins\' password is put once for all', () async {
    // Generated per run: no password literal in the repository.
    final password = 'p${DateTime.now().microsecondsSinceEpoch}';
    setup((_) => http.Response('', 204));
    await api.setTestPassword(password);
    expect(seen.single.method, 'PUT');
    expect(seen.single.url.path, '$base/test-accounts/password');
    expect(jsonDecode(seen.single.body), {'password': password});
  });

  test('deleting a user is a DELETE on the account', () async {
    setup((_) => http.Response('', 204));
    await api.deleteUser(7);
    expect('${seen.single.method} ${seen.single.url.path}', 'DELETE $base/users/7');
  });

  test('shops are listed for the super admin only, and removal sends the typed name', () async {
    setup((_) => json(200, [
          {'id': 3, 'name': 'Chez Test', 'category': 'maquis', 'commune': 'Cocody', 'is_sample': true, 'owner_masked': '07 •• •• 56 79'},
        ]));
    final shops = await api.shops('chez');
    expect(shops!.single.name, 'Chez Test');
    expect(seen.single.url.queryParameters, {'q': 'chez'});

    setup((_) => json(403, {'detail': 'Reserve au super admin.'}));
    expect(await api.shops(''), isNull);

    setup((_) => json(200, {'deleted': {'venues': 1, 'deals': 2, 'users': 1}}));
    expect(await api.deleteShop(3, 'Chez Test'), 4);
    expect(seen.single.method, 'DELETE');
    expect(jsonDecode(seen.single.body), {'confirm_name': 'Chez Test'});
  });
}
