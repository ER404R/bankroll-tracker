import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'domain.dart';
import 'import_format.dart';
import 'repository.dart';

class ImportPreview {
  final ImportDocument document;
  final String revision, bankroll;
  final List<ImportRecord> additions, duplicates, conflicts, possibleDuplicates;
  ImportPreview(
    this.document,
    this.revision,
    this.bankroll,
    this.additions,
    this.duplicates,
    this.conflicts,
    this.possibleDuplicates,
  );
  int get effect => additions.fold(0, (s, r) => s + r.expectedResult);
  bool get canImport => conflicts.isEmpty && additions.isNotEmpty;
}

class ImportRepository {
  final LedgerRepository repo;
  ImportRepository(this.repo);

  Future<Json> _snapshot(DatabaseExecutor db) async => {
    'definitions': await db.query('definitions', orderBy: 'id'),
    'entries': await db.query('entries', orderBy: 'id'),
    'state': await db.query('state', orderBy: 'key'),
  };
  Future<List<Json>> _history(DatabaseExecutor db) async =>
      (await db.query('migration_archive', orderBy: 'id'))
          .map(
            (r) => {
              'id': r['id'],
              ...object(jsonDecode(r['metadata'] as String), 'metadata'),
            },
          )
          .toList()
        ..sort(
          (a, b) =>
              (a['createdAt'] as String).compareTo(b['createdAt'] as String),
        );
  Future<List<Json>> history() async =>
      (await _history(repo.db)).reversed.toList();

  Future<ImportPreview> preview(ImportDocument doc) =>
      repo.db.transaction((t) => _preview(t, doc));
  Future<ImportPreview> _preview(
    DatabaseExecutor db,
    ImportDocument doc,
  ) async {
    final snapshot = await _snapshot(db);
    final banks = (snapshot['definitions'] as List)
        .where((r) => r['category'] == 'bankroll')
        .toList();
    if (banks.length != 1) {
      throw const FormatException(
        'Import benötigt genau eine Ziel-Bankroll. Bestehende Bankrolls werden nicht zusammengelegt.',
      );
    }
    final bank = object(jsonDecode(banks.single['payload']), 'bankroll');
    if (bank['currency'] != doc.currency) {
      throw const FormatException(
        'Datei und Ziel-Bankroll haben unterschiedliche Währungen. Keine automatische Umrechnung.',
      );
    }
    final histories = await _history(db);
    final revision = semanticHash({'snapshot': snapshot, 'history': histories});
    final old = <String, Json>{};
    for (final h in histories.where(
      (h) => h['status'] == 'imported' && h['sourceId'] == doc.sourceId,
    )) {
      for (final r in h['records'] as List) {
        old[r['sourceId'] as String] = object(r, 'record');
      }
    }
    final existing = (snapshot['entries'] as List)
        .map((r) => Entry(object(jsonDecode(r['payload']), 'entry')))
        .toList();
    final additions = <ImportRecord>[],
        duplicates = <ImportRecord>[],
        conflicts = <ImportRecord>[],
        possible = <ImportRecord>[];
    for (final r in doc.records) {
      final previous = old[r.sourceId];
      if (previous != null) {
        (previous['hash'] == r.hash ? duplicates : conflicts).add(r);
        continue;
      }
      additions.add(r);
      // Deliberately conservative: flag lookalikes, never silently collapse them.
      if (existing.any(
        (e) =>
            e.currency == doc.currency &&
            e.kind == r.entry['kind'] &&
            e.start.toIso8601String().substring(0, 10) == r.date &&
            e.profit() == r.expectedResult,
      )) {
        possible.add(r);
      }
    }
    return ImportPreview(
      doc,
      revision,
      bank['id'] as String,
      additions,
      duplicates,
      conflicts,
      possible,
    );
  }

