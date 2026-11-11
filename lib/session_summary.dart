import 'package:flutter/material.dart';

import 'domain.dart';

String sessionGameLabel(Entry entry, Json? game) {
  if (!entry.session) {
    if (isTransfer(entry.kind)) {
      return entry.transfer < 0 ? 'Auszahlung' : 'Einzahlung';
    }
    return entryKindLabel(entry.kind);
  }
  final rawName = (game?['name'] as String?) ?? 'Spiel';
  final name = rawName
      .replaceFirst(RegExp(r'^(NL|PL|FL)\s+', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\s+\d+[,.]?\d*\s*/\s*\d+[,.]?\d*\s*$'), '')
      .trim();
  final rawLimit = '${game?['limit'] ?? 'NL'}';
  final limit = switch (rawLimit) {
    'No Limit' => 'NL',
    'Pot Limit' => 'PL',
    'Fixed Limit' => 'FL',
    _ => rawLimit,
  };
  final symbol =
      {'EUR': '€', 'USD': r'$', 'GBP': '£', 'CHF': 'CHF '}[entry.currency] ??
      '${entry.currency} ';
  String compact(int n) => moneyInput(n).replaceFirst(RegExp(r',00$'), '');
  if (entry.kind == kinds[0]) {
    final bb = entry.data.containsKey('bigBlind')
        ? entry.n('bigBlind')
        : (game?['bigBlind'] as num?)?.toInt() ?? 0;
    final sb = entry.data.containsKey('smallBlind')
        ? entry.n('smallBlind')
        : (game?['smallBlind'] as num?)?.toInt() ?? defaultSmallBlind(bb);
    return '$symbol${compact(sb)}/${compact(bb)} $limit $name';
  }
  if (entry.poker) return '$symbol${compact(entry.n('buyIn'))} $limit $name';
  return '$name · ${entry.kind}';
}

/// The same compact two-line header is used in history and expanded Home cards.
class SessionSummary extends StatelessWidget {
  final String title, location, date, result;
  final String kind;
  final int outcome;
  const SessionSummary({
    super.key,
    required this.title,
    required this.location,
    required this.date,
    required this.result,
    required this.kind,
    required this.outcome,
  });

  @override
  Widget build(BuildContext context) {
    final tournament = kind == kinds[1] || kind == kinds[2];
    final transfer = isTransfer(kind);
    final iconColor = kind == 'Staking'
        ? const Color(0xff8a77d6)
        : transfer
        ? const Color(0xff8a77d6)
        : tournament
        ? const Color(0xffffcc32)
        : const Color(0xff49afd0);
    final resultColor = outcome < 0
        ? const Color(0xfff15d6b)
        : outcome > 0
        ? const Color(0xff21da16)
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              kind == 'Staking'
                  ? Icons.handshake_outlined
                  : transfer
                  ? Icons.swap_vert_circle_outlined
                  : Icons.monetization_on_outlined,
              color: iconColor,
              size: 15,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, height: 1.25),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              result,
              maxLines: 1,
              style: TextStyle(fontSize: 13, height: 1.25, color: resultColor),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Text(
                location,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, height: 1.25),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              date,
              maxLines: 1,
              style: const TextStyle(fontSize: 12, height: 1.25),
            ),
          ],
        ),
      ],
    );
  }
}
