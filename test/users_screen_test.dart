import 'package:fidelia_admin/core/accounts/accounts_api.dart';
import 'package:fidelia_admin/core/accounts/models.dart';
import 'package:fidelia_admin/core/net/api_exception.dart';
import 'package:fidelia_admin/core/providers.dart';
import 'package:fidelia_admin/features/session_gate.dart';
import 'package:fidelia_admin/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth.dart';

class FakeUsers implements AccountsApi {
  AdminUserView? user = AdminUserView(
    id: 7,
    phoneMasked: '+225 ** ** 12',
    roles: const ['customer', 'merchant'],
    disabled: false,
    verified: true,
    lastLoginAt: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
  );
  final calls = <String>[];
  final searched = <String>[];
  Object? error;
  int checkLoads = 0;
  bool failChecks = false;

  @override
  Future<AdminUserView?> findUser(String phone) async {
    searched.add(phone);
    if (error != null) throw error!;
    return user;
  }

  void _set(bool disabled) => user = AdminUserView(
        id: user!.id,
        phoneMasked: user!.phoneMasked,
        roles: user!.roles,
        disabled: disabled,
        verified: user!.verified,
        lastLoginAt: user!.lastLoginAt,
      );

  @override
  Future<void> suspend(int id) async {
    calls.add('suspend $id');
    _set(true);
  }

  @override
  Future<void> restore(int id) async {
    calls.add('restore $id');
    _set(false);
  }

  @override
  Future<void> signOut(int id) async => calls.add('signOut $id');

  @override
  Future<int> resetPassword(int id) async {
    calls.add('reset $id');
    return 99;
  }