  Future<String> commit(
    ImportPreview preview, {
    bool allowPossibleDuplicates = false,
  }) async {
    return repo.db.transaction((t) async {
      final fresh = await _preview(t, preview.document);
      if (fresh.revision != preview.revision) {
        throw const FormatException(
          'Daten haben sich geändert. Bitte neue Vorschau laden.',
        );
      }
      if (!fresh.canImport) {
        throw const FormatException(
          'Keine neuen konfliktfreien Einträge vorhanden.',
        );
      }
      if (fresh.possibleDuplicates.isNotEmpty && !allowPossibleDuplicates) {
        throw const FormatException(
          'Ähnliche bestehende Einträge zuerst ausdrücklich bestätigen.',
        );
      }
      final snapshot = await _snapshot(t);
      final id = newId(), now = DateTime.now().toUtc().toIso8601String();
      final createdDefinitions = <Json>[], imported = <Json>[];
      final definitionIds = <String, String>{};
      Future<String> definition(String category, Json values) async {
        if (values.isEmpty) return '';
        final key = '$category:${canonicalJson(values)}';
        if (definitionIds.containsKey(key)) return definitionIds[key]!;
        final did = newId(), payload = jsonEncode({...values, 'id': did});
        final row = {'id': did, 'category': category, 'payload': payload};
        await t.insert('definitions', row);
        createdDefinitions.add(row);
        definitionIds[key] = did;
        return did;
      }

      for (final r in fresh.additions) {
        final lid = await definition('location', r.location),
            gid = await definition('game', r.game);
        final entry = r.materialize(
          newId(),
          fresh.bankroll,
          lid,
          gid,
          id,
          fresh.document.sourceId,
        );
        entry.validate();
        final payload = jsonEncode(entry.data);
        await t.insert('entries', {
          'id': entry.id,
          'bankroll': fresh.bankroll,
          'payload': payload,
        });
        imported.add({
          'sourceId': r.sourceId,
          'hash': r.hash,
          'entryId': entry.id,
          'payload': payload,
        });
      }
      await t.insert('migration_archive', {
        'id': id,
        'payload': fresh.document.bytes,
        'metadata': jsonEncode({
          'status': 'imported',
          'createdAt': now,
          'sourceId': fresh.document.sourceId,
          'sourceName': fresh.document.sourceName,
          'sha256': fresh.document.hash,
          'currency': fresh.document.currency,
          'count': imported.length,
          'effect': fresh.effect,
          'records': imported,
          'definitions': createdDefinitions,
          'snapshot': snapshot,
          'priorStatuses': {
            for (final h in await _history(t)) h['id'] as String: h['status'],
          },
          'coverage': fresh.document.coverage,
          'warnings': fresh.document.warnings,
        }),
      });
      return id;
    });
  }

  Future<Uint8List> sourceBytes(String id) async {
    final rows = await repo.db.query(
      'migration_archive',
      where: 'id=?',
      whereArgs: [id],
    );
    if (rows.isEmpty) {
      throw const FormatException('Importarchiv nicht gefunden');
    }
    return Uint8List.fromList((rows.single['payload'] as List).cast<int>());
  }

