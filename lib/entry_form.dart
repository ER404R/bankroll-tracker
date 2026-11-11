import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import 'domain.dart';
import 'repository.dart';

class EntryForm extends StatefulWidget {
  final LedgerRepository repo;
  final List<Json> bankrolls, locations, games;
  final Entry? entry;
  final bool live, finishing;
  final Json prefs;
  const EntryForm({
    super.key,
    required this.repo,
    required this.bankrolls,
    required this.locations,
    required this.games,
    this.entry,
    this.live = false,
    this.finishing = false,
    required this.prefs,
  });
  @override
  State<EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<EntryForm> {
  late Json d;
  final controls = <String, TextEditingController>{};
  final initialMoney = <String, String>{};
  String? error;
  bool saving = false;
  late List<Json> locations, games;
  final moneyFields = [
    'buyIn',
    'cashOut',
    'rebuyCost',
    'expenses',
    'chipExpenses',
    'bounty',
    'stakingSettlement',
    'transfer',
    'stakingBoughtCost',
    'stakingBoughtReturn',
  ];
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    d = Map<String, dynamic>.from(
      widget.entry?.data ??
          {
            'id': newId(),
            'kind': kinds.first,
            'bankroll': widget.bankrolls.first['id'],
            'currency': widget.bankrolls.first['currency'],
            'start': now.subtract(const Duration(hours: 1)).toIso8601String(),
            'end': now.toIso8601String(),
            'tableSize': 'Short-Handed',
            'handsPerHour': 25,
            'events': [],
          },
    );
    locations = List.from(widget.locations);
    games = List.from(widget.games);
    for (final k in [
      ...moneyFields,
      'rebuys',
      'breakMinutes',
      'soldPercent',
      'placement',
      'players',
      'multiDay',
      'note',
    ]) {
      controls[k] = TextEditingController(
        text: moneyFields.contains(k)
            ? widget.entry == null
                  ? ''
                  : moneyInput((d[k] as int?) ?? 0)
            : k == 'breakMinutes'
            ? widget.entry == null
                  ? ''
                  : ((d['breakSeconds'] as num? ?? 0) / 60).toString()
            : k == 'soldPercent'
            ? widget.entry == null
                  ? ''
                  : ((d['soldBp'] as num? ?? 0) / 100).toString()
            : d[k]?.toString() ?? '',
      );
    }
    for (final k in moneyFields) {
      initialMoney[k] = controls[k]!.text;
    }
  }

