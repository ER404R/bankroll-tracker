import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'domain.dart';
import 'reports.dart';
import 'repository.dart';
import 'entry_form.dart';
import 'settings.dart';
import 'session_chart.dart';
import 'session_summary.dart';
import 'device_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await LedgerRepository.open();
  runApp(LedgerApp(repo: repo));
}

const accent = Color(0xff49afd0),
    positive = Color(0xff21da16),
    negative = Color(0xfff15d6b),
    tournamentColor = Color(0xffffcc32);

class LedgerApp extends StatefulWidget {
  final LedgerRepository repo;
  const LedgerApp({super.key, required this.repo});
  @override
  State<LedgerApp> createState() => _LedgerAppState();
}

class _LedgerAppState extends State<LedgerApp> with WidgetsBindingObserver {
  bool locked = false;
  bool authenticated = false;
  String? lockError;
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && prefs['biometric'] == true) {
      setState(() => locked = true);
    }
  }

  Future<void> unlock() async {
    try {
      if (await DeviceServices.authenticate()) {
        setState(() {
          locked = false;
          authenticated = true;
          lockError = null;
        });
      }
    } catch (e) {
      setState(() => lockError = e.toString());
    }
  }

  Json prefs = {};
  bool ready = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  Future<void> load() async {
    prefs = Map<String, dynamic>.from(
      await widget.repo.state('preferences') ?? {},
    );
    setState(() {
      ready = true;
      locked = prefs['biometric'] == true && !authenticated;
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Bankroll Tracker',
    locale: const Locale('de'),
    supportedLocales: const [Locale('de')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      brightness: prefs['theme'] == 'Hell' ? Brightness.light : Brightness.dark,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: accent,
            brightness: prefs['theme'] == 'Hell'
                ? Brightness.light
                : Brightness.dark,
          ).copyWith(
            primary: accent,
            secondary: tournamentColor,
            surface: prefs['theme'] == 'Hell'
                ? Colors.white
                : const Color(0xff0c2732),
          ),
      scaffoldBackgroundColor: prefs['theme'] == 'Hell'
          ? const Color(0xffeef6f5)
          : const Color(0xff174758),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 14),
        color: prefs['theme'] == 'Hell'
            ? Colors.white
            : const Color(0xff0c2732),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xff395563)),
          borderRadius: BorderRadius.all(Radius.circular(5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xff395563)),
          borderRadius: BorderRadius.all(Radius.circular(5)),
        ),
        labelStyle: TextStyle(color: accent, fontSize: 12),
        floatingLabelStyle: TextStyle(color: accent, fontSize: 12),
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        isDense: true,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: Color(0xff0d2833),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: accent),
        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: Color(0xff9baeb8),
        indicatorColor: accent,
        dividerColor: Colors.transparent,
        labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        shape: CircleBorder(),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
        ),
      ),
      useMaterial3: true,
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(
          (prefs['fontSize'] as num? ?? 1).toDouble(),
        ),
      ),
      child: Stack(
        children: [
          child!,
          if (locked)
            Positioned.fill(
              child: Material(
                child: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_outline, size: 54),
                          const SizedBox(height: 20),
                          const Text('Bankroll Tracker ist gesperrt'),
                          if (lockError != null) Text(lockError!),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: unlock,
                            child: const Text('Entsperren'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    home: ready
        ? LedgerHome(repo: widget.repo, prefs: prefs, onPreferences: load)
        : const Scaffold(body: Center(child: CircularProgressIndicator())),
  );
}

class LedgerHome extends StatefulWidget {
  final LedgerRepository repo;
  final Json prefs;
  final Future<void> Function() onPreferences;
  const LedgerHome({
    super.key,
    required this.repo,
    required this.prefs,
    required this.onPreferences,
  });
  @override
  State<LedgerHome> createState() => _LedgerHomeState();
}

class _LedgerHomeState extends State<LedgerHome> {
  List<Entry> all = [];
  List<Json> bankrolls = [], locations = [], games = [];
  Json? live;
  int page = 0;
  EntryFilter filter = EntryFilter();
  String reportCurrency = 'EUR';
  String trendMetric = 'Gesamtergebnis', period = 'MAX', trendKind = 'Alle';
  bool fill = false;
  int reportMonths = 12;
  Timer? timer;
  final tabs = [
    'Überblick',
    'Session',
    'Locations',
    'Diagramme',
    'Trend',
    'Staking',
    'Wartung',
  ];
  LedgerRepository get repo => widget.repo;
  @override
  void initState() {
    super.initState();
    page = [
      'Home',
      'Bankroll',
      'Live Session',
    ].indexOf(widget.prefs['startup'] ?? 'Home');
    refresh();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && live != null) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    all = await repo.entries();
    bankrolls = await repo.definitions('bankroll');
    locations = await repo.definitions('location');
    games = await repo.definitions('game');
    live = await repo.state('live');
    if (!bankrolls.any((b) => b['currency'] == reportCurrency) &&
        bankrolls.isNotEmpty) {
      reportCurrency = bankrolls.first['currency'];
    }
    if (mounted) setState(() {});
  }

  List<Entry> get included => all
      .where((e) => e.currency == reportCurrency && filter.matches(e))
      .toList();
  int investment(Entry e) =>
      e.capital(truePerformance: widget.prefs['truePerformance'] != false);
  int result(Entry e) =>
      e.profit(truePerformance: widget.prefs['truePerformance'] != false);
  Totals totals(List<Entry> entries) => Totals(
    entries,
    truePerformance: widget.prefs['truePerformance'] != false,
    unionTime: widget.prefs['multiTime'] == true,
  );
  String name(List<Json> defs, String id) =>
      defs
          .where((d) => d['id'] == id)
          .map((e) => e['name'].toString())
          .firstOrNull ??
      '—';
  String money(num n, {bool fixed = false}) {
    final locale = widget.prefs['numberFormat'] == '1,234.56'
        ? 'en_US'
        : 'de_DE';
    final symbol =
        {'EUR': '€', 'USD': r'$', 'GBP': '£', 'CHF': 'CHF'}[reportCurrency] ??
        reportCurrency;
    final sign = n < 0 ? '-' : '';
    if (!fixed &&
        widget.prefs['abbreviate'] == true &&
        n.abs() >= 1000 * unit) {
      return '$sign$symbol${NumberFormat('0.##', locale).format(n.abs() / (1000 * unit))}k';
    }
    final digits =
        !fixed &&
            (n % unit == 0 ||
                widget.prefs['roundNumbers'] == true && n.abs() >= 1000 * unit)
        ? 0
        : 2;
    return '$sign$symbol${NumberFormat.decimalPatternDigits(locale: locale, decimalDigits: digits).format(n.abs() / unit)}';
  }

  String number(num n) => NumberFormat('0.##', 'de_DE').format(n);
  String date(DateTime d) =>
      DateFormat(widget.prefs['dateFormat'] ?? 'dd.MM.yyyy', 'de').format(d);
  Widget value(num n, {bool cash = true}) => Text(
    cash ? money(n) : number(n),
    style: TextStyle(
      color: n < 0
          ? negative
          : n > 0
          ? positive
          : null,
      fontWeight: FontWeight.w600,
    ),
  );
  Future<void> guarded(Future<void> Function() action) async {
    try {
      await action();
      await refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Nicht gespeichert: $e')));
      }
    }
  }

  Future<void> info(String title, String message) async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  Future<bool> confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(text),
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
  Future<void> form({Entry? entry, bool startLive = false}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => EntryForm(
          repo: repo,
          bankrolls: bankrolls,
          locations: locations,
          games: games,
          entry: entry,
          live: startLive,
          prefs: widget.prefs,
        ),
      ),
    );
    await refresh();
  }

  Widget card(String title, List<Widget> children, {Widget? trailing}) => Card(
    semanticContainer: false,
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          if (title.isNotEmpty) const SizedBox(height: 9),
          ...children,
        ],
      ),
    ),
  );
  Widget line(String label, Widget v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        v,
      ],
    ),
  );
  Widget empty(String text) => Padding(
    padding: const EdgeInsets.all(24),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.blueGrey),
    ),
  );
  Widget list(List<Widget> children) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: widget.prefs['theme'] == 'Hell'
            ? [const Color(0xffe4f1f4), const Color(0xfff5f8fa)]
            : [const Color(0xff153f50), const Color(0xff1c5367)],
      ),
    ),
    child: ListView(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 90),
      children: children,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final currencies = bankrolls
        .map((b) => b['currency'].toString())
        .toSet()
        .toList();
    return DefaultTabController(
      length: page == 1
          ? 7
          : page == 2
          ? 2
          : 1,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            page == 0
                ? 'Hallo!'
                : page == 1
                ? 'Bankroll'
                : 'Live Session',
          ),
          actions: [
            if (page == 1)
              IconButton(
                tooltip: 'Bankroll Filter',
                onPressed: filters,
                icon: Icon(Icons.tune, color: filter.active ? accent : null),
              ),
            if (page == 0)
              IconButton(
                tooltip: 'Mitteilungen',
                onPressed: () => info(
                  'Mitteilungen',
                  'Keine lokalen Mitteilungen. Ein Benachrichtigungsdienst ist nicht eingerichtet.',
                ),
                icon: const Icon(Icons.notifications_none),
              ),
          ],
          bottom: page == 1
              ? TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: tabs.map((t) => Tab(text: t.toUpperCase())).toList(),
                )
              : page == 2
              ? const TabBar(
                  tabs: [
                    Tab(text: 'Neue Session starten'),
                    Tab(text: 'Restart'),
                  ],
                )
              : null,
        ),
        drawer: Drawer(
          width: MediaQuery.sizeOf(context).width * .65,
          backgroundColor: const Color(0xff0c2732),
          child: SafeArea(
            child: Column(
              children: [
                const ListTile(
                  title: Text(
                    'FELT LEDGER',
                    style: TextStyle(
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text('Dein Spiel. Deine Übersicht.'),
                ),
                const Divider(),
                ...['Home', 'Bankroll', 'Live Session'].asMap().entries.map(
                  (e) => ListTile(
                    selected: page == e.key,
                    leading: Icon(
                      [
                        Icons.home_outlined,
                        Icons.account_balance_wallet_outlined,
                        Icons.play_circle_outline,
                      ][e.key],
                    ),
                    title: Text(e.value),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => page = e.key);
                    },
                  ),
                ),
                const Spacer(),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Settings'),
                  onTap: () async {
                    Navigator.pop(context);
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SettingsScreen(
                          repo: repo,
                          onChanged: widget.onPreferences,
                        ),
                      ),
                    );
                    await refresh();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Account'),
                  onTap: () {
                    Navigator.pop(context);
                    account();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const Text('Bug Report'),
                  onTap: () {
                    Navigator.pop(context);
                    info(
                      'Bug Report',
                      'Beschreibe den Fehler, die Schritte und deine App-Version (Bankroll Tracker 0.1.3). Es werden keine Daten oder Logs automatisch versendet. Projektkontakt: Besitzer dieses lokalen Projekts.',
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        body: page == 0
            ? home()
            : page == 1
            ? Column(
                children: [
                  if (currencies.length > 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: DropdownButton<String>(
                        value: reportCurrency,
                        items: currencies
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text('Währung: $c'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => reportCurrency = v!),
                      ),
                    ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        overview(),
                        sessions(),
                        locationList(),
                        diagrams(),
                        trend(),
                        staking(),
                        maintenance(),
                      ],
                    ),
                  ),
                ],
              )
            : TabBarView(
                children: [
                  liveScreen(),
                  list([
                    card('Restart', [
                      const Text(
                        'Neustart abgeschlossener Sessions gehört zu den späteren Funktionen. Eine neue Session kann jederzeit separat gestartet werden.',
                      ),
                    ]),
                  ]),
                ],
              ),
        floatingActionButton: Builder(
          builder: (tabContext) {
            final controller = DefaultTabController.of(tabContext);
            return AnimatedBuilder(
              animation: controller,
              builder: (context, child) {
                if (page == 1 && controller.index == 4) {
                  return const SizedBox.shrink();
                }
                return widget.prefs['floatingButtons'] != false && page != 2
                    ? FloatingActionButton(
                        onPressed: () => showModalBottomSheet(
                          context: context,
                          builder: (c) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.edit_outlined),
                                  title: const Text('Session eintragen'),
                                  onTap: () {
                                    Navigator.pop(c);
                                    form();
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.play_arrow),
                                  title: const Text('Live Session starten'),
                                  onTap: () {
                                    Navigator.pop(c);
                                    setState(() => page = 2);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        child: const Icon(Icons.add),
                      )
                    : const SizedBox.shrink();
              },
            );
          },
        ),
      ),
    );
  }

  Widget monthMetric(
    String current,
    String previous,
    String label, {
    (num, num)? outcomes,
  }) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: current,
                    style: TextStyle(
                      color: outcomes == null || outcomes.$1 == 0
                          ? null
                          : outcomes.$1 < 0
                          ? negative
                          : positive,
                    ),
                  ),
                  const TextSpan(text: '/'),
                  TextSpan(
                    text: previous,
                    style: TextStyle(
                      color: outcomes == null || outcomes.$2 == 0
                          ? null
                          : outcomes.$2 < 0
                          ? negative
                          : positive,
                    ),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(color: Color(0xff78a5b7), fontSize: 9),
          ),
        ],
      ),
    ),
  );

  Widget home() {
    final now = DateTime.now();
    final current = all
        .where(
          (e) =>
              e.start.year == now.year &&
              e.start.month == now.month &&
              e.currency == reportCurrency,
        )
        .toList();
    final prevDate = DateTime(now.year, now.month - 1);
    final prev = all
        .where(
          (e) =>
              e.start.year == prevDate.year &&
              e.start.month == prevDate.month &&
              e.currency == reportCurrency,
        )
        .toList();
    final a = totals(current), b = totals(prev);
    return list([
      const Text(
        'Deine letzte Session',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 14),
      if (all.where((e) => e.session).isEmpty)
        card('Bereit für deine erste Session?', [
          const Text(
            'Erfasse ein Spiel oder starte den Live-Timer. Deine Bankroll beginnt ohne Beispieldaten.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => form(),
            icon: const Icon(Icons.add),
            label: const Text('Session eintragen'),
          ),
        ])
      else
        sessionCard(
          all.firstWhere((e) => e.session),
          expanded: true,
          actions: false,
        ),
      card('Aktueller Monat / Letzter Monat', [
        Row(
          children: [
            monthMetric(
              '${a.sessions.length}',
              '${b.sessions.length}',
              'SESSIONS',
            ),
            monthMetric(number(a.hours), number(b.hours), 'STUNDEN'),
            monthMetric(
              money(a.profit),
              money(b.profit),
              'NETTO PROFIT',
              outcomes: (a.profit, b.profit),
            ),
            monthMetric(
              money(a.hourly),
              money(b.hourly),
              'HOURLY',
              outcomes: (a.hourly, b.hourly),
            ),
          ],
        ),
        Row(
          children: [
            monthMetric(
              '${number(a.roi)}%',
              '${number(b.roi)}%',
              'ROI',
              outcomes: (a.roi, b.roi),
            ),
          ],
        ),
      ]),
      card('3-Monats-Trend', [
        LedgerChart(
          values: all
              .where(
                (e) =>
                    e.start.isAfter(DateTime(now.year, now.month - 2)) &&
                    e.currency == reportCurrency,
              )
              .toList()
              .reversed
              .map((e) => result(e).toDouble())
              .toList(),
          cumulative: true,
        ),
        line(
          'Zeitraum',
          Text('${date(DateTime(now.year, now.month - 2))} – ${date(now)}'),
        ),
      ]),
    ]);
  }

  Color? resultColor(String text, String metric) {
    final financial = [
      'profit',
      'roi',
      '€/h',
      '€/100',
      'einzahl',
      'auszahl',
      'gesamtergebnis',
      'gewonn',
      'bb/h',
      'bb/100',
      'gewinne',
      'verluste',
    ].any((k) => metric.toLowerCase().contains(k));
    if (!financial || text.isEmpty || !RegExp(r'[1-9]').hasMatch(text)) {
      return null;
    }
    if (metric.toLowerCase().contains('gewonn')) {
      final value = double.tryParse(
        text.replaceAll('%', '').replaceAll(',', '.').trim(),
      );
      return value == null
          ? null
          : value >= 50
          ? positive
          : negative;
    }
    return text.contains('−') || text.contains('-') ? negative : positive;
  }

  Widget table(List<String> headings, List<List<String>> rows) => LayoutBuilder(
    builder: (c, bounds) {
      Widget cell(
        String text,
        int col, {
        bool heading = false,
        String metric = '',
      }) {
        final isCash = text == 'CG',
            isTournament = text == 'Turnier' && heading;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          child: Align(
            alignment: col == 0 ? Alignment.centerLeft : Alignment.centerRight,
            child: isCash || isTournament
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.monetization_on_outlined,
                        size: 18,
                        color: isCash ? accent : tournamentColor,
                      ),
                      Text(
                        isCash ? 'CG' : 'TURNIER',
                        style: TextStyle(
                          fontSize: 8,
                          color: isCash ? accent : tournamentColor,
                        ),
                      ),
                    ],
                  )
                : Text(
                    text,
                    softWrap: true,
                    textAlign: col == 0 ? TextAlign.left : TextAlign.right,
                    style: TextStyle(
                      fontSize: heading
                          ? 13
                          : bounds.maxWidth < 340
                          ? 11.5
                          : 13,
                      fontWeight: heading ? FontWeight.w500 : FontWeight.normal,
                      color: heading ? null : resultColor(text, metric),
                    ),
                  ),
          ),
        );
      }

      final widths = <int, TableColumnWidth>{
        0: FlexColumnWidth(headings.length == 4 ? 1.8 : 1.4),
      };
      return Table(
        columnWidths: widths,
        defaultColumnWidth: const FlexColumnWidth(),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xff35505d))),
            ),
            children: [
              for (var i = 0; i < headings.length; i++)
                cell(headings[i], i, heading: true),
            ],
          ),
          for (var row = 0; row < rows.length; row++)
            TableRow(
              decoration: BoxDecoration(
                color: row.isEven
                    ? Colors.black.withValues(alpha: .06)
                    : Colors.transparent,
              ),
              children: [
                for (var col = 0; col < headings.length; col++)
                  cell(
                    rows[row][col],
                    col,
                    metric: col > 0 ? rows[row][0] : '',
                  ),
              ],
            ),
        ],
      );
    },
  );
  Widget overview() {
    final t = totals(included),
        cg = totals(included.where((e) => e.kind == kinds[0]).toList()),
        tr = totals(
          included.where((e) => kinds.sublist(1, 3).contains(e.kind)).toList(),
        );
    final opening = bankrolls
        .where((b) => b['currency'] == reportCurrency)
        .fold<int>(0, (n, b) => n + (b['opening'] as int? ?? 0));
    final columns = [cg, tr, t];
    return list([
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Gesamt',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          money(opening + t.balanceEffect, fixed: true),
                          key: const ValueKey('overview-balance'),
                          style: TextStyle(
                            fontSize: 29,
                            fontWeight: FontWeight.w300,
                            color: opening + t.balanceEffect < 0
                                ? negative
                                : positive,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              table(
                ['Bilanz', 'CG', 'Turnier', 'Gesamt'],
                [
                  for (final field in ['Buy-in', 'Cash-out', 'Netto Profit'])
                    [
                      field,
                      ...columns.map(
                        (x) => money(
                          field == 'Buy-in'
                              ? x.invested
                              : field == 'Cash-out'
                              ? x.cashOut
                              : x.profit,
                        ),
                      ),
                    ],
                  [
                    'Einzahlungen',
                    '',
                    '',
                    money(
                      included
                          .where((e) => isTransfer(e.kind) && e.transfer > 0)
                          .fold<int>(0, (n, e) => n + e.transfer),
                    ),
                  ],
                  [
                    'Auszahlungen',
                    '',
                    '',
                    money(
                      included
                          .where((e) => isTransfer(e.kind) && e.transfer < 0)
                          .fold<int>(0, (n, e) => n + e.transfer),
                    ),
                  ],
                  [
                    'Staking',
                    '',
                    '',
                    money(
                      included
                          .where((e) => e.kind == 'Staking')
                          .fold<int>(0, (n, e) => n + e.rawProfit),
                    ),
                  ],
                  if (included.any(
                    (e) =>
                        !e.session &&
                        !isTransfer(e.kind) &&
                        e.kind != 'Staking',
                  ))
                    [
                      'Weitere Buchungen',
                      '',
                      '',
                      money(
                        included
                            .where(
                              (e) =>
                                  !e.session &&
                                  !isTransfer(e.kind) &&
                                  e.kind != 'Staking',
                            )
                            .fold<int>(0, (n, e) => n + result(e)),
                      ),
                    ],
                  if (opening != 0) ['Startkapital', '', '', money(opening)],
                  [
                    'Gesamtergebnis',
                    money(cg.profit),
                    money(tr.profit),
                    money(opening + t.balanceEffect),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
      card('', [
        table(
          ['Sessions', 'CG', 'Turnier', 'Gesamt'],
          [
            for (final metric in [
              'Sessions',
              'Stunden',
              'Hände',
              '€/h',
              '€/100',
              'ROI',
              'Gewonnen',
              'Ø Buy-in',
              'Ø Profit',
              'Ø Rebuys',
            ])
              [
                metric,
                ...columns.map((x) {
                  final count = x.sessions.length;
                  return switch (metric) {
                    'Sessions' => '$count',
                    'Stunden' => number(x.hours),
                    'Hände' => number(x.hands),
                    '€/h' => money(x.hourly),
                    '€/100' => money(x.per100),
                    'ROI' => '${number(x.roi)} %',
                    'Gewonnen' => '${number(x.win)} %',
                    'Ø Buy-in' => money(count == 0 ? 0 : x.invested / count),
                    'Ø Profit' => money(count == 0 ? 0 : x.profit / count),
                    _ => number(
                      count == 0
                          ? 0
                          : x.sessions.fold<int>(
                                  0,
                                  (n, e) => n + e.n('rebuys'),
                                ) /
                                count,
                    ),
                  };
                }),
              ],
          ],
        ),
      ]),
      card('Spiele', [
        ...games.map((g) {
          final s = totals(
            included.where((e) => e.s('game') == g['id']).toList(),
          );
          return line(
            g['name'],
            Text(
              '${number(s.hours)} h   ${money(s.hourly)}/h   ${money(s.profit)}',
            ),
          );
        }),
      ]),
      ...['Cash Game', 'Turnier'].map((kind) {
        final rows = <List<String>>[];
        for (final group
            in kind == 'Cash Game'
                ? ['Heads-Up', 'Short-Handed', 'Full-Ring']
                : ['Turnier', 'Mehrtages Turnier']) {
          final stats = totals(
            included
                .where(
                  (e) => kind == 'Cash Game'
                      ? e.kind == kind && e.s('tableSize') == group
                      : e.kind == group,
                )
                .toList(),
          );
          rows.add([
            group,
            '${stats.sessions.length}',
            number(stats.hours),
            money(stats.profit),
          ]);
        }
        final stats = kind == 'Cash Game' ? cg : tr;
        final wins = stats.sessions.where((e) => result(e) > 0).toList(),
            losses = stats.sessions.where((e) => result(e) < 0).toList();
        return Card(
          child: ExpansionTile(
            title: Text(kind),
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    table(['Gruppe', 'Sessions', 'Stunden', 'Profit'], rows),
                    if (kind == 'Cash Game')
                      table(
                        ['Stakes (Big Blind)', 'Stunden', '€/h', 'Profit'],
                        [
                          for (final blind
                              in stats.sessions
                                  .map((e) => e.n('bigBlind'))
                                  .toSet()
                                  .toList()
                                ..sort())
                            ...() {
                              final tier = totals(
                                stats.sessions
                                    .where((e) => e.n('bigBlind') == blind)
                                    .toList(),
                              );
                              return [
                                [
                                  money(blind),
                                  number(tier.hours),
                                  money(tier.hourly),
                                  money(tier.profit),
                                ],
                              ];
                            }(),
                        ],
                      ),
                    line(
                      'Rebuys',
                      Text(
                        '${stats.sessions.fold<int>(0, (n, e) => n + e.n('rebuys'))}',
                      ),
                    ),
                    if (kind == 'Cash Game') ...[
                      line(
                        'BB/h',
                        Text(
                          number(stats.hours == 0 ? 0 : stats.bb / stats.hours),
                        ),
                      ),
                      line(
                        'BB/100 Hände',
                        Text(
                          number(
                            stats.hands == 0 ? 0 : stats.bb / stats.hands * 100,
                          ),
                        ),
                      ),
                    ],
                    line(
                      'Ø Gewinn',
                      value(
                        wins.isEmpty
                            ? 0
                            : wins.fold<int>(0, (n, e) => n + result(e)) /
                                  wins.length,
                      ),
                    ),
                    line(
                      'Ø Verlust',
                      value(
                        losses.isEmpty
                            ? 0
                            : losses.fold<int>(0, (n, e) => n + result(e)) /
                                  losses.length,
                      ),
                    ),
                    if (kind == 'Turnier') ...[
                      line(
                        'Bounty Gewinne',
                        value(
                          stats.sessions.fold<int>(
                            0,
                            (n, e) => n + e.n('bounty'),
                          ),
                        ),
                      ),
                      line(
                        'In den Geldrängen / ausbezahlt',
                        Text(
                          '${stats.sessions.where((e) => e.n('cashOut') + e.n('bounty') > 0).length}',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    ]);
  }

  Widget sessionMetrics(Entry e) {
    if (!e.session) {
      return Column(
        children: [
          if (e.kind == 'Staking') ...[
            line('Einsatz', Text(money(e.n('stakingBoughtCost')))),
            line('Auszahlung', Text(money(e.n('stakingBoughtReturn')))),
            if (e.n('stakingSettlement') != 0)
              line('Abrechnung', value(e.n('stakingSettlement'))),
          ],
          line(isTransfer(e.kind) ? 'Betrag' : 'Ergebnis', value(result(e))),
        ],
      );
    }

    Widget metric(String v, String label, {num? outcome}) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              v,
              style: TextStyle(
                fontSize: 14,
                color: outcome == null || outcome == 0
                    ? null
                    : outcome < 0
                    ? negative
                    : positive,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: Color(0xff78a5b7), fontSize: 10),
            ),
          ],
        ),
      ),
    );
    final roi = investment(e) == 0 ? 0 : 100 * result(e) / investment(e);
    final hourly = e.hours == 0 ? 0 : result(e) / e.hours;
    return Column(
      children: [
        Row(
          children: [
            metric(money(e.n('buyIn')), 'BUY-IN'),
            metric(money(e.n('cashOut')), 'CASH-OUT'),
            metric(money(hourly), 'HOURLY', outcome: hourly),
          ],
        ),
        Row(
          children: [
            metric('${e.n('rebuys')}', 'REBUYS'),
            metric(money(e.n('rebuyCost')), 'REBUY KOSTEN'),
            metric('${number(roi)}%', 'ROI', outcome: roi),
          ],
        ),
        Row(
          children: [
            metric(DateFormat.Hm().format(e.start), 'START'),
            metric(DateFormat.Hm().format(e.end), 'ENDE'),
            metric(
              '${e.seconds ~/ 3600}:${((e.seconds % 3600) ~/ 60).toString().padLeft(2, '0')}',
              'DAUER',
            ),
          ],
        ),
        Row(
          children: [
            metric(e.s('tableSize'), 'TISCHGRÖSSE'),
            metric(
              locations
                      .where((l) => l['id'] == e.s('location'))
                      .map((l) => '${l['room']}')
                      .firstOrNull ??
                  '—',
              'ART',
            ),
            metric(e.currency, 'WÄHRUNG'),
          ],
        ),
      ],
    );
  }

  Widget sessionCard(Entry e, {bool expanded = false, bool actions = true}) =>
      Card(
        key: ValueKey(e.id),
        child: ExpansionTile(
          key: PageStorageKey('session-${e.id}'),
          initiallyExpanded: expanded,
          showTrailingIcon: false,
          dense: true,
          visualDensity: VisualDensity.compact,
          minTileHeight: 0,
          tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          shape: const Border(),
          collapsedShape: const Border(),
          title: SessionSummary(
            key: ValueKey('summary-${e.id}'),
            title: sessionGameLabel(
              e,
              games.where((g) => g['id'] == e.s('game')).firstOrNull,
            ),
            location: e.session ? name(locations, e.s('location')) : '',
            date:
                widget.prefs['dateFormat'] == null ||
                    widget.prefs['dateFormat'] == 'dd.MM.yyyy'
                ? DateFormat('EEE, d. MMM yyyy', 'de').format(e.start)
                : date(e.start),
            result: money(result(e)),
            kind: e.kind,
            outcome: result(e),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  sessionMetrics(e),
                  if (e.s('note').isNotEmpty)
                    line('Notiz', Flexible(child: Text(e.s('note')))),
                  if (e.session)
                    SessionChart(
                      entry: e,
                      active: false,
                      truePerformance: widget.prefs['truePerformance'] != false,
                    ),
                  if (actions)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => form(entry: e),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Bearbeiten'),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            if (await confirm(
                              'Eintrag löschen?',
                              'Dieser Eintrag wird dauerhaft von diesem Gerät gelöscht.',
                            )) {
                              await guarded(() => repo.deleteEntry(e.id));
                            }
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Löschen'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      );
  Widget sessions() => list([
    if (included.isEmpty) empty('Keine Einträge für diese Auswahl.'),
    for (final year in included.map((e) => e.start.year).toSet()) ...[
      Center(
        child: Container(
          margin: const EdgeInsets.only(bottom: 18, top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xff0c2732),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            '$year',
            style: const TextStyle(color: Color(0xff88a5b2), fontSize: 13),
          ),
        ),
      ),
      ...included.where((e) => e.start.year == year).map((e) => sessionCard(e)),
    ],
    if (included.any((e) => e.session))
      card('Beste Sessions', [
        ...(included.where((e) => e.session).toList()
              ..sort((a, b) => result(b).compareTo(result(a))))
            .take(5)
            .map(
              (e) => line(
                '${date(e.start)} · ${name(locations, e.s('location'))}',
                value(result(e)),
              ),
            ),
      ]),
  ]);
  Widget locationList() => list([
    if (locations.isEmpty)
      card('Locations', [
        const Text('Lege eine Location an, um deine Spielorte zu vergleichen.'),
        TextButton(
          onPressed: () => definition('location'),
          child: const Text('Location hinzufügen'),
        ),
      ]),
    ...locations.map((location) {
      final stats = totals(
        included.where((e) => e.s('location') == location['id']).toList(),
      );
      return Card(
        child: ListTile(
          title: Text(location['name']),
          subtitle: Text(
            '${location['room'] ?? 'Home Game'} · ${location['currency'] ?? 'EUR'}\n${stats.entries.length} Einträge · ${number(stats.hours)} h · ${number(stats.win)} % gewonnen',
          ),
          isThreeLine: true,
          trailing: value(stats.profit),
          onTap: () => locationDetail(location, stats),
        ),
      );
    }),
  ]);
  void locationDetail(Json location, Totals stats) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Location Info')),
          body: list([
            card(location['name'], [
              LedgerChart(
                values: stats.entries.reversed
                    .map((e) => result(e).toDouble())
                    .toList(),
                cumulative: true,
              ),
              line('Netto Profit', value(stats.profit)),
              line('ROI', Text('${number(stats.roi)} %')),
              line(
                'Gewonnen / Verloren',
                Text(
                  '${stats.sessions.where((e) => result(e) > 0).length} / ${stats.sessions.where((e) => result(e) < 0).length}',
                ),
              ),
              line(
                'Stunden / €/h',
                Text('${number(stats.hours)} / ${money(stats.hourly)}'),
              ),
              ...entryKinds.map(
                (k) => line(
                  k,
                  Text(
                    '${stats.entries.where((e) => matchesKind(e, k)).length}',
                  ),
                ),
              ),
            ]),
            ...stats.entries.map((e) => sessionCard(e)),
          ]),
        ),
      ),
    );
  }

  Widget diagrams() {
    final now = DateTime.now();
    final performance = widget.prefs['truePerformance'] != false;
    final months = monthlyReport(
      included,
      now,
      reportMonths,
      truePerformance: performance,
    );
    final years = yearlyReport(included, now, truePerformance: performance);
    return list([
      card('Monatsübersicht', [
        DropdownButtonFormField<int>(
          key: const ValueKey('report-months'),
          initialValue: reportMonths,
          decoration: const InputDecoration(labelText: 'ZEITRAUM'),
          items: [3, 6, 12, 24, 36]
              .map(
                (n) =>
                    DropdownMenuItem(value: n, child: Text('Letzte $n Monate')),
              )
              .toList(),
          onChanged: (v) => setState(() => reportMonths = v!),
        ),
        const SizedBox(height: 16),
        PeriodProfitChart(
          buckets: months,
          monthly: true,
          money: (n) => money(n),
        ),
      ]),
      card('Jahresübersicht', [
        PeriodProfitChart(
          buckets: years,
          monthly: false,
          money: (n) => money(n),
        ),
      ]),
      const Padding(
        padding: EdgeInsets.all(8),
        child: Text(
          'Ergebnisse inklusive Staking, ohne Ein- und Auszahlungen. Monate und Jahre werden getrennt ausgewertet; leere Zeiträume bleiben sichtbar.',
          style: TextStyle(color: Colors.blueGrey, fontSize: 12),
        ),
      ),
    ]);
  }

  Widget trend() {
    final data = trendEntries(
      included,
      now: DateTime.now(),
      period: period,
      category: trendKind,
      metric: trendMetric,
    );
    Widget chart(double height) => TrendChart(
      entries: data,
      money: (n) => money(n),
      fill: fill,
      sessionAxis: trendMetric == 'Netto Profit/Sessions',
      truePerformance: widget.prefs['truePerformance'] != false,
      height: height,
    );
    Widget control(String label, bool selected, VoidCallback onTap) => Expanded(
      child: TextButton(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 14),
          minimumSize: const Size(0, 44),
          foregroundColor: selected ? accent : const Color(0xff7895a1),
        ),
        onPressed: onTap,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
    return list([
      Card(
        semanticContainer: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('trend-metric'),
                initialValue: trendMetric,
                decoration: const InputDecoration(labelText: 'ART'),
                items:
                    [
                          'Gesamtergebnis',
                          'Netto Profit/Datum',
                          'Netto Profit/Sessions',
                        ]
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                onChanged: (v) => setState(() => trendMetric = v!),
              ),
              const SizedBox(height: 12),
              chart(
                (MediaQuery.sizeOf(context).height * .55)
                    .clamp(300, 570)
                    .toDouble(),
              ),
            ],
          ),
        ),
      ),
      Card(
        child: Column(
          children: [
            Row(
              children: [
                for (final p in ['1W', '1M', '3M', 'YTD', '1J', '3J', 'MAX'])
                  control(p, period == p, () => setState(() => period = p)),
              ],
            ),
            const Divider(height: 1),
            Row(
              children: [
                control(
                  'CASH GAME',
                  trendKind == 'Cash Game',
                  () => setState(() => trendKind = 'Cash Game'),
                ),
                control(
                  'TURNIER',
                  trendKind == 'Turnier',
                  () => setState(() => trendKind = 'Turnier'),
                ),
                control(
                  'GESAMT',
                  trendKind == 'Alle',
                  () => setState(() => trendKind = 'Alle'),
                ),
                control('FÜLLUNG', fill, () => setState(() => fill = !fill)),
              ],
            ),
          ],
        ),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: IconButton.filledTonal(
          tooltip: 'Trend vergrößern',
          icon: const Icon(Icons.open_in_full),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (c) => Scaffold(
                appBar: AppBar(title: Text(trendMetric)),
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: LayoutBuilder(builder: (c, b) => chart(b.maxHeight)),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget staking() {
    final rows = included
        .where(
          (e) =>
              e.kind == 'Staking' ||
              e.n('soldBp') > 0 ||
              e.n('stakingSettlement') != 0 ||
              e.n('stakingBoughtCost') > 0 ||
              e.n('stakingBoughtReturn') > 0,
        )
        .toList();
    return list([
      card('Staking', [
        if (rows.isEmpty)
          const Text(
            'Noch keine Staking-Einträge. Staking kann separat oder als Anteil einer eigenen Session erfasst werden.',
          ),
        ...rows.map(
          (e) => line(
            e.kind == 'Staking'
                ? '${date(e.start)} · Staking'
                : '${date(e.start)} · ${number(e.n('soldBp') / 100)} % verkauft',
            value(result(e)),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Berechnung: (Cash-out + Bounty − Buy-in − Rebuys − Chipausgaben − Ausgaben) × eigener Anteil + vereinbarte Abrechnung + gekaufte Auszahlung − gekaufter Einsatz. „True Performance“ steuert die Auswertung.',
        ),
      ]),
    ]);
  }

  Widget maintenance() => list([
    card('Bankroll', [
      line('Einträge', Text('${all.length}')),
      line(
        'Startkapital',
        Text(
          money(
            bankrolls
                .where((b) => b['currency'] == reportCurrency)
                .fold<int>(
                  0,
                  (n, b) => n + ((b['opening'] as num?)?.toInt() ?? 0),
                ),
          ),
        ),
      ),
      if (bankrolls.isNotEmpty)
        TextButton.icon(
          onPressed: () => definition('bankroll', existing: bankrolls.first),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Startkapital / Währung bearbeiten'),
        ),
    ]),
    for (final cat in ['location', 'game'])
      card(cat == 'location' ? 'Locations verwalten' : 'Spiele verwalten', [
        ...(cat == 'location' ? locations : games).map(
          (d) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(d['name']),
            subtitle: Text(
              d['hidden'] == true
                  ? 'In Eingabe ausgeblendet'
                  : 'In Eingabe sichtbar',
            ),
            onTap: () => definition(cat, existing: d),
            trailing: IconButton(
              tooltip: 'Zusammenführen',
              icon: const Icon(Icons.merge),
              onPressed: () => merge(cat, d),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () => definition(cat),
          icon: const Icon(Icons.add),
          label: Text(
            cat == 'location' ? 'Location erstellen' : 'Spiel erstellen',
          ),
        ),
      ]),
    card('Wartung', [
      ListTile(
        title: const Text('Duplikate suchen'),
        subtitle: const Text('Nur prüfen; keine automatische Löschung'),
        onTap: duplicates,
      ),
      const ListTile(
        title: Text('Bulk Tags · Papierkorb'),
        subtitle: Text('Für spätere Versionen vorgesehen'),
        enabled: false,
      ),
    ]),
  ]);
  Future<void> definition(String cat, {Json? existing}) async {
    final d = Map<String, dynamic>.from(
      existing ??
          {
            'id': newId(),
            'name': '',
            'currency': widget.prefs['currency'] ?? reportCurrency,
            'opening': 0,
            'included': true,
            'room': 'Home Game',
            'limit': 'NL',
            'hidden': false,
            'bigBlind': 0,
            'smallBlind': 0,
            'thirdBlind': 0,
            'ante': 0,
          },
    );
    final title = cat == 'bankroll'
        ? 'Bankroll'
        : cat == 'location'
        ? 'Location'
        : 'Spiel';
    final n = TextEditingController(text: d['name']);
    final opening = TextEditingController(
      text: existing == null ? '' : moneyInput(d['opening'] ?? 0),
    );
    final bb = TextEditingController(
      text: existing == null ? '' : moneyInput(d['bigBlind'] ?? 0),
    );
    final sb = TextEditingController(
      text: existing == null ? '' : moneyInput(d['smallBlind'] ?? 0),
    );
    final ante = TextEditingController(
      text: existing == null ? '' : moneyInput(d['ante'] ?? 0),
    );
    final third = TextEditingController(
      text: existing == null ? '' : moneyInput(d['thirdBlind'] ?? 0),
    );
    final originalAmounts = {
      for (final key in [
        'opening',
        'bigBlind',
        'smallBlind',
        'thirdBlind',
        'ante',
      ])
        key: d[key] ?? 0,
    };
    String? error;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text(
            '$title ${existing == null ? 'erstellen' : 'bearbeiten'}',
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
                if (cat != 'game')
                  DropdownButtonFormField<String>(
                    initialValue: d['currency'],
                    decoration: const InputDecoration(labelText: 'Währung'),
                    items: ['EUR', 'USD', 'GBP', 'CHF']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (s) => d['currency'] = s,
                  ),
                if (cat == 'bankroll')
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: TextField(
                      controller: opening,
                      decoration: const InputDecoration(
                        labelText: 'Startkapital',
                      ),
                    ),
                  ),
                if (cat == 'location')
                  DropdownButtonFormField<String>(
                    initialValue: d['room'],
                    decoration: const InputDecoration(labelText: 'Raumtyp'),
                    items: ['Home Game', 'Casino', 'Online', 'Sonstige']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (s) => d['room'] = s,
                  ),
                if (cat == 'game') ...[
                  DropdownButtonFormField<String>(
                    initialValue: d['limit'],
                    items: ['NL', 'PL', 'FL', 'Sonstige']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (s) => d['limit'] = s,
                  ),
                  for (final pair in [
                    ('Small Blind', sb),
                    ('Big Blind', bb),
                    ('Third Blind', third),
                    ('Ante', ante),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: TextField(
                        controller: pair.$2,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => update(() {}),
                        decoration: InputDecoration(
                          labelText: pair.$1,
                          hintText:
                              pair.$1 == 'Small Blind' &&
                                  bb.text.trim().isNotEmpty
                              ? defaultSmallBlindHint(bb.text)
                              : '0,00',
                        ),
                      ),
                    ),
                ],
                if (cat != 'bankroll')
                  SwitchListTile(
                    title: const Text('In Eingabe ausblenden'),
                    value: d['hidden'] == true,
                    onChanged: (v) => update(() => d['hidden'] = v),
                  ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: negative)),
              ],
            ),
          ),
          actions: [
            if (existing != null && cat != 'bankroll')
              TextButton(
                onPressed: () async {
                  final count = all
                      .where(
                        (e) =>
                            e.s(cat == 'location' ? 'location' : 'game') ==
                            d['id'],
                      )
                      .length;
                  if (await confirm(
                    '$title und Einträge löschen?',
                    '$count zugeordnete Einträge in allen Bankrolls werden dauerhaft gelöscht. Zum Erhalten der Einträge stattdessen ausblenden oder zusammenführen.',
                  )) {
                    try {
                      await repo.deleteDefinitionAndEntries(cat, d['id']);
                      if (c.mounted) Navigator.pop(c);
                    } catch (e) {
                      update(() => error = e.toString());
                    }
                  }
                },
                child: const Text('Löschen', style: TextStyle(color: negative)),
              ),
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
                  d['name'] = n.text.trim();
                  if (cat == 'bankroll') {
                    d['opening'] =
                        existing != null &&
                            opening.text ==
                                moneyInput(originalAmounts['opening'])
                        ? originalAmounts['opening']
                        : amount(opening.text);
                    if (existing != null &&
                        d['currency'] != existing['currency'] &&
                        all.any((e) => e.bankroll == d['id'])) {
                      throw const FormatException(
                        'Währung einer befüllten Bankroll ist nicht änderbar',
                      );
                    }
                  }
                  if (cat == 'location' &&
                      existing != null &&
                      d['currency'] != existing['currency'] &&
                      all.any((e) => e.s('location') == d['id'])) {
                    throw const FormatException(
                      'Bestehende Einträge behalten ihre Währung; bitte neue Location erstellen',
                    );
                  }
                  if (cat == 'game') {
                    d['bigBlind'] =
                        existing != null &&
                            bb.text == moneyInput(originalAmounts['bigBlind'])
                        ? originalAmounts['bigBlind']
                        : amount(bb.text);
                    d['smallBlind'] = sb.text.trim().isEmpty
                        ? defaultSmallBlind(d['bigBlind'])
                        : existing != null &&
                              sb.text ==
                                  moneyInput(originalAmounts['smallBlind'])
                        ? originalAmounts['smallBlind']
                        : amount(sb.text);
                    d['thirdBlind'] =
                        existing != null &&
                            third.text ==
                                moneyInput(originalAmounts['thirdBlind'])
                        ? originalAmounts['thirdBlind']
                        : amount(third.text);
                    d['ante'] =
                        existing != null &&
                            ante.text == moneyInput(originalAmounts['ante'])
                        ? originalAmounts['ante']
                        : amount(ante.text);
                    if ([
                      d['bigBlind'],
                      d['smallBlind'],
                      d['thirdBlind'],
                      d['ante'],
                    ].any((v) => v < 0)) {
                      throw const FormatException('Blinds müssen positiv sein');
                    }
                  }
                  if (existing != null &&
                      cat != 'bankroll' &&
                      !await confirm(
                        'Definition ändern?',
                        '${all.where((e) => e.s(cat == 'location' ? 'location' : 'game') == d['id']).length} zugeordnete Einträge in allen Bankrolls werden unter dieser Definition angezeigt.',
                      )) {
                    return;
                  }
                  if (existing != null && cat != 'bankroll') {
                    await repo.replaceDefinition(cat, d);
                  } else {
                    await repo.saveDefinition(cat, d);
                  }
                  if (c.mounted) Navigator.pop(c);
                } catch (e) {
                  update(() => error = e.toString());
                }
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
    await refresh();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    for (final t in [n, opening, bb, sb, third, ante]) {
      t.dispose();
    }
  }

  Future<void> merge(String cat, Json source) async {
    final defs = (cat == 'location' ? locations : games)
        .where(
          (e) =>
              e['id'] != source['id'] &&
              (cat != 'location' || e['currency'] == source['currency']),
        )
        .toList();
    if (defs.isEmpty) {
      await info(
        'Zusammenführen',
        'Keine passende zweite Definition vorhanden.',
      );
      return;
    }
    String target = defs.first['id'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Zusammenführen'),
        content: DropdownButtonFormField<String>(
          initialValue: target,
          items: defs
              .map(
                (d) => DropdownMenuItem<String>(
                  value: d['id'],
                  child: Text(d['name']),
                ),
              )
              .toList(),
          onChanged: (v) => target = v!,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Weiter'),
          ),
        ],
      ),
    );
    if (ok == true &&
        await confirm(
          'Zusammenführen bestätigen',
          '${all.where((e) => e.s(cat == 'location' ? 'location' : 'game') == source['id']).length} Einträge in allen Bankrolls werden zugeordnet. „${source['name']}“ wird entfernt.',
        )) {
      await guarded(
        () => repo.replaceDefinition(cat, source, mergeInto: target),
      );
    }
  }

  Future<void> duplicates() async {
    final seen = <String, Entry>{};
    final matches = <Entry>[];
    for (final e in all) {
      final key =
          '${e.start.toIso8601String()}|${e.kind}|${e.invested}|${e.n('cashOut')}|${e.s('location')}|${e.s('game')}|${e.currency}';
      if (seen.containsKey(key)) {
        matches.add(e);
      } else {
        seen[key] = e;
      }
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Mögliche Duplikate')),
          body: list([
            const Text(
              'Gleicher Start, Typ, Buy-in, Cash-out, Location, Spiel und Währung. Gleich aussehende legitime Sessions bitte behalten.',
            ),
            const SizedBox(height: 16),
            if (matches.isEmpty) empty('Keine möglichen Duplikate gefunden.'),
            ...matches.map((e) => sessionCard(e)),
          ]),
        ),
      ),
    );
    await refresh();
  }

  Future<void> filters() async {
    final draft = filter.copy();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + MediaQuery.viewInsetsOf(c).bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Bankroll Filter', style: TextStyle(fontSize: 22)),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    initialValue: draft.kind,
                    decoration: const InputDecoration(labelText: 'Art'),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Alle'),
                      ),
                      ...entryKinds.map(
                        (s) => DropdownMenuItem(value: s, child: Text(s)),
                      ),
                    ],
                    onChanged: (v) => draft.kind = v,
                  ),
                  const SizedBox(height: 14),
                  for (final pair in [
                    ('Location', locations),
                    ('Spiel', games),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: DropdownButtonFormField<String>(
                        initialValue: pair.$1 == 'Location'
                            ? draft.location
                            : draft.game,
                        decoration: InputDecoration(labelText: pair.$1),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('Alle'),
                          ),
                          ...pair.$2.map(
                            (d) => DropdownMenuItem<String>(
                              value: d['id'],
                              child: Text(d['name']),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          if (pair.$1 == 'Location') {
                            draft.location = v;
                          } else {
                            draft.game = v;
                          }
                        },
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: c,
                              initialDate: draft.from ?? DateTime.now(),
                              firstDate: DateTime(1980),
                              lastDate: DateTime(2100),
                            );
                            if (d != null) update(() => draft.from = d);
                          },
                          child: Text(
                            draft.from == null
                                ? 'Von Datum'
                                : date(draft.from!),
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextButton(
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: c,
                              initialDate: draft.to ?? DateTime.now(),
                              firstDate: DateTime(1980),
                              lastDate: DateTime(2100),
                            );
                            if (d != null) update(() => draft.to = d);
                          },
                          child: Text(
                            draft.to == null ? 'Bis Datum' : date(draft.to!),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'Erweiterte Filter: Blinds, Chipausgaben, Platzierung, Spieler, Bounty, Kalender, Dauer und Geldbereiche folgen später.',
                    style: TextStyle(color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() => filter = EntryFilter());
                          Navigator.pop(c);
                        },
                        child: const Text('Zurücksetzen'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('Abbrechen'),
                      ),
                      FilledButton(
                        onPressed: () {
                          if (draft.from != null &&
                              draft.to != null &&
                              draft.to!.isBefore(draft.from!)) {
                            return;
                          }
                          setState(() => filter = draft);
                          Navigator.pop(c);
                        },
                        child: const Text('Filter'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> account() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Account')),
          body: list([
            card('Lokal · Ohne Server', [
              const Text(
                'Bankroll Tracker funktioniert offline und ohne Konto. Login, Registrierung, Cloud-Synchronisierung und Cloud-Wiederherstellung sind für diese lokale Version nicht verfügbar.',
              ),
              for (final title in [
                'Login',
                'Registrierung',
                'Synchronisieren',
                'Cloud-Wiederherstellung',
              ])
                ListTile(
                  leading: const Icon(Icons.cloud_off),
                  title: Text(title),
                  onTap: () => info(
                    title,
                    'Diese Funktion benötigt einen eigenen Dienst und gehört nicht zur lokalen Version. Deine lokalen Daten bleiben nutzbar.',
                  ),
                ),
            ]),
            card('Daten verwalten', [
              for (final title in [
                'Import from Poker Bankroll Tracker',
                'CSV importieren',
                'CSV exportieren',
                'Vollständiges Backup / Wiederherstellen',
              ])
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(title),
                  subtitle: const Text('Geplant: finaler 1.0-Meilenstein'),
                  onTap: () => info(
                    title,
                    'Import, Export und vollständige Migration werden nach dem Kern-App-Vergleich im finalen 1.0-Meilenstein implementiert. Quelldateien, Vorschau, Abgleich und Rücknahme müssen dann validiert werden.',
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: negative),
                title: const Text('Alle lokalen Einträge löschen'),
                subtitle: const Text(
                  'Bankroll-Definitionen und Einstellungen bleiben erhalten. Kein Cloud-Konto vorhanden.',
                ),
                onTap: () async {
                  if (await confirm(
                    'Alle Einträge löschen?',
                    'Alle Sessions, Finanzbewegungen, die laufende Session und Migrationsarchive auf diesem Gerät werden dauerhaft gelöscht.',
                  )) {
                    await guarded(() async {
                      await repo.clearLocal();
                      await DeviceServices.cancelReminder();
                    });
                    if (mounted) Navigator.pop(context);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: negative),
                title: const Text('Alle lokalen Daten zurücksetzen'),
                subtitle: const Text(
                  'Auch Bankrolls, Startkapital, Locations, Spiele und Einstellungen.',
                ),
                onTap: () async {
                  if (await confirm(
                    'Gesamte lokale App zurücksetzen?',
                    'Alle Einträge, Bankrolls mit Startkapital, Definitionen, Einstellungen und laufenden Sessions werden dauerhaft gelöscht. Es gibt keine Cloud-Kopie.',
                  )) {
                    await DeviceServices.cancelReminder();
                    await guarded(repo.resetAll);
                    await widget.onPreferences();
                    if (mounted) Navigator.pop(context);
                  }
                },
              ),
            ]),
            card('Version / Status', [
              const Text(
                'Bankroll Tracker 0.1 · Lokaler Entwicklungsstand\nKeine Abos oder Käufe. Keine Übernahme fremder Lizenzen.\nVollständige Version 1.0: Migration noch ausstehend.',
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget liveScreen() {
    if (live == null) {
      return list([
        card('Neue Session starten', [
          const Text(
            'Wähle Spiel, Location und Buy-in. Erst „Start“ legt eine laufende Session an. Ein Konto oder Standortzugriff ist nicht erforderlich.',
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => form(startLive: true),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Session konfigurieren'),
          ),
        ]),
      ]);
    }
    final e = Entry(live!);
    final paused = live!['pausedAt'] != null;
    final now = DateTime.now();
    final breakNow = paused
        ? now.difference(DateTime.parse(live!['pausedAt'])).inSeconds
        : 0;
    final elapsed =
        now.difference(e.start).inSeconds - e.n('breakSeconds') - breakNow;
    return list([
      card(paused ? 'Session pausiert' : 'Session läuft', [
        Text(
          '${(elapsed ~/ 3600).toString().padLeft(2, '0')}:${((elapsed % 3600) ~/ 60).toString().padLeft(2, '0')}:${(elapsed % 60).toString().padLeft(2, '0')}',
          style: const TextStyle(fontSize: 48, color: accent),
        ),
        Text('${e.kind} · ${name(locations, e.s('location'))}'),
        line('Investiert', value(e.invested)),
        line('Rebuys / Add-ons', Text('${e.n('rebuys')} / ${e.n('addOns')}')),
        line(
          'Aktueller Stack',
          value(
            e.events
                    .where((v) => v['kind'] == 'stack')
                    .map((v) => (v['value'] as num).toInt())
                    .lastOrNull ??
                e.n('buyIn'),
          ),
        ),
        line(
          'Pause',
          Text('${number((e.n('breakSeconds') + breakNow) / 60)} min'),
        ),
        FilledButton.icon(
          onPressed: () => guarded(() async {
            final l = Map<String, dynamic>.from(live!);
            final events = Entry(l).events;
            if (paused) {
              await DeviceServices.cancelReminder();
              final at = l.remove('pausedAt');
              final seconds = DateTime.now()
                  .difference(DateTime.parse(at))
                  .inSeconds;
              l['breakSeconds'] = (l['breakSeconds'] as int? ?? 0) + seconds;
              events.add({
                'kind': 'break',
                'at': at,
                'end': DateTime.now().toUtc().toIso8601String(),
              });
            } else {
              l['pausedAt'] = DateTime.now().toUtc().toIso8601String();
            }
            l['events'] = events;
            await repo.setState('live', l);
          }),
          icon: Icon(paused ? Icons.play_arrow : Icons.pause),
          label: Text(paused ? 'Fortsetzen' : 'Pause starten'),
        ),
        if (paused)
          TextButton.icon(
            onPressed: pauseReminder,
            icon: const Icon(Icons.alarm),
            label: const Text('Pausen-Timer setzen'),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => liveEvent('rebuy'),
              child: const Text('Rebuy'),
            ),
            OutlinedButton(
              onPressed: () => liveEvent('addon'),
              child: const Text('Add-on'),
            ),
            OutlinedButton(
              onPressed: () => liveEvent('stack'),
              child: const Text('Stack aktualisieren'),
            ),
            OutlinedButton(
              onPressed: () => liveEvent('note'),
              child: const Text('Notiz'),
            ),
          ],
        ),
        SessionChart(
          entry: e,
          active: true,
          truePerformance: widget.prefs['truePerformance'] != false,
        ),
        FilledButton(onPressed: finish, child: const Text('Session beenden')),
        TextButton(
          onPressed: () async {
            if (await confirm(
              'Laufende Session verwerfen?',
              'Es wird kein fertiger Eintrag gespeichert.',
            )) {
              await guarded(() async {
                await repo.setState('live', null);
                await DeviceServices.cancelReminder();
              });
            }
          },
          child: const Text('Verwerfen'),
        ),
      ]),
      card('Session-Ereignisse', [
        ...e.events.reversed.map(
          (v) => line(
            DateFormat.Hm().format(DateTime.parse(v['at']).toLocal()),
            Flexible(
              child: Text(
                '${eventName(v['kind'])} · ${(v['note']?.toString().isNotEmpty == true ? v['note'] : (v['value'] == null ? '' : money(v['value'])))}',
              ),
            ),
          ),
        ),
      ]),
    ]);
  }

  Future<void> pauseReminder() async {
    if (live == null || live!['pausedAt'] == null) return;
    if (widget.prefs['notifications'] != true) {
      await info(
        'Pausenerinnerung',
        'Aktiviere Benachrichtigungen in Settings und erlaube sie ausdrücklich in Android.',
      );
      return;
    }
    final controller = TextEditingController();
    final minutes = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Restpause planen'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Minuten ab jetzt (mindestens 3)',
            hintText: '15',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(controller.text);
              if (n != null && n >= 3) Navigator.pop(c, n);
            },
            child: const Text('Erinnerung setzen'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    controller.dispose();
    if (minutes == null) return;
    final at = DateTime.now().add(Duration(minutes: minutes - 2));
    try {
      await DeviceServices.remindAt(at);
      await info(
        'Erinnerung gesetzt',
        'Android benachrichtigt ungefähr zwei Minuten vor dem geplanten Pausenende. Energiesparregeln können Alarme verzögern.',
      );
    } catch (e) {
      await info('Erinnerung nicht gesetzt', e.toString());
    }
  }

  Future<void> liveEvent(String kind) async {
    if (live == null) return;
    final id = live!['id'] as String;
    final text = TextEditingController(), stack = TextEditingController();
    final purchase = kind == 'rebuy' || kind == 'addon';
    String? error;
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text(
            purchase
                ? kind == 'rebuy'
                      ? 'Rebuy erfassen'
                      : 'Add-on erfassen'
                : kind == 'stack'
                ? 'Stack aktualisieren'
                : 'Notiz erfassen',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey('eventValue'),
                  controller: text,
                  autofocus: true,
                  keyboardType: kind == 'note'
                      ? TextInputType.multiline
                      : const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: kind == 'note'
                        ? 'Notiz'
                        : purchase
                        ? 'Kaufbetrag'
                        : 'Aktueller Stack',
                    hintText: kind == 'note' ? null : '0,00',
                  ),
                ),
                if (purchase) ...[
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('resultingStack'),
                    controller: stack,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Stack nach dem Kauf',
                      hintText: '0,00',
                    ),
                  ),
                ],
                if (error != null)
                  Text(error!, style: const TextStyle(color: negative)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(c),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (busy) return;
                      update(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        if (kind != 'note' && text.text.trim().isEmpty) {
                          throw const FormatException('Betrag erforderlich');
                        }
                        final value = kind == 'note' ? 0 : amount(text.text);
                        if (value < 0 || purchase && value == 0) {
                          throw const FormatException(
                            'Kaufbetrag muss positiv sein',
                          );
                        }
                        if (purchase) {
                          if (stack.text.trim().isEmpty) {
                            throw const FormatException(
                              'Stack nach dem Kauf erforderlich',
                            );
                          }
                          await repo.recordPurchase(
                            id,
                            kind,
                            value,
                            amount(stack.text),
                          );
                        } else {
                          await repo.recordObservation(
                            id,
                            kind,
                            value,
                            text.text,
                          );
                        }
                        if (c.mounted) Navigator.pop(c);
                        await refresh();
                      } catch (e) {
                        if (c.mounted) {
                          update(() {
                            error = e.toString();
                            busy = false;
                          });
                        }
                      }
                    },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    text.dispose();
    stack.dispose();
  }

  Future<void> finish() async {
    final l = Map<String, dynamic>.from(live!);
    final now = DateTime.now();
    if (l['pausedAt'] != null) {
      final at = l.remove('pausedAt');
      l['breakSeconds'] =
          (l['breakSeconds'] as int? ?? 0) +
          now.difference(DateTime.parse(at)).inSeconds;
      l['events'] = [
        ...Entry(l).events,
        {'kind': 'break', 'at': at, 'end': now.toIso8601String()},
      ];
    }
    l['end'] = now.toIso8601String();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EntryForm(
          repo: repo,
          bankrolls: bankrolls,
          locations: locations,
          games: games,
          entry: Entry(l),
          finishing: true,
          prefs: widget.prefs,
        ),
      ),
    );
    await refresh();
    if (live == null) await DeviceServices.cancelReminder();
  }
}