  @override
  Future<List<AccountCheck>> checks(String kind) async {
    checkLoads++;
    if (failChecks) throw const NetworkException('Pas de connexion.');
    if (kind != 'verify_number') return const [];
    return [
      AccountCheck(id: 2, kind: kind, app: 'user', phoneMasked: 'b', createdAt: DateTime.utc(2026), sentAt: null, teamCreated: false),
      AccountCheck(id: 1, kind: kind, app: 'user', phoneMasked: 'a', createdAt: DateTime.utc(2026), sentAt: null, teamCreated: false),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeUsers api;
  late FakeAuth auth;

  setUp(() {
    api = FakeUsers();
    auth = FakeAuth(session: true);
  });

  Future<void> pump(WidgetTester tester, {Widget home = const SessionGate()}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [accountsApiProvider.overrideWithValue(api), authRepositoryProvider.overrideWithValue(auth)],
      child: MaterialApp(theme: fideliaTheme(), home: home),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, [String phone = '07 00 00 00 12']) async {
    await tester.tap(find.text('Utilisateurs'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), phone);
    await tester.tap(find.text('Rechercher'));
    await tester.pumpAndSettle();
  }

  testWidgets('À traiter is the first tab', (tester) async {
    await pump(tester);
    expect(find.text('Numéros à vérifier'), findsOneWidget);
    expect(find.text('Utilisateurs'), findsOneWidget);
    expect(find.text('Compte'), findsOneWidget);
  });

  testWidgets('unknown number shows « Aucun compte pour ce numéro »', (tester) async {
    api.user = null;
    await pump(tester);
    await search(tester);
    expect(find.text('Aucun compte pour ce numéro'), findsOneWidget);
    expect(api.searched, ['07 00 00 00 12']);
  });

  testWidgets('found account shows roles, chips and last sign-in', (tester) async {
    await pump(tester);
    await search(tester);
    expect(find.text('+225 ** ** 12'), findsOneWidget);
    expect(find.text('Client, Commerçant'), findsOneWidget);
    expect(find.text('Vérifié'), findsOneWidget);
    expect(find.text('Suspendu'), findsNothing);
    expect(find.text('Dernière connexion : il y a 3 h'), findsOneWidget);
  });

  testWidgets('never signed in', (tester) async {
    api.user = const AdminUserView(id: 7, phoneMasked: 'x', roles: [], disabled: false, verified: false, lastLoginAt: null);
    await pump(tester);
    await search(tester);
    expect(find.text('Non vérifié'), findsOneWidget);
    expect(find.text('Jamais connecté'), findsOneWidget);
  });

  testWidgets('suspend asks and calls the API', (tester) async {
    await pump(tester);
    await search(tester);
    await tester.tap(find.text('Suspendre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);

    await tester.tap(find.text('Suspendre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmer'));
    await tester.pumpAndSettle();
    expect(api.calls, ['suspend 7']);
    expect(find.text('Compte suspendu'), findsOneWidget);
    expect(find.text('Suspendu'), findsOneWidget); // chip after reload
    expect(find.text('Réactiver'), findsOneWidget);
  });

  testWidgets('restore shown only for a suspended account', (tester) async {
    await pump(tester);
    await search(tester);
    expect(find.text('Réactiver'), findsNothing);

    api.user = const AdminUserView(id: 7, phoneMasked: 'x', roles: [], disabled: true, verified: true, lastLoginAt: null);
    await tester.tap(find.text('Rechercher'));
    await tester.pumpAndSettle();
    expect(find.text('Suspendre'), findsNothing);
    await tester.tap(find.text('Réactiver'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmer'));
    await tester.pumpAndSettle();
    expect(api.calls, ['restore 7']);
    expect(find.text('Compte réactivé'), findsOneWidget);
  });

  testWidgets('sign out everywhere and reset password', (tester) async {
    await pump(tester);
    await search(tester);
    await tester.tap(find.text('Déconnecter partout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmer'));
    await tester.pumpAndSettle();
    expect(find.text('Sessions fermées'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    final before = api.checkLoads;
    await tester.tap(find.text('Réinitialiser le mot de passe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmer'));
    await tester.pumpAndSettle();
    expect(api.calls, ['signOut 7', 'reset 7']);
    expect(find.textContaining('Demande créée'), findsOneWidget);
    expect(api.checkLoads, greaterThanOrEqualTo(before));
  });

  testWidgets('API error is shown as a SnackBar', (tester) async {
    api.error = const NetworkException('Pas de connexion.');
    await pump(tester);
    await search(tester);
    expect(find.text('Pas de connexion.'), findsOneWidget);
  });

  testWidgets('sign out returns to the sign-in screen, even over a pushed route', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Changer mon mot de passe'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Se déconnecter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(auth.signedOut, isFalse);

    await tester.tap(find.text('Se déconnecter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmer'));
    await tester.pumpAndSettle();
    expect(auth.signedOut, isTrue);
    expect(find.text('Se connecter'), findsOneWidget);
  });

  testWidgets('session ending under a pushed route pops to the gate', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Changer mon mot de passe'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    container.read(sessionProvider.notifier).onTokenRejected();
    await tester.pumpAndSettle();
    expect(find.text('Se connecter'), findsOneWidget);
    expect(find.text('Changer le mot de passe'), findsNothing);
  });

  testWidgets('changing the password pops back with a confirmation', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Changer mon mot de passe'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Mot de passe actuel'), 'oldpassword1');
    await tester.enterText(find.widgetWithText(TextField, 'Nouveau mot de passe'), 'goodpassword1');
    await tester.enterText(find.widgetWithText(TextField, 'Confirmez le mot de passe'), 'goodpassword1');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Mot de passe changé'), findsOneWidget);
  });

  testWidgets('failed refresh keeps the list and shows the error', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Numéros à vérifier'));
    await tester.pumpAndSettle();
    api.failChecks = true;
    await tester.drag(find.byType(ListView).first, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('Pas de connexion.'), findsOneWidget);
    expect(find.byType(Card), findsNWidgets(2));
  });

  testWidgets('ties are broken by id', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Numéros à vérifier'));
    await tester.pumpAndSettle();
    final ids = tester.widgetList<Card>(find.byType(Card)).map((c) => (c.key as ValueKey).value).toList();
    expect(ids, [1, 2]);
  });
}
