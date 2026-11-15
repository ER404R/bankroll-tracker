import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:felt_ledger/domain.dart';
import 'package:felt_ledger/import_format.dart';
import 'package:felt_ledger/import_repository.dart';
import 'package:felt_ledger/repository.dart';

Json sample({String id = 'cash-1'}) => {
  'sourceId': id,
  'kind': 'cash_game',
  'currency': 'EUR',
  'date': '2025-03-04',
  'start': '2025-03-04T21:00',
  'end': '2025-03-05T01:00',
  'durationSeconds': 10800,
  'tableSize': 'Short-Handed',
  'location': {'name': 'Test Room', 'room': 'Home Game'},
  'game': {
    'name': 'Texas Holdem',
    'limit': 'NL',
    'smallBlind': '0.05',
    'bigBlind': '0.10',
  },
  'money': {
    'buyIn': '10.1234',
    'cashOut': '30.5678',
    'rebuyCost': '5',
    'addonCost': '2',
    'bounty': '0',
  },
  'result': '13.4444',
  'note': 'Synthetic note\nwith a newline',
  'sourceRecord': {
    'history_events_display': [
      {
        'time_display': '22:00',
        'source_fragments': ['unknown detail'],
      },
    ],
    'unknown': 'preserve me',
  },
};
Json envelope(List<Json> records, {String source = 'synthetic-source'}) => {
  'format': 'bankroll-tracker-import',
  'version': 1,
  'source': {'id': source, 'name': 'Synthetic fixture'},
  'currency': 'EUR',
  'coverage': {
    'sessions': 'mapped',
    'events': 'preserved-only',
    'settings': 'missing',
  },
  'warnings': ['Synthetic partial capture'],
  'expected': {
    'count': records.length,
    'balanceEffect': decimal(records.fold(0, (s, r) => s + amount(r['result'])))
        .replaceAll(',', '.'),
  },
  'records': records,
  'unknownRoot': {
    'retain': [1, 2, 3],
  },
};
ImportDocument document(Json data) =>
    ImportDocument.parse(utf8.encode(jsonEncode(data)));

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test('imported tournament definitions have a distinct type and no cash-stakes label', () async {
    final cash = sample();
    final tournament = sample(id: 'tournament-1')..['kind'] = 'tournament';
    tournament['game'] = {
      ...(tournament['game'] as Map),
      'smallBlind': '0',
      'bigBlind': '0',
    };
    final doc = ImportDocument.parse(
      utf8.encode(jsonEncode(envelope([cash, tournament]))),
    );
    expect(doc.records[0].game['gameType'], 'cash_game');
    expect(doc.records[1].game['gameType'], 'tournament');
    final repo = await LedgerRepository.open(path: inMemoryDatabasePath);
    final imports = ImportRepository(repo);
    final batch = await imports.commit(await imports.preview(doc));
    final games = await repo.definitions('game');
    expect(games.map((g) => g['gameType']).toSet(), {
      'cash_game',
      'tournament',
    });
    expect(
      (await repo.entries())
          .where((e) => e.kind == 'Turnier')
          .single
          .n('buyIn'),
      amount('10.1234'),
    );
    await imports.rollback(batch);
    expect(await repo.entries(), isEmpty);
    await repo.db.close();
  });
  test('format preserves decimal precision, original data, duration and overnight times', () {
    final doc = document(envelope([sample()]));
    final e = doc.records.single.materialize('a', 'b', 'c', 'd', 'e', 's');
    expect(e.profit(), 134444);
    expect(e.n('buyIn'), 101234);
    expect(e.seconds, 10800);
    expect(e.n('breakSeconds'), 0);
    expect(e.end.day, 5);
    expect(e.events, isEmpty);
    expect(e.data['sourceRecord']['sourceRecord']['unknown'], 'preserve me');
    expect(doc.data['unknownRoot'], {
      'retain': [1, 2, 3],
    });
  });
  test('malformed dates, amounts, mixed currencies, duplicate IDs and mismatched totals reject entire file', () {
    final variants = <Json>[
      {
        ...envelope([sample()]),
        'version': 2,
      },
      envelope([sample(), sample()]),
      envelope([
        {...sample(), 'currency': 'USD'},
      ]),
      envelope([
        {...sample(), 'date': '2025-02-30'},
      ]),
      envelope([
        {...sample(), 'start': '2025-03-04T25:00'},
      ]),
      envelope([
        {...sample(), 'end': '2025-03-03T20:00'},
      ]),
      envelope([
        {...sample(), 'durationSeconds': 20000},
      ]),
      envelope([
        {
          ...sample(),
          'money': {...sample()['money'], 'buyIn': 10.1234},
        },
      ]),
      envelope([
        {
          ...sample(),
          'money': {...sample()['money'], 'buyIn': '10.12345'},
        },
      ]),
      {
        ...envelope([sample()]),
        'expected': {'count': 9, 'balanceEffect': '13.4444'},
      },
    ];
    for (final value in variants) {
      expect(() => document(value), throwsFormatException);
    }
    expect(
      () => ImportDocument.parse(utf8.encode('{"format":')),
      throwsFormatException,
    );
    expect(() => ImportDocument.parse([0xff, 0xfe]), throwsFormatException);
    expect(
      () => ImportDocument.parse(List.filled(ImportDocument.maxBytes + 1, 0)),
      throwsFormatException,
    );
  });
  test(
    'transfers and staking preserve balance without counting played sessions',
    () {
      final records = [
        {
          'sourceId': 'd',
          'kind': 'deposit',
          'currency': 'EUR',
          'date': '2025-01-01',
          'money': {'amount': '12.50'},
          'result': '12.50',
        },
        {
          'sourceId': 'w',
          'kind': 'withdrawal',
          'currency': 'EUR',
          'date': '2025-01-01',
          'money': {'amount': '2.25'},
          'result': '-2.25',
        },
        {
          'sourceId': 's',
          'kind': 'staking',
          'currency': 'EUR',
          'date': '2025-01-01',
          'money': {
            'stakingBoughtCost': '5',
            'stakingBoughtReturn': '9',
            'stakingSettlement': '-1',
          },
          'result': '3',
        },
      ];
      final doc = document(envelope(records));
      final entries = doc.records
          .map((r) => r.materialize(r.sourceId, 'b', '', '', 'batch', 'source'))
          .toList();
      expect(Totals(entries).balanceEffect, 132500);
      expect(Totals(entries).sessions, isEmpty);
    },
  );
  test('preview/cancel do not mutate, commit persists, repeat and overlapping imports skip by source ID', () async {
    final directory = await Directory.systemTemp.createTemp(
      'bankroll-import-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/db';
    var repo = await LedgerRepository.open(path: path);
    var importer = ImportRepository(repo);
    final doc = document(envelope([sample()]));
    final p = await importer.preview(doc);
    expect(await repo.entries(), isEmpty);
    expect(await importer.history(), isEmpty);
    final batch = await importer.commit(p);
    expect(await importer.sourceBytes(batch), doc.bytes);
    final archive = jsonDecode(utf8.decode(await importer.archiveBytes(batch)));
    expect(archive['metadata']['snapshot']['entries'], isEmpty);
    expect(base64Decode(archive['sourceBase64']), doc.bytes);
    await repo.db.close();
    repo = await LedgerRepository.open(path: path);
    importer = ImportRepository(repo);
    addTearDown(repo.db.close);
    expect((await repo.entries()).single.seconds, 10800);
    final repeat = await importer.preview(doc);
    expect(repeat.duplicates.length, 1);
    expect(repeat.canImport, isFalse);
    final overlap = await importer.preview(
      document(envelope([sample(), sample(id: 'cash-2')])),
    );
    expect(overlap.additions.length, 1);
    expect(overlap.duplicates.length, 1);
    expect(overlap.possibleDuplicates.length, 1);
    await expectLater(importer.commit(overlap), throwsFormatException);
    await importer.commit(overlap, allowPossibleDuplicates: true);
    expect((await repo.entries()).length, 2);
    final changed = await importer.preview(
      document(
        envelope([
          {...sample(), 'note': 'changed source'},
        ]),
      ),
    );
    expect(changed.conflicts.length, 1);
    expect(changed.canImport, isFalse);
  });
  test(
    'stale previews and currency mismatch fail without changing entries',
    () async {
      final repo = await LedgerRepository.open(path: inMemoryDatabasePath);
      addTearDown(repo.db.close);
      final importer = ImportRepository(repo),
          doc = document(envelope([sample()]));
      final p = await importer.preview(doc);
      await repo.setState('preferences', {'currency': 'EUR'});
      await expectLater(importer.commit(p), throwsFormatException);
      expect(await repo.entries(), isEmpty);
      final bank = (await repo.definitions('bankroll')).single;
      await repo.saveDefinition('bankroll', {...bank, 'currency': 'USD'});
      await expectLater(importer.preview(doc), throwsFormatException);
    },
  );
  test('SQL failure mid-batch rolls back entries, definitions and archive atomically', () async {
    final repo = await LedgerRepository.open(path: inMemoryDatabasePath);
    addTearDown(repo.db.close);
    final importer = ImportRepository(repo);
    await repo.db.execute(
      "CREATE TRIGGER fail_second BEFORE INSERT ON entries WHEN (SELECT COUNT(*) FROM entries)>0 BEGIN SELECT RAISE(ABORT, 'simulated disk failure'); END",
    );
    final p = await importer.preview(
      document(envelope([sample(), sample(id: 'second')])),
    );
    await expectLater(importer.commit(p), throwsA(isA<DatabaseException>()));
    expect(await repo.entries(), isEmpty);
    expect(await repo.definitions('location'), isEmpty);
    expect(await importer.history(), isEmpty);
  });
  test('rollback preserves unrelated changes, blocks edited imports, and permits reimport after undo', () async {
    final repo = await LedgerRepository.open(path: inMemoryDatabasePath);
    addTearDown(repo.db.close);
    final importer = ImportRepository(repo),
        doc = document(envelope([sample()]));
    final batch = await importer.commit(await importer.preview(doc));
    final imported = (await repo.entries()).single;
    final original = Map<String, dynamic>.from(imported.data);
    await repo.setState('preferences', {'theme': 'dark'});
    imported.data['note'] = 'owner edit';
    await repo.saveEntry(imported);
    await expectLater(importer.rollback(batch), throwsFormatException);
    expect((await repo.entries()).single.s('note'), 'owner edit');
    await repo.saveEntry(Entry(original));
    final unrelated = Entry({
      ...original,
      'id': newId(),
      'note': 'unrelated',
      'import': null,
    });
    await repo.saveEntry(unrelated);
    await importer.rollback(batch);
    expect((await repo.entries()).single.id, unrelated.id);
    expect(await repo.state('preferences'), {'theme': 'dark'});
    expect((await repo.definitions('location')).length, 1); // still referenced
    expect((await importer.preview(doc)).additions.length, 1);
  });
  test('snapshot recovery previews current state, rejects stale confirmation and restores prior facts', () async {
    final repo = await LedgerRepository.open(path: inMemoryDatabasePath);
    addTearDown(repo.db.close);
    final service = ImportRepository(repo);
    await repo.setState('preferences', {'theme': 'before'});
    final doc = document(envelope([sample()]));
    final batch = await service.commit(await service.preview(doc));
    final stale = await service.snapshotPreview(batch);
    final entry = (await repo.entries()).single;
    entry.data['note'] = 'edited';
    await repo.saveEntry(entry);
    await expectLater(
      service.restoreSnapshot(batch, stale['revision']),
      throwsFormatException,
    );
    expect((await repo.entries()).single.s('note'), 'edited');
    await repo.setState('preferences', {'theme': 'after'});
    final preview = await service.snapshotPreview(batch);
    expect(preview['beforeCount'], 0);
    expect(preview['currentCount'], 1);
    await service.restoreSnapshot(batch, preview['revision']);
    expect(await repo.entries(), isEmpty);
    expect(await repo.definitions('location'), isEmpty);
    expect(await repo.state('preferences'), {'theme': 'before'});
    expect((await service.history()).single['status'], 'rolledBack');
    expect((await service.preview(doc)).additions.length, 1);
  });
}
