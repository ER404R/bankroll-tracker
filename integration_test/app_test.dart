import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:felt_ledger/device_services.dart';
import 'package:felt_ledger/session_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:felt_ledger/main.dart';
import 'package:felt_ledger/domain.dart';
import 'package:felt_ledger/repository.dart';
import 'package:felt_ledger/entry_form.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'new form has empty numeric hints and no bankroll or hands input',
    (tester) async {
      final r = await LedgerRepository.open();
      await r.resetAll();
      final banks = await r.definitions('bankroll');
      await tester.pumpWidget(
        MaterialApp(
          home: EntryForm(
            repo: r,
            bankrolls: banks,
            locations: const [],
            games: const [],
            prefs: const {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final input = tester.widget<TextFormField>(
        find.byKey(const ValueKey('buyIn')),
      );
      expect(input.controller!.text, isEmpty);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('buyIn')),
                matching: find.byType(TextField),
              ),
            )
            .decoration!
            .hintText,
        '0,00',
      );
      expect(find.text('Bankroll'), findsNothing);
      expect(find.byKey(const ValueKey('handsPerHour')), findsNothing);
      await tester.tap(find.byTooltip('Spiel erstellen'));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      final fields = find.descendant(
        of: dialog,
        matching: find.byType(TextField),
      );
      expect(fields, findsNWidgets(3));
      await tester.enterText(fields.at(2), '0,10');
      await tester.pump();
      expect(
        tester.widget<TextField>(fields.at(1)).decoration!.hintText,
        '0,05',
      );
      await tester.enterText(fields.at(1), '0,03');
      await tester.enterText(fields.at(2), '0,20');
      await tester.pump();
      expect(tester.widget<TextField>(fields.at(1)).controller!.text, '0,03');
      await tester.enterText(fields.first, 'Synthetic game');
      await tester.tap(find.text('Erstellen'));
      await tester.pumpAndSettle();
      final game = (await r.definitions('game'))
          .where((g) => g['name'] == 'Synthetic game')
          .single;
      expect(game['smallBlind'], amount('0,03'));
      expect(game['bigBlind'], amount('0,20'));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await r.db.close();
    },
  );
  testWidgets(
    'unchanged rounded monetary edit preserves exact historical value',
    (tester) async {
      final r = await LedgerRepository.open();
      await r.resetAll();
      final bank = (await r.definitions('bankroll')).first;
      final e = Entry({
        'id': newId(),
        'bankroll': bank['id'],
        'kind': kinds[4],
        'cashOut': 1234,
        'start': '2026-01-01T10:00:00Z',
        'end': '2026-01-01T11:00:00Z',
      });
      await r.saveEntry(e);
      await tester.pumpWidget(
        MaterialApp(
          initialRoute: '/form',
          routes: {
            '/': (_) => const Scaffold(),
            '/form': (_) => EntryForm(
              repo: r,
              bankrolls: [bank],
              locations: const [],
              games: const [],
              prefs: const {},
              entry: e,
            ),
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('cashOut')))
            .controller!
            .text,
        '0,12',
      );
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect((await r.entries()).single.n('cashOut'), 1234);
      await tester.pumpWidget(const SizedBox());
      await r.db.close();
    },
  );
  testWidgets('Android workflows: forms, reports, live, settings and account', (
    tester,
  ) async {
    final repo = await LedgerRepository.open();
    await repo.resetAll();
    final bank = (await repo.definitions('bankroll')).first;
    final location = {
      'id': newId(),
      'name': 'Testclub Nord',
      'currency': 'EUR',
      'room': 'Home Game',
      'hidden': false,
    };
    final game = {
      'id': newId(),
      'name': 'NL Holdem 0,10/0,20',
      'bigBlind': 2000,
      'smallBlind': 1000,
      'hidden': false,
    };
    await repo.saveDefinition('location', location);
    await repo.saveDefinition('game', game);
    Future<void> pumpApp() async {
      await tester.pumpWidget(LedgerApp(repo: repo));
      await tester.pumpAndSettle();
    }

    Future<void> openPage(String title) async {
      await tester.tap(find.byTooltip('Navigationsmenü öffnen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(title).last);
      await tester.pumpAndSettle();
    }

    await pumpApp();
    expect(find.text('Bereit für deine erste Session?'), findsOneWidget);
    // Cancellation must not create an entry.
    await tester.tap(find.text('Session eintragen').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Abbrechen'));
    await tester.pumpAndSettle();
    expect(await repo.entries(), isEmpty);
    Future<void> choose(String label, String value) async {
      await Scrollable.ensureVisible(
        tester.element(find.text(label.toUpperCase()).last),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      final dropdown = find
          .ancestor(
            of: find.text(label.toUpperCase()).last,
            matching: find.byWidgetPredicate(
              (w) => w is DropdownButtonFormField<String>,
            ),
          )
          .first;
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(value).last);
      await tester.pumpAndSettle();
    }

    // Start is an explicit UI commit; no account or location permission is needed.
    await openPage('Live Session');
    await tester.tap(find.text('Session konfigurieren'));
    await tester.pumpAndSettle();
    await choose('Location', location['name'] as String);
    await choose('Spiel', game['name'] as String);
    await tester.ensureVisible(find.byKey(const ValueKey('buyIn')));
    await tester.enterText(find.byKey(const ValueKey('buyIn')), '10');
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(await repo.state('live'), isNotNull);
    await Scrollable.ensureVisible(
      tester.element(find.text('Verwerfen')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verwerfen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bestätigen'));
    await tester.pumpAndSettle();
    expect(await repo.state('live'), null);
    // Complete every entry type through the real form and persist/reload.
    for (final kind in kinds) {
      final e = Entry({
        'id': newId(),
        'bankroll': bank['id'],
        'currency': 'EUR',
        'kind': kind,
        'location': location['id'],
        'game': game['id'],
        'start': '2026-11-01T10:00:00',
        'end': '2026-11-01T12:00:00',
        'tableSize': 'Short-Handed',
        'buyIn': 100000,
        'cashOut': kind == kinds[1] ? 0 : 250000,
        'rebuys': 1,
        'rebuyCost': 100000,
        'expenses': 10000,
        'chipExpenses': 0,
        'breakSeconds': 600,
        'transfer': kind == kinds[6] ? 500000 : 0,
        'bounty': 0,
        'handsPerHour': 25,
        'events': [],
      });
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          initialRoute: '/form',
          routes: {
            '/': (_) => const Scaffold(),
            '/form': (_) => EntryForm(
              repo: repo,
              bankrolls: [bank],
              locations: [location],
              games: [game],
              entry: e,
              prefs: const {},
            ),
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speichern').last);
      await tester.pumpAndSettle();
      expect(
        (await repo.entries()).any((x) => x.id == e.id),
        true,
        reason: kind,
      );
      expect(tester.takeException(), null);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await pumpApp();
    await openPage('Bankroll');
    expect(find.text('Gesamt').first, findsOneWidget);
    for (final label in [
      'Session',
      'Locations',
      'Diagramme',
      'Trend',
      'Staking',
      'Wartung',
    ]) {
      await tester.ensureVisible(find.widgetWithText(Tab, label.toUpperCase()));
      await tester.tap(find.widgetWithText(Tab, label.toUpperCase()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), null, reason: label);
    }
    await tester.tap(find.byTooltip('Bankroll Filter'));
    await tester.pumpAndSettle();
    expect(find.text('Bankroll Filter'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    // Edit and delete a saved record using its visible controls.
    await tester.ensureVisible(find.widgetWithText(Tab, 'SESSION'));
    await tester.tap(find.widgetWithText(Tab, 'SESSION'));
    await tester.pumpAndSettle();
    final cashId = (await repo.entries())
        .where((e) => e.kind == kinds[0])
        .single
        .id;
    await tester.tap(find.byKey(ValueKey('summary-$cashId')));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('Bearbeiten').first),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bearbeiten').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('cashOut')));
    await tester.enterText(find.byKey(const ValueKey('cashOut')), '31');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(
      (await repo.entries())
          .where((e) => e.kind == kinds[0])
          .single
          .n('cashOut'),
      310000,
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('Löschen').first),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bestätigen'));
    await tester.pumpAndSettle();
    expect((await repo.entries()).length, 6);
    expect((await repo.entries()).where((e) => e.kind == kinds[0]), isEmpty);
    // Native local services: no biometric enrollment is silently enabled.
    await expectLater(
      DeviceServices.authenticate(),
      throwsA(isA<PlatformException>()),
    );
    expect(await DeviceServices.enableNotifications(), true);
    await DeviceServices.remindAt(DateTime.now().add(const Duration(hours: 1)));
    await DeviceServices.cancelReminder();
    // Active live session remains separate from saved history and survives a new app instance.
    final live = Entry({
      'id': newId(),
      'bankroll': bank['id'],
      'currency': 'EUR',
      'kind': kinds[0],
      'location': location['id'],
      'game': game['id'],
      'start': DateTime.now()
          .subtract(const Duration(minutes: 20))
          .toIso8601String(),
      'end': DateTime.now().toIso8601String(),
      'tableSize': 'Short-Handed',
      'buyIn': 100000,
      'breakSeconds': 0,
      'events': [],
    });
    await repo.setState('live', live.data);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await pumpApp();
    await openPage('Live Session');
    expect(find.text('Session läuft'), findsOneWidget);
    await tester.tap(find.text('Pause starten'));
    await tester.pumpAndSettle();
    expect((await repo.state('live'))['pausedAt'], isNotNull);
    await tester.tap(find.text('Fortsetzen'));
    await tester.pumpAndSettle();
    expect((await repo.state('live'))['pausedAt'], isNull);
    await tester.tap(find.text('Rebuy'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('eventValue')), '20');
    await tester.enterText(find.byKey(const ValueKey('resultingStack')), '28');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect((await repo.state('live'))['rebuyCost'], 200000);
    await tester.tap(find.text('Stack aktualisieren'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '45');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(SessionChart));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SessionChart));
    await tester.pumpAndSettle();
    expect(find.text('Erfasste Ereignisse'), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Session beenden'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Session beenden'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('cashOut')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('cashOut')), '50');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(await repo.state('live'), null);
    expect((await repo.entries()).where((e) => e.id == live.id).length, 1);
    await openPage('Settings');
    await tester.tap(find.text('Einstellungen speichern'));
    await tester.pumpAndSettle();
    expect((await repo.state('preferences'))['handsLive'], isNull);
    expect(find.textContaining('Hände/Stunde'), findsNothing);
    expect(tester.takeException(), null);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await openPage('Account');
    expect(find.text('Lokal · Ohne Server'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(tester.takeException(), null);
    await repo.saveEntry(
      Entry({
        ...live.data,
        'id': newId(),
        'start': '2026-10-01T10:00:00Z',
        'end': '2026-10-01T12:00:00Z',
        'cashOut': 400000,
        'events': [],
      }),
    );
    await repo.saveEntry(
      Entry({
        ...live.data,
        'id': newId(),
        'start': '2026-10-02T10:00:00Z',
        'end': '2026-10-02T12:00:00Z',
        'cashOut': 0,
        'events': [],
      }),
    );
    // Leave a durable synthetic live fixture for external process-death validation.
    await repo.setState('live', {
      ...live.data,
      'id': newId(),
      'note': 'Emulator recovery fixture',
    });
  });
}
