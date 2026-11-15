import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';

class LedgerRepository {
  final Database db;
  LedgerRepository(this.db);
  static Future<LedgerRepository> open({String? path}) async {
    final db = await openDatabase(
      path ?? p.join(await getDatabasesPath(), 'felt_ledger.db'),
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, v) async {
        await db.execute(
          'CREATE TABLE definitions(id TEXT PRIMARY KEY, category TEXT NOT NULL, payload TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE entries(id TEXT PRIMARY KEY, bankroll TEXT NOT NULL REFERENCES definitions(id), payload TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE state(key TEXT PRIMARY KEY, payload TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE migration_archive(id TEXT PRIMARY KEY, payload BLOB NOT NULL, metadata TEXT NOT NULL)',
        );
        final id = newId();
        await db.insert('definitions', {
          'id': id,
          'category': 'bankroll',
          'payload': jsonEncode({
            'id': id,
            'name': 'Meine Bankroll',
            'currency': 'EUR',
            'opening': 0,
            'included': true,
          }),
        });
      },
    );
    return LedgerRepository(db);
  }

  Future<List<Json>> definitions(String category) async =>
      (await db.query(
            'definitions',
            where: 'category=?',
            whereArgs: [category],
          ))
          .map(
            (e) =>
                Map<String, dynamic>.from(jsonDecode(e['payload'] as String)),
          )
          .toList();
  Future<List<Entry>> entries() async {
    final all = (await db.query('entries'))
        .map(
          (e) => Entry(
            Map<String, dynamic>.from(jsonDecode(e['payload'] as String)),
          ),
        )
        .toList();
    all.sort((a, b) => b.start.compareTo(a.start));
    return all;
  }

  Future<void> saveDefinition(String category, Json d) async {
    await db.insert('definitions', {
      'id': d['id'],
      'category': category,
      'payload': jsonEncode(d),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveEntry(Entry e) async {
    e.validate();
    await db.transaction((t) async {
      await t.insert('entries', {
        'id': e.id,
        'bankroll': e.bankroll,
        'payload': jsonEncode(e.data),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> deleteEntry(String id) async {
    await db.delete('entries', where: 'id=?', whereArgs: [id]);
  }

  Future<dynamic> state(String key) async {
    final r = await db.query('state', where: 'key=?', whereArgs: [key]);
    return r.isEmpty ? null : jsonDecode(r.first['payload'] as String);
  }

  Future<void> setState(String key, dynamic value) async {
    await db.insert('state', {
      'key': key,
      'payload': jsonEncode(value),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> startLive(Entry e) async {
    e.validate();
    await db.transaction((t) async {
      final old = await t.query('state', where: 'key=?', whereArgs: ['live']);
      if (old.isNotEmpty &&
          jsonDecode(old.first['payload'] as String) != null) {
        throw const FormatException('Es läuft bereits eine Session');
      }
      await t.insert('state', {
        'key': 'live',
        'payload': jsonEncode(e.data),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  // Purchase and the owner's observed resulting stack commit together.
  Future<void> recordPurchase(
    String id,
    String kind,
    int purchase,
    int stack,
  ) async {
    if (!['rebuy', 'addon'].contains(kind) || purchase <= 0 || stack < 0) {
      throw const FormatException(
        'Kaufbetrag positiv und aktuellen Stack angeben',
      );
    }
    await db.transaction((t) async {
      final rows = await t.query('state', where: 'key=?', whereArgs: ['live']);
      final live = rows.isEmpty
          ? null
          : jsonDecode(rows.first['payload'] as String);
      if (live == null || live['id'] != id) {
        throw const FormatException('Session ist nicht mehr aktiv');
      }
      final at = DateTime.now().toUtc().toIso8601String();
      final events = List<dynamic>.from(live['events'] ?? []);
      events.add({'kind': kind, 'at': at, 'value': purchase});
      events.add({'kind': 'stack', 'at': at, 'value': stack});
      live['events'] = events;
      live['rebuyCost'] = (live['rebuyCost'] ?? 0) + purchase;
      final count = kind == 'rebuy' ? 'rebuys' : 'addOns';
      live[count] = (live[count] ?? 0) + 1;
      await t.update(
        'state',
        {'payload': jsonEncode(live)},
        where: 'key=?',
        whereArgs: ['live'],
      );
    });
  }

  Future<void> recordObservation(
    String id,
    String kind,
    int value,
    String note,
  ) async {
    if (!['stack', 'note'].contains(kind) || value < 0) {
      throw const FormatException('Ungültiger Stack');
    }
    await db.transaction((t) async {
      final rows = await t.query('state', where: 'key=?', whereArgs: ['live']);
      final live = rows.isEmpty
          ? null
          : jsonDecode(rows.first['payload'] as String);
      if (live == null || live['id'] != id) {
        throw const FormatException('Session ist nicht mehr aktiv');
      }
      live['events'] = [
        ...(live['events'] as List? ?? []),
        {
          'kind': kind,
          'at': DateTime.now().toUtc().toIso8601String(),
          'value': value,
          if (kind == 'note') 'note': note,
        },
      ];
      await t.update(
        'state',
        {'payload': jsonEncode(live)},
        where: 'key=?',
        whereArgs: ['live'],
      );
    });
  }

  Future<void> finishLive(Entry e) async {
    e.validate();
    await db.transaction((t) async {
      final active = await t.query(
        'state',
        where: 'key=?',
        whereArgs: ['live'],
      );
      if (active.isEmpty ||
          jsonDecode(active.first['payload'] as String) == null) {
        return;
      }
      if (jsonDecode(active.first['payload'] as String)['id'] != e.id) return;
      await t.insert('entries', {
        'id': e.id,
        'bankroll': e.bankroll,
        'payload': jsonEncode(e.data),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await t.delete('state', where: 'key=?', whereArgs: ['live']);
    });
  }

  Future<void> bulkUpdate(List<Entry> entries) async {
    for (final e in entries) {
      e.validate();
    }
    await db.transaction((t) async {
      for (final e in entries) {
        await t.update(
          'entries',
          {'bankroll': e.bankroll, 'payload': jsonEncode(e.data)},
          where: 'id=?',
          whereArgs: [e.id],
        );
      }
    });
  }

  Future<void> replaceDefinition(
    String category,
    Json d, {
    String? mergeInto,
  }) async {
    final key = category == 'location' ? 'location' : 'game';
    await db.transaction((t) async {
      final oldRows = await t.query(
        'definitions',
        where: 'id=? AND category=?',
        whereArgs: [d['id'], category],
      );
      if (oldRows.isEmpty) {
        throw const FormatException('Definition nicht gefunden');
      }
      final old = Map<String, dynamic>.from(
        jsonDecode(oldRows.single['payload'] as String),
      );
      if (mergeInto != null) {
        if (mergeInto == d['id']) {
          throw const FormatException('Identische Definition');
        }
        final target = await t.query(
          'definitions',
          where: 'id=? AND category=?',
          whereArgs: [mergeInto, category],
        );
        if (target.isEmpty) {
          throw const FormatException('Zieldefinition nicht gefunden');
        }
        final targetData = Map<String, dynamic>.from(
          jsonDecode(target.single['payload'] as String),
        );
        if (old['currency'] != null &&
            targetData['currency'] != null &&
            old['currency'] != targetData['currency']) {
          throw const FormatException(
            'Definitionen mit unterschiedlichen Währungen können nicht zusammengeführt werden',
          );
        }
      }
      Json preserveFacts(Json entry) {
        if (category == 'game') {
          // Freeze legacy fallback values before changing a game's defaults/ID.
          entry.putIfAbsent('bigBlind', () => old['bigBlind'] ?? 0);
          entry.putIfAbsent(
            'smallBlind',
            () =>
                old['smallBlind'] ??
                defaultSmallBlind((entry['bigBlind'] as num?)?.toInt() ?? 0),
          );
          entry.putIfAbsent(
            'smallBlindOverride',
            () => old['smallBlindOverride'] ?? true,
          );
        }
        if (mergeInto != null) entry[key] = mergeInto;
        return entry;
      }

      for (final row in await t.query('entries')) {
        final entry = Map<String, dynamic>.from(
          jsonDecode(row['payload'] as String),
        );
        if (entry[key] != d['id']) continue;
        await t.update(
          'entries',
          {'payload': jsonEncode(preserveFacts(entry))},
          where: 'id=?',
          whereArgs: [row['id']],
        );
      }
      final activeRows = await t.query(
        'state',
        where: 'key=?',
        whereArgs: ['live'],
      );
      if (activeRows.isNotEmpty) {
        final active = jsonDecode(activeRows.single['payload'] as String);
        if (active != null && active[key] == d['id']) {
          await t.update(
            'state',
            {
              'payload': jsonEncode(
                preserveFacts(Map<String, dynamic>.from(active)),
              ),
            },
            where: 'key=?',
            whereArgs: ['live'],
          );
        }
      }
      if (mergeInto != null) {
        await t.delete('definitions', where: 'id=?', whereArgs: [d['id']]);
      } else {
        await t.update(
          'definitions',
          {'payload': jsonEncode(d)},
          where: 'id=?',
          whereArgs: [d['id']],
        );
      }
    });
  }

  /// Removing a game from future selection must never delete played sessions.
  Future<void> archiveGame(String id) async {
    final rows = await db.query(
      'definitions',
      where: 'id=? AND category=?',
      whereArgs: [id, 'game'],
    );
    if (rows.isEmpty) throw const FormatException('Spiel nicht gefunden');
    final game = Map<String, dynamic>.from(
      jsonDecode(rows.single['payload'] as String),
    );
    await replaceDefinition('game', {...game, 'hidden': true});
  }

  Future<void> deleteDefinitionAndEntries(String category, String id) async {
    if (category == 'game') {
      await archiveGame(id);
      return;
    }
    if (category == 'bankroll') {
      throw const FormatException('Bankroll zuerst leeren und archivieren');
    }
    final key = category == 'location' ? 'location' : 'game';
    final active = await state('live');
    if (active != null && active[key] == id) {
      throw const FormatException(
        'Laufende Session zuerst abschließen oder verwerfen.',
      );
    }
    final affected = (await entries()).where((e) => e.s(key) == id).toList();
    await db.transaction((t) async {
      for (final e in affected) {
        await t.delete('entries', where: 'id=?', whereArgs: [e.id]);
      }
      await t.delete('definitions', where: 'id=?', whereArgs: [id]);
    });
  }

  Future<void> resetAll() async {
    await db.transaction((t) async {
      await t.delete('entries');
      await t.delete('state');
      await t.delete('migration_archive');
      await t.delete('definitions');
      final id = newId();
      await t.insert('definitions', {
        'id': id,
        'category': 'bankroll',
        'payload': jsonEncode({
          'id': id,
          'name': 'Meine Bankroll',
          'currency': 'EUR',
          'opening': 0,
          'included': true,
        }),
      });
    });
  }

  Future<void> clearLocal() async {
    await db.transaction((t) async {
      await t.delete('entries');
      await t.delete('state', where: 'key=?', whereArgs: ['live']);
      await t.delete('migration_archive');
    });
  }
}
