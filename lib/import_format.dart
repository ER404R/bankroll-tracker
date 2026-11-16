import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'domain.dart';

// Canonical JSON is used for semantic duplicate checks; original bytes are kept too.
String canonicalJson(dynamic value) {
  dynamic sorted(dynamic v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final k in keys) k: sorted(v[k])};
    }
    if (v is List) return v.map(sorted).toList();
    return v;
  }

  return jsonEncode(sorted(value));
}

String contentHash(List<int> bytes) => sha256.convert(bytes).toString();
String semanticHash(dynamic value) =>
    contentHash(utf8.encode(canonicalJson(value)));

class ImportDocument {
  static const maxBytes = 16 * 1024 * 1024;
  final Uint8List bytes;
  final Json data;
  final List<ImportRecord> records;
  ImportDocument._(this.bytes, this.data, this.records);
  String get hash => contentHash(bytes);
  String get sourceId => (data['source'] as Map)['id'] as String;
  String get sourceName => (data['source'] as Map)['name'] as String;
  String get currency => data['currency'] as String;
  int get total => records.fold(0, (sum, r) => sum + r.expectedResult);
  List<String> get warnings => (data['warnings'] as List? ?? []).cast<String>();
  Json get coverage => Map<String, dynamic>.from(data['coverage'] as Map);

  factory ImportDocument.parse(List<int> input) {
    try {
      if (input.isEmpty || input.length > maxBytes) {
        throw const FormatException('Datei leer oder größer als 16 MiB');
      }
      final bytes = Uint8List.fromList(input);
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('JSON-Objekt erwartet');
      }
      if (decoded['format'] != 'bankroll-tracker-import' ||
          decoded['version'] != 1) {
        throw const FormatException(
          'Nicht unterstütztes Importformat / Version (erwartet: bankroll-tracker-import, 1)',
        );
      }
      final source = object(decoded['source'], 'source');
      requiredString(source, 'id');
      requiredString(source, 'name');
      final currency = requiredString(decoded, 'currency');
      if (!['EUR', 'USD', 'GBP', 'CHF'].contains(currency)) {
        throw const FormatException('Währung nicht unterstützt');
      }
      final coverage = object(decoded['coverage'], 'coverage');
      if (coverage.isEmpty ||
          coverage.values.any(
            (v) => ![
              'mapped',
              'preserved-only',
              'missing',
              'empty-confirmed',
            ].contains(v),
          )) {
        throw const FormatException('Abdeckung fehlt oder ist ungültig');
      }
      if (decoded['warnings'] is! List ||
          (decoded['warnings'] as List).any((v) => v is! String)) {
        throw const FormatException('warnings muss eine Textliste sein');
      }
      final raw = decoded['records'];
      if (raw is! List || raw.isEmpty || raw.length > 10000) {
        throw const FormatException('1–10000 Datensätze erforderlich');
      }
      final records = raw
          .map((r) => ImportRecord.parse(object(r, 'record'), currency))
          .toList();
      if (records.map((r) => r.sourceId).toSet().length != records.length) {
        throw const FormatException('Doppelte Quell-IDs innerhalb der Datei');
      }
      final expected = object(decoded['expected'], 'expected');
      if (expected['count'] != records.length ||
          records.fold<int>(0, (s, r) => s + r.expectedResult) !=
              exactMoney(expected['balanceEffect'])) {
        throw const FormatException(
          'Kontrollsumme / Datensatzanzahl stimmt nicht',
        );
      }
      return ImportDocument._(bytes, decoded, records);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'Ungültige Struktur oder Feldtypen in der Importdatei',
      );
    }
  }
}

Json object(dynamic v, String name) {
  if (v is! Map<String, dynamic>) {
    throw FormatException('$name: Objekt erforderlich');
  }
  return v;
}

String requiredString(Json d, String k) {
  final v = d[k];
  if (v is! String || v.trim().isEmpty || v.length > 1000) {
    throw FormatException('$k: Text erforderlich');
  }
  return v;
}

int exactMoney(dynamic v) {
  if (v is! String || !RegExp(r'^-?\d{1,10}(\.\d{1,4})?$').hasMatch(v)) {
    throw const FormatException(
      'Geldbeträge müssen Dezimalstrings mit Punkt und maximal 4 Nachkommastellen sein',
    );
  }
  return amount(v);
}

DateTime strictDate(String s) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
    throw const FormatException('Datum muss YYYY-MM-DD sein');
  }
  final d = DateTime.tryParse(s);
  if (d == null || d.toIso8601String().substring(0, 10) != s) {
    throw const FormatException('Ungültiges Datum');
  }
  return d;
}

String localMinute(dynamic value) {
  if (value is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$').hasMatch(value)) {
    throw const FormatException('Lokale Zeit muss YYYY-MM-DDTHH:mm sein');
  }
  strictDate(value.substring(0, 10));
  if (int.parse(value.substring(11, 13)) > 23 ||
      int.parse(value.substring(14, 16)) > 59) {
    throw const FormatException('Ungültige Uhrzeit');
  }
  return value;
}

