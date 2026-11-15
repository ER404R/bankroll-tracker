import 'dart:convert';

import 'package:flutter/material.dart';

import 'domain.dart';

/// Shows source facts without interpreting uncertain event dates/stack precision.
class SourceRecordView extends StatelessWidget {
  final Json record;
  const SourceRecordView({super.key, required this.record});
  @override
  Widget build(BuildContext context) {
    final captured = record['sourceRecord'];
    final source = captured is Map ? captured : <String, dynamic>{};
    final fields = source['fields_display'];
    final history = source['history_events_display'];
    final limits = source['known_limits'];
    return Scaffold(
      appBar: AppBar(title: const Text('Originalangaben der Quelle')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${record['date'] ?? ''} · Quell-ID ${record['sourceId'] ?? ''}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Diese Angaben sind unverändert aus der Importdatei erhalten. Sie werden durch spätere Bearbeitungen des Eintrags nicht überschrieben.',
          ),
          if ((record['note'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SelectableText(record['note'].toString()),
            ),
          if (fields is Map) ...[
            const Divider(),
            const Text(
              'Erfasste Felder',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final e in fields.entries)
              ListTile(
                dense: true,
                title: Text(e.key.toString()),
                subtitle: SelectableText(e.value.toString()),
              ),
          ],
          const Divider(),
          const Text(
            'Erfasster Verlauf',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          if (history is List && history.isNotEmpty)
            for (final event in history)
              if (event is Map)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: SelectableText(
                    (event['source_fragments'] is List
                        ? (event['source_fragments'] as List)
                              .map(
                                (v) => switch (v) {
                                  'arrow_up' => '↑',
                                  'arrow_down' => '↓',
                                  'arrow_right' => '→',
                                  _ => v.toString(),
                                },
                              )
                              .join(' ')
                        : event.toString()),
                  ),
                ),
          if (history is! List || history.isEmpty)
            const Text('Kein Verlauf in diesem Quellbeleg enthalten.'),
          if (source['history_coverage'] != null)
            Text(source['history_coverage'].toString()),
          if (limits is List)
            for (final warning in limits)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(warning.toString()),
              ),
          ExpansionTile(
            title: const Text('Vollständiger Quellbeleg'),
            children: [
              SelectableText(
                const JsonEncoder.withIndent('  ').convert(record),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
