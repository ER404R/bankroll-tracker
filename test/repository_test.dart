import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:felt_ledger/domain.dart';
import 'package:felt_ledger/repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test(
    'durable entries, atomic validation, FK integrity, live finish idempotence',
    () async {
      final repo = await LedgerRepository.open(path: inMemoryDatabasePath);
      final bank = (await repo.definitions('bankroll')).first;
      final e = Entry({
        'id': newId(),
        'bankroll': bank['id'],
        'kind': kinds[0],
        'start': '2026-01-01T10:00:00',
        'end': '2026-01-01T11:00:00',
        'cashOut': 0,
        'buyIn': 100000,
        'note': 'test',
      });
      expect(await repo.entries(), isEmpty);
      await repo.saveEntry(e);
      expect((await repo.entries()).single.profit(), -100000);
      await repo.setState('preferences', {'handsLive': 33});
      expect((await repo.state('preferences'))['handsLive'], 33);
      final invalid = Entry({...e.data, 'id': newId(), 'buyIn': -1});
      await expectLater(
        repo.bulkUpdate([
          Entry({...e.data, 'note': 'changed'}),
          invalid,
        ]),
        throwsFormatException,
      );
      expect((await repo.entries()).single.s('note'), 'test');
      await expectLater(
        repo.saveEntry(
          Entry({...e.data, 'id': newId(), 'bankroll': 'missing'}),
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect((await repo.entries()).length, 1);
      final live = Entry({
        ...e.data,
        'id': newId(),
        'events': [
          {'kind': 'rebuy', 'at': '2026-01-01T10:30:00', 'value': 20000},
        ],
      });
      await repo.setState('live', live.data);
      expect((await repo.state('live'))['id'], live.id);
      await repo.finishLive(live);
      await repo.finishLive(live);
      expect((await repo.entries()).length, 2);
      expect(await repo.state('live'), null);
      await repo.deleteEntry(e.id);
      expect((await repo.entries()).length, 1);
      await repo.clearLocal();
      expect(await repo.entries(), isEmpty);
      expect((await repo.definitions('bankroll')).length, 1);
      await repo.db.close();
    },
  );
  test('disk reopen preserves unknown fields, events, preferences and live recovery', () async {
    final dir = await Directory.systemTemp.createTemp('felt-ledger-test-');
    final path = '${dir.path}/ledger.db';
    var repo = await LedgerRepository.open(path: path);
    final bank = (await repo.definitions('bankroll')).first;
    final payload = {
      'id': newId(),
      'bankroll': bank['id'],
      'kind': kinds[2],
      'start': '2026-01-01T23:00:00+01:00',
      'end': '2026-01-02T01:00:00+01:00',
      'buyIn': 123456,
      'cashOut': 0,
      'futureSourceField': {'original': 'preserved'},
      'events': [
        {
          'at': '2026-01-02T00:00:00+01:00',
          'kind': 'note',
          'note': 'Line 1\nLine 2',
        },
      ],
    };
    await repo.saveEntry(Entry(payload));
    await repo.setState('live', payload);
    await repo.setState('preferences', {'theme': 'Hell'});
    await repo.db.close();
    repo = await LedgerRepository.open(path: path);
    expect((await repo.entries()).single.data['futureSourceField'], {
      'original': 'preserved',
    });
    expect(
      (await repo.entries()).single.events.single['note'],
      'Line 1\nLine 2',
    );
    expect((await repo.state('live'))['id'], payload['id']);
    expect((await repo.state('preferences'))['theme'], 'Hell');
    await repo.db.close();
    await dir.delete(recursive: true);
  });
  test('bulk foreign-key failure rolls back all changes and definitions merge retains entries', () async {
    final repo = await LedgerRepository.open(path: inMemoryDatabasePath);
    final bank = (await repo.definitions('bankroll')).first;
    final one = {'id': newId(), 'name': 'One', 'currency': 'EUR'};
    final two = {'id': newId(), 'name': 'Two', 'currency': 'EUR'};
    await repo.saveDefinition('location', one);
    await repo.saveDefinition('location', two);
    final a = Entry({
      'id': newId(),
      'bankroll': bank['id'],
      'kind': kinds[0],
      'start': '2026-01-01T10:00:00',
      'end': '2026-01-01T11:00:00',
      'note': 'before',
      'location': one['id'],
    });
    await repo.saveEntry(a);
    final b = Entry({...a.data, 'id': newId()});
    await repo.saveEntry(b);
    await expectLater(
      repo.bulkUpdate([
        Entry({...a.data, 'note': 'partial'}),
        Entry({...b.data, 'bankroll': 'missing'}),
      ]),
      throwsA(isA<DatabaseException>()),
    );
    expect((await repo.entries()).every((e) => e.s('note') == 'before'), true);
    await repo.replaceDefinition('location', one, mergeInto: two['id']);
    expect(
      (await repo.entries()).every((e) => e.s('location') == two['id']),
      true,
    );
    expect((await repo.definitions('location')).length, 1);
    await repo.deleteDefinitionAndEntries('location', two['id']!);
    expect(await repo.entries(), isEmpty);
    await repo.resetAll();
    expect((await repo.definitions('bankroll')).single['opening'], 0);
    await repo.db.close();
  });
  test('live start is atomic and stale finish does not delete a newer active session', () async {
    final repo = await LedgerRepository.open(path: inMemoryDatabasePath);
    final bank = (await repo.definitions('bankroll')).first;
    final first = Entry({
      'id': newId(),
      'bankroll': bank['id'],
      'kind': kinds[0],
      'start': '2026-01-01T10:00:00',
      'end': '2026-01-01T11:00:00',
    });
    final second = Entry({...first.data, 'id': newId()});
    await repo.startLive(first);
    await expectLater(repo.startLive(second), throwsFormatException);
    expect((await repo.state('live'))['id'], first.id);
    await repo.finishLive(first);
    await repo.startLive(second);
    await repo.finishLive(first);
    expect((await repo.state('live'))['id'], second.id);
    expect((await repo.entries()).length, 1);
    await repo.db.close();
  });
  test(
    'game default edits preserve historic blind metrics, money and IDs',
    () async {
      final repo = await LedgerRepository.open(path: inMemoryDatabasePath);
      final bank = (await repo.definitions('bankroll')).first;
      final game = {'id': newId(), 'name': 'Test NL', 'bigBlind': 1000};
      await repo.saveDefinition('game', game);
      final entry = Entry({
        'id': newId(),
        'bankroll': bank['id'],
        'kind': kinds[0],
        'game': game['id'],
        'bigBlind': 1000,
        'start': '2026-01-01T10:00:00',
        'end': '2026-01-01T11:00:00',
        'buyIn': 100000,
        'cashOut': 200000,
      });
      await repo.saveEntry(entry);
      expect(Totals(await repo.entries()).bb, 100);
      await repo.replaceDefinition('game', {...game, 'bigBlind': 2000});
      final saved = (await repo.entries()).single;
      expect(saved.id, entry.id);
      expect(saved.profit(), 100000);
      expect(Totals([saved]).bb, 100);
      expect(saved.n('bigBlind'), 1000);
      await repo.db.close();
    },
  );
  test(
    'game archive and merge preserve legacy blinds, entries and active session',
    () async {
      final repo = await LedgerRepository.open(path: inMemoryDatabasePath);
      addTearDown(repo.db.close);
      final bank = (await repo.definitions('bankroll')).single;
      final original = {
        'id': newId(),
        'name': 'Texas Holdem',
        'limit': 'NL',
        'bigBlind': 2000,
        'smallBlind': 500,
      };
      final target = {
        'id': newId(),
        'name': 'Other',
        'limit': 'NL',
        'bigBlind': 100000,
        'smallBlind': 50000,
      };
      await repo.saveDefinition('game', original);
      await repo.saveDefinition('game', target);
      final legacy = Entry({
        'id': newId(),
        'bankroll': bank['id'],
        'kind': kinds[0],
        'game': original['id'],
        'start': '2026-01-01T10:00:00',
        'end': '2026-01-01T11:00:00',
        'buyIn': 200000,
        'cashOut': 300000,
      });
      await repo.saveEntry(legacy);
      await repo.startLive(
        Entry({
          ...legacy.data,
          'id': newId(),
          'smallBlind': 700,
          'bigBlind': 3000,
        }),
      );
      await repo.replaceDefinition('game', {
        ...original,
        'name': 'Renamed',
        'bigBlind': 10000,
      });
      final frozen = (await repo.entries()).single;
      expect(frozen.n('bigBlind'), 2000);
      expect(frozen.n('smallBlind'), 500);
      expect((await repo.state('live'))['bigBlind'], 3000);
      await repo.deleteDefinitionAndEntries('game', original['id'] as String);
      expect((await repo.entries()).length, 1);
      expect(
        (await repo.definitions('game'))
            .singleWhere((g) => g['id'] == original['id'])['hidden'],
        true,
      );
      final archived = (await repo.definitions('game'))
          .singleWhere((g) => g['id'] == original['id']);
      await repo.replaceDefinition('game', {...archived, 'hidden': false});
      expect(
        (await repo.definitions('game'))
            .singleWhere((g) => g['id'] == original['id'])['hidden'],
        false,
      );
      await repo.replaceDefinition(
        'game',
        archived,
        mergeInto: target['id'] as String,
      );
      final merged = (await repo.entries()).single;
      expect(merged.id, legacy.id);
      expect(merged.profit(), 100000);
      expect(merged.n('bigBlind'), 2000);
      expect(merged.n('smallBlind'), 500);
      expect(merged.s('game'), target['id']);
      expect((await repo.state('live'))['game'], target['id']);
      expect((await repo.state('live'))['smallBlind'], 700);
      expect((await repo.state('live'))['bigBlind'], 3000);
      expect((await repo.definitions('game')).length, 1);
      await expectLater(
        repo.replaceDefinition('game', target, mergeInto: 'missing'),
        throwsFormatException,
      );
      expect((await repo.entries()).single.data, merged.data);
    },
  );
  test(
    'game edit freezes missing small blind from historical explicit big blind',
    () async {
      final repo = await LedgerRepository.open(path: inMemoryDatabasePath);
      addTearDown(repo.db.close);
      final bank = (await repo.definitions('bankroll')).single;
      final game = {
        'id': newId(),
        'name': 'Texas Holdem',
        'bigBlind': 2000,
        'currency': 'EUR',
      };
      await repo.saveDefinition('game', game);
      final e = Entry({
        'id': newId(),
        'bankroll': bank['id'],
        'kind': kinds[0],
        'game': game['id'],
        'bigBlind': 4000,
        'start': '2026-01-01T10:00:00',
        'end': '2026-01-01T11:00:00',
      });
      await repo.saveEntry(e);
      await repo.replaceDefinition('game', {...game, 'name': 'Renamed'});
      expect((await repo.entries()).single.n('smallBlind'), 2000);
      final target = {'id': newId(), 'name': 'USD game', 'currency': 'USD'};
      await repo.saveDefinition('game', target);
      await expectLater(
        repo.replaceDefinition('game', game, mergeInto: target['id'] as String),
        throwsFormatException,
      );
      expect((await repo.entries()).single.s('game'), game['id']);
    },
  );
}
