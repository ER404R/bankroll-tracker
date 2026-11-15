import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:felt_ledger/domain.dart';
import 'package:felt_ledger/entry_form.dart';
import 'package:felt_ledger/repository.dart';

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryRepo extends LedgerRepository {
  _MemoryRepo() : super(_UnusedDatabase());
  final Map<String, List<Json>> defs = {
    'bankroll': [
      {'id': 'bank', 'currency': 'EUR'},
    ],
  };
  Json? active;
  @override
  Future<List<Json>> definitions(String category) async => defs[category] ?? [];
  @override
  Future<void> saveDefinition(String category, Json data) async {
    defs.putIfAbsent(category, () => []).add(data);
  }

  @override
  Future<dynamic> state(String key) async => key == 'live' ? active : null;
  @override
  Future<void> startLive(Entry entry) async {
    entry.validate();
    active = entry.data;
  }

  @override
  Future<List<Entry>> entries() async => [];
}

void main() {
  testWidgets(
    'embedded setup displays inputs immediately and starts atomically without popping route',
    (tester) async {
      final repo = _MemoryRepo();
      final banks = await repo.definitions('bankroll');
      final location = {
        'id': 'loc',
        'name': 'Test room',
        'room': 'Home Game',
        'currency': 'EUR',
      };
      final game = {
        'id': 'game',
        'name': 'Texas Holdem',
        'smallBlind': 500,
        'bigBlind': 1000,
        'limit': 'NL',
        'currency': 'EUR',
      };
      await repo.saveDefinition('location', location);
      await repo.saveDefinition('game', game);
      var saved = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EntryForm(
              repo: repo,
              bankrolls: banks,
              locations: [location],
              games: [game],
              prefs: {},
              embedded: true,
              live: true,
              onSaved: () async {
                saved = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Session konfigurieren'), findsNothing);
      expect(find.byKey(const ValueKey('buyIn')), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('buyIn')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.byKey(const ValueKey('inline-start')), findsOneWidget);
      expect(await repo.state('live'), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('inline-start')));
      await tester.tap(find.byKey(const ValueKey('inline-start')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Bitte Location'), findsOneWidget);
      expect(await repo.state('live'), isNull);
      for (final label in ['Location wählen', 'Spiel wählen']) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(
          find.byWidgetPredicate(
            (w) =>
                w is DropdownButtonFormField<String> &&
                w.key.toString().contains(
                  label.startsWith('Location') ? 'location-' : 'game-',
                ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .textContaining(
                label.startsWith('Location') ? 'Test room' : '0,05/0,10',
              )
              .last,
        );
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byKey(const ValueKey('buyIn')), '12,50');
      await tester.ensureVisible(find.byKey(const ValueKey('inline-start')));
      await tester.tap(find.byKey(const ValueKey('inline-start')));
      await tester.pumpAndSettle();
      expect(saved, isTrue);
      expect(find.byType(EntryForm), findsOneWidget);
      final active = Entry(Map<String, dynamic>.from(await repo.state('live')));
      expect(active.n('buyIn'), 125000);
      expect(active.n('smallBlind'), 500);
      expect(active.n('bigBlind'), 1000);
      expect(await repo.entries(), isEmpty);
    },
  );
  testWidgets(
    'cancel game creation restores choice and never creates a live session',
    (tester) async {
      final repo = _MemoryRepo();
      await tester.pumpWidget(
        MaterialApp(
          home: EntryForm(
            repo: repo,
            bankrolls: await repo.definitions('bankroll'),
            locations: [],
            games: [],
            prefs: {},
            embedded: true,
            live: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.key.toString().contains('game-'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ Spiel erstellen').last);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(find.text('Spiel wählen'), findsOneWidget);
      expect(await repo.definitions('game'), isEmpty);
      expect(await repo.state('live'), isNull);
    },
  );
  testWidgets(
    'manual draft reloads game definitions after management returns',
    (tester) async {
      final repo = _MemoryRepo();
      final oldGame = <String, dynamic>{
        'id': 'game',
        'name': 'Before',
        'limit': 'NL',
        'smallBlind': 500,
        'bigBlind': 1000,
      };
      repo.defs['game'] = [oldGame];
      await tester.pumpWidget(
        MaterialApp(
          home: EntryForm(
            repo: repo,
            bankrolls: await repo.definitions('bankroll'),
            locations: [],
            games: [oldGame],
            prefs: {},
            onManageGames: () async {
              repo.defs['game'] = [
                {
                  'id': 'new',
                  'name': 'After',
                  'limit': 'NL',
                  'smallBlind': 1000,
                  'bigBlind': 2000,
                },
              ];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Spiele verwalten'));
      await tester.tap(find.text('Spiele verwalten'));
      await tester.pumpAndSettle();
      final selector = find.ancestor(
        of: find.text('Spiel wählen'),
        matching: find.byType(DropdownButtonFormField<String>),
      );
      await Scrollable.ensureVisible(tester.element(selector), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(find.textContaining('0,10/0,20 NL After'), findsOneWidget);
      expect(find.textContaining('Before'), findsNothing);
      expect(await repo.state('live'), isNull);
    },
  );
}
