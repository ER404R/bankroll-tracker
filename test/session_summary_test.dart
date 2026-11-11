import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:felt_ledger/domain.dart';
import 'package:felt_ledger/session_summary.dart';

Entry record({String kind = 'Cash Game', int? sb, int? bb}) => Entry({
  'id': 'test',
  'bankroll': 'bank',
  'kind': kind,
  'currency': 'EUR',
  'start': '2026-01-01T10:00:00Z',
  'end': '2026-01-01T11:00:00Z',
  'buyIn': amount('30'),
  'smallBlind': ?sb,
  'bigBlind': ?bb,
});
void main() {
  test(
    'history header shows independent saved blinds and normalized limit/game',
    () {
      expect(
        sessionGameLabel(record(sb: amount('0,05'), bb: amount('0,20')), {
          'name': 'NL Texas Holdem 0,10/0,20',
          'limit': 'NL',
        }),
        '€0,05/0,20 NL Texas Holdem',
      );
      expect(
        sessionGameLabel(record(), {
          'name': 'Texas Holdem',
          'bigBlind': amount('0,10'),
        }),
        '€0,05/0,10 NL Texas Holdem',
      );
      expect(
        sessionGameLabel(record(sb: 0, bb: amount('0,10')), {
          'name': 'Texas Holdem',
          'smallBlind': amount('0,05'),
        }),
        '€0/0,10 NL Texas Holdem',
      );
      expect(
        sessionGameLabel(record(kind: kinds[1]), {
          'name': 'PLO',
          'limit': 'Pot Limit',
        }),
        '€30 PL PLO',
      );
      final transfer = record(kind: kinds[6])..data['transfer'] = amount('-10');
      expect(sessionGameLabel(transfer, null), 'Auszahlung');
    },
  );
  testWidgets('compact header fits long session information at 320px', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: Padding(
              padding: EdgeInsets.all(10),
              child: SessionSummary(
                title: '€0,05/0,10 NL Texas Holdem',
                location: 'Ein längerer synthetischer Spielort',
                date: 'Sa, 7. Nov 2026',
                result: '-€29',
                kind: 'Cash Game',
                outcome: -290000,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('€0,05/0,10 NL Texas Holdem'), findsOneWidget);
    expect(find.text('Sa, 7. Nov 2026'), findsOneWidget);
    expect(tester.getSize(find.byType(SessionSummary)).height, lessThan(50));
    expect(tester.takeException(), isNull);
  });
}
