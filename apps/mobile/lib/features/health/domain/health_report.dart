import '../../../core/storage/app_database.dart';
import 'health_metric.dart';

/// Only descriptive statistics of recorded values. Never a medical range.
class HealthDescriptiveStats {
  const HealthDescriptiveStats({
    required this.count,
    required this.minMilliunits,
    required this.maxMilliunits,
    required this.meanMilliunits,
  });

  final int count;
  final int minMilliunits;
  final int maxMilliunits;
  final int meanMilliunits;

  static HealthDescriptiveStats? of(Iterable<int> values) {
    final data = values.where((n) => n > 0).toList();
    if (data.isEmpty) return null;
    var low = data.first;
    var high = data.first;
    var total = 0;
    for (final n in data) {
      if (n < low) low = n;
      if (n > high) high = n;
      total += n;
    }
    return HealthDescriptiveStats(
      count: data.length,
      minMilliunits: low,
      maxMilliunits: high,
      meanMilliunits: (total / data.length).round(),
    );
  }
}

class HealthReportSummary {
  const HealthReportSummary({
    required this.count,
    required this.stats,
    required this.excludedCount,
  });

  final int count;
  final Map<String, HealthDescriptiveStats> stats;
  final int excludedCount;

  bool get hasQualityWarning => excludedCount > 0;

  static HealthReportSummary calculate(
      HealthMetric metric, List<HealthMeasurement> records) {
    final groups = <String, List<int>>{};
    var excluded = 0;
    for (final entry in records) {
      if (entry.metric != metric.name ||
          entry.unit != metric.unit ||
          entry.primaryMilliunits <= 0 ||
          (metric.hasSecondValue &&
              (entry.secondaryMilliunits == null ||
                  entry.secondaryMilliunits! <= 0)) ||
          (!metric.hasSecondValue && entry.secondaryMilliunits != null)) {
        excluded++;
        continue;
      }
      if (metric == HealthMetric.pressure) {
        groups.putIfAbsent('فشار بالا', () => []).add(entry.primaryMilliunits);
        groups.putIfAbsent('فشار پایین', () => [])
            .add(entry.secondaryMilliunits!);
      } else if (metric == HealthMetric.glucose) {
        final context = entry.context;
        const known = {'fasting', 'before_meal', 'after_meal', 'other'};
        if (context == null || !known.contains(context)) {
          excluded++;
          continue;
        }
        groups.putIfAbsent(healthContextLabel(context), () => [])
            .add(entry.primaryMilliunits);
      } else {
        groups.putIfAbsent(metric.label, () => []).add(entry.primaryMilliunits);
      }
    }
    return HealthReportSummary(
      count: records.length,
      stats: {
        for (final item in groups.entries)
          if (HealthDescriptiveStats.of(item.value) case final stats?)
            item.key: stats,
      },
      excludedCount: excluded,
    );
  }
}

String healthContextLabel(String value) => switch (value) {
  'fasting' => 'ناشتا',
  'before_meal' => 'قبل غذا',
  'after_meal' => 'بعد غذا',
  'other' => 'سایر شرایط',
  _ => 'شرایط نامشخص',
};

List<HealthMeasurement> selectHealthDateRange({
  required List<HealthMeasurement> records,
  required DateTime startLocal,
  required DateTime endLocal,
}) {
  final start = DateTime(startLocal.year, startLocal.month, startLocal.day);
  final exclusiveEnd = DateTime(endLocal.year, endLocal.month, endLocal.day + 1);
  if (!start.isBefore(exclusiveEnd)) {
    throw ArgumentError('بازه تاریخی معتبر نیست.');
  }
  return [
    for (final entry in records)
      if (!entry.observedAt.toLocal().isBefore(start) &&
          entry.observedAt.toLocal().isBefore(exclusiveEnd))
        entry,
  ];
}

String healthReportFileName(HealthMetric metric, DateTime start, DateTime end,
    String extension) {
  String stamp(DateTime date) =>
      '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
  return 'health_${metric.name}_${stamp(start)}_${stamp(end)}.$extension';
}

/// RFC 4180 quoted values with spreadsheet-formula neutralization.
/// BOM makes Persian UTF-8 reliable in Excel-compatible CSV readers.
String buildHealthCsv({
  required Profile profile,
  required HealthMetric metric,
  required DateTime start,
  required DateTime end,
  required List<HealthMeasurement> records,
}) {
  String cell(String raw) {
    final compact = raw.replaceAll('\r', ' ').replaceAll('\n', ' ');
    final safe = RegExp(r'^\s*[=+\-@]').hasMatch(compact)
        ? "'$compact"
        : compact;
    return '"${safe.replaceAll('"', '""')}"';
  }
  String row(List<String> parts) => parts.map(cell).join(',');
  const disclaimer = 'اطلاعات ثبت‌شده توسط کاربر/مراقب؛ تأیید پزشکی نشده';
  final lines = <String>[
    row(const [
      'پروفایل',
      'شاخص',
      'مقدار اول',
      'مقدار دوم',
      'واحد',
      'شرایط ثبت',
      'زمان اندازه‌گیری (میلادی، محلی)',
      'زمان ثبت (میلادی، محلی)',
      'یادداشت',
      'نسخه ثبت',
      'وضعیت اعتبار',
    ]),
  ];
  for (final record in records) {
    lines.add(row([
      profile.displayName,
      metric.label,
      HealthNumber.format(record.primaryMilliunits),
      record.secondaryMilliunits == null
          ? ''
          : HealthNumber.format(record.secondaryMilliunits!),
      record.unit,
      record.context == null ? '' : healthContextLabel(record.context!),
      healthDateTimeLabel(record.observedAt),
      healthDateTimeLabel(record.recordedAt),
      record.note ?? '',
      '${record.version}',
      disclaimer,
    ]));
  }
  if (records.isEmpty) {
    lines.add(row([
      profile.displayName,
      metric.label,
      '',
      '',
      metric.unit,
      '',
      'از ${healthDateTimeLabel(start)} تا ${healthDateTimeLabel(end)}',
      '',
      'در این بازه داده‌ای ثبت نشده است.',
      '',
      disclaimer,
    ]));
  }
  return '\uFEFF${lines.join('\r\n')}\r\n';
}
