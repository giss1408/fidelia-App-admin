import 'package:fidelia_admin/core/auth/auth_repository.dart';
import 'package:fidelia_admin/core/providers.dart';
import 'package:fidelia_admin/features/session_gate.dart';
import 'package:fidelia_admin/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth.dart';

ProviderContainer container(FakeAuth auth) {
  final c = ProviderContainer(overrides: [authRepositoryProvider.overrideWithValue(auth)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('SessionGate', () {
    Future<void> pumpGate(WidgetTester tester, FakeAuth auth) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(auth)],
        child: MaterialApp(theme: fideliaTheme(), home: const SessionGate()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('no session shows sign-in', (tester) async {
      await pumpGate(tester, FakeAuth());
      expect(find.text('Se connecter'), findsOneWidget);
    });

    testWidgets('session with pc shows the forced change', (tester) async {
      await pumpGate(tester, FakeAuth(session: true, pc: true));
      expect(find.text('Choisissez votre mot de passe'), findsOneWidget);
    });

    testWidgets('session shows home', (tester) async {
      await pumpGate(tester, FakeAuth(session: true));
      expect(find.text('À traiter'), findsOneWidget);
    });

    testWidgets('after the change the gate shows home', (tester) async {
      await pumpGate(tester, FakeAuth(session: true, pc: true));
      await tester.enterText(find.widgetWithText(TextField, 'Nouveau mot de passe'), 'goodpassword1');
      await tester.enterText(find.widgetWithText(TextField, 'Confirmez le mot de passe'), 'goodpassword1');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(find.text('À traiter'), findsOneWidget);
      expect(find.text('Choisissez votre mot de passe'), findsNothing);
    });

    testWidgets('a rejected token mid-session returns to sign-in', (tester) async {
      await pumpGate(tester, FakeAuth(session: true));
      final c = ProviderScope.containerOf(tester.element(find.byType(SessionGate)));
      c.read(sessionProvider.notifier).onTokenRejected();
      await tester.pumpAndSettle();
      expect(find.text('Se connecter'), findsOneWidget);
    });
  });

  group('SessionNotifier', () {
    test('restore with a valid session', () async {
      final c = container(FakeAuth(session: true, pc: true));
      await c.read(sessionProvider.notifier).restore();
      final s = c.read(sessionProvider);
      expect((s.checked, s.signedIn, s.mustChangePassword), (true, true, true));
      expect(s.username, isNotNull);
    });

    test('restore without a session', () async {
      final c = container(FakeAuth());
      await c.read(sessionProvider.notifier).restore();
      final s = c.read(sessionProvider);
      expect((s.checked, s.signedIn, s.username), (true, false, null));
    });

    test('signIn success updates the state, rejection leaves it', () async {
      final auth = FakeAuth(signInResult: const SignInRejected('non'));
      final c = container(auth);
      await c.read(sessionProvider.notifier).restore();
      final rejected = await c.read(sessionProvider.notifier).signIn(phone: '1', password: 'x');
      expect(rejected, isA<SignInRejected>());
      expect(c.read(sessionProvider).signedIn, isFalse);

      auth.signInResult = const SignedIn(mustChangePassword: true);
      await c.read(sessionProvider.notifier).signIn(phone: '1', password: 'x');
      expect(c.read(sessionProvider).signedIn, isTrue);
      expect(c.read(sessionProvider).mustChangePassword, isTrue);
    });

    test('changePassword clears the pc flag; failure rethrows and keeps state', () async {
      final auth = FakeAuth(session: true, pc: true);
      final c = container(auth);
      await c.read(sessionProvider.notifier).restore();

      auth.changeError = 'refusé';
      await expectLater(
        c.read(sessionProvider.notifier).changePassword(newPassword: 'goodpassword1'),
        throwsA(isA<AccountActionException>()),
      );
      expect(c.read(sessionProvider).mustChangePassword, isTrue);

      auth.changeError = null;
      await c.read(sessionProvider.notifier).changePassword(newPassword: 'goodpassword1');
      expect(c.read(sessionProvider).mustChangePassword, isFalse);
      expect(c.read(sessionProvider).signedIn, isTrue);
    });

    test('signOut and onTokenRejected end the session', () async {
      final auth = FakeAuth(session: true);
      final c = container(auth);
      await c.read(sessionProvider.notifier).restore();
      await c.read(sessionProvider.notifier).signOut();
      expect(auth.signedOut, isTrue);
      expect(c.read(sessionProvider).signedIn, isFalse);

      auth.session = true;
      await c.read(sessionProvider.notifier).restore();
      c.read(sessionProvider.notifier).onTokenRejected();
      expect(c.read(sessionProvider).signedIn, isFalse);
      expect(c.read(sessionProvider).checked, isTrue);
    });
  });
}