class ImportRecord {
  final Json raw, entry, location, game;
  final int expectedResult;
  ImportRecord._(
    this.raw,
    this.entry,
    this.location,
    this.game,
    this.expectedResult,
  );
  String get sourceId => raw['sourceId'] as String;
  String get hash => semanticHash(raw);
  String get fingerprint {
    final facts = Map<String, dynamic>.from(entry)..remove('sourceRecord');
    return semanticHash({
      ...facts,
      'locationName': location['name'],
      'gameName': game['name'],
    });
  }

  String get date => raw['date'] as String;
  Entry materialize(
    String id,
    String bank,
    String locationId,
    String gameId,
    String batch,
    String source,
  ) => Entry({
    ...entry,
    'id': id,
    'bankroll': bank,
    if (location.isNotEmpty) 'location': locationId,
    if (game.isNotEmpty) 'game': gameId,
    'import': {
      'batchId': batch,
      'source': source,
      'sourceId': sourceId,
      'sourceHash': hash,
      'fingerprint': fingerprint,
    },
  });

  factory ImportRecord.parse(Json raw, String currency) {
    final id = requiredString(raw, 'sourceId');
    final kind = requiredString(raw, 'kind');
    if (![
      'cash_game',
      'tournament',
      'deposit',
      'withdrawal',
      'staking',
    ].contains(kind)) {
      throw FormatException('Unbekannte Art bei $id');
    }
    final date = requiredString(raw, 'date');
    strictDate(date);
    if (raw['currency'] != currency) {
      throw FormatException('Gemischte Währungen bei $id');
    }
    final money = object(raw['money'], 'money');
    final result = exactMoney(raw['result']);
    final session = kind == 'cash_game' || kind == 'tournament';
    final entry = <String, dynamic>{
      'kind': {
        'cash_game': 'Cash Game',
        'tournament': 'Turnier',
        'deposit': 'Einzahlung',
        'withdrawal': 'Auszahlung',
        'staking': 'Staking',
      }[kind],
      'currency': currency,
      'start': session ? localMinute(raw['start']) : '${date}T00:00',
      'end': session ? localMinute(raw['end']) : '${date}T00:00',
      'timestampPrecision': session ? 'local-minute' : 'date',
      'note': raw['note'] is String ? raw['note'] : '',
      'sourceRecord': raw,
      'events': <Json>[],
    };
    final location = <String, dynamic>{}, game = <String, dynamic>{};
    if (session) {
      if (!(entry['start'] as String).startsWith(date)) {
        throw FormatException('Startdatum widerspricht Datum bei $id');
      }
      for (final key in [
        'buyIn',
        'cashOut',
        'rebuyCost',
        'addonCost',
        'bounty',
      ]) {
        final value = exactMoney(money[key]);
        if (value < 0) throw FormatException('Negativer $key bei $id');
        entry[key] = value;
      }
      // Existing schema includes add-ons in the total additional purchase cost.
      entry['rebuyCost'] =
          (entry['rebuyCost'] as int) + (entry['addonCost'] as int);
      final duration = raw['durationSeconds'];
      if (duration is! int || duration < 0) {
        throw FormatException('Spieldauer fehlt bei $id');
      }
      entry['reportedDurationSeconds'] = duration;
      for (final key in ['rebuys', 'placement', 'players', 'paidPlaces']) {
        final v = raw[key];
        if (v != null) {
          if (v is! int || v < 0) {
            throw FormatException('$key ungültig bei $id');
          }
          entry[key] = v;
        }
      }
      entry['tableSize'] = requiredString(raw, 'tableSize');
      final loc = object(raw['location'], 'location');
      location.addAll({
        'name': requiredString(loc, 'name'),
        'room': requiredString(loc, 'room'),
        'currency': currency,
        'hidden': false,
      });
      final g = object(raw['game'], 'game');
      game.addAll({
        'gameType': kind,
        'name': requiredString(g, 'name'),
        'limit': requiredString(g, 'limit'),
        'currency': currency,
        'hidden': false,
      });
      if (!['NL', 'PL', 'FL'].contains(game['limit'])) {
        throw const FormatException('Ungültiges Limit');
      }
      for (final k in ['smallBlind', 'bigBlind']) {
        final value = exactMoney(g[k]);
        if (value < 0) {
          throw const FormatException('Blinds müssen positiv sein');
        }
        entry[k] = value;
        game[k] = value;
      }
      game['smallBlindOverride'] = true;
      entry['smallBlindOverride'] = true;
    } else if (kind == 'staking') {
      for (final k in [
        'stakingBoughtCost',
        'stakingBoughtReturn',
        'stakingSettlement',
      ]) {
        entry[k] = exactMoney(money[k]);
      }
    } else {
      entry['transfer'] = exactMoney(money['amount']);
      if ((entry['transfer'] as int) <= 0) {
        throw FormatException('Transferbetrag muss positiv sein bei $id');
      }
    }
    final test = Entry({
      ...entry,
      'id': 'validation',
      'bankroll': 'validation',
    });
    test.validate();
    if (test.profit() != result) {
      throw FormatException(
        'Ergebnis stimmt nicht mit Beträgen überein bei $id',
      );
    }
    return ImportRecord._(raw, entry, location, game, result);
  }
}
