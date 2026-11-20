import 'package:fidelia_admin/core/auth/auth_repository.dart';
import 'package:fidelia_admin/core/net/api_exception.dart';
import 'package:fidelia_admin/core/providers.dart';
import 'package:fidelia_admin/features/step_up.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth.dart';

class _ProvingAuth extends FakeAuth {
  final proofs = <(String, String)>[];
  Object? failWith;

  @override
  Future<void> stepUp({required String password, required String totp}) async {
    proofs.add((password, totp));
    if (failWith != null) throw failWith!;
  }
}

const _needsProof = ClientErrorException(403, 'forbidden', detail: 'step_up_required');

/// What the pressed button saw: filled in as the action settles (it may still be waiting on the prompt when `_run` returns).
class _Seen {
  final log = <String>[];
  Object? error;
}

Future<_Seen> _run(WidgetTester tester, _ProvingAuth auth, Future<String> Function(int call) action, {bool authMode = true, String? typePassword, String? typeTotp}) async {
  final seen = _Seen();
  var calls = 0;
  await tester.pumpWidget(ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(auth)],
    child: MaterialApp(
      home: Consumer(
        builder: (context, ref, _) => Scaffold(
          body: TextButton(
            onPressed: () async {
              try {
                seen.log.add(await withStepUp(context, ref, () => action(++calls), authMode: authMode));
              } catch (e) {
                seen.error = e;
              }
            },
            child: const Text('go'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  if (typePassword != null) {
    await tester.enterText(find.byKey(const Key('stepup-password')), typePassword);
    await tester.enterText(find.byKey(const Key('stepup-totp')), typeTotp ?? '');
    await tester.tap(find.byKey(const Key('stepup-confirm')));
    await tester.pumpAndSettle();
  }
  return seen;
}

void main() {
  testWidgets('an action refused for want of a fresh proof asks for password and code, proves it, and runs again', (tester) async {
    final auth = _ProvingAuth();
    final seen = await _run(tester, auth, (n) async => n == 1 ? throw _needsProof : 'done on call $n', typePassword: 'pw-secret-1', typeTotp: '123456');
    expect(auth.proofs, [('pw-secret-1', '123456')]);
    expect(seen.log, ['done on call 2']);
    expect(seen.error, isNull);
  });

  testWidgets('cancelling the prompt gives back the original refusal and proves nothing', (tester) async {
    final auth = _ProvingAuth();
    final seen = await _run(tester, auth, (n) async => throw _needsProof);
    expect(find.text('Confirmez que c’est bien vous'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(auth.proofs, isEmpty);
    expect(seen.log, isEmpty);
    expect(seen.error, same(_needsProof));
  });

  testWidgets('a wrong proof is reported and the action is not retried', (tester) async {
    final auth = _ProvingAuth()..failWith = const AccountActionException('Mot de passe incorrect.');
    var calls = 0;
    final seen = await _run(tester, auth, (n) async {
      calls = n;
      throw _needsProof;
    }, typePassword: 'wrong', typeTotp: '123456');
    expect(calls, 1);
    expect(seen.log, isEmpty);
    expect(seen.error, isA<ClientErrorException>().having((e) => e.message, 'message', 'Mot de passe incorrect.'));
  });

  testWidgets('other errors, and builds without the auth service, are left alone', (tester) async {
    const other = ClientErrorException(409, 'conflict', detail: 'already_handled');
    final s1 = await _run(tester, _ProvingAuth(), (n) async => throw other);
    expect(s1.error, same(other));
    expect(find.text('Confirmez que c’est bien vous'), findsNothing);
    final s2 = await _run(tester, _ProvingAuth(), (n) async => throw _needsProof, authMode: false);
    expect(s2.error, same(_needsProof));
    expect(find.text('Confirmez que c’est bien vous'), findsNothing);
  });
}