class LedgerChart extends StatelessWidget {
  final List<double> values;
  final bool cumulative, fill;
  final List<DateTime>? dates;
  const LedgerChart({
    super.key,
    required this.values,
    this.cumulative = false,
    this.fill = true,
    this.dates,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 180,
    child: values.isEmpty
        ? const Center(
            child: Text(
              'Noch keine Daten',
              style: TextStyle(color: Colors.blueGrey),
            ),
          )
        : CustomPaint(
            painter: _Chart(values, cumulative, fill, dates),
            size: Size.infinite,
          ),
  );
}

class _Chart extends CustomPainter {
  final List<double> data;
  final bool cumulative, fill;
  final List<DateTime>? dates;
  _Chart(this.data, this.cumulative, this.fill, this.dates);
  @override
  void paint(Canvas canvas, Size size) {
    final values = <double>[0];
    double total = 0;
    for (final v in data) {
      total = cumulative ? total + v : v;
      values.add(total);
    }
    final low = values.reduce((a, b) => a < b ? a : b),
        high = values.reduce((a, b) => a > b ? a : b);
    final span = high == low ? 1 : high - low;
    final w = size.width, h = size.height - 30;
    final grid = Paint()
      ..color = Colors.blueGrey.withValues(alpha: .25)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(Offset(0, i * h / 3), Offset(w, i * h / 3), grid);
    }
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      var x = i * w / (values.length - 1);
      if (dates != null && dates!.length == data.length && dates!.length > 1) {
        final duration = dates!.last.difference(dates!.first).inMicroseconds;
        if (duration > 0) {
          x = i == 0
              ? 0
              : dates![i - 1].difference(dates!.first).inMicroseconds /
                    duration *
                    w;
        }
      }
      final y = h - (values[i] - low) / span * h;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    if (fill) {
      final area = Path.from(path)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      canvas.drawPath(area, Paint()..color = accent.withValues(alpha: .12));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );
    for (final tuple in [(low, h), (high, 0.0)]) {
      final p = TextPainter(
        text: TextSpan(
          text: (tuple.$1 / unit).toStringAsFixed(2),
          style: const TextStyle(color: Colors.blueGrey, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      p.paint(canvas, Offset(4, tuple.$2));
    }
  }

  @override
  bool shouldRepaint(covariant _Chart oldDelegate) => true;
}
