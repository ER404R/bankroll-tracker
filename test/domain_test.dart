import 'package:flutter_test/flutter_test.dart';
import 'package:felt_ledger/domain.dart';
import 'package:felt_ledger/session_chart.dart';

Entry fixture({
  String kind = 'Cash Game',
  int buy = 200000,
  int cash = 110000,
  int rebuy = 200000,
  int breaks = 0,
  String start = '2026-01-01T10:00:00',
  String end = '2026-01-01T12:00:00',
}) => Entry({
  'id': newId(),
  'bankroll': 'bank',
  'currency': 'EUR',
  'kind': kind,
  'start': start,
  'end': end,
  'buyIn': buy,
  'cashOut': cash,
  'rebuyCost': rebuy,
  'breakSeconds': breaks,
  'handsPerHour': 25,
});
void main() {
  test('exact localized money and invalid values', () {
    expect(amount('1.234,5678'), 12345678);
    expect(amount('-0,01'), -100);
    expect(amount('12.34'), 123400);
    expect(() => amount('NaN'), throwsFormatException);
    expect(() => amount('1,00001'), throwsFormatException);
  });
  test('rebuy loss and independent aggregates', () {
    final a = fixture();
    expect(a.invested, 400000);
    expect(a.profit(), -290000);
    expect(Totals([a]).roi, -72.5);
    final b = fixture(buy: 100000, cash: 600000, rebuy: 0);
    final t = Totals([a, b]);
    expect(t.profit, 210000);
    expect(t.hourly, 52500);
    expect(t.roi, 42);
    expect(t.hands, 100);
    expect(t.per100, 210000);
  });
  test('transfers bonuses costs affect balance only', () {
    final transfer = fixture(kind: kinds[6])..data['transfer'] = 1000000;
    final cost = fixture(kind: kinds[5])..data['expenses'] = 20000;
    final bonus = fixture(kind: kinds[4], cash: 70000);
    final t = Totals([transfer, cost, bonus]);
    expect(t.sessions, isEmpty);
    expect(t.balanceEffect, 1050000);
    expect(t.roi, 0);
    expect(t.hourly, 0);
  });
  test(
    'overnight and zero cash-out valid, invalid time and breaks rejected',
    () {
      final e = fixture(
        cash: 0,
        breaks: 1800,
        start: '2026-01-01T23:00:00',
        end: '2026-01-02T01:00:00',
      );
      e.validate();
      expect(e.hours, 1.5);
      expect(e.profit(), -400000);
      expect(() => fixture(breaks: 7201).validate(), throwsFormatException);
      expect(
        () => fixture(end: '2026-01-01T09:00:00').validate(),
        throwsFormatException,
      );
    },
  );
  test('overlap interval union and event breaks', () {
    final a = fixture(start: '2026-01-01T10:00:00', end: '2026-01-01T12:00:00');
    final b = fixture(start: '2026-01-01T11:00:00', end: '2026-01-01T13:00:00');
    expect(Totals([a, b]).hours, 4);
    expect(Totals([a, b], unionTime: true).hours, 3);
    a.data['events'] = [
      {
        'kind': 'break',
        'at': '2026-01-01T10:00:00',
        'end': '2026-01-01T11:00:00',
      },
    ];
    a.data['breakSeconds'] = 3600;
    expect(Totals([a, b], unionTime: true).hours, 2);
  });
  test('stake normalization per session, sold shares, expenses', () {
    final a = fixture(buy: 100000, cash: 200000, rebuy: 0)
      ..data['bigBlind'] = 1000;
    final b = fixture(buy: 100000, cash: 300000, rebuy: 0)
      ..data['bigBlind'] = 2000;
    expect(Totals([a, b]).bb, 200);
    a.data['soldBp'] = 5000;
    a.data['expenses'] = 10000;
    a.data['chipExpenses'] = 10000;
    a.data['stakingSettlement'] = 20000;
    expect(a.profit(), 60000);
    expect(a.profit(truePerformance: false), 90000);
  });
  test('filter date inclusive and cancel copy isolated', () {
    final f = EntryFilter()
      ..kind = kinds[0]
      ..from = DateTime(2026, 1, 1)
      ..to = DateTime(2026, 1, 1);
    expect(f.matches(fixture()), true);
    final draft = f.copy()..kind = kinds[1];
    expect(f.kind, kinds[0]);
    expect(draft.matches(fixture()), false);
  });
  test('purchased stakes are separate from own result and timezone instants are retained', () {
    final e = fixture(
      buy: 100000,
      cash: 200000,
      rebuy: 0,
      start: '2026-01-01T23:00:00+01:00',
      end: '2026-01-02T01:00:00+01:00',
    );
    e.data['stakingBoughtCost'] = 50000;
    e.data['stakingBoughtReturn'] = 90000;
    expect(e.profit(), 140000);
    expect(Totals([e]).invested, 150000);
    expect(Totals([e]).roi, closeTo(93.3333333333, .000001));
    expect(e.profit(truePerformance: false), 100000);
    expect(e.hours, 2);
    expect(e.start.toUtc().hour, 22);
  });
  test('stake percentages reject silent precision loss', () {
    expect(shareBasisPoints('12,34'), 1234);
    expect(shareBasisPoints('100'), 10000);
    for (final input in ['12,345', '100,01', '-1']) {
      expect(() => shareBasisPoints(input), throwsFormatException);
    }
  });
  test('stack/profit trace derives rebuys without inventing observations', () {
    final e = fixture();
    e.data['events'] = [
      {'kind': 'rebuy', 'at': '2026-01-01T10:30:00', 'value': 200000},
      {'kind': 'note', 'at': '2026-01-01T10:45:00', 'note': 'Test'},
      {'kind': 'stack', 'at': '2026-01-01T11:00:00', 'value': 500000},
    ];
    final points = stackPoints(e);
    expect(points.length, 3);
    expect(points.first.stack, 200000);
    expect(points[1].profit, 100000);
    expect(points.last.profit, -290000);
    expect(stackPoints(e, active: true).length, 2);
    expect(e.events.length, 3);
  });
}
