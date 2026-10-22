import 'package:fidelia_admin/core/auth/auth_repository.dart';
import 'package:fidelia_admin/core/providers.dart';
import 'package:fidelia_admin/features/change_password_screen.dart';
import 'package:fidelia_admin/features/session_gate.dart';
import 'package:fidelia_admin/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth.dart';

Widget app(FakeAuth auth, {Widget home = const SessionGate()}) => ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
      child: MaterialApp(theme: fideliaTheme(), home: home),
    );

void main() {
  testWidgets('sign-in sends phone and password', (tester) async {
    final auth = FakeAuth();
    await tester.pumpWidget(app(auth));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Numéro de téléphone'), '07 01 02 03 04');
    await tester.enterText(find.widgetWithText(TextField, 'Mot de passe'), 'secret-pass');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(auth.lastPhone, '07 01 02 03 04');
    expect(auth.lastPassword, 'secret-pass');
    expect(find.text('À traiter'), findsOneWidget);
  });

  testWidgets('password is obscured and can be revealed', (tester) async {
    await tester.pumpWidget(app(FakeAuth()));
    await tester.pumpAndSettle();
    TextField field() => tester.widget<TextField>(find.widgetWithText(TextField, 'Mot de passe'));
    expect(field().obscureText, isTrue);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(field().obscureText, isFalse);
  });

  testWidgets('server message is shown under the form', (tester) async {
    final auth = FakeAuth(signInResult: const SignInRejected('Numéro ou mot de passe incorrect.'));
    await tester.pumpWidget(app(auth));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Numéro de téléphone'), '0701020304');
    await tester.enterText(find.widgetWithText(TextField, 'Mot de passe'), 'wrongwrong');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(find.text('Numéro ou mot de passe incorrect.'), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
  });

  testWidgets('forced change screen has no back button and no current-password field', (tester) async {
    final auth = FakeAuth(session: true, pc: true);
    await tester.pumpWidget(app(auth));
    await tester.pumpAndSettle();

    expect(find.text('Choisissez votre mot de passe'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('Mot de passe actuel'), findsNothing);
    expect(find.text('Se déconnecter'), findsOneWidget);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);

    await tester.tap(find.text('Se déconnecter'));
    await tester.pumpAndSettle();
    expect(auth.signedOut, isTrue);
    expect(find.text('Se connecter'), findsOneWidget);
  });

  testWidgets('non-forced change asks for the current password and passes it on', (tester) async {
    final auth = FakeAuth(session: true);
    await tester.pumpWidget(app(auth, home: const ChangePasswordScreen(forced: false)));
    await tester.pumpAndSettle();

    expect(find.text('Mot de passe actuel'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Mot de passe actuel'), 'oldoldold');
    await tester.enterText(find.widgetWithText(TextField, 'Nouveau mot de passe'), 'brand-new-pw');
    await tester.enterText(find.widgetWithText(TextField, 'Confirmez le mot de passe'), 'brand-new-pw');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(auth.lastCurrent, 'oldoldold');
    expect(auth.lastNew, 'brand-new-pw');
  });

  testWidgets('password rules shown inline', (tester) async {
    final auth = FakeAuth(session: true, pc: true);
    await tester.pumpWidget(app(auth));
    await tester.pumpAndSettle();

    for (final bad in ['abc', '12345678']) {
      await tester.enterText(find.widgetWithText(TextField, 'Nouveau mot de passe'), bad);
      await tester.enterText(find.widgetWithText(TextField, 'Confirmez le mot de passe'), bad);
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      // Hint line plus the inline error.
      expect(find.text('8 caractères minimum, pas seulement des chiffres'), findsNWidgets(2));
    }
    expect(auth.lastNew, isNull);
  });

  testWidgets('mismatched confirmation is refused', (tester) async {
    final auth = FakeAuth(session: true, pc: true);
    await tester.pumpWidget(app(auth));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Nouveau mot de passe'), 'goodpassword1');
    await tester.enterText(find.widgetWithText(TextField, 'Confirmez le mot de passe'), 'goodpassword2');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Les deux mots de passe sont différents'), findsOneWidget);
    expect(auth.lastNew, isNull);
  });

  testWidgets('server refusal of the new password is shown', (tester) async {
    final auth = FakeAuth(session: true, pc: true, changeError: 'Ce mot de passe est trop courant.');
    await tester.pumpWidget(app(auth));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Nouveau mot de passe'), 'password123');
    await tester.enterText(find.widgetWithText(TextField, 'Confirmez le mot de passe'), 'password123');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Ce mot de passe est trop courant.'), findsOneWidget);
    expect(find.text('Choisissez votre mot de passe'), findsOneWidget);
  });
}