  Future<void> rollback(String id) async {
    await repo.db.transaction((t) async {
      final rows = await t.query(
        'migration_archive',
        where: 'id=?',
        whereArgs: [id],
      );
      if (rows.isEmpty) throw const FormatException('Import nicht gefunden');
      final meta = object(
        jsonDecode(rows.single['metadata'] as String),
        'metadata',
      );
      if (meta['status'] != 'imported') {
        throw const FormatException('Import wurde bereits zurückgenommen');
      }
      final records = (meta['records'] as List).cast<Map>();
      final conflicts = <String>[];
      for (final r in records) {
        final entries = await t.query(
          'entries',
          where: 'id=?',
          whereArgs: [r['entryId']],
        );
        if (entries.isNotEmpty &&
            canonicalJson(jsonDecode(entries.single['payload'] as String)) !=
                canonicalJson(jsonDecode(r['payload'] as String))) {
          conflicts.add(r['sourceId'] as String);
        }
      }
      if (conflicts.isNotEmpty) {
        throw FormatException(
          'Nachträglich bearbeitete Einträge: ${conflicts.join(', ')}. Rücknahme abgebrochen; keine Daten geändert. Die Sicherung vor dem Import ist im Archiv erhalten.',
        );
      }
      for (final r in records) {
        await t.delete('entries', where: 'id=?', whereArgs: [r['entryId']]);
      }
      final all = (await t.query('entries'))
          .map((r) => object(jsonDecode(r['payload'] as String), 'entry'))
          .toList();
      final live = await t.query('state', where: 'key=?', whereArgs: ['live']);
      if (live.isNotEmpty) {
        final value = jsonDecode(live.single['payload'] as String);
        if (value is Map<String, dynamic>) all.add(value);
      }
      for (final d in meta['definitions'] as List) {
        final current = await t.query(
          'definitions',
          where: 'id=?',
          whereArgs: [d['id']],
        );
        final referenced = all.any(
          (e) => e['location'] == d['id'] || e['game'] == d['id'],
        );
        if (!referenced &&
            current.isNotEmpty &&
            current.single['payload'] == d['payload']) {
          await t.delete('definitions', where: 'id=?', whereArgs: [d['id']]);
        }
      }
      meta['status'] = 'rolledBack';
      meta['rolledBackAt'] = DateTime.now().toUtc().toIso8601String();
      await t.update(
        'migration_archive',
        {'metadata': jsonEncode(meta)},
        where: 'id=?',
        whereArgs: [id],
      );
    });
  }

  // Full archive export includes original source bytes and pre-import snapshot.
  Future<Uint8List> archiveBytes(String id) async {
    final rows = await repo.db.query(
      'migration_archive',
      where: 'id=?',
      whereArgs: [id],
    );
    if (rows.isEmpty) throw const FormatException('Import nicht gefunden');
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'bankroll-tracker-import-archive',
          'version': 1,
          'sourceBase64': base64Encode(
            (rows.single['payload'] as List).cast<int>(),
          ),
          'metadata': jsonDecode(rows.single['metadata'] as String),
        }),
      ),
    );
  }

  Future<Json> snapshotPreview(String id) async =>
      repo.db.transaction((t) async {
        final rows = await t.query(
          'migration_archive',
          where: 'id=?',
          whereArgs: [id],
        );
        if (rows.isEmpty) {
          throw const FormatException('Sicherungsstand nicht gefunden');
        }
        final meta = object(
          jsonDecode(rows.single['metadata'] as String),
          'metadata',
        );
        final current = await _snapshot(t);
        return {
          'revision': semanticHash({
            'snapshot': current,
            'history': await _history(t),
          }),
          'beforeCount': (meta['snapshot']['entries'] as List).length,
          'currentCount': (current['entries'] as List).length,
          'createdAt': meta['createdAt'],
        };
      });

  /// Explicit disaster recovery: unlike rollback, this replaces ALL local facts
  /// with the pre-import snapshot. The UI separately confirms the data loss.
  Future<void> restoreSnapshot(String id, String expectedRevision) async {
    await repo.db.transaction((t) async {
      final current = await _snapshot(t);
      final history = await _history(t);
      if (semanticHash({'snapshot': current, 'history': history}) !=
          expectedRevision) {
        throw const FormatException(
          'Daten geändert. Sicherungs-Vorschau erneut öffnen.',
        );
      }
      final meta = history.firstWhere((h) => h['id'] == id);
      final snapshot = object(meta['snapshot'], 'snapshot');
      await t.delete('entries');
      await t.delete('definitions');
      await t.delete('state');
      for (final table in ['definitions', 'entries', 'state']) {
        for (final row in snapshot[table] as List) {
          await t.insert(table, Map<String, Object?>.from(row as Map));
        }
      }
      final prior = object(meta['priorStatuses'], 'priorStatuses');
      for (final h in history) {
        final hid = h['id'] as String;
        h.remove('id');
        h['status'] = prior[hid] ?? 'rolledBack';
        h['snapshotRestoredAt'] = DateTime.now().toUtc().toIso8601String();
        await t.update(
          'migration_archive',
          {'metadata': jsonEncode(h)},
          where: 'id=?',
          whereArgs: [hid],
        );
      }
    });
  }
}
