import 'package:flutter_test/flutter_test.dart';
import 'package:felt_ledger/domain.dart';
import 'package:felt_ledger/repository.dart';
import 'package:felt_ledger/session_chart.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test(
    'cent presentation and half-blind defaults preserve explicit overrides',
    () {
      expect(moneyInput(amount('12,50')), '12,50');
      expect(moneyInput(0), '0,00');
      expect(defaultSmallBlind(amount('0,10')), amount('0,05'));
      expect(defaultSmallBlind(amount('0,05')), amount('0,03'));
      expect(defaultSmallBlindHint('n/a'), '0,00');
    },
  );
  test('chart bounds retain a visible zero baseline for all sign ranges', () {
    for (final values in <List<int>>[
      [0],
      [0, 10000],
      [-20000, -10000],
      [-20000, 30000],
      [],
    ]) {
      final b = ChartBounds.of(values);
      expect(b.low, lessThan(0));
      expect(b.high, greaterThan(0));
      expect(b.span, greaterThan(0));
    }
  });
  test(
    'purchase and resulting stack commit together, stale session is rejected',
    () async {
      final r = await LedgerRepository.open(path: inMemoryDatabasePath);
      final bank = (await r.definitions('bankroll')).first;
      final e = Entry({
        'id': newId(),
        'bankroll': bank['id'],
        'kind': kinds[0],
        'buyIn': amount('20'),
        'start': '2026-01-01T10:00:00Z',
        'end': '2026-01-01T10:00:00Z',
        'events': [],
      });
      await r.startLive(e);
      await r.recordPurchase(e.id, 'rebuy', amount('10'), amount('18'));
      final saved = await r.state('live');
      expect(saved['rebuyCost'], amount('10'));
      expect(saved['rebuys'], 1);
      expect(saved['events'].length, 2);
      var points = stackPoints(
        Entry(Map<String, dynamic>.from(saved)),
        active: true,
      );
      expect(points.last.stack, amount('18'));
      expect(points.last.profit, amount('-12'));
      await expectLater(
        r.recordPurchase(e.id, 'rebuy', amount('10'), -1),
        throwsFormatException,
      );
      expect((await r.state('live'))['events'], saved['events']);
      await expectLater(
        r.recordPurchase('stale', 'addon', amount('5'), amount('23')),
        throwsFormatException,
      );
      await r.recordPurchase(e.id, 'addon', amount('5'), amount('23'));
      final addon = Map<String, dynamic>.from(await r.state('live'));
      expect(addon['addOns'], 1);
      expect(addon['rebuyCost'], amount('15'));
      points = stackPoints(Entry(addon), active: true);
      expect(points.last.profit, amount('-12'));
      await r.db.close();
    },
  );
}
