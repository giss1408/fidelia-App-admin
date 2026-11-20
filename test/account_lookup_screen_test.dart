import 'package:fidelia_admin/core/accounts/frozen_accounts_api.dart';
import 'package:fidelia_admin/core/net/api_exception.dart';
import 'package:fidelia_admin/features/account_lookup_screen.dart';
import 'package:fidelia_admin/features/frozen_accounts_screen.dart';
import 'package:fidelia_admin/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'frozen_accounts_screen_test.dart' show FakeFrozen;

AccountHit hit({String status = 'active', String? name = 'Awa K.'}) =>
    AccountHit(id: 'u1', displayName: name, phoneMasked: '+225 07 •• •• 04', status: status, roles: const ['fidelia:customer']);

Future<void> pump(WidgetTester tester, FakeFrozen api) async {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [frozenAccountsApiProvider.overrideWithValue(api)],
    child: MaterialApp(theme: fideliaTheme(), home: const AccountLookupScreen()),
  ));
  await tester.pumpAndSettle();
}

Future<void> search(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('lookup-phone')), '07 01 02 03 04');
  await tester.tap(find.byKey(const Key('lookup-search')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('finds an account by number and shows who it is, with the masked number only', (tester) async {
    final api = FakeFrozen([])..hit = hit();
    await pump(tester, api);
    await search(tester);
    expect(find.text('Awa K.'), findsOneWidget);
    expect(find.text('+225 07 •• •• 04'), findsOneWidget);
    expect(find.text('fidelia:customer'), findsOneWidget);
    expect(find.textContaining('0701020304'), findsNothing);
  });

  testWidgets('an unknown number says so in words', (tester) async {
    final api = FakeFrozen([])..searchError = const ClientErrorException(404, 'x', detail: 'user_not_found');
    await pump(tester, api);
    await search(tester);
    expect(find.text('Aucun compte avec ce numéro.'), findsOneWidget);
    expect(find.byKey(const Key('lookup-result')), findsNothing);
  });

  testWidgets('switching off needs a real reason, then goes through and the result clears', (tester) async {
    final api = FakeFrozen([])..hit = hit();
    await pump(tester, api);
    await search(tester);
    await tester.tap(find.byKey(const Key('lookup-disable')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const Key('confirm-disable'));
    expect(tester.widget<TextButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byType(TextField).last, 'vol');
    await tester.pump();
    expect(tester.widget<TextButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byType(TextField).last, 'Téléphone volé, signalé par la cliente');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(api.calls, ['search', 'disable u1']);
    expect(api.notes.single, 'Téléphone volé, signalé par la cliente');
    expect(find.byKey(const Key('lookup-result')), findsNothing);
  });

  testWidgets('an account that is not active is not offered for suspension', (tester) async {
    final api = FakeFrozen([])..hit = hit(status: 'disabled');
    await pump(tester, api);
    await search(tester);
    expect(find.byKey(const Key('lookup-disable')), findsNothing);
    expect(find.byKey(const Key('lookup-not-active')), findsOneWidget);
  });

  testWidgets('cancelling the reason dialog changes nothing', (tester) async {
    final api = FakeFrozen([])..hit = hit();
    await pump(tester, api);
    await search(tester);
    await tester.tap(find.byKey(const Key('lookup-disable')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(api.calls, ['search']);
    expect(find.byKey(const Key('lookup-result')), findsOneWidget);
  });

  testWidgets('the frozen accounts screen opens this lookup from its app bar', (tester) async {
    final api = FakeFrozen([]);
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [frozenAccountsApiProvider.overrideWithValue(api)],
      child: MaterialApp(theme: fideliaTheme(), home: const FrozenAccountsScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lookup')));
    await tester.pumpAndSettle();
    expect(find.text('Suspendre un compte'), findsWidgets);
    expect(find.byKey(const Key('lookup-phone')), findsOneWidget);
  });

  test('reads the search JSON into roles per product', () {
    final h = AccountHit.fromJson({
      'id': 'u1', 'display_name': null, 'phone_masked': '+225 07 •• •• 04', 'status': 'active',
      'memberships': [{'product': 'fidelia', 'role': 'merchant'}, {'product': 'flariane', 'role': 'customer'}],
    });
    expect(h.roles, ['fidelia:merchant', 'flariane:customer']);
    expect(h.isActive, isTrue);
  });
}
