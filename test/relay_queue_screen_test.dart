import 'package:fidelia_admin/core/accounts/relay_queue_api.dart';
import 'package:fidelia_admin/core/net/api_exception.dart';
import 'package:fidelia_admin/features/relay_queue_screen.dart';
import 'package:fidelia_admin/features/whatsapp.dart';
import 'package:fidelia_admin/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

RelayItem item(int id, String purpose, {String status = 'open', String? name}) => RelayItem(
      id: id,
      purpose: purpose,
      status: status,
      displayName: name,
      phoneMasked: '+225 07 •• •• 04',
      createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 30)),
    );

class FakeRelay implements RelayQueueApi {
  FakeRelay(this.rows);

  List<RelayItem> rows;
  final calls = <String>[];
  Object? sendError;

  @override
  Future<List<RelayItem>> pending() async => rows;

  @override
  Future<Uri> send(int id) async {
    calls.add('send $id');
    if (sendError != null) throw sendError!;
    rows = [for (final r in rows) r.id == id ? item(id, r.purpose, status: r.isActivation ? 'sent' : 'done', name: r.displayName) : r]
        .where((r) => r.status != 'done')
        .toList();
    return Uri.parse('https://wa.me/2250701020304?text=Fidelia%20*123456*');
  }

  @override
  Future<void> reject(int id) async {
    calls.add('reject $id');
    rows = [for (final r in rows) if (r.id != id) r];
  }
}

Future<void> pump(WidgetTester tester, FakeRelay api, {List<Uri>? opened}) async {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      relayQueueApiProvider.overrideWithValue(api),
      whatsappLauncherProvider.overrideWithValue((uri) async {
        opened?.add(uri);
        return true;
      }),
    ],
    child: MaterialApp(theme: fideliaTheme(), home: const RelayQueueScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists activation codes and temporary passwords with masked numbers', (tester) async {
    await pump(tester, FakeRelay([item(1, 'activation', name: 'Awa'), item(2, 'password_reset', name: 'Moussa'), item(3, 'activation', status: 'sent')]));
    expect(find.text('Code d’activation à envoyer'), findsOneWidget);
    expect(find.text('Code d’activation envoyé, pas encore saisi'), findsOneWidget);
    expect(find.text('Mot de passe temporaire à envoyer'), findsOneWidget);
    expect(find.text('Nouvelle inscription'), findsOneWidget); // no name given
    expect(find.text('+225 07 •• •• 04'), findsNWidgets(3));
    expect(find.textContaining('0701020304'), findsNothing);
  });

  testWidgets('an empty queue says so', (tester) async {
    await pump(tester, FakeRelay([]));
    expect(find.byKey(const Key('relay-empty')), findsOneWidget);
  });

  testWidgets('sending opens WhatsApp with the message the server wrote, then the list refreshes; a sent code can be sent again', (tester) async {
    final api = FakeRelay([item(1, 'activation')]);
    final opened = <Uri>[];
    await pump(tester, api, opened: opened);
    await tester.tap(find.byKey(const Key('send-1')));
    await tester.pumpAndSettle();
    expect(api.calls, ['send 1']);
    expect(opened.single.host, 'wa.me');
    expect(find.text('Renvoyer (WhatsApp)'), findsOneWidget);
  });

  testWidgets('a temporary password leaves the list once sent, and has no refuse button', (tester) async {
    final api = FakeRelay([item(2, 'password_reset')]);
    await pump(tester, api);
    expect(find.byKey(const Key('reject-2')), findsNothing);
    await tester.tap(find.byKey(const Key('send-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('relay-empty')), findsOneWidget);
  });

  testWidgets('refusing a number asks first, then releases it', (tester) async {
    final api = FakeRelay([item(1, 'activation')]);
    await pump(tester, api);
    await tester.tap(find.byKey(const Key('reject-1')));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty, reason: 'a dialog first');
    await tester.tap(find.byKey(const Key('confirm-reject')));
    await tester.pumpAndSettle();
    expect(api.calls, ['reject 1']);
    expect(find.byKey(const Key('relay-empty')), findsOneWidget);
  });

  testWidgets('a failure is explained in words', (tester) async {
    final api = FakeRelay([item(1, 'activation')]);
    await pump(tester, api);
    api.sendError = const ClientErrorException(409, 'x', detail: 'request_closed');
    await tester.tap(find.byKey(const Key('send-1')));
    await tester.pumpAndSettle();
    expect(find.text('Cette demande est déjà traitée.'), findsOneWidget);
    expect(find.textContaining('request_closed'), findsNothing);
  });

  test('only activation and password reset are kept from the queue; the number-change messages belong to their own screen', () {
    final rows = [
      {'id': 1, 'purpose': 'activation', 'status': 'open', 'display_name': null, 'phone_masked': null, 'created_at': '2026-11-20T10:00:00Z'},
      {'id': 2, 'purpose': 'phone_change', 'status': 'open', 'display_name': null, 'phone_masked': null, 'created_at': '2026-11-20T10:00:00Z'},
    ];
    expect(RelayQueueApi.purposes.contains(rows[0]['purpose']), isTrue);
    expect(RelayQueueApi.purposes.contains(rows[1]['purpose']), isFalse);
    expect(RelayItem.fromJson(rows[0]).isActivation, isTrue);
  });
}
