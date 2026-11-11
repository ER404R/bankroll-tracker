import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'domain.dart';

/// Calendar buckets retain the year and include empty periods.
class ReportBucket {
  final DateTime start;
  final List<Entry> entries;
  final int profit;
  ReportBucket(this.start, this.entries, {required bool truePerformance})
    : profit = entries.fold(
        0,
        (n, e) => n + e.profit(truePerformance: truePerformance),
      );
  int get sessions => entries.where((e) => e.session).length;
}

List<ReportBucket> monthlyReport(
  List<Entry> entries,
  DateTime now,
  int months, {
  bool truePerformance = true,
}) => List.generate(months, (i) {
  final start = DateTime(now.year, now.month - months + 1 + i);
  final end = DateTime(start.year, start.month + 1);
  return ReportBucket(
    start,
    entries
        .where(
          (e) =>
              !isTransfer(e.kind) &&
              !e.start.isBefore(start) &&
              e.start.isBefore(end) &&
              !e.start.isAfter(now),
        )
        .toList(),
    truePerformance: truePerformance,
  );
});
List<ReportBucket> yearlyReport(
  List<Entry> entries,
  DateTime now, {
  bool truePerformance = true,
}) {
  final eligible = entries
      .where((e) => !isTransfer(e.kind) && !e.start.isAfter(now))
      .toList();
  final first = eligible.fold(
    now.year,
    (year, e) => math.min(year, e.start.year),
  );
  return List.generate(
    now.year - first + 1,
    (i) => ReportBucket(
      DateTime(first + i),
      eligible.where((e) => e.start.year == first + i).toList(),
      truePerformance: truePerformance,
    ),
  );
}

DateTime shiftCalendarMonths(DateTime date, int months) {
  final first = DateTime(date.year, date.month + months);
  final day = math.min(date.day, DateTime(first.year, first.month + 1, 0).day);
  return DateTime(
    first.year,
    first.month,
    day,
    date.hour,
    date.minute,
    date.second,
  );
}

DateTime trendCutoff(DateTime now, String period) => switch (period) {
  '1W' => now.subtract(const Duration(days: 7)),
  '1M' => shiftCalendarMonths(now, -1),
  '3M' => shiftCalendarMonths(now, -3),
  'YTD' => DateTime(now.year),
  '1J' => shiftCalendarMonths(now, -12),
  '3J' => shiftCalendarMonths(now, -36),
  _ => DateTime(1),
};
List<Entry> trendEntries(
  List<Entry> entries, {
  required DateTime now,
  required String period,
  required String category,
  required String metric,
}) {
  final cutoff = trendCutoff(now, period);
  final result = entries
      .where(
        (e) =>
            !e.start.isBefore(cutoff) &&
            !e.start.isAfter(now) &&
            (category == 'Alle' || matchesKind(e, category)) &&
            (metric == 'Gesamtergebnis' || e.poker),
      )
      .toList();
  result.sort((a, b) {
    final date = a.start.compareTo(b.start);
    return date == 0 ? a.id.compareTo(b.id) : date;
  });
  return result;
}

class PeriodProfitChart extends StatelessWidget {
  final List<ReportBucket> buckets;
  final bool monthly;
  final String Function(num) money;
  const PeriodProfitChart({
    super.key,
    required this.buckets,
    required this.monthly,
    required this.money,
  });
  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 210,
        child: Semantics(
          container: true,
          label:
              'Ergebnis je ${monthly ? 'Kalendermonat' : 'Kalenderjahr'}, grün positiv, rot negativ',
          child: CustomPaint(
            painter: _PeriodPainter(buckets, monthly, money),
            size: Size.infinite,
          ),
        ),
      ),
      const SizedBox(height: 8),
      for (final bucket in buckets.reversed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  monthly
                      ? DateFormat('MMM yyyy', 'de').format(bucket.start)
                      : '${bucket.start.year}',
                ),
              ),
              Text(
                '${bucket.sessions} ${bucket.sessions == 1 ? 'Session' : 'Sessions'}',
                style: const TextStyle(color: Colors.blueGrey, fontSize: 11),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 95,
                child: Text(
                  money(bucket.profit),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: bucket.profit < 0
                        ? const Color(0xfff15d6b)
                        : bucket.profit > 0
                        ? const Color(0xff21da16)
                        : Colors.blueGrey,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class _PeriodPainter extends CustomPainter {
  final List<ReportBucket> buckets;
  final bool monthly;
  final String Function(num) money;
  _PeriodPainter(this.buckets, this.monthly, this.money);
  @override
  void paint(Canvas canvas, Size size) {
    final low = buckets.fold(0.0, (n, b) => math.min(n, b.profit.toDouble()));
    final high = buckets.fold(0.0, (n, b) => math.max(n, b.profit.toDouble()));
    final span = high == low ? unit.toDouble() : high - low;
    double y(num value) => 14 + (high - value) / span * 155;
    final zero = y(0);
    final paint = Paint()
      ..color = Colors.blueGrey.withValues(alpha: .35)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(54, zero), Offset(size.width, zero), paint);
    void label(String text, Offset at) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(color: Color(0xffa7bdc5), fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, at);
    }

    if (high != 0) label(money(high), const Offset(0, 0));
    label('0', Offset(0, zero - 7));
    if (low < 0) label(money(low), const Offset(0, 169));
    final step = (size.width - 54) / buckets.length;
    for (var i = 0; i < buckets.length; i++) {
      final bucket = buckets[i];
      final x = 54 + i * step;
      final end = y(bucket.profit);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            x + step * .2,
            math.min(zero, end),
            x + step * .8,
            math.max(zero, end) + (bucket.profit == 0 ? 1 : 0),
          ),
          const Radius.circular(3),
        ),
        Paint()
          ..color = bucket.profit < 0
              ? const Color(0xfff15d6b)
              : const Color(0xff21da16),
      );
      if (i % math.max(1, (buckets.length / 6).ceil()) == 0) {
        label(
          monthly
              ? DateFormat('MM/yy').format(bucket.start)
              : '${bucket.start.year}',
          Offset(x + 2, 188),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PeriodPainter oldDelegate) => true;
}

