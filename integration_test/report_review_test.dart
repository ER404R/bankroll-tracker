import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:felt_ledger/domain.dart';
import 'package:felt_ledger/entry_form.dart';
import 'package:felt_ledger/main.dart';
import 'package:felt_ledger/reports.dart';
import 'package:felt_ledger/repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Home actions, report windows, original Trend controls and new transactions preserve existing history',
    (tester) async {
      final repo = await LedgerRepository.open();
      final before = (await repo.entries()).map((e) => e.id).toSet();
      final created = <String>[];
      Future<void> pumpApp() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.pumpWidget(LedgerApp(repo: repo));
        await tester.pumpAndSettle();
      }

      Future<void> page(String name) async {
        await tester.tap(find.byTooltip('Navigationsmenü öffnen'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();
      }

      Future<void> tab(String name) async {
        final target = find.widgetWithText(Tab, name);
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      try {
        await pumpApp();
        expect(find.text('Bearbeiten'), findsNothing);
        expect(find.text('Löschen'), findsNothing);
        await page('Bankroll');
        final balance = find.byKey(const ValueKey('overview-balance'));
        final alignment = find
            .ancestor(of: balance, matching: find.byType(Align))
            .first;
        expect(
          tester.getBottomRight(balance).dx,
          closeTo(tester.getBottomRight(alignment).dx, 1),
        );
        await tab('DIAGRAMME');
        expect(find.text('Wochentag'), findsNothing);
        expect(find.text('Monatsübersicht'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('report-months')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Letzte 3 Monate').last);
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<PeriodProfitChart>(find.byType(PeriodProfitChart))
              .first
              .buckets,
          hasLength(3),
        );
        await tab('TREND');
        expect(find.byType(TrendChart), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('CASH GAME'),
          250,
          scrollable: find
              .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(find.text('CASH GAME'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TrendChart>(find.byType(TrendChart))
              .entries
              .every((e) => e.kind == 'Cash Game'),
          isTrue,
        );
        await tester.tap(find.text('TURNIER'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TrendChart>(find.byType(TrendChart))
              .entries
              .every((e) => isTournament(e.kind)),
          isTrue,
        );
        await tester.tap(find.text('GESAMT'));
        await tester.tap(find.text('FÜLLUNG'));
        await tester.pumpAndSettle();
        expect(tester.widget<TrendChart>(find.byType(TrendChart)).fill, isTrue);
        await tab('SESSION');
        final first = (await repo.entries()).first;
        await tester.tap(find.byKey(ValueKey('summary-${first.id}')));
        await tester.pumpAndSettle();
        expect(find.text('Bearbeiten'), findsWidgets);
        expect(find.text('Löschen'), findsWidgets);
        // Create each new standalone transaction through its real form, then clean up only these records.
        for (final kind in ['Einzahlung', 'Auszahlung', 'Staking']) {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          final banks = await repo.definitions('bankroll');
          await tester.pumpWidget(
            MaterialApp(
              initialRoute: '/form',
              routes: {
                '/': (_) => const Scaffold(),
                '/form': (_) => EntryForm(
                  repo: repo,
                  bankrolls: banks,
                  locations: const [],
                  games: const [],
                  prefs: const {},
                ),
              },
            ),
          );
          await tester.pumpAndSettle();
          final art = find
              .byWidgetPredicate((w) => w is DropdownButtonFormField<String>)
              .first;
          await tester.tap(art);
          await tester.pumpAndSettle();
          expect(find.text('Jackpot/Bonus'), findsNothing);
          expect(find.text('Casino Games'), findsNothing);
          expect(find.text('Kosten'), findsNothing);
          await tester.tap(find.text(kind).last);
          await tester.pumpAndSettle();
          if (kind == 'Staking') {
            await tester.enterText(
              find.byKey(const ValueKey('stakingBoughtCost')),
              '30',
            );
            await tester.enterText(
              find.byKey(const ValueKey('stakingBoughtReturn')),
              '50',
            );
          } else {
            await tester.enterText(
              find.byKey(const ValueKey('transfer')),
              '20',
            );
          }
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          await tester.tap(find.text('Speichern'));
          await tester.pumpAndSettle();
          final entry = (await repo.entries())
              .where((e) => !before.contains(e.id) && !created.contains(e.id))
              .single;
          created.add(entry.id);
          expect(entry.kind, kind);
          expect(entry.profit(), amount(kind == 'Auszahlung' ? '-20' : '20'));
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        for (final id in created) {
          await repo.deleteEntry(id);
        }
        expect((await repo.entries()).map((e) => e.id).toSet(), before);
        await repo.db.close();
      }
    },
  );
}
