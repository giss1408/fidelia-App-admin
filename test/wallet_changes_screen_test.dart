import 'package:fidelia_admin/core/accounts/wallet_changes_api.dart';
import 'package:fidelia_admin/core/net/api_exception.dart';
import 'package:fidelia_admin/core/providers.dart';
import 'package:fidelia_admin/features/wallet_changes_screen.dart';
import 'package:fidelia_admin/features/whatsapp.dart';
import 'package:fidelia_admin/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

WalletChangeItem change(int id, String status, {String shop = 'Maquis Test', bool codeSent = false, List<WalletEvent>? events}) => WalletChangeItem(
      id: id,
      status: status,
      shop: shop,
      provider: 'orange',
      newAccountMasked: '••••2222',
      currentAccountMasked: '••••1111',
      merchantPhoneMasked: '07 •• •• 03 04',
      requestedAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
      codeSent: codeSent,
      activatesAt: status == 'confirmed_waiting' ? DateTime.now().toUtc().add(const Duration(hours: 20)) : null,
      callNote: null,
      events: events ?? [WalletEvent(at: DateTime.now().toUtc(), actor: '07 •• •• 03 04', action: 'requested', detail: 'orange ••••2222')],
    );

class FakeWallets implements WalletChangesApi {
  FakeWallets(this.rows);

  List<WalletChangeItem> rows;
  final calls = <String>[];
  final notes = <String>[];
  Object? error;

  @override
  Future<List<WalletChangeItem>> open() async {
    if (error != null) throw error!;
    return rows;
  }

  @override
  Future<Uri> sendCode(int id) async {
    calls.add('send $id');
    if (error != null) throw error!;
    return Uri.parse('https://wa.me/2250701020304?text=Fidelia%20code%20*123456*');
  }

  @override
  Future<void> activateNow(int id, String callNote) async {
    calls.add('activate $id');
    notes.add(callNote);
    rows = [for (final r in rows) if (r.id != id) r];
  }

  @override
  Future<void> reject(int id, {String? reason}) async {
    calls.add('reject $id ${reason ?? ''}'.trim());
    rows = [for (final r in rows) if (r.id != id) r];
  }
}

Future<void> pump(WidgetTester tester, FakeWallets api, {List<Uri>? opened}) async {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      walletChangesApiProvider.overrideWithValue(api),
      whatsappLauncherProvider.overrideWithValue((uri) async {
        opened?.add(uri);
        return true;
      }),
    ],
    child: MaterialApp(theme: fideliaTheme(), home: const WalletChangesScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists the open changes with masked numbers, old to new, and the status', (tester) async {
    await pump(tester, FakeWallets([change(1, 'pending_confirmation'), change(2, 'confirmed_waiting', shop: 'Pharmacie Test', codeSent: true)]));
    expect(find.text('Maquis Test'), findsOneWidget);
    expect(find.textContaining('••••1111  →  Orange Money ••••2222'), findsNWidgets(2));
    expect(find.text('Code à envoyer'), findsOneWidget);
    expect(find.textContaining('Confirmé, active'), findsOneWidget);
    expect(find.textContaining('0701020304'), findsNothing);
  });

  testWidgets('an empty queue says so', (tester) async {
    await pump(tester, FakeWallets([]));
    expect(find.byKey(const Key('wallet-empty')), findsOneWidget);
  });

  testWidgets('sending the code opens WhatsApp with the link the server gave, and the card refreshes', (tester) async {
    final api = FakeWallets([change(1, 'pending_confirmation')]);
    final opened = <Uri>[];
    await pump(tester, api, opened: opened);
    await tester.tap(find.byKey(const Key('send-1')));
    await tester.pumpAndSettle();
    expect(api.calls, ['send 1']);
    expect(opened.single.host, 'wa.me');
    expect(find.text('Envoyer le code (WhatsApp)'), findsOneWidget);
  });

  testWidgets('activating after a call needs a real note, then goes through', (tester) async {
    final api = FakeWallets([change(1, 'pending_confirmation')]);
    await pump(tester, api);
    await tester.tap(find.byKey(const Key('activate-1')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const Key('confirm-activate'));
    expect(tester.widget<TextButton>(confirm).onPressed, isNull, reason: 'no note, no activation');
    await tester.enterText(find.byType(TextField), 'ok');
    await tester.pump();
    expect(tester.widget<TextButton>(confirm).onPressed, isNull, reason: 'a note of two characters is not a note');
    await tester.enterText(find.byType(TextField), 'Appelé à 10 h, voix reconnue');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(api.calls, ['activate 1']);
    expect(api.notes.single, 'Appelé à 10 h, voix reconnue');
    expect(find.byKey(const Key('wallet-empty')), findsOneWidget);
  });

  testWidgets('a frozen change shows first, in red words, with no send and no activate, only reject', (tester) async {
    await pump(tester, FakeWallets([change(1, 'pending_confirmation'), change(2, 'frozen', shop: 'Maquis Gelé')]));
    final first = tester.getTopLeft(find.byKey(const Key('wallet-change-2'))).dy;
    final second = tester.getTopLeft(find.byKey(const Key('wallet-change-1'))).dy;
    expect(first, lessThan(second), reason: 'frozen goes to the top');
    expect(find.textContaining('GELÉ'), findsOneWidget);
    expect(find.byKey(const Key('send-2')), findsNothing);
    expect(find.byKey(const Key('activate-2')), findsNothing);
    expect(find.byKey(const Key('reject-2')), findsOneWidget);
  });

  testWidgets('rejecting asks for confirmation and passes the reason', (tester) async {
    final api = FakeWallets([change(1, 'frozen')]);
    await pump(tester, api);
    await tester.tap(find.byKey(const Key('reject-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'le commerçant dit non');
    await tester.tap(find.widgetWithText(TextButton, 'Rejeter').last);
    await tester.pumpAndSettle();
    expect(api.calls, ['reject 1 le commerçant dit non']);
  });

  testWidgets('the trail is readable and holds no codes', (tester) async {
    final events = [
      WalletEvent(at: DateTime.now().toUtc(), actor: '07 •• •• 03 04', action: 'requested'),
      WalletEvent(at: DateTime.now().toUtc(), actor: '07 •• •• 00 01', action: 'code_sent'),
    ];
    await pump(tester, FakeWallets([change(1, 'pending_confirmation', events: events)]));
    await tester.tap(find.text('Historique'));
    await tester.pumpAndSettle();
    expect(find.text('Demande'), findsOneWidget);
    expect(find.text('Code envoyé'), findsOneWidget);
  });

  testWidgets('a legacy or stale admin session gets an explanation, not a raw code', (tester) async {
    final api = FakeWallets([])..error = const ClientErrorException(403, 'forbidden', detail: 'auth_login_required');
    await pump(tester, api);
    expect(find.textContaining('mot de passe et code d’authentification'), findsOneWidget);
    expect(find.textContaining('auth_login_required'), findsNothing);
  });

  test('errors map to words', () {
    String say(String d) => walletChangeErrorMessage(ClientErrorException(409, 'x', detail: d));
    expect(say('frozen_review'), contains('gelé'));
    expect(say('call_note_required'), contains('10 caractères'));
    expect(say('step_up_required'), contains('code d’authentification'));
    expect(say('something_else'), 'something_else');
  });
}
