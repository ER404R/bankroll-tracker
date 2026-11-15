import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:felt_ledger/domain.dart';
import 'package:felt_ledger/entry_form.dart';
import 'package:felt_ledger/repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('tournament creation and live recovery use typed games', (
    tester,
  ) async {
    // Isolated synthetic database; never reset the installed app's ledger.
    final repo = await LedgerRepository.open(
      path: '${await getDatabasesPath()}/tournament-validation-${newId()}.db',
    );
    final banks = await repo.definitions('bankroll');
    final location = <String, dynamic>{
      'id': 'loc',
      'name': 'Synthetic room',
      'currency': 'EUR',
    };
    await repo.saveDefinition('location', location);
    await repo.saveDefinition('game', {
      'id': 'cash',
      'name': 'Cash only',
      'gameType': 'cash_game',
      'bigBlind': 20000,
    });
    Finder gameSelector() => find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<String> &&
          w.key.toString().contains('game-'),
    );
    Future<void> choose(Finder finder, String label) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await tester.pumpAndSettle();
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
      expect(
        find.text(label),
        findsWidgets,
        reason: 'Dropdown must expose $label',
      );
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    Future<void> form({bool live = false, Entry? entry}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EntryForm(
            key: UniqueKey(),
            repo: repo,
            bankrolls: banks,
            locations: [location],
            games: await repo.definitions('game'),
            prefs: const {},
            embedded: true,
            live: live,
            entry: entry,
            onSaved: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await form(live: true);
    await choose(find.byKey(const ValueKey('kind')), 'Turnier');
    await tester.ensureVisible(gameSelector());
    await tester.tap(gameSelector());
    await tester.pumpAndSettle();
    expect(find.textContaining('Cash only'), findsNothing);
    await tester.tap(find.text('+ Spiel erstellen').last);
    await tester.pumpAndSettle();
    expect(find.text('Turnierspiel erstellen'), findsOneWidget);
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.first, 'Synthetic tournament');
    await tester.tap(find.text('Erstellen').last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Turnier · NL Synthetic tournament'),
      findsOneWidget,
    );
    final games = await repo.definitions('game');
    expect(
      games
          .where((g) => g['name'] == 'Synthetic tournament')
          .single['gameType'],
      'tournament',
    );
    await choose(
      find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.key.toString().contains('location-'),
      ),
      'Synthetic room (Home Game • EUR)',
    );
    await tester.enterText(find.byKey(const ValueKey('buyIn')), '50,00');
    await tester.ensureVisible(find.byKey(const ValueKey('inline-start')));
    await tester.tap(find.byKey(const ValueKey('inline-start')));
    await tester.pumpAndSettle();
    final active = Entry(Map<String, dynamic>.from(await repo.state('live')));
    expect(active.kind, 'Turnier');
    expect(active.n('buyIn'), amount('50'));
    await repo.recordPurchase(active.id, 'rebuy', amount('50'), amount('120'));
    final path = repo.db.path;
    await repo.db.close();
    final reopened = await LedgerRepository.open(path: path);
    final recovered = Entry(
      Map<String, dynamic>.from(await reopened.state('live')),
    );
    expect(recovered.n('rebuyCost'), amount('50'));
    await reopened.finishLive(
      Entry({
        ...recovered.data,
        'end': DateTime.now().toUtc().toIso8601String(),
        'cashOut': amount('150'),
      }),
    );
    expect((await reopened.entries()).single.profit(), amount('50'));
    await tester.pumpWidget(const SizedBox());
    await reopened.db.close();
    await deleteDatabase(path);
  });
}
