import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:felt_ledger/domain.dart';
import 'package:felt_ledger/entry_form.dart';
import 'package:felt_ledger/game_label.dart';
import 'package:felt_ledger/repository.dart';

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingRepo extends LedgerRepository {
  _RecordingRepo() : super(_UnusedDatabase());
  Entry? saved;
  @override
  Future<void> saveEntry(Entry entry) async => saved = entry;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test('legacy types derive from session usage without rewriting records or definitions', () async {
    final repo = await LedgerRepository.open(path: inMemoryDatabasePath);
    final bank = (await repo.definitions('bankroll')).first;
    for (final id in ['cash', 'tour', 'mixed', 'unused', 'live']) {
      await repo.saveDefinition('game', {
        'id': id,
        'name': 'Holdem',
        'bigBlind': 0,
        'smallBlind': 0,
      });
    }
    Entry entry(String id, String game, String kind) => Entry({
      'id': id,
      'game': game,
      'kind': kind,
      'bankroll': bank['id'],
      'start': '2026-01-01T10:00:00Z',
      'end': '2026-01-01T11:00:00Z',
      'buyIn': 100001,
      'cashOut': 250003,
    });
    await repo.saveEntry(entry('1', 'cash', 'Cash Game'));
    await repo.saveEntry(entry('2', 'tour', 'Turnier'));
    await repo.saveEntry(entry('3', 'tour', 'Mehrtages Turnier'));
    await repo.saveEntry(entry('4', 'mixed', 'Cash Game'));
    await repo.saveEntry(entry('5', 'mixed', 'Turnier'));
    await repo.startLive(entry('6', 'live', 'Turnier'));
    final beforeEntries = await repo.db.query('entries');
    final beforeDefinitions = await repo.db.query('definitions');
    final games = {
      for (final game in await repo.definitions('game')) game['id']: game,
    };
    expect(games['tour']!['gameType'], 'tournament');
    expect(games['live']!['gameType'], 'tournament');
    for (final id in ['cash', 'mixed', 'unused']) {
      expect(games[id]!['gameType'], 'cash_game');
    }
    expect(gameDefinitionLabel(games['tour']!), 'Turnier · NL Holdem');
    expect(gameMatchesSession(games['tour']!, 'Cash Game'), isFalse);
    expect(gameMatchesSession(games['tour']!, 'Mehrtages Turnier'), isTrue);
    expect(await repo.db.query('entries'), beforeEntries);
    expect(await repo.db.query('definitions'), beforeDefinitions);
    await expectLater(
      repo.replaceDefinition('game', games['cash']!, mergeInto: 'tour'),
      throwsFormatException,
    );
    expect(await repo.db.query('entries'), beforeEntries);
    await repo.db.close();
  });
  testWidgets(
    'existing mixed-use tournament remains editable without converting its game or amounts',
    (tester) async {
      final repo = _RecordingRepo();
      final entry = Entry({
        'id': 'legacy',
        'kind': 'Turnier',
        'bankroll': 'bank',
        'currency': 'EUR',
        'location': 'loc',
        'game': 'mixed',
        'smallBlind': 1234,
        'bigBlind': 4567,
        'buyIn': 101234,
        'cashOut': 205678,
        'start': '2026-01-01T10:00:00Z',
        'end': '2026-01-01T11:00:00Z',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: EntryForm(
            repo: repo,
            entry: entry,
            embedded: true,
            bankrolls: const [
              {'id': 'bank', 'currency': 'EUR'},
            ],
            locations: const [
              {'id': 'loc', 'name': 'Test room', 'currency': 'EUR'},
            ],
            games: const [
              {
                'id': 'mixed',
                'name': 'Shared legacy game',
                'gameType': 'cash_game',
                'bigBlind': 0,
              },
            ],
            prefs: const {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Shared legacy game'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('inline-start')));
      await tester.tap(find.byKey(const ValueKey('inline-start')));
      await tester.pumpAndSettle();
      expect(repo.saved, isNotNull);
      for (final key in [
        'game',
        'buyIn',
        'cashOut',
        'smallBlind',
        'bigBlind',
      ]) {
        expect(repo.saved!.data[key], entry.data[key]);
      }
    },
  );
  testWidgets(
    'manual and live selectors separate games and clear a selection when kind changes',
    (tester) async {
      for (final live in [false, true]) {
        final repo = LedgerRepository(_UnusedDatabase());
        final banks = <Json>[
          {'id': 'bank', 'currency': 'EUR'},
        ];
        await tester.pumpWidget(
          MaterialApp(
            home: EntryForm(
              key: ValueKey(live),
              repo: repo,
              bankrolls: banks,
              locations: const [],
              games: const [
                {
                  'id': 'cash',
                  'name': 'Cash variant',
                  'gameType': 'cash_game',
                  'bigBlind': 20000,
                },
                {
                  'id': 'tour',
                  'name': 'Tournament variant',
                  'gameType': 'tournament',
                  'bigBlind': 0,
                },
              ],
              prefs: const {},
              live: live,
            ),
          ),
        );
        await tester.pumpAndSettle();
        Finder selector() => find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.key.toString().contains('game-'),
        );
        await tester.ensureVisible(selector());
        await tester.tap(selector());
        await tester.pumpAndSettle();
        expect(find.textContaining('Tournament variant'), findsNothing);
        await tester.tap(find.textContaining('Cash variant').last);
        await tester.pumpAndSettle();
        final kind = find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.key == const ValueKey('kind'),
        );
        await tester.ensureVisible(kind);
        await tester.tap(kind);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Turnier').last);
        await tester.pumpAndSettle();
        expect(find.textContaining('Cash variant'), findsNothing);
        await tester.ensureVisible(selector());
        await tester.tap(selector());
        await tester.pumpAndSettle();
        expect(find.textContaining('Cash variant'), findsNothing);
        expect(find.text('Turnier · NL Tournament variant'), findsOneWidget);
        await tester.tap(find.text('Turnier · NL Tournament variant'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
