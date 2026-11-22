import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../core/calendar/persian_date.dart';
import '../../../core/ui/app_design.dart';

/// A conversational date belongs with the daily summary, not in a large card.
String todayReadablePersianDate(DateTime date) {
  const weekdays = <String>[
    'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه', 'شنبه', 'یکشنبه',
  ];
  const months = <String>[
    'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
    'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
  ];
  final local = date.toLocal();
  final persian = PersianDate.fromGregorian(local);
  return '${weekdays[local.weekday - 1]}، '
      '${PersianDate.persianDigits('${persian.day}')} '
      '${months[persian.month - 1]}';
}

Color todayDoseStatusColor(String status) => switch (status) {
  'taken' => AppColors.success,
  'skipped' => const Color(0xFFD34E58),
  'unknown' => const Color(0xFFDD962E),
  _ => const Color(0xFFD6E2E4),
};

Color todayDoseCardBackground(String status) => switch (status) {
  'taken' => const Color(0xFFD9EFE4), // Distinct desaturated mint-green for taken.
  'skipped' => const Color(0xFFF9DEE3), // Distinct desaturated rose for skipped.
  'unknown' => const Color(0xFFFFE8CB), // Distinct desaturated amber for unsure.
  _ => Colors.white,
};

/// Unlike a single green progress arc, each segment preserves the *actual*
/// logged outcome. An unlogged slot stays neutral gray.
class TodayStatusRing extends StatelessWidget {
  const TodayStatusRing({super.key, required this.statuses, this.size = 88});

  final List<String> statuses;
  final double size;

  @override
  Widget build(BuildContext context) {
    final taken = statuses.where((value) => value == 'taken').length;
    return Semantics(
      label: PersianDate.persianDigits(
        '$taken از ${statuses.length} نوبت مصرف‌شده'),
      child: SizedBox(
        width: size, height: size,
        child: Stack(alignment: Alignment.center, children: [
          Positioned.fill(child: CustomPaint(
            key: const Key('today-multistatus-ring'),
            painter: _TodayStatusRingPainter(statuses),
          )),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              PersianDate.persianDigits('$taken/${statuses.length}'),
              maxLines: 1,
              style: const TextStyle(fontFamily: 'Vazirmatn',
                fontSize: 20, fontWeight: FontWeight.bold,
                color: AppColors.primaryDark),
            ),
          ),
        ]),
      ),
    );
  }
}

class _TodayStatusRingPainter extends CustomPainter {
  const _TodayStatusRingPainter(this.statuses);
  final List<String> statuses;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Rect.fromLTWH(5, 5, size.width - 10, size.height - 10);
    final base = Paint()
      ..color = const Color(0xFFD6E2E4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawArc(bounds, 0, 2 * math.pi, false, base);
    if (statuses.isEmpty) return;
    final angle = 2 * math.pi / statuses.length;
    for (var i = 0; i < statuses.length; i++) {
      final status = statuses[i];
      if (status == 'pending') continue;
      final pen = Paint()
        ..color = todayDoseStatusColor(status)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8;
      canvas.drawArc(bounds, -math.pi / 2 + i * angle + .024,
          math.max(.01, angle - .048), false, pen);
    }
  }

  @override
  bool shouldRepaint(_TodayStatusRingPainter oldDelegate) {
    if (oldDelegate.statuses.length != statuses.length) return true;
    for (var i = 0; i < statuses.length; i++) {
      if (oldDelegate.statuses[i] != statuses[i]) return true;
    }
    return false;
  }
}

/// A single clock-to-visual mapping keeps the greeting, icon and sky in sync.
enum TodaySkyPhase { morning, noon, evening, night }

TodaySkyPhase todaySkyPhaseForHour(int hour) {
  if (hour >= 5 && hour < 11) return TodaySkyPhase.morning;
  if (hour >= 11 && hour < 16) return TodaySkyPhase.noon;
  if (hour >= 16 && hour < 18) return TodaySkyPhase.evening;
  return TodaySkyPhase.night;
}

String todayGreetingForHour(int hour) => switch (todaySkyPhaseForHour(hour)) {
      TodaySkyPhase.morning => 'صبح بخیر',
      TodaySkyPhase.noon => 'ظهر بخیر',
      TodaySkyPhase.evening => 'عصر بخیر',
      TodaySkyPhase.night => 'شب بخیر',
    };

class TodaySkyGreeting extends StatelessWidget {
  const TodaySkyGreeting({super.key, required this.hour, required this.name});

