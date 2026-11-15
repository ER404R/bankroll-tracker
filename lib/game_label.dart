import 'domain.dart';

/// A name alone cannot distinguish imported game definitions with different stakes.
String gameDefinitionLabel(Json game) {
  final name = (game['name']?.toString() ?? 'Spiel')
      .replaceFirst(RegExp(r'^(NL|PL|FL)\s+', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\s+\d+[,.]?\d*\s*/\s*\d+[,.]?\d*\s*$'), '')
      .trim();
  final bb = (game['bigBlind'] as num?)?.toInt() ?? 0;
  final sb = (game['smallBlind'] as num?)?.toInt() ?? defaultSmallBlind(bb);
  final limit = game['limit'] ?? 'NL';
  final currency = game['currency']?.toString();
  return '${moneyInput(sb)}/${moneyInput(bb)} $limit $name${currency == null ? '' : ' · $currency'}';
}
