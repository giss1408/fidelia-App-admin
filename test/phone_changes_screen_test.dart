import 'package:fidelia_admin/core/accounts/phone_changes_api.dart';
import 'package:fidelia_admin/core/net/api_exception.dart';
import 'package:fidelia_admin/features/phone_changes_screen.dart';
import 'package:fidelia_admin/features/whatsapp.dart';
import 'package:fidelia_admin/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

PhoneChangeItem change(int id, String status, {String? name = 'Awa K.', PhoneRelay? code, PhoneRelay? alert, PhoneRelay? notice, DateTime? effectiveAt}) => PhoneChangeItem(
      id: id,
      status: status,
      displayName: name,
      newPhoneMasked: '+225 07 •• •• 08',
      oldPhoneMasked: '+225 07 •• •• 04',
      createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      effectiveAt: effectiveAt,
      code: code,
      alert: alert,
      notice: notice,
    );

class FakePhones implements PhoneChangesApi {
  FakePhones(this.rows);

  List<PhoneChangeItem> rows;
  final calls = <String>[];
  final notes = <String>[];
  Object? error;

  @override
  Future<List<PhoneChangeItem>> open() async {
    if (error != null) throw error!;
    return rows;
  }

  @override
  Future<Uri> sendRelay(int relayId) async {
    calls.add('send $relayId');
    return Uri.parse('https://wa.me/2250701020304?text=Fidelia%20*123456*');
  }

  @override
  Future<void> activateNow(int id, String note) async {
    calls.add('activate $id');
    notes.add(note);
    rows = [for (final r in rows) if (r.id != id) r];
  }

  @override
  Future<void> notMe(int id) async {
    calls.add('not-me $id');
    rows = [for (final r in rows) if (r.id != id) r];
  }
}

Future<void> pump(WidgetTester tester, FakePhones api, {List<Uri>? opened}) async {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      phoneChangesApiProvider.overrideWithValue(api),
      whatsappLauncherProvider.overrideWithValue((uri) async {
        opened?.add(uri);
        return true;
      }),
    ],
    child: MaterialApp(theme: fideliaTheme(), home: const PhoneChangesScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists the changes with masked numbers and what each one waits for', (tester) async {
    await pump(
      tester,
      FakePhones([
        change(1, 'requested', code: const PhoneRelay(id: 11, sent: false), alert: const PhoneRelay(id: 12, sent: false)),
        change(2, 'scheduled', name: 'Moussa', effectiveAt: DateTime.now().toUtc().add(const Duration(hours: 20))),
        change(3, 'done', name: 'Fanta', notice: const PhoneRelay(id: 31, sent: false)),
      ]),
    );
    expect(find.text('Code à envoyer au nouveau numéro'), findsOneWidget);
    expect(find.textContaining('Prend effet le'), findsOneWidget);
    expect(find.textContaining('avis à envoyer'), findsOneWidget);
    expect(find.text('+225 07 •• •• 04  →  +225 07 •• •• 08'), findsNWidgets(3));
    expect(find.textContaining('0701020304'), findsNothing);
  });

  testWidgets('an empty list says so', (tester) async {
    await pump(tester, FakePhones([]));
    expect(find.byKey(const Key('phone-empty')), findsOneWidget);
  });

  testWidgets('the code, the warning and the notice each open WhatsApp with the link the server wrote', (tester) async {
    final api = FakePhones([
      change(1, 'requested', code: const PhoneRelay(id: 11, sent: false), alert: const PhoneRelay(id: 12, sent: false)),
      change(3, 'done', notice: const PhoneRelay(id: 31, sent: false)),
    ]);
    final opened = <Uri>[];
    await pump(tester, api, opened: opened);
    await tester.tap(find.byKey(const Key('send-code-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('send-alert-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('send-notice-3')));
    await tester.pumpAndSettle();
    expect(api.calls, ['send 11', 'send 12', 'send 31']);
    expect(opened.length, 3);
    expect(opened.first.host, 'wa.me');
  });

  testWidgets('a code already sent can be sent again', (tester) async {
    await pump(tester, FakePhones([change(1, 'requested', code: const PhoneRelay(id: 11, sent: true))]));
    expect(find.text('Renvoyer le code (WhatsApp)'), findsOneWidget);
    expect(find.textContaining('en attente de saisie'), findsOneWidget);
  });

  testWidgets('"change now" exists only for a scheduled change and needs a real note', (tester) async {
    final api = FakePhones([change(1, 'requested', code: const PhoneRelay(id: 11, sent: false)), change(2, 'scheduled', name: 'Moussa')]);
    await pump(tester, api);
    expect(find.byKey(const Key('activate-1')), findsNothing);
    await tester.tap(find.byKey(const Key('activate-2')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const Key('confirm-activate'));
    expect(tester.widget<TextButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'ok');
    await tester.pump();
    expect(tester.widget<TextButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'Appelée sur l’ancien numéro, confirme');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(api.calls, ['activate 2']);
    expect(api.notes.single, 'Appelée sur l’ancien numéro, confirme');
    expect(find.text('Moussa'), findsNothing);
  });

  testWidgets('"ce n’était pas moi" asks first, then freezes through the API; not offered once the change is done', (tester) async {
    final api = FakePhones([change(1, 'scheduled'), change(3, 'done', notice: const PhoneRelay(id: 31, sent: false))]);
    await pump(tester, api);
    expect(find.byKey(const Key('not-me-3')), findsNothing);
    await tester.tap(find.byKey(const Key('not-me-1')));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty, reason: 'a dialog first');
    await tester.tap(find.byKey(const Key('confirm-not-me')));
    await tester.pumpAndSettle();
    expect(api.calls, ['not-me 1']);
  });

  testWidgets('a refusal is explained in words, not codes', (tester) async {
    final api = FakePhones([change(1, 'scheduled')])..error = const ClientErrorException(409, 'x', detail: 'old_phone_taken');
    await pump(tester, api);
    expect(find.textContaining('old_phone_taken'), findsNothing);
    expect(phoneChangeErrorMessage(const ClientErrorException(403, 'x', detail: 'step_up_required')), contains('mot de passe'));
    expect(phoneChangeErrorMessage(const ClientErrorException(409, 'x', detail: 'old_phone_taken')), contains('pris entre-temps'));
  });

  test('the item reads the server JSON: relays by kind, dates, masks', () {
    final item = PhoneChangeItem.fromJson({
      'id': 7,
      'status': 'requested',
      'display_name': null,
      'new_phone_masked': '+225 07 •• •• 08',
      'old_phone_masked': null,
      'created_at': '2026-11-20T10:00:00Z',
      'effective_at': null,
      'relays': {'code': {'id': 70, 'status': 'sent'}, 'alert': {'id': 71, 'status': 'open'}},
    });
    expect(item.code!.sent, isTrue);
    expect(item.alert!.sent, isFalse);
    expect(item.notice, isNull);
    expect(item.canStop, isTrue);
  });
}
