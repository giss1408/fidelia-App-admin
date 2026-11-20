import 'package:fidelia_admin/core/accounts/frozen_accounts_api.dart';
import 'package:fidelia_admin/core/net/api_exception.dart';
import 'package:fidelia_admin/features/frozen_accounts_screen.dart';
import 'package:fidelia_admin/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

FrozenAccount frozen(String id, String reason, {String? name}) => FrozenAccount(
      id: id,
      displayName: name,
      phoneMasked: '+225 07 •• •• 04',
      reason: reason,
      since: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
    );

class FakeFrozen implements FrozenAccountsApi {
  FakeFrozen(this.rows);

  List<FrozenAccount> rows;
  final calls = <String>[];
  final notes = <String>[];
  Object? enableError;

  @override
  Future<List<FrozenAccount>> list() async => rows;

  @override
  Future<void> enable(String id, String note) async {
    calls.add('enable $id');
    notes.add(note);
    if (enableError != null) throw enableError!;
    rows = [for (final r in rows) if (r.id != id) r];
  }
}

Future<void> pump(WidgetTester tester, FakeFrozen api) async {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [frozenAccountsApiProvider.overrideWithValue(api)],
    child: MaterialApp(theme: fideliaTheme(), home: const FrozenAccountsScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists frozen accounts with the reason in words and masked numbers', (tester) async {
    await pump(tester, FakeFrozen([frozen('a', 'not_me', name: 'Awa'), frozen('b', 'disabled'), frozen('c', 'unknown')]));
    expect(find.textContaining('ce n’était pas moi'), findsOneWidget);
    expect(find.text('Désactivé par l’équipe'), findsOneWidget);
    expect(find.text('Raison inconnue'), findsOneWidget);
    expect(find.text('+225 07 •• •• 04'), findsNWidgets(3));
    expect(find.textContaining('0701020304'), findsNothing);
  });

  testWidgets('an empty list says so', (tester) async {
    await pump(tester, FakeFrozen([]));
    expect(find.byKey(const Key('frozen-empty')), findsOneWidget);
  });

  testWidgets('giving an account back needs a real note, then goes through and the card leaves', (tester) async {
    final api = FakeFrozen([frozen('a', 'not_me')]);
    await pump(tester, api);
    await tester.tap(find.byKey(const Key('enable-a')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const Key('confirm-enable'));
    expect(tester.widget<TextButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'ok');
    await tester.pump();
    expect(tester.widget<TextButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'Appelée, voix reconnue, confirme');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(api.calls, ['enable a']);
    expect(api.notes.single, 'Appelée, voix reconnue, confirme');
    expect(find.byKey(const Key('frozen-empty')), findsOneWidget);
  });

  testWidgets('cancelling the note dialog changes nothing', (tester) async {
    final api = FakeFrozen([frozen('a', 'not_me')]);
    await pump(tester, api);
    await tester.tap(find.byKey(const Key('enable-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);
    expect(find.byKey(const Key('frozen-a')), findsOneWidget);
  });

  testWidgets('a refusal is explained in words', (tester) async {
    final api = FakeFrozen([frozen('a', 'disabled')])..enableError = const ClientErrorException(403, 'x', detail: 'super_admin_only');
    await pump(tester, api);
    await tester.tap(find.byKey(const Key('enable-a')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Appelée, voix reconnue, confirme');
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-enable')));
    await tester.pumpAndSettle();
    expect(find.text('Seul un super administrateur peut réactiver un compte de l’équipe.'), findsOneWidget);
    expect(find.textContaining('super_admin_only'), findsNothing);
  });

  test('reads the server JSON', () {
    final a = FrozenAccount.fromJson({'id': 'u1', 'display_name': null, 'phone_masked': '+225 07 •• •• 04', 'products': ['fidelia'], 'reason': 'not_me', 'since': '2026-11-20T10:00:00Z'});
    expect(a.reason, 'not_me');
    expect(a.since, DateTime.utc(2026, 11, 20, 10));
    expect(FrozenAccount.fromJson({'id': 'u2'}).reason, 'unknown');
  });
}
