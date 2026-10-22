import 'package:fidelia_admin/core/accounts/accounts_api.dart';
import 'package:fidelia_admin/core/accounts/models.dart';
import 'package:fidelia_admin/core/net/api_exception.dart';
import 'package:fidelia_admin/core/providers.dart';
import 'package:fidelia_admin/features/home_screen.dart';
import 'package:fidelia_admin/features/whatsapp.dart';
import 'package:fidelia_admin/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AccountCheck check(
  int id,
  String kind, {
  String app = 'user',
  bool sent = false,
  bool team = false,
  String phone = '+225 ** ** 12',
  Duration age = const Duration(hours: 3),
}) =>
    AccountCheck(
      id: id,
      kind: kind,
      app: app,
      phoneMasked: phone,
      createdAt: DateTime.now().toUtc().subtract(age),
      sentAt: sent ? DateTime.now().toUtc() : null,
      teamCreated: team,
    );

class FakeAccounts implements AccountsApi {
  FakeAccounts(this.rows);

  Map<String, List<AccountCheck>> rows;
  Object? sendError;
  Object? refuseError;
  final sent = <int>[];
  final refused = <int>[];
  int loads = 0;

  @override
  Future<List<AccountCheck>> checks(String kind) async {
    loads++;
    return List.of(rows[kind] ?? const []);
  }

  @override
  Future<Uri> send(int id) async {
    if (sendError != null) throw sendError!;
    sent.add(id);
    return Uri.parse('https://wa.me/2250700000000?text=secret');
  }

  @override
  Future<void> refuse(int id) async {
    if (refuseError != null) throw refuseError!;
    refused.add(id);
    for (final list in rows.values) {
      list.removeWhere((c) => c.id == id);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeAccounts api;
  late List<Uri> opened;
  bool launchResult = true;

  Future<void> pump(WidgetTester tester) async {
    opened = [];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        accountsApiProvider.overrideWithValue(api),
        whatsappLauncherProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return launchResult;
        }),
      ],
      child: MaterialApp(theme: fideliaTheme(), home: const HomeScreen()),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() {
    launchResult = true;
    api = FakeAccounts({
      'verify_number': [check(1, 'verify_number'), check(2, 'verify_number', app: 'merchant', age: const Duration(days: 2))],
      'change_number': [check(3, 'change_number', age: const Duration(hours: 5))],
      'reset_password': [
        check(4, 'reset_password'),
        check(5, 'reset_password', team: true, app: 'merchant'),
        check(6, 'reset_password', team: true),
      ],
    });
  });

  testWidgets('lists are split by kind and origin', (tester) async {
    await pump(tester);
    expect(find.text('Numéros à vérifier'), findsOneWidget);
    expect(find.text('Mots de passe oubliés'), findsOneWidget);
    expect(find.text('Identifiants commerçant'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('card-verify')), matching: find.text('3')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('card-forgot')), matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('card-team')), matching: find.text('2')), findsOneWidget);

    await tester.tap(find.text('Numéros à vérifier'));
    await tester.pumpAndSettle();
    // Oldest first: id 2 (2 days), then 3 (5 h), then 1 (3 h).
    final ids = tester.widgetList<Card>(find.byType(Card)).map((c) => (c.key as ValueKey).value).toList();
    expect(ids, [2, 3, 1]);
    expect(find.text('Fidelia Pro'), findsOneWidget);
    expect(find.text('Nouveau numéro'), findsOneWidget);
    expect(find.text('il y a 2 j'), findsOneWidget);
    expect(find.text('Envoyer le code sur WhatsApp'), findsNWidgets(3));

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mots de passe oubliés'));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsOneWidget);
    expect(find.text('Envoyer un mot de passe temporaire sur WhatsApp'), findsOneWidget);
  });

  testWidgets('sent checks say so and offer to resend', (tester) async {
    api.rows['verify_number'] = [check(1, 'verify_number', sent: true)];
    await pump(tester);
    await tester.tap(find.text('Numéros à vérifier'));
    await tester.pumpAndSettle();
    expect(find.text('Code déjà envoyé'), findsOneWidget);
    expect(find.text('Renvoyer le code sur WhatsApp'), findsOneWidget);
  });

  testWidgets('send opens the WhatsApp link and refreshes', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Mots de passe oubliés'));
    await tester.pumpAndSettle();
    final before = api.loads;
    await tester.tap(find.text('Envoyer un mot de passe temporaire sur WhatsApp'));
    await tester.pumpAndSettle();
    expect(api.sent, [4]);
    expect(opened.single.host, 'wa.me');
    expect(api.loads, greaterThan(before));
  });

  testWidgets('WhatsApp failing shows the message and refreshes', (tester) async {
    launchResult = false;
    await pump(tester);
    await tester.tap(find.text('Mots de passe oubliés'));
    await tester.pumpAndSettle();
    final before = api.loads;
    await tester.tap(find.text('Envoyer un mot de passe temporaire sur WhatsApp'));
    await tester.pumpAndSettle();
    expect(find.text("WhatsApp n'a pas pu s'ouvrir."), findsOneWidget);
    expect(api.loads, greaterThan(before));
  });

  testWidgets('already handled shows the message and refreshes', (tester) async {
    api.sendError = const AlreadyHandled();
    await pump(tester);
    await tester.tap(find.text('Mots de passe oubliés'));
    await tester.pumpAndSettle();
    final before = api.loads;
    await tester.tap(find.text('Envoyer un mot de passe temporaire sur WhatsApp'));
    await tester.pumpAndSettle();
    expect(find.text('Cette demande est déjà traitée.'), findsOneWidget);
    expect(opened, isEmpty);
    expect(api.loads, greaterThan(before));
  });

  testWidgets('server message is shown when the account is suspended', (tester) async {
    api.sendError = const AlreadyHandled('Compte suspendu.');
    await pump(tester);
    await tester.tap(find.text('Mots de passe oubliés'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Envoyer un mot de passe temporaire sur WhatsApp'));
    await tester.pumpAndSettle();
    expect(find.text('Compte suspendu.'), findsOneWidget);
  });

  testWidgets('other API errors show their message', (tester) async {
    api.sendError = const NetworkException('Pas de connexion.');
    await pump(tester);
    await tester.tap(find.text('Mots de passe oubliés'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Envoyer un mot de passe temporaire sur WhatsApp'));
    await tester.pumpAndSettle();
    expect(find.text('Pas de connexion.'), findsOneWidget);
  });

  testWidgets('refuse needs confirmation', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Mots de passe oubliés'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Refuser'));
    await tester.pumpAndSettle();
    expect(find.text('Refuser cette demande ?'), findsOneWidget);
    expect(find.text('La demande sera close.'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(api.refused, isEmpty);

    await tester.tap(find.text('Refuser'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Refuser')));
    await tester.pumpAndSettle();
    expect(api.refused, [4]);
    expect(find.text('Rien à traiter'), findsOneWidget);
  });

  testWidgets('refusing a number explains what the person sees', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Numéros à vérifier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refuser').first);
    await tester.pumpAndSettle();
    expect(
      find.text("La personne verra que son numéro n'a pas pu être vérifié et pourra le corriger."),
      findsOneWidget,
    );
  });

  testWidgets('empty list says « Rien à traiter »', (tester) async {
    api.rows = {};
    await pump(tester);
    await tester.tap(find.text('Numéros à vérifier'));
    await tester.pumpAndSettle();
    expect(find.text('Rien à traiter'), findsOneWidget);
  });
}