  @override
  void dispose() {
    for (final c in controls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget field(String key, String label, {bool text = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey(key),
      controller: controls[key],
      keyboardType: text
          ? TextInputType.multiline
          : const TextInputType.numberWithOptions(decimal: true, signed: true),
      maxLines: text ? 3 : 1,
      autocorrect: widget.prefs['disableAutocorrect'] != true,
      selectAllOnFocus: widget.prefs['selectInput'] == true,
      decoration: InputDecoration(
        labelText: label.toUpperCase(),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        hintText: text
            ? null
            : moneyFields.contains(key)
            ? '0,00'
            : '0',
      ),
    ),
  );
  Widget dropdown(String label, String key, List<String> values) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<String>(
      initialValue: d[key],
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label.toUpperCase(),
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
      items: values
          .map(
            (s) => DropdownMenuItem(
              value: s,
              child: Text(key == 'kind' ? entryKindLabel(s) : s),
            ),
          )
          .toList(),
      onChanged: (v) => setState(() => d[key] = v),
    ),
  );
  Widget pair(Widget a, Widget b) => LayoutBuilder(
    builder: (c, bounds) => bounds.maxWidth < 240
        ? Column(children: [a, b])
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              const SizedBox(width: 12),
              Expanded(child: b),
            ],
          ),
  );
  Future<void> pickTime(String key) async {
    final old = DateTime.parse(d[key]).toLocal();
    if (widget.prefs['wheelPicker'] == true) {
      var chosen = old;
      final accepted = await showModalBottomSheet<bool>(
        context: context,
        builder: (c) => SafeArea(
          child: SizedBox(
            height: 300,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Abbrechen'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Übernehmen'),
                    ),
                  ],
                ),
                Expanded(
                  child: CupertinoDatePicker(
                    initialDateTime: old,
                    use24hFormat: widget.prefs['timeFormat'] != '12 Stunden',
                    onDateTimeChanged: (v) => chosen = v,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (accepted == true) setState(() => d[key] = chosen.toIso8601String());
      return;
    }

    final day = await showDatePicker(
      context: context,
      initialDate: old,
      firstDate: DateTime(1980),
      lastDate: DateTime(2100),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(old),
    );
    if (time != null) {
      setState(
        () => d[key] = DateTime(
          day.year,
          day.month,
          day.day,
          time.hour,
          time.minute,
        ).toIso8601String(),
      );
    }
  }

  Widget dateField(String key, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: OutlinedButton(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      onPressed: () => pickTime(key),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
          '$label\n${DateFormat(widget.prefs['timeFormat'] == '12 Stunden' ? 'dd.MM.yy hh:mm a' : 'dd.MM.yy HH:mm').format(DateTime.parse(d[key]).toLocal())}',
        ),
      ),
    ),
  );
  Widget definition(String category, String label, List<Json> definitions) {
    final key = category == 'location' ? 'location' : 'game';
    final available = definitions
        .where((x) => x['hidden'] != true || x['id'] == d[key])
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              key: ValueKey('$key-${available.length}'),
              initialValue: available.any((x) => x['id'] == d[key])
                  ? d[key]
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: label.toUpperCase(),
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
              items: available
                  .map(
                    (x) => DropdownMenuItem<String>(
                      value: x['id'],
                      child: Text(x['name'], overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() {
                d[key] = v;
                if (category == 'location' && widget.entry == null) {
                  final place = definitions.firstWhere(
                    (item) => item['id'] == v,
                  );
                  d['handsPerHour'] = place['room'] == 'Online' ? 75 : 25;
                }
              }),
            ),
          ),
          IconButton(
            tooltip: '$label erstellen',
            onPressed: () => addDefinition(category),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }

  Future<void> addDefinition(String category) async {
    final n = TextEditingController();
    String room = 'Home Game';
    final bb = TextEditingController();
    final sb = TextEditingController();
    String? issue;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text(
            category == 'location' ? 'Location erstellen' : 'Spiel erstellen',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: n,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 14),
                if (category == 'location')
                  DropdownButtonFormField<String>(
                    initialValue: room,
                    items: ['Home Game', 'Casino', 'Online', 'Sonstige']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => room = v!,
                  )
                else ...[
                  TextField(
                    controller: sb,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Small Blind',
                      hintText: defaultSmallBlindHint(bb.text),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: bb,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => update(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Big Blind',
                      hintText: '0,00',
                    ),
                  ),
                ],
                if (issue != null) Text(issue!),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  if (n.text.trim().isEmpty) {
                    throw const FormatException('Name fehlt');
                  }
                  final value = amount(bb.text);
                  if (value < 0 ||
                      (sb.text.trim().isNotEmpty && amount(sb.text) < 0)) {
                    throw const FormatException(
                      'Blind darf nicht negativ sein',
                    );
                  }
                  final item = {
                    'id': newId(),
                    'name': n.text.trim(),
                    'currency': d['currency'],
                    'room': room,
                    'bigBlind': value,
                    'smallBlind': sb.text.trim().isEmpty
                        ? defaultSmallBlind(value)
                        : amount(sb.text),
                    'limit': 'NL',
                    'hidden': false,
                  };
                  await widget.repo.saveDefinition(category, item);
                  setState(() {
                    (category == 'location' ? locations : games).add(item);
                    d[category == 'location' ? 'location' : 'game'] =
                        item['id'];
                  });
                  if (c.mounted) Navigator.pop(c);
                } catch (e) {
                  update(() => issue = e.toString());
                }
              },
              child: const Text('Erstellen'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    n.dispose();
    bb.dispose();
    sb.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    setState(() => error = null);
    try {
      final entry = Map<String, dynamic>.from(d);
      for (final k in moneyFields) {
        entry[k] = widget.entry != null && controls[k]!.text == initialMoney[k]
            ? (d[k] ?? 0)
            : amount(controls[k]!.text);
      }
      for (final k in ['rebuys', 'placement', 'players']) {
        entry[k] =
            int.tryParse(
              controls[k]!.text.trim().isEmpty ? '0' : controls[k]!.text.trim(),
            ) ??
            (throw FormatException('$k: ganze Zahl erforderlich'));
      }
      final pause = double.tryParse(
        controls['breakMinutes']!.text.trim().isEmpty
            ? '0'
            : controls['breakMinutes']!.text.replaceAll(',', '.'),
      );
      if (pause == null || !pause.isFinite) {
        throw const FormatException('Ungültige Pause');
      }
      entry['breakSeconds'] = (pause * 60).round();
      entry['soldBp'] = shareBasisPoints(controls['soldPercent']!.text);
      entry['note'] = controls['note']!.text;
      entry['multiDay'] = controls['multiDay']!.text;
      final kind = entry['kind'];
      final isSession = kinds.take(4).contains(kind);
      if ((kind == 'Einzahlung' || kind == 'Auszahlung') &&
          entry['transfer'] <= 0) {
        throw const FormatException('Bitte einen positiven Betrag eingeben');
      }
      if (isSession && entry['location'] == null) {
        throw const FormatException('Bitte Location wählen oder erstellen');
      }
      if (isSession && entry['game'] == null) {
        throw const FormatException('Bitte Spiel wählen oder erstellen');
      }
      final bankroll = widget.bankrolls.firstWhere(
        (b) => b['id'] == entry['bankroll'],
      );
      entry['currency'] = bankroll['currency'];
      if (isSession) {
        final location = locations.firstWhere(
          (l) => l['id'] == entry['location'],
        );
        if (location['currency'] != entry['currency']) {
          throw const FormatException(
            'Location und Bankroll benötigen dieselbe Währung',
          );
        }
        entry['smallBlind'] =
            games.firstWhere((g) => g['id'] == entry['game'])['smallBlind'] ??
            0;
        entry['bigBlind'] =
            games.firstWhere((g) => g['id'] == entry['game'])['bigBlind'] ?? 0;
      }
      if (kind == kinds[5] && entry['expenses'] < 0) {
        throw const FormatException('Kosten positiv erfassen');
      }
      if (widget.live) {
        final now = DateTime.now().toIso8601String();
        entry['start'] = now;
        entry['end'] = now;
        entry['breakSeconds'] = 0;
        entry['events'] = [];
      }
      final start = DateTime.parse(entry['start']),
          end = DateTime.parse(entry['end']);
      entry['startOffsetMinutes'] =
          widget.entry != null && start.isAtSameMomentAs(widget.entry!.start)
          ? widget.entry!.data['startOffsetMinutes'] ??
                start.timeZoneOffset.inMinutes
          : start.timeZoneOffset.inMinutes;
      entry['endOffsetMinutes'] =
          !widget.finishing &&
              widget.entry != null &&
              end.isAtSameMomentAs(widget.entry!.end)
          ? widget.entry!.data['endOffsetMinutes'] ??
                end.timeZoneOffset.inMinutes
          : end.timeZoneOffset.inMinutes;
      entry['start'] = start.toUtc().toIso8601String();
      entry['end'] = end.toUtc().toIso8601String();
      Entry(entry).validate();
      setState(() => saving = true);
      if (widget.live) {
        await widget.repo.startLive(Entry(entry));
      } else if (widget.finishing) {
        await widget.repo.finishLive(Entry(entry));
      } else {
        await widget.repo.saveEntry(Entry(entry));
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        error = e.toString();
        saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = d['kind'];
    final session = kinds.take(4).contains(kind);
    final tournament = kinds.sublist(1, 3).contains(kind);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.live
              ? 'Live Session konfigurieren'
              : widget.finishing
              ? 'Session abschließen'
              : widget.entry == null
              ? 'Eintrag hinzufügen'
              : 'Eintrag bearbeiten',
        ),
        actions: [
          IconButton(
            tooltip: 'Abbrechen',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: FilledButton.icon(
            onPressed: saving ? null : save,
            icon: Icon(widget.live ? Icons.play_arrow : Icons.check),
            label: Text(
              saving
                  ? 'Wird gespeichert …'
                  : widget.live
                  ? 'Start'
                  : 'Speichern',
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      error!,
                      key: const ValueKey('formError'),
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                pair(
                  dropdown(
                    'Art',
                    'kind',
                    widget.live
                        ? {
                            ...liveKinds,
                            if (widget.entry != null) kind as String,
                          }.toList()
                        : {
                            ...entryKinds,
                            if (widget.entry != null) kind as String,
                          }.toList(),
                  ),
                  session
                      ? dropdown('Tischgröße', 'tableSize', [
                          'Heads-Up',
                          'Short-Handed',
                          'Full-Ring',
                        ])
                      : const SizedBox(),
                ),
                if (!widget.live)
                  pair(dateField('start', 'Start'), dateField('end', 'Ende')),
                if (session) ...[
                  definition('location', 'Location', locations),
                  definition('game', 'Spiel', games),
                  pair(
                    field('buyIn', 'Buy-in'),
                    !widget.live
                        ? field('cashOut', 'Cash-out')
                        : const SizedBox(),
                  ),
                  if (!widget.live) ...[
                    pair(
                      field('rebuys', 'Anzahl an Rebuys'),
                      field('rebuyCost', 'Rebuy Kosten'),
                    ),
                    pair(
                      field('expenses', 'Ausgaben'),
                      field('chipExpenses', 'Ausgaben in Chips'),
                    ),
                    field('breakMinutes', 'Pause in Minuten'),
                    if (tournament) ...[
                      pair(
                        field('placement', 'Platzierung'),
                        field('players', 'Anzahl Spieler'),
                      ),
                      field('bounty', 'Bounty Gewinne'),
                      if (kind == kinds[2])
                        field(
                          'multiDay',
                          'Mehrtages-Verknüpfung / Event-ID',
                          text: true,
                        ),
                    ],
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Staking · eigener Ergebnisanteil nach verkauften Anteilen',
                      ),
                    ),
                    pair(
                      field('soldPercent', 'Verkaufte Anteile (%)'),
                      field('stakingSettlement', 'Abrechnung (±)'),
                    ),
                    pair(
                      field('stakingBoughtCost', 'Gekaufte Anteile: Einsatz'),
                      field(
                        'stakingBoughtReturn',
                        'Gekaufte Anteile: Auszahlung',
                      ),
                    ),
                  ],
                ],
                if (kind == kinds[4]) field('cashOut', 'Betrag (Bestand)'),
                if (kind == kinds[5]) field('expenses', 'Kosten Betrag'),
                if (kind == 'Staking') ...[
                  field('stakingBoughtCost', 'Staking Einsatz'),
                  field('stakingBoughtReturn', 'Staking Auszahlung'),
                  field('stakingSettlement', 'Zusätzliche Abrechnung (±)'),
                  const Text(
                    'Staking-Ergebnis = Auszahlung − Einsatz + Abrechnung. Ändert den Saldo, zählt aber nicht als selbst gespielte Session.',
                  ),
                  const SizedBox(height: 16),
                ],
                if (isTransfer(kind)) ...[
                  field('transfer', kind == kinds[6] ? 'Betrag (±)' : 'Betrag'),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      kind == kinds[6]
                          ? 'Einzahlung mit Plus-, Auszahlung mit Minuszeichen. Beide ändern keine Pokerstatistik.'
                          : 'Betrag positiv eingeben. Die gewählte Art bestimmt die Richtung; Pokerstatistiken bleiben unverändert.',
                    ),
                  ),
                ],
                field('note', 'Session Notiz', text: true),
                if (session)
                  const Text(
                    'Tags und Fotos folgen in einer späteren Version.',
                    style: TextStyle(color: Colors.blueGrey),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
