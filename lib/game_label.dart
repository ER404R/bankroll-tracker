import 'domain.dart';

bool tournamentKind(String? kind) => kind != null && isTournament(kind);

String gameTypeForSession(String? kind) =>
    tournamentKind(kind) ? 'tournament' : 'cash_game';

/// Untyped legacy definitions remain untouched in storage. Only tournament-only
/// usage identifies a tournament; mixed/unused definitions keep the cash default.
String effectiveGameType(Json game, Iterable<Json> sessions) {
  if (['cash_game', 'tournament'].contains(game['gameType'])) {
    return game['gameType'] as String;
  }
  final uses = sessions.where((e) => e['game'] == game['id']).toList();
  return uses.isNotEmpty &&
          uses.every((e) => tournamentKind(e['kind'] as String?))
      ? 'tournament'
      : 'cash_game';
}

bool gameMatchesSession(Json game, String? kind) =>
    effectiveGameType(game, const []) == gameTypeForSession(kind);

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
  if (game['gameType'] == 'tournament') {
    return 'Turnier · $limit $name${currency == null ? '' : ' · $currency'}';
  }
  return '${moneyInput(sb)}/${moneyInput(bb)} $limit $name${currency == null ? '' : ' · $currency'}';
}
