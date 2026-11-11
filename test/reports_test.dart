import 'package:flutter_test/flutter_test.dart';
import 'package:felt_ledger/domain.dart';
import 'package:felt_ledger/reports.dart';

Entry entry(String id, String at, int profit, {String kind = 'Cash Game'}) =>
    Entry({
      'id': id,
      'bankroll': 'bank',
      'kind': kind,
      'start': at,
      'end': at,
      'buyIn': amount('100'),
      'cashOut': amount('100') + profit,
      if (isTransfer(kind)) 'transfer': profit.abs(),
    });
void main() {
  test(
    'rolling calendar months retain year and empty months, excluding transfers',
    () {
      final data = [
        entry('old', '2025-01-15', 100),
        entry('jan', '2026-01-15', 400),
        entry('mar', '2026-03-01', -100),
        entry('deposit', '2026-02-01', 900, kind: 'Einzahlung'),
        entry('future', '2026-03-31', 200),
      ];
      final report = monthlyReport(data, DateTime(2026, 3, 20), 4);
      expect(report.map((b) => b.start), [
        DateTime(2025, 12),
        DateTime(2026, 1),
        DateTime(2026, 2),
        DateTime(2026, 3),
      ]);
      expect(report.map((b) => b.profit), [0, 400, 0, -100]);
      expect(report.map((b) => b.sessions), [0, 1, 0, 1]);
      expect(yearlyReport(data, DateTime(2026, 3, 20)).map((b) => b.profit), [
        100,
        300,
      ]);
      expect(monthlyReport([], DateTime(2026, 1, 1), 12), hasLength(12));
      expect(yearlyReport([], DateTime(2026, 1, 1)).single.profit, 0);
    },
  );
  test('trend category and metric filters separate bankroll changes from poker results', () {
    final data = [
      entry('tourney', '2026-03-05', -100, kind: 'Turnier'),
      entry('cash', '2026-03-01', 300),
      entry('deposit', '2026-03-02', 900, kind: 'Einzahlung'),
      entry('legacy-tourney', '2026-03-06', 200, kind: 'Mehrtages Turnier'),
    ];
    List<Entry> series(String category, String metric) => trendEntries(
      data,
      now: DateTime(2026, 3, 20),
      period: '1M',
      category: category,
      metric: metric,
    );
    expect(series('Alle', 'Gesamtergebnis').map((e) => e.id), [
      'cash',
      'deposit',
      'tourney',
      'legacy-tourney',
    ]);
    expect(series('Alle', 'Netto Profit/Datum').map((e) => e.id), [
      'cash',
      'tourney',
      'legacy-tourney',
    ]);
    expect(series('Turnier', 'Netto Profit/Sessions').map((e) => e.id), [
      'tourney',
      'legacy-tourney',
    ]);
    expect(series('Cash Game', 'Gesamtergebnis').single.id, 'cash');
    expect(trendCutoff(DateTime(2026, 3, 31), '1M'), DateTime(2026, 2, 28));
    expect(trendCutoff(DateTime(2024, 2, 29), '1J'), DateTime(2023, 2, 28));
  });
  test('new transfer directions and standalone staking affect balance without poker stats', () {
    final deposit = entry(
      'deposit',
      '2026-01-01',
      amount('100'),
      kind: 'Einzahlung',
    );
    final withdrawal = entry(
      'withdrawal',
      '2026-01-01',
      amount('20'),
      kind: 'Auszahlung',
    );
    final staking = Entry({
      'id': 'stake',
      'bankroll': 'bank',
      'kind': 'Staking',
      'start': '2026-01-01',
      'end': '2026-01-01',
      'stakingBoughtCost': amount('30'),
      'stakingBoughtReturn': amount('50'),
      'stakingSettlement': amount('-5'),
    });
    for (final e in [deposit, withdrawal, staking]) {
      e.validate();
    }
    expect(deposit.profit(), amount('100'));
    expect(withdrawal.profit(), amount('-20'));
    expect(staking.profit(), amount('15'));
    expect(staking.profit(truePerformance: false), amount('15'));
    final totals = Totals([deposit, withdrawal, staking]);
    expect(totals.balanceEffect, amount('95'));
    expect(totals.sessions, isEmpty);
    expect(totals.profit, 0);
    expect(totals.hours, 0);
    expect(
      monthlyReport(
        [deposit, withdrawal, staking],
        DateTime(2026, 1, 15),
        1,
      ).single.profit,
      amount('15'),
    );
    expect((EntryFilter()..kind = 'Auszahlung').matches(withdrawal), isTrue);
    final legacy = entry('legacy', '2026-01-01', 0, kind: kinds[6])
      ..data['transfer'] = amount('-8');
    expect((EntryFilter()..kind = 'Auszahlung').matches(legacy), isTrue);
    expect(entryKinds, [
      'Cash Game',
      'Turnier',
      'Einzahlung',
      'Auszahlung',
      'Staking',
    ]);
  });
}
