import 'dart:math';

import 'package:uuid/uuid.dart';

// Stored legacy values remain readable for migration and existing records.
const kinds = [
  'Cash Game',
  'Turnier',
  'Mehrtages Turnier',
  'Casino Games',
  'Jackpot/Bonus',
  'Kosten',
  'Einzahlung/Auszahlung',
];
const entryKinds = [
  'Cash Game',
  'Turnier',
  'Einzahlung',
  'Auszahlung',
  'Staking',
];
const liveKinds = ['Cash Game', 'Turnier'];
bool isTournament(String kind) => kind == kinds[1] || kind == kinds[2];
bool isTransfer(String kind) =>
    kind == kinds[6] || kind == 'Einzahlung' || kind == 'Auszahlung';
bool matchesKind(Entry entry, String kind) => switch (kind) {
  'Turnier' => isTournament(entry.kind),
  'Einzahlung' => isTransfer(entry.kind) && entry.transfer > 0,
  'Auszahlung' => isTransfer(entry.kind) && entry.transfer < 0,
  _ => entry.kind == kind,
};
String entryKindLabel(String kind) => isTournament(kind)
    ? 'Turnier'
    : entryKinds.contains(kind)
    ? kind
    : isTransfer(kind)
    ? 'Ein-/Auszahlung (Bestand)'
    : 'Archivierter Eintrag';
const unit = 10000;
String newId() => const Uuid().v4();
int amount(String input) {
  var s = input.trim().replaceAll(' ', '');
  if (s.isEmpty) return 0;
  if (s.contains(',')) s = s.replaceAll('.', '').replaceAll(',', '.');
  if (!RegExp(r'^-?\d+(\.\d{1,4})?$').hasMatch(s)) {
    throw const FormatException('Betrag: maximal 4 Nachkommastellen');
  }
  final negative = s.startsWith('-');
  s = s.replaceAll('-', '');
  final p = s.split('.');
  return (int.parse(p[0]) * unit +
          int.parse((p.length > 1 ? p[1] : '').padRight(4, '0'))) *
      (negative ? -1 : 1);
}

int shareBasisPoints(String input) {
  final scaled = amount(input);
  if (scaled < 0 || scaled > 100 * unit || scaled % 100 != 0) {
    throw const FormatException(
      'Anteile: 0–100 %, maximal zwei Nachkommastellen',
    );
  }
  return scaled ~/ 100;
}

String decimal(int n) =>
    '${n < 0 ? '-' : ''}${n.abs() ~/ unit},${(n.abs() % unit).toString().padLeft(4, '0')}';
// Two-decimal presentation; raw stored amounts retain four-decimal precision.
String moneyInput(int n) => (n / unit).toStringAsFixed(2).replaceAll('.', ',');
// Inputs use cents; an odd-cent big blind defaults to the nearest cent.
int defaultSmallBlind(int bigBlind) => ((bigBlind / 2) / 100).round() * 100;
String defaultSmallBlindHint(String input) {
  try {
    return moneyInput(defaultSmallBlind(amount(input)));
  } catch (_) {
    return '0,00';
  }
}

class ChartBounds {
  final double low, high;
  const ChartBounds(this.low, this.high);
  factory ChartBounds.of(Iterable<num> values) {
    var lo = 0.0, hi = 0.0;
    for (final v in values) {
      lo = min(lo, v.toDouble());
      hi = max(hi, v.toDouble());
    }
    final pad = hi == lo ? unit.toDouble() : (hi - lo) * .10;
    return ChartBounds(lo - pad, hi + pad);
  }
  double get span => high - low;
}

typedef Json = Map<String, dynamic>;

class Entry {
  final Json data;
  Entry(this.data);
  String get id => data['id'];
  String get kind => data['kind'] ?? kinds.first;
  String get bankroll => data['bankroll'];
  String get currency => data['currency'] ?? 'EUR';
  DateTime get start => DateTime.parse(data['start']).toLocal();
  DateTime get end => DateTime.parse(data['end'] ?? data['start']).toLocal();
  int n(String key) => (data[key] as num?)?.toInt() ?? 0;
  String s(String key) => data[key]?.toString() ?? '';
  bool get session => kinds.take(4).contains(kind);
  bool get poker => kinds.take(3).contains(kind);
  int get invested => n('buyIn') + n('rebuyCost');
  int capital({bool truePerformance = true}) => truePerformance
      ? invested * (10000 - n('soldBp')) ~/ 10000 + n('stakingBoughtCost')
      : invested;
  int get transfer => kind == 'Auszahlung'
      ? -n('transfer').abs()
      : kind == 'Einzahlung'
      ? n('transfer').abs()
      : n('transfer');
  int get rawProfit => isTransfer(kind)
      ? transfer
      : kind == 'Staking'
      ? n('stakingBoughtReturn') -
            n('stakingBoughtCost') +
            n('stakingSettlement')
      : kind == kinds[5]
      ? -n('expenses')
      : kind == kinds[4]
      ? n('cashOut')
      : n('cashOut') + n('bounty') - invested - n('chipExpenses');
  int profit({bool truePerformance = true}) {
    if (!session) return rawProfit;
    final base = rawProfit - (truePerformance ? n('expenses') : 0);
    return truePerformance
        ? (base * (10000 - n('soldBp')) ~/ 10000) +
              n('stakingSettlement') +
              n('stakingBoughtReturn') -
              n('stakingBoughtCost')
        : base;
  }