/// The reference Trend uses a large white line with monetary axes and dotted grid.
class TrendChart extends StatelessWidget {
  final List<Entry> entries;
  final bool fill, sessionAxis, truePerformance;
  final double height;
  final String Function(num) money;
  const TrendChart({
    super.key,
    required this.entries,
    required this.money,
    this.fill = false,
    this.sessionAxis = false,
    this.truePerformance = true,
    this.height = 420,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: entries.isEmpty
        ? const Center(
            child: Text(
              'Keine Einträge für diese Auswahl',
              style: TextStyle(color: Colors.blueGrey),
            ),
          )
        : Semantics(
            label:
                'Kumulativer Trend: ${entries.length} Einträge, ${money(entries.fold<int>(0, (n, e) => n + e.profit(truePerformance: truePerformance)))}',
            child: CustomPaint(
              painter: _TrendPainter(
                entries,
                fill,
                sessionAxis,
                truePerformance,
                money,
              ),
              size: Size.infinite,
            ),
          ),
  );
}

class _TrendPainter extends CustomPainter {
  final List<Entry> entries;
  final bool fill, sessionAxis, truePerformance;
  final String Function(num) money;
  _TrendPainter(
    this.entries,
    this.fill,
    this.sessionAxis,
    this.truePerformance,
    this.money,
  );
  @override
  void paint(Canvas canvas, Size size) {
    final values = <int>[0];
    for (final e in entries) {
      values.add(values.last + e.profit(truePerformance: truePerformance));
    }
    final low = values.reduce(math.min), high = values.reduce(math.max);
    final span = math.max(unit, high - low).toDouble();
    const left = 0.0, top = 24.0;
    final bottom = size.height - 24, width = size.width;
    double y(num value) => bottom - (value - low) / span * (bottom - top);
    void label(String text, double x, double y) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(color: Color(0xffd3dfe4), fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width);
      painter.paint(
        canvas,
        Offset(x.clamp(0, math.max(0, width - painter.width)), y),
      );
    }

    final grid = Paint()
      ..color = Colors.blueGrey.withValues(alpha: .3)
      ..strokeWidth = 1;
    for (final value in {
      low,
      high,
      0,
      low + (high - low) ~/ 3,
      low + 2 * (high - low) ~/ 3,
    }) {
      final at = y(value);
      for (double x = 0; x < width; x += 7) {
        canvas.drawLine(
          Offset(x, at),
          Offset(math.min(x + 2, width), at),
          grid,
        );
      }
      label(money(value), 4, math.max(0, at - 16));
    }
    for (var i = 1; i < 4; i++) {
      for (double yy = top; yy < bottom; yy += 7) {
        canvas.drawLine(
          Offset(width * i / 4, yy),
          Offset(width * i / 4, math.min(yy + 2, bottom)),
          grid,
        );
      }
    }
    final path = Path()..moveTo(left, y(0));
    final elapsed = entries.last.start
        .difference(entries.first.start)
        .inMicroseconds;
    for (var i = 0; i < entries.length; i++) {
      final x = sessionAxis || elapsed <= 0
          ? (i + 1) * width / entries.length
          : entries[i].start.difference(entries.first.start).inMicroseconds /
                elapsed *
                width;
      path.lineTo(x, y(values[i + 1]));
    }
    if (fill) {
      final area = Path.from(path)
        ..lineTo(width, y(0))
        ..lineTo(0, y(0))
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x6049afd0), Color(0x1049afd0)],
          ).createShader(Rect.fromLTWH(0, top, width, bottom - top)),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xffeef4f6)
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke,
    );
    final first = sessionAxis
        ? '0'
        : DateFormat('dd.MM.yyyy').format(entries.first.start);
    final last = sessionAxis
        ? '${entries.length} Sessions'
        : DateFormat('dd.MM.yyyy').format(entries.last.start);
    label(first, 0, bottom + 8);
    label(last, width, bottom + 8);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) => true;
}
