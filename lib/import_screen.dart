import 'package:flutter/material.dart';

import 'device_services.dart';
import 'domain.dart';
import 'import_format.dart';
import 'import_repository.dart';
import 'repository.dart';
import 'source_record_view.dart';

class ImportScreen extends StatefulWidget {
  final LedgerRepository repo;
  const ImportScreen({super.key, required this.repo});
  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  late final service = ImportRepository(widget.repo);
  ImportPreview? preview;
  List<Json> history = [];
  String? error, notice;
  bool busy = false, acknowledged = false, allowSimilar = false;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final rows = await service.history();
    if (mounted) setState(() => history = rows);
  }

  Future<void> action(Future<void> Function() work) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) {
        setState(() => error = e is FormatException ? e.message : e.toString());
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Bestätigen'),
            ),
          ],
        ),
      ) ??
      false;
  String money(int n, String currency) => '${moneyInput(n)} $currency';
  @override
  Widget build(BuildContext context) {
    final p = preview;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('JSON importieren')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Bankroll-Tracker-Importdatei (.json)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Die Datei wird nur auf diesem Gerät gelesen. Vor dem Speichern siehst du eine Vorschau. Bestehende Einträge werden nicht überschrieben; Startkapital und Einstellungen bleiben erhalten.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('pick-import'),
              onPressed: busy
                  ? null
                  : () => action(() async {
                      final bytes = await DeviceServices.pickImportFile();
                      if (bytes == null) return;
                      if (mounted) {
                        setState(() {
                          preview = null;
                          acknowledged = false;
                          allowSimilar = false;
                        });
                      }
                      final doc = ImportDocument.parse(bytes);
                      final next = await service.preview(doc);
                      if (mounted) setState(() => preview = next);
                    }),
              icon: const Icon(Icons.file_open),
              label: const Text('Datei auswählen'),
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SelectableText(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (notice != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(notice!),
              ),
            if (p != null) ...[
              const Divider(),
              Text(
                'Vorschau · ${p.document.sourceName}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${p.document.records.length} Datensätze · ${p.document.currency}',
              ),
              Text(
                '${(p.document.records.map((r) => r.date).toList()..sort()).first} bis ${(p.document.records.map((r) => r.date).toList()..sort()).last}',
              ),
              Text(
                '${p.additions.length} neu · ${p.duplicates.length} bereits importiert · ${p.conflicts.length} Konflikte',
              ),
              Text(
                'Ergebnis aller Quelldatensätze: ${money(p.document.total, p.document.currency)}',
              ),
              Text(
                'Änderung deiner Bankroll: ${money(p.effect, p.document.currency)}',
              ),
              const Text(
                'Fehlerhafte Dateien werden vollständig abgewiesen. Unbekannte Zusatzfelder bleiben in der gespeicherten Quelldatei erhalten.',
              ),
              ExpansionTile(
                title: const Text('Abdeckung und Hinweise'),
                initiallyExpanded: true,
                children: [
                  for (final c in p.document.coverage.entries)
                    ListTile(
                      dense: true,
                      title: Text(c.key),
                      subtitle: Text(switch (c.value) {
                        'mapped' => 'Übernommen und nutzbar',
                        'preserved-only' => 'Im Quellarchiv erhalten',
                        'missing' => 'Nicht in der Quelle verfügbar',
                        _ => 'Leer, durch Quelle bestätigt',
                      }),
                    ),
                  for (final w in p.document.warnings)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.info_outline),
                      title: Text(w),
                    ),
                ],
              ),
              if (p.conflicts.isNotEmpty)
                Text(
                  'Geänderte Quell-IDs: ${p.conflicts.map((r) => r.sourceId).join(', ')}. Kein automatisches Überschreiben.',
                ),
              if (p.possibleDuplicates.isNotEmpty)
                CheckboxListTile(
                  value: allowSimilar,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => allowSimilar = v!),
                  title: Text(
                    '${p.possibleDuplicates.length} ähnliche bestehende Einträge',
                  ),
                  subtitle: Text(
                    'Quell-IDs: ${p.possibleDuplicates.map((r) => r.sourceId).join(', ')}. Ich habe sie geprüft und möchte diese zusätzlich importieren.',
                  ),
                ),
              ExpansionTile(
                title: const Text('Datensätze prüfen'),
                children: [
                  for (final r in p.document.records)
                    ListTile(
                      dense: true,
                      title: Text(
                        '${r.date} · ${r.entry['kind']} · ${r.location['name'] ?? ''}',
                      ),
                      subtitle: Text('Quell-ID ${r.sourceId}'),
                      trailing: Text(
                        money(r.expectedResult, p.document.currency),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SourceRecordView(record: r.raw),
                        ),
                      ),
                    ),
                ],
              ),
              CheckboxListTile(
                key: const ValueKey('ack-import'),
                value: acknowledged,
                onChanged: busy
                    ? null
                    : (v) => setState(() => acknowledged = v!),
                title: const Text('Vorschau und Einschränkungen geprüft'),
                subtitle: const Text(
                  'Fehlende Angaben gelten nicht als bestätigte Nullwerte. Dieser Import ist kein vollständiges Backup der Original-App.',
                ),
              ),
              FilledButton(
                key: const ValueKey('commit-import'),
                onPressed:
                    busy ||
                        !p.canImport ||
                        !acknowledged ||
                        (p.possibleDuplicates.isNotEmpty && !allowSimilar)
                    ? null
                    : () => action(() async {
                        if (!await confirm(
                          'Import speichern?',
                          '${p.additions.length} neue Einträge hinzufügen? Ein Sicherungsstand und die Quelldatei werden lokal aufbewahrt.',
                        )) {
                          return;
                        }
                        await service.commit(
                          p,
                          allowPossibleDuplicates: allowSimilar,
                        );
                        if (mounted) {
                          setState(() {
                            preview = null;
                            notice =
                                '${p.additions.length} Einträge gespeichert. Abgleich: ${money(p.effect, p.document.currency)}.';
                          });
                        }
                        await refresh();
                      }),
                child: Text('${p.additions.length} Einträge importieren'),
              ),
              TextButton(
                onPressed: busy ? null : () => setState(() => preview = null),
                child: const Text('Vorschau verwerfen'),
              ),
            ],
            const Divider(),
            const Text(
              'Importverlauf',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            for (final h in history)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${h['sourceName']} · ${h['count']} Einträge'),
                      Text(
                        '${h['createdAt']} · ${h['status'] == 'imported' ? 'Importiert' : 'Zurückgenommen'}',
                      ),
                      Text(
                        'Abgleich: ${money(h['effect'] as int, h['currency'] as String)}',
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => action(() async {
                                    final bytes = await service.sourceBytes(
                                      h['id'],
                                    );
                                    final saved =
                                        await DeviceServices.saveDocument(
                                          'bankroll-source.json',
                                          bytes,
                                        );
                                    if (mounted) {
                                      setState(
                                        () => notice = saved
                                            ? 'Quelldatei gespeichert.'
                                            : 'Speichern abgebrochen.',
                                      );
                                    }
                                  }),
                            child: const Text('Quelldatei speichern'),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => action(() async {
                                    final bytes = await service.archiveBytes(
                                      h['id'],
                                    );
                                    final saved =
                                        await DeviceServices.saveDocument(
                                          'bankroll-import-archive.json',
                                          bytes,
                                        );
                                    if (mounted) {
                                      setState(
                                        () => notice = saved
                                            ? 'Archiv mit Sicherungsstand gespeichert.'
                                            : 'Speichern abgebrochen.',
                                      );
                                    }
                                  }),
                            child: const Text('Archiv sichern'),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => action(() async {
                                    final snapshot = await service
                                        .snapshotPreview(h['id']);
                                    if (!mounted) return;
                                    if (!await confirm(
                                      'Gesamten Sicherungsstand wiederherstellen?',
                                      'Stand vor diesem Import: ${snapshot['beforeCount']} Einträge. Aktuell: ${snapshot['currentCount']}. Alle seitdem angelegten oder bearbeiteten Einträge, Definitionen, Einstellungen und die laufende Session werden durch den alten Stand ersetzt. Für eine normale Rücknahme bitte „Rückgängig“ verwenden.',
                                    )) {
                                      return;
                                    }
                                    await service.restoreSnapshot(
                                      h['id'],
                                      snapshot['revision'],
                                    );
                                    await DeviceServices.cancelReminder();
                                    await refresh();
                                    if (mounted) {
                                      setState(() {
                                        preview = null;
                                        notice = 'Sicherungsstand wiederhergestellt.';
                                      });
                                    }
                                  }),
                            child: const Text(
                              'Sicherungsstand wiederherstellen',
                            ),
                          ),
                          if (h['status'] == 'imported')
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => action(() async {
                                      if (!await confirm(
                                        'Import zurücknehmen?',
                                        'Nur unveränderte Einträge dieses Imports werden entfernt. Bei nachträglichen Änderungen wird abgebrochen. Andere Einträge und Einstellungen bleiben erhalten.',
                                      )) {
                                        return;
                                      }
                                      await service.rollback(h['id']);
                                      await refresh();
                                      if (mounted) {
                                        setState(() {
                                          preview = null;
                                          notice = 'Import zurückgenommen.';
                                        });
                                      }
                                    }),
                              child: const Text('Rückgängig'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
