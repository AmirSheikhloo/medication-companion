import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../core/storage/app_database.dart';
import '../domain/health_metric.dart';

/// Descriptive dots and short adjacent-day segments only. Missing days are
/// never interpolated; glucose contexts are never joined into one trajectory.
class HealthChart extends StatelessWidget {
  const HealthChart({
    super.key,
    required this.metric,
    required this.records,
  });

  final HealthMetric metric;
  final List<HealthMeasurement> records;

  @override
  Widget build(BuildContext context) {
    final valid = [
      for (final record in records)
        if (record.metric == metric.name &&
            record.unit == metric.unit &&
            record.primaryMilliunits > 0)
          record,
    ]..sort((a, b) => a.observedAt.compareTo(b.observedAt));
    if (valid.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text('داده قابل‌نمایش در نمودار وجود ندارد.'),
      );
    }
    return Semantics(
      label: 'نمودار توصیفی ${metric.label} با ${valid.length} نقطه ثبت‌شده',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 210,
            width: double.infinity,
            child: CustomPaint(
              painter: _HealthChartPainter(metric, valid),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'از ${healthDateTimeLabel(valid.first.observedAt)}'
            ' تا ${healthDateTimeLabel(valid.last.observedAt)}',
            style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
          ),
          if (metric == HealthMetric.pressure)
            const Text('آبی: عدد بالا • سبز: عدد پایین',
                style: TextStyle(fontSize: 12)),
          if (metric == HealthMetric.glucose)
            const Text(
              'نقاط قند با شرایط مختلف به هم وصل نمی‌شوند؛ '
              'میانگین‌ها به تفکیک شرایط محاسبه می‌شوند.',
              style: TextStyle(fontSize: 12),
            ),
          const Text(
            'فاصله‌های بدون ثبت، دادهٔ تخمینی یا اندازه‌گیری نشده نیستند.',
            style: TextStyle(fontSize: 11, color: Colors.blueGrey),
          ),
        ],
      ),
    );
  }
}

class _HealthChartPainter extends CustomPainter {
  _HealthChartPainter(this.metric, this.entries);

  final HealthMetric metric;
  final List<HealthMeasurement> entries;

  @override
  void paint(Canvas canvas, Size size) {
    final values = <int>[
      for (final entry in entries) entry.primaryMilliunits,
      if (metric.hasSecondValue)
        for (final entry in entries)
          if (entry.secondaryMilliunits != null &&
              entry.secondaryMilliunits! > 0)
            entry.secondaryMilliunits!,
    ];
    if (values.isEmpty || size.width < 90 || size.height < 70) return;
    final left = 52.0;
    final right = size.width - 12;
    final top = 14.0;
    final bottom = size.height - 23;
    final minRaw = values.reduce(math.min) / 1000;
    final maxRaw = values.reduce(math.max) / 1000;
    final span = (maxRaw - minRaw).abs();
    final pad = math.max(span * 0.12, 1.0);
    final minimum = math.max(0.0, minRaw - pad);
    final maximum = maxRaw + pad;
    final firstMs = entries.first.observedAt.millisecondsSinceEpoch;
    final lastMs = entries.last.observedAt.millisecondsSinceEpoch;
    final timeSpan = math.max(lastMs - firstMs, 1);
    final paintAxis = Paint()
      ..color = const Color(0xFFB0BEC5)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = top + (bottom - top) * i / 4;
      canvas.drawLine(Offset(left, y), Offset(right, y), paintAxis);
      final value = maximum - (maximum - minimum) * i / 4;
      _label(canvas, value.toStringAsFixed(1), 1.0, y - 7);
    }
    double xOf(HealthMeasurement entry) {
      if (lastMs == firstMs) return (left + right) / 2;
      return left +
          (entry.observedAt.millisecondsSinceEpoch - firstMs) /
              timeSpan *
              (right - left);
    }

    double yOf(int milliunits) =>
        bottom - ((milliunits / 1000 - minimum) / (maximum - minimum)) *
            (bottom - top);

    void series(bool secondary, Color color) {
      final points = <(HealthMeasurement, int)>[];
      for (final entry in entries) {
        final value = secondary
            ? entry.secondaryMilliunits
            : entry.primaryMilliunits;
        if (value != null && value > 0) points.add((entry, value));
      }
      final line = Paint()
        ..color = color.withValues(alpha: 0.75)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      for (var i = 0; i < points.length; i++) {
        final current = points[i];
        final center = Offset(xOf(current.$1), yOf(current.$2));
        if (i > 0 && metric != HealthMetric.glucose) {
          final before = points[i - 1];
          final gap = current.$1.observedAt.difference(before.$1.observedAt);
          if (!gap.isNegative && gap <= const Duration(hours: 48)) {
            canvas.drawLine(
              Offset(xOf(before.$1), yOf(before.$2)),
              center,
              line,
            );
          }
        }
        final pointColor = metric == HealthMetric.glucose
            ? switch (current.$1.context) {
                'fasting' => const Color(0xFF0277BD),
                'before_meal' => const Color(0xFF008577),
                'after_meal' => const Color(0xFFFF8F00),
                _ => const Color(0xFF6D4C92),
              }
            : color;
        canvas.drawCircle(center, 3.5, Paint()..color = pointColor);
      }
    }

    series(false, const Color(0xFF0277BD));
    if (metric.hasSecondValue) series(true, const Color(0xFF008577));
  }

  void _label(Canvas canvas, String text, double x, double y) {
    final paragraph = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Color(0xFF546E7A), fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    paragraph.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant _HealthChartPainter oldDelegate) =>
      oldDelegate.metric != metric || oldDelegate.entries != entries;
}
