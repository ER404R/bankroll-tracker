import 'package:flutter_test/flutter_test.dart';
import 'package:felt_ledger/game_label.dart';

void main() {
  test(
    'game choices distinguish same names by independent blinds and limit',
    () {
      expect(
        gameDefinitionLabel({
          'name': 'Texas Holdem',
          'smallBlind': 500,
          'bigBlind': 1000,
          'limit': 'NL',
        }),
        '0,05/0,10 NL Texas Holdem',
      );
      expect(
        gameDefinitionLabel({
          'name': 'NL Texas Holdem',
          'smallBlind': 700,
          'bigBlind': 2000,
          'limit': 'PL',
          'currency': 'EUR',
        }),
        '0,07/0,20 PL Texas Holdem · EUR',
      );
      expect(
        gameDefinitionLabel({'name': 'Texas Holdem', 'bigBlind': 2000}),
        '0,10/0,20 NL Texas Holdem',
      );
    },
  );
}
