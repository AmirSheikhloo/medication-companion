/// Quantities are exact thousandths of a user-labelled package unit.
/// No dose is inferred from free-text instructions.
class StockQuantity {
  static const maxMilliunits = 999999999;

  static int parsePositive(String raw) {
    final value = parseNonNegative(raw);
    if (value == 0) {
      throw ArgumentError('مقدار باید بزرگ‌تر از صفر باشد.');
    }
    return value;
  }

  static int parseNonNegative(String raw) {
    final normalized = _ascii(raw.trim()).replaceAll('٫', '.');
    final match = RegExp(r'^(0|[1-9][0-9]{0,5})(?:\.([0-9]{1,3}))?$')
        .firstMatch(normalized);
    if (match == null) {
      throw ArgumentError('مقدار عددی معتبر با حداکثر سه رقم اعشار وارد کنید.');
    }
    final units = int.parse(match.group(1)!);
    final fraction = (match.group(2) ?? '').padRight(3, '0');
    final milliunits = units * 1000 + (fraction.isEmpty ? 0 : int.parse(fraction));
    if (milliunits > maxMilliunits) {
      throw ArgumentError('مقدار واردشده بیش از حد مجاز است.');
    }
    return milliunits;
  }

  static String format(int milliunits) {
    final negative = milliunits < 0 ? '-' : '';
    final absolute = milliunits.abs();
    final whole = absolute ~/ 1000;
    final tail = (absolute % 1000).toString().padLeft(3, '0');
    final decimals = tail.replaceFirst(RegExp(r'0+$'), '');
    return '$negative$whole${decimals.isEmpty ? '' : '.$decimals'}';
  }

  static String _ascii(String input) => String.fromCharCodes([
        for (final code in input.runes)
          if (code >= 0x06F0 && code <= 0x06F9)
            code - 0x06F0 + 0x30
          else if (code >= 0x0660 && code <= 0x0669)
            code - 0x0660 + 0x30
          else
            code,
      ]);

  /// The app's first inventory UI accepts Gregorian calendar dates.
  /// The original calendar and precision are retained in the package row.
  static bool isExpired(String? iso, String precision, DateTime localNow) {
    if (iso == null || precision == 'none') return false;
    final date = parseIso(iso);
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    if (precision == 'month') {
      return DateTime(date.year, date.month + 1).isBefore(today) ||
          DateTime(date.year, date.month + 1).isAtSameMomentAs(today);
    }
    if (precision == 'day') return date.isBefore(today);
    throw ArgumentError('دقت تاریخ انقضا ناشناخته است.');
  }

  static DateTime parseIso(String iso) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(iso)) {
      throw ArgumentError('تاریخ انقضا معتبر نیست.');
    }
    final parts = iso.split('-').map(int.parse).toList();
    final parsed = DateTime(parts[0], parts[1], parts[2]);
    if (parsed.year != parts[0] ||
        parsed.month != parts[1] ||
        parsed.day != parts[2]) {
      throw ArgumentError('تاریخ انقضا معتبر نیست.');
    }
    return parsed;
  }

  static String isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
