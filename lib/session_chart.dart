import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'domain.dart';

String eventName(String kind) => switch (kind) {
  'rebuy' => 'Rebuy',
  'addon' => 'Add-on',
  'stack' => 'Stack',
  'note' => 'Notiz',
  'break' => 'Pause',
  _ => kind,
};

class StackPoint {
  final DateTime at;
  final int stack, profit;
  StackPoint(this.at, this.stack, this.profit);
}

List<StackPoint> stackPoints(
  Entry entry, {
  bool active = false,
  bool truePerformance = true,
}) {
  final points = [StackPoint(entry.start, entry.n('buyIn'), 0)];
  var invested = entry.n('buyIn');
  final indexed = entry.events.asMap().entries.toList()
    ..sort((a, b) {
      final c = a.value['at'].compareTo(b.value['at']) as int;
      return c == 0 ? a.key.compareTo(b.key) : c;
    });
  final events = indexed.map((e) => e.value);
  for (final event in events) {
    if (event['kind'] == 'rebuy' || event['kind'] == 'addon') {
      invested += (event['value'] as num).toInt();
    }
    if (event['kind'] == 'stack') {
      final stack = (event['value'] as num).toInt();
      final raw = stack - invested;
      points.add(
        StackPoint(
          DateTime.parse(event['at']).toLocal(),
          stack,
          truePerformance ? raw * (10000 - entry.n('soldBp')) ~/ 10000 : raw,
        ),
      );
    }
  }
  if (!active) {
    points.add(
      StackPoint(
        entry.end,
        entry.n('cashOut'),
        entry.profit(truePerformance: truePerformance),
      ),
    );
  }
  return points;
}

class SessionChart extends StatelessWidget {
  final Entry entry;
  final bool active, truePerformance;
  const SessionChart({
    super.key,
    required this.entry,
    this.active = false,
    this.truePerformance = true,
  });
  void showEvents(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Erfasste Ereignisse'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Linien verbinden nur Start, Ende und erfasste Stack-Werte. Ausgaben, Bountys und Abrechnung fließen am Ende in den Netto-Profit ein.',
                ),
                const SizedBox(height: 16),
                if (entry.events.isEmpty)
                  const Text('Keine zusätzlichen Ereignisse erfasst.'),
                ...entry.events.map((e) {
                  final value = e['kind'] == 'note'
                      ? e['note'] ?? ''
                      : e['value'] == null
                      ? ''
                      : moneyInput((e['value'] as num).toInt());
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '${DateFormat('dd.MM. HH:mm').format(DateTime.parse(e['at']).toLocal())} · ${eventName(e['kind'])}\n$value',
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        label: 'Stack gestrichelt, Profit als Farbverlauf mit Fläche und Nulllinie. Erfasste Ereignisse öffnen.',
        button: true,
        child: InkWell(
          onTap: () => showEvents(context),
          child: SizedBox(
            height: 180,
            child: CustomPaint(
              painter: _SessionPainter(entry, active, truePerformance),
              size: Size.infinite,
            ),
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 5),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              '┄ STACK',
              style: TextStyle(color: Color(0xff62c0da), fontSize: 11),
            ),
            Text('&', style: TextStyle(color: Colors.blueGrey, fontSize: 11)),
            Text(
              '━ PROFIT',
              style: TextStyle(color: Color(0xfff15d6b), fontSize: 11),
            ),
            Text(
              'R Rebuy · A Add-on · N Notiz',
              style: TextStyle(color: Colors.blueGrey, fontSize: 10),
            ),
          ],
        ),
      ),
    ],
  );
}