  final int hour;
  final String name;

  @override
  Widget build(BuildContext context) {
    final phase = todaySkyPhaseForHour(hour);
    final dark = phase == TodaySkyPhase.night || phase == TodaySkyPhase.evening;
    final sky = switch (phase) {
      TodaySkyPhase.morning => const [Color(0xFFD6FAF8), Color(0xFFE9F7FF)],
      TodaySkyPhase.noon => const [Color(0xFFB7F2ED), Color(0xFFDBF4FF)],
      TodaySkyPhase.evening => const [Color(0xFF183C57), Color(0xFF38556B)],
      TodaySkyPhase.night => const [Color(0xFF081F35), Color(0xFF12384A)],
    };
    final foreground = dark ? Colors.white : AppColors.primaryDark;
    return ClipRRect(
      key: const Key('today-sky-greeting'),
      borderRadius: BorderRadius.circular(23),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 126),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: sky,
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _SkyPainter(phase))),
              Padding(
                padding: const EdgeInsets.fromLTRB(104, 19, 18, 18),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${todayGreetingForHour(hour)}، $name 👋',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Vazirmatn',
                        fontWeight: FontWeight.bold,
                        fontSize: 21,
                        height: 1.6,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'امروز هم قدم‌به‌قدم مراقب خودت باش.',
                      maxLines: 2,
                      style: TextStyle(
                        fontFamily: 'Vazirmatn',
                        fontSize: 12.5,
                        height: 1.65,
                        color: dark
                            ? const Color(0xFFDBF2F7)
                            : const Color(0xFF42686C),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkyPainter extends CustomPainter {
  const _SkyPainter(this.phase);
  final TodaySkyPhase phase;

  @override
  void paint(Canvas canvas, Size size) {
    final night = phase == TodaySkyPhase.night ||
        phase == TodaySkyPhase.evening;
    final cx = size.width * .135;
    final cy = size.height * .49;
    final radius = size.height * .265;
    canvas.drawCircle(
      Offset(cx, cy),
      radius * 1.55,
      Paint()
        ..color = night
            ? const Color(0xFF8BE7DE).withValues(alpha: .07)
            : Colors.white.withValues(alpha: .27),
    );
    if (night) {
      canvas.drawCircle(
        Offset(cx, cy),
        radius,
        Paint()..color = const Color(0xFFFFF3CE),
      );
      canvas.drawCircle(
        Offset(cx + radius * .39, cy - radius * .29),
        radius * .9,
        Paint()..color = phase == TodaySkyPhase.night
            ? const Color(0xFF0E3045)
            : const Color(0xFF2A4B62),
      );
      for (final (x, y, r) in <(double, double, double)>[
        (.04, .20, 1.7), (.28, .23, 2.2), (.31, .74, 1.5),
        (.08, .86, 1.4), (.21, .90, 1.9),
      ]) {
        canvas.drawCircle(
          Offset(size.width * x, size.height * y),
          r,
          Paint()..color = const Color(0xFFFFE7AD),
        );
      }
    } else {
      final ray = Paint()
        ..color = const Color(0xFFFFBC44)
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 8; i++) {
        final angle = i * math.pi / 4;
        final from = Offset(cx + math.cos(angle) * radius * 1.27,
            cy + math.sin(angle) * radius * 1.27);
        final to = Offset(cx + math.cos(angle) * radius * 1.51,
            cy + math.sin(angle) * radius * 1.51);
        canvas.drawLine(from, to, ray);
      }
      canvas.drawCircle(Offset(cx, cy), radius,
          Paint()..color = const Color(0xFFFFCA54));
      canvas.drawCircle(
        Offset(cx - radius * .2, cy - radius * .2),
        radius * .7,
        Paint()..color = const Color(0xFFFFE091).withValues(alpha: .53),
      );
    }
    final wave = Path()
      ..moveTo(0, size.height * .86)
      ..quadraticBezierTo(size.width * .22, size.height * .73,
          size.width * .47, size.height * .95)
      ..quadraticBezierTo(size.width * .73, size.height * 1.05,
          size.width, size.height * .80)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(wave, Paint()
      ..color = night
          ? const Color(0xFF53C3CB).withValues(alpha: .11)
          : const Color(0xFF57D9CD).withValues(alpha: .18));
  }

  @override
  bool shouldRepaint(_SkyPainter oldDelegate) => oldDelegate.phase != phase;
}
