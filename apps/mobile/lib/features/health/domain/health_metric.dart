/// Units are explicit and never combined or converted implicitly.
enum HealthMetric {
  pressure('فشار خون', 'mmHg', true),
  glucose('قند خون', 'mg/dL', false),
  weight('وزن', 'kg', false),
  pulse('ضربان قلب', 'bpm', false);

  const HealthMetric(this.label, this.unit, this.hasSecondValue);

  final String label;
  final String unit;
  final bool hasSecondValue;

  static HealthMetric fromCode(String code) {
    for (final value in HealthMetric.values) {
      if (value.name == code) return value;
    }
    throw ArgumentError('شاخص ناشناخته: $code');
  }
}

/// Parses localized digits and up to three decimal places without doubles.
class HealthNumber {
  static int parseMilliunits(String raw) {
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    final normalized = raw.trim().split('').map((c) {
      final p = persian.indexOf(c);
      if (p >= 0) return '$p';
      final a = arabic.indexOf(c);
      if (a >= 0) return '$a';
      if (c == '٫') return '.';
      return c;
    }).join();
    if (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(normalized)) {
      throw FormatException('عدد معتبر با حداکثر سه رقم اعشار وارد کنید.');
    }
    final parts = normalized.split('.');
    final whole = int.tryParse(parts.first);
    if (whole == null || whole > 1000000) {
      throw FormatException('مقدار خارج از محدوده قابل ذخیره است.');
    }
    final decimals = parts.length == 2
        ? int.parse(parts.last.padRight(3, '0'))
        : 0;
    final milliunits = whole * 1000 + decimals;
    if (milliunits <= 0 || milliunits > 1000000000) {
      throw FormatException('مقدار باید مثبت و قابل ذخیره باشد.');
    }
    return milliunits;
  }

  static String format(int value) {
    final whole = value ~/ 1000;
    final decimals = value % 1000;
    if (decimals == 0) return '$whole';
    return '$whole.${decimals.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '')}';
  }
}

class HealthMeasurementDraft {
  const HealthMeasurementDraft({
    required this.metric,
    required this.primaryMilliunits,
    this.secondaryMilliunits,
    required this.observedAt,
    this.context,
    this.note,
  });

  final HealthMetric metric;
  final int primaryMilliunits;
  final int? secondaryMilliunits;
  final DateTime observedAt;
  final String? context;
  final String? note;
}

String healthDateTimeLabel(DateTime date) {
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute (میلادی)';
}