  int get seconds =>
      max(0, end.difference(start).inSeconds - n('breakSeconds'));
  double get hours => seconds / 3600;
  double get hands => hours * (n('handsPerHour') == 0 ? 25 : n('handsPerHour'));
  List<Json> get events => (data['events'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  void validate() {
    if (!kinds.contains(kind) && !entryKinds.contains(kind)) {
      throw const FormatException('Unbekannte Art');
    }
    if ((kind == 'Einzahlung' || kind == 'Auszahlung') && n('transfer') <= 0) {
      throw const FormatException('Betrag muss positiv sein');
    }
    if (end.isBefore(start)) {
      throw const FormatException('Ende liegt vor Start');
    }
    if (n('breakSeconds') < 0 ||
        n('breakSeconds') > end.difference(start).inSeconds) {
      throw const FormatException('Pause überschreitet Sessiondauer');
    }
    for (final k in [
      'buyIn',
      'cashOut',
      'rebuyCost',
      'rebuys',
      'expenses',
      'chipExpenses',
      'bounty',
      'handsPerHour',
      'placement',
      'players',
      'stakingBoughtCost',
      'stakingBoughtReturn',
    ]) {
      if (n(k) < 0) throw FormatException('$k darf nicht negativ sein');
    }
    if (n('soldBp') < 0 || n('soldBp') > 10000) {
      throw const FormatException('Anteile müssen zwischen 0 und 100 % liegen');
    }
    if (n('players') > 0 && n('placement') > n('players')) {
      throw const FormatException('Platzierung über Spieleranzahl');
    }
  }
}

class Totals {
  final List<Entry> entries;
  final bool truePerformance, unionTime;
  Totals(this.entries, {this.truePerformance = true, this.unionTime = false});
  List<Entry> get sessions => entries.where((e) => e.session).toList();
  int get profit => sessions.fold(
    0,
    (n, e) => n + e.profit(truePerformance: truePerformance),
  );
  int get balanceEffect =>
      entries.fold(0, (n, e) => n + e.profit(truePerformance: truePerformance));
  int get invested => sessions.fold(
    0,
    (n, e) => n + e.capital(truePerformance: truePerformance),
  );
  int get cashOut =>
      sessions.fold(0, (n, e) => n + e.n('cashOut') + e.n('bounty'));
  double get hours {
    if (!unionTime) return sessions.fold(0.0, (n, e) => n + e.hours);
    final intervals = <List<DateTime>>[];
    for (final e in sessions) {
      final breaks =
          e.events
              .where((x) => x['kind'] == 'break' && x['end'] != null)
              .toList()
            ..sort((a, b) => a['at'].compareTo(b['at']));
      var cursor = e.start;
      if (breaks.isEmpty) {
        intervals.add([cursor, cursor.add(Duration(seconds: e.seconds))]);
        continue;
      }
      for (final b in breaks) {
        final at = DateTime.parse(b['at']);
        final end = DateTime.parse(b['end']);
        if (at.isAfter(cursor)) intervals.add([cursor, at]);
        cursor = end;
      }
      if (e.end.isAfter(cursor)) intervals.add([cursor, e.end]);
    }
    intervals.sort((a, b) => a[0].compareTo(b[0]));
    DateTime? from, to;
    var seconds = 0;
    for (final i in intervals) {
      if (to == null) {
        from = i[0];
        to = i[1];
      } else if (!i[0].isAfter(to)) {
        if (i[1].isAfter(to)) to = i[1];
      } else {
        seconds += to.difference(from!).inSeconds;
        from = i[0];
        to = i[1];
      }
    }
    if (to != null) seconds += to.difference(from!).inSeconds;
    return seconds / 3600;
  }

  double get hourly => hours == 0 ? 0 : profit / hours;
  double get roi => invested == 0 ? 0 : 100 * profit / invested;
  double get hands => sessions.fold(0.0, (n, e) => n + e.hands);
  double get per100 => hands == 0 ? 0 : profit / hands * 100;
  double get win => sessions.isEmpty
      ? 0
      : 100 *
            sessions
                .where((e) => e.profit(truePerformance: truePerformance) > 0)
                .length /
            sessions.length;
  double get bb => sessions.fold(
    0.0,
    (n, e) =>
        n +
        (e.n('bigBlind') == 0
            ? 0
            : e.profit(truePerformance: truePerformance) / e.n('bigBlind')),
  );
}

class EntryFilter {
  String? kind, location, game;
  DateTime? from, to;
  bool matches(Entry e) =>
      (kind == null || matchesKind(e, kind!)) &&
      (location == null || e.s('location') == location) &&
      (game == null || e.s('game') == game) &&
      (from == null || !e.start.isBefore(from!)) &&
      (to == null || e.start.isBefore(to!.add(const Duration(days: 1))));
  EntryFilter copy() => EntryFilter()
    ..kind = kind
    ..location = location
    ..game = game
    ..from = from
    ..to = to;
  bool get active =>
      kind != null ||
      location != null ||
      game != null ||
      from != null ||
      to != null;
}
