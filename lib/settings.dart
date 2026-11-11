import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'domain.dart';
import 'repository.dart';
import 'device_services.dart';

class SettingsScreen extends StatefulWidget {
  final LedgerRepository repo;
  final Future<void> Function() onChanged;
  const SettingsScreen({
    super.key,
    required this.repo,
    required this.onChanged,
  });
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Json prefs = {};
  bool ready = false;
  String installation = '—';
  final fields = <String, TextEditingController>{};
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    prefs = Map<String, dynamic>.from(
      await widget.repo.state('preferences') ?? {},
    );
    for (final (key, fallback) in [
      ('city', ''),
      ('country', 'Deutschland'),
      ('rss', ''),
    ]) {
      fields[key] = TextEditingController(
        text: prefs[key]?.toString() ?? fallback,
      );
    }
    try {
      final meta = await DeviceServices.appInfo();
      if (meta['installedAt'] is int) {
        installation = DateFormat('dd.MM.yyyy HH:mm').format(
          DateTime.fromMillisecondsSinceEpoch(meta['installedAt'] as int),
        );
      }
    } catch (_) {}
    setState(() => ready = true);
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget group(String name, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            name.toUpperCase(),
            style: const TextStyle(
              color: Color(0xff49afd0),
              letterSpacing: 1.5,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
  Widget choice(
    String label,
    String key,
    List<String> values,
    String fallback,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<String>(
      initialValue: prefs[key] ?? fallback,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: values
          .map((v) => DropdownMenuItem(value: v, child: Text(v)))
          .toList(),
      onChanged: (v) => prefs[key] = v,
    ),
  );
  Widget input(String label, String key) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: fields[key],
      decoration: InputDecoration(labelText: label),
    ),
  );
  Widget toggle(
    String label,
    String key, {
    bool fallback = false,
    String? help,
    bool deferred = false,
  }) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: help != null || deferred
        ? Text(
            [
              ?help,
              if (deferred) 'Wert wird gespeichert. Zugehörige Funktion ist in dieser lokalen Version nicht verfügbar.',
            ].join(' '),
          )
        : null,
    value: prefs[key] ?? fallback,
    onChanged: (v) => setState(() => prefs[key] = v),
  );
  Future<void> save() async {
    try {
      for (final key in ['city', 'country', 'rss']) {
        prefs[key] = fields[key]!.text;
      }
      await widget.repo.setState('preferences', prefs);
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Einstellungen gespeichert')),
        );
      }
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        bottom: const TabBar(
          isScrollable: true,
          tabs: [
            Tab(text: 'Settings'),
            Tab(text: 'Partner Deals'),
            Tab(text: 'Über Bankroll Tracker'),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: ready ? save : null,
            child: const Text('Einstellungen speichern'),
          ),
        ),
      ),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (error != null)
                      Text(
                        error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    group('Allgemein', [
                      choice('Sprache', 'language', ['Deutsch'], 'Deutsch'),
                      choice('Standardwährung', 'currency', [
                        'EUR',
                        'USD',
                        'GBP',
                        'CHF',
                      ], 'EUR'),
                      input('Land', 'country'),
                      input('Stadt', 'city'),
                      choice('Datumsformat', 'dateFormat', [
                        'dd.MM.yyyy',
                        'yyyy-MM-dd',
                      ], 'dd.MM.yyyy'),
                      choice('Zeitformat', 'timeFormat', [
                        '24 Stunden',
                        '12 Stunden',
                      ], '24 Stunden'),
                      choice('Zahlenformat', 'numberFormat', [
                        '1.234,56',
                        '1,234.56',
                      ], '1.234,56'),
                      choice('Startseite', 'startup', [
                        'Home',
                        'Bankroll',
                        'Live Session',
                      ], 'Home'),
                      input('RSS-Feed (Inhalt später verfügbar)', 'rss'),
                      choice('Theme', 'theme', ['Dunkel', 'Hell'], 'Dunkel'),
                    ]),
                    group('Benachrichtigungen', [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Benachrichtigungen'),
                        subtitle: const Text(
                          'Lokale Pausenerinnerungen. Android fragt nur bei Aktivierung nach Erlaubnis.',
                        ),
                        value: prefs['notifications'] == true,
                        onChanged: (v) async {
                          try {
                            final ok =
                                !v ||
                                await DeviceServices.enableNotifications();
                            if (ok) setState(() => prefs['notifications'] = v);
                          } catch (e) {
                            setState(() => error = e.toString());
                          }
                        },
                      ),
                      const Text(
                        'Im Live-Modus während einer Pause „Pausen-Timer setzen“ wählen. Erinnerung ungefähr zwei Minuten vor Ende; Android-Energiesparen kann Alarme verzögern.',
                      ),
                    ]),
                    group('Datenschutz / Sicherheit', [
                      toggle(
                        '3-Monats-Trend zeigen',
                        'publicTrend',
                        deferred: true,
                      ),
                      toggle(
                        'Öffentliche Freundesliste',
                        'publicFriends',
                        deferred: true,
                      ),
                      toggle(
                        'Freundesanfragen automatisch annehmen',
                        'acceptFriends',
                        deferred: true,
                      ),
                      toggle(
                        'Emojis und Kommentare erlauben',
                        'comments',
                        deferred: true,
                      ),
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Analytics'),
                        subtitle: Text(
                          'Keine Nutzungsanalyse eingebaut. Es werden keine Analyse-Daten gesendet.',
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Gesicht / Fingerabdruck'),
                        subtitle: const Text(
                          'Android 11+: Biometrie oder Gerätesperre. Erst nach erfolgreicher Bestätigung aktivierbar. Nach Verlassen der App erneut entsperren.',
                        ),
                        value: prefs['biometric'] == true,
                        onChanged: (v) async {
                          try {
                            if (await DeviceServices.authenticate()) {
                              setState(() => prefs['biometric'] = v);
                            }
                          } catch (e) {
                            setState(() => error = e.toString());
                          }
                        },
                      ),
                    ]),
                    group('Statistik', [
                      toggle(
                        'True Performance',
                        'truePerformance',
                        fallback: true,
                        help: 'Verkaufte Anteile und Ausgaben einbeziehen.',
                      ),
                      toggle(
                        'Multi-Tabling Zeit',
                        'multiTime',
                        help: 'Überlappende Spielintervalle zählen einmal. Manuelle Pausen ohne Zeitpunkte werden am Session-Ende abgezogen.',
                      ),
                      toggle('Große Zahlen runden', 'roundNumbers'),
                      toggle('Ab 1k abkürzen', 'abbreviate'),
                    ]),
                    group('Benutzeroberfläche', [
                      toggle('Vierfarbiges Deck', 'fourColor', deferred: true),
                      toggle(
                        'Kartenkürzel in Notizen umwandeln',
                        'cardImages',
                        deferred: true,
                      ),
                      toggle('Zeitpicker mit Rad', 'wheelPicker'),
                      toggle(
                        'Floating Buttons',
                        'floatingButtons',
                        fallback: true,
                      ),
                      toggle(
                        'Schatten / Transparenz reduzieren',
                        'reduceEffects',
                        help: 'Das lokale Design verwendet bereits reduzierte Schatten.',
                      ),
                    ]),
                    group('Sonstiges', [
                      toggle(
                        'Eigene Sessions in Timeline',
                        'ownTimeline',
                        deferred: true,
                      ),
                      toggle(
                        'Turniere in der Nähe vor Live-Start',
                        'nearby',
                        deferred: true,
                      ),
                      toggle(
                        'Laufende Cash Games auf Casino-Seite',
                        'runningGames',
                        deferred: true,
                      ),
                      toggle('Eingabeinhalt markieren', 'selectInput'),
                      toggle(
                        'Notiz-Autokorrektur deaktivieren',
                        'disableAutocorrect',
                      ),
                      toggle(
                        'Alternativer Endpunkt für blockierte Regionen',
                        'alternativeEndpoint',
                        deferred: true,
                      ),
                      const Text('Schriftgröße'),
                      Slider(
                        value: (prefs['fontSize'] as num? ?? 1).toDouble(),
                        min: .85,
                        max: 1.3,
                        divisions: 9,
                        label:
                            '${((prefs['fontSize'] as num? ?? 1) * 100).round()} %',
                        onChanged: (v) => setState(() => prefs['fontSize'] = v),
                      ),
                    ]),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    group('Partner Deals', [
                      const Text(
                        'Keine Partneraktionen oder Kaufangebote für diese lokale App konfiguriert.',
                      ),
                    ]),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    group('Bankroll Tracker', [
                      Text(
                        'Version 0.1.3 · Android 8+\nInstalliert: $installation\nEigenständiger lokaler Poker-Bankroll-Tracker.\nEntwickelt für dieses Projekt. Keine Verbindung zum Anbieter der Referenz-App.',
                      ),
                      const SizedBox(height: 12),
                      for (final title in [
                        'Handbuch',
                        'Tutorials',
                        'FAQ',
                        'Datenschutz',
                        'Nutzungsbedingungen',
                        'Logfile',
                      ])
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(title),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(switch (title) {
                                'Handbuch' => 'Über + eine Session erfassen. Unter Wartung Startkapital, Locations und Spiele verwalten. Transfers ändern nur den Saldo. Live Sessions bleiben nach Neustart erhalten.',
                                'Tutorials' => '1. Location und Spiel erstellen. 3. Session mit Buy-in und Cash-out speichern. 4. Berichte öffnen.',
                                'FAQ' => 'Keine Daten sichtbar? Filter und Währung prüfen. Gemischte Währungen werden nie automatisch umgerechnet.',
                                'Datenschutz' => 'Einträge und Einstellungen bleiben lokal in der Android-App-Datenbank. Keine Analyse, keine Werbung, kein Server. Android-Gerätesicherung kann je nach Systemeinstellung gelten.',
                                'Nutzungsbedingungen' => 'Entwicklungssoftware für persönliche Aufzeichnung. Original-App und dieser Tracker sind unabhängig.',
                                'Logfile' => 'Es werden keine persönlichen Finanzdaten in eine eigene Logdatei geschrieben. Fehler erscheinen direkt im jeweiligen Bildschirm.',
                                _ => '',
                              }),
                            ),
                          ],
                        ),
                    ]),
                  ],
                ),
              ],
            ),
    ),
  );
}