class _SessionPainter extends CustomPainter {
  final Entry entry;
  final bool active, truePerformance;
  _SessionPainter(this.entry, this.active, this.truePerformance);
  @override
  void paint(Canvas canvas, Size size) {
    final points = stackPoints(
      entry,
      active: active,
      truePerformance: truePerformance,
    );
    final end = active ? DateTime.now() : entry.end;
    final span = end.difference(entry.start).inMilliseconds;
    final bounds = ChartBounds.of(points.expand((p) => [p.stack, p.profit]));
    final low = bounds.low, high = bounds.high, delta = bounds.span;
    final top = 18.0, bottom = size.height - 20, w = size.width;
    double x(DateTime d) => span <= 0
        ? 0
        : (d.difference(entry.start).inMilliseconds / span).clamp(0, 1) * w;
    double y(int n) => bottom - (n - low) / delta * (bottom - top);
    final grid = Paint()
      ..color = Colors.blueGrey.withValues(alpha: .23)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final line = top + (bottom - top) * i / 3;
      canvas.drawLine(Offset(0, line), Offset(w, line), grid);
    }
    final zeroY = y(0);
    final plot = Rect.fromLTRB(0, top, w, bottom);
    final profitPath = Path(), stackPath = Path();
    for (var i = 0; i < points.length; i++) {
      final dx = x(points[i].at);
      if (i == 0) {
        profitPath.moveTo(dx, y(points[i].profit));
        stackPath.moveTo(dx, y(points[i].stack));
      } else {
        profitPath.lineTo(dx, y(points[i].profit));
        stackPath.lineTo(dx, y(points[i].stack));
      }
    }
    final area = Path.from(profitPath)
      ..lineTo(x(points.last.at), zeroY)
      ..lineTo(x(points.first.at), zeroY)
      ..close();
    final zeroFraction = ((zeroY - top) / (bottom - top)).clamp(0.0, 1.0);
    canvas.save();
    canvas.clipPath(area);
    canvas.drawRect(
      plot,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xff21da16).withValues(alpha: .27),
            const Color(0xfff15d6b).withValues(alpha: .07),
            const Color(0xfff15d6b).withValues(alpha: .30),
          ],
          stops: [0, zeroFraction, 1],
        ).createShader(plot),
    );
    canvas.restore();
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(w, zeroY),
      Paint()
        ..color = const Color(0xffadccd7)
        ..strokeWidth = 1.2,
    );
    final dashed = Path();
    for (final metric in stackPath.computeMetrics()) {
      for (var start = 0.0; start < metric.length; start += 8) {
        dashed.addPath(
          metric.extractPath(start, (start + 4.5).clamp(0, metric.length)),
          Offset.zero,
        );
      }
    }
    canvas.drawPath(
      dashed,
      Paint()
        ..color = const Color(0xff62c0da)
        ..strokeWidth = 1.9
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      profitPath,
      Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xffd2b44c),
            const Color(0xffef9a64),
            points.last.profit > 0
                ? const Color(0xff21da16)
                : const Color(0xfff15d6b),
          ],
        ).createShader(plot)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    final zeroLabel = TextPainter(
      text: const TextSpan(
        text: '0',
        style: TextStyle(
          fontSize: 10,
          color: Color(0xffdceaf0),
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    zeroLabel.paint(canvas, Offset(3, zeroY - 14));
    for (final e in entry.events.where(
      (e) =>
          e['kind'] == 'rebuy' || e['kind'] == 'addon' || e['kind'] == 'note',
    )) {
      final dx = x(DateTime.parse(e['at']));
      canvas.drawLine(
        Offset(dx, top),
        Offset(dx, bottom),
        Paint()
          ..color = Colors.blueGrey.withValues(alpha: .45)
          ..strokeWidth = 1,
      );
      final text = TextPainter(
        text: TextSpan(
          text: e['kind'] == 'rebuy'
              ? 'R'
              : e['kind'] == 'addon'
              ? 'A'
              : 'N',
          style: const TextStyle(fontSize: 10, color: Colors.blueGrey),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(dx.clamp(0, w - 10), 1));
    }
    for (final tuple in [(low, bottom), (high, top)]) {
      final text = TextPainter(
        text: TextSpan(
          text: ('${(tuple.$1 / unit).toStringAsFixed(2)} ${entry.currency}')
              .replaceAll('.', ','),
          style: const TextStyle(fontSize: 9, color: Colors.blueGrey),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(3, tuple.$2));
    }
  }

  @override
  bool shouldRepaint(covariant _SessionPainter oldDelegate) => true;
}
