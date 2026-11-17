/// Civil Jalali date support for the app's supported 1900–2100 Gregorian UI.
///
/// Uses the Borkowski break-year method (as documented by jalaali-js), with
/// UTC *date-only* arithmetic so local DST transitions cannot shift a date.
/// Storage and scheduling continue to use the original Gregorian DateTime.
class PersianDate {
  const PersianDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  static const _breaks = <int>[
    -61, 9, 38, 199, 426, 686, 756, 818, 1111, 1181,
    1210, 1635, 2060, 2097, 2192, 2262, 2324, 2394, 2456, 3178,
  ];

  static int _farvardinMarchDay(int jy) {
    if (jy < 1200 || jy > 1600) {
      throw RangeError('تاریخ شمسی خارج از محدوده پشتیبانی است.');
    }
    final gy = jy + 621;
    var leapJ = -14;
    var jp = _breaks.first;
    var jump = 0;
    for (var i = 1; i < _breaks.length; i++) {
      final jm = _breaks[i];
      jump = jm - jp;
      if (jy < jm) break;
      leapJ += (jump ~/ 33) * 8 + ((jump % 33) ~/ 4);
      jp = jm;
    }
    final n = jy - jp;
    leapJ += (n ~/ 33) * 8 + ((n % 33 + 3) ~/ 4);
    if (jump % 33 == 4 && jump - n == 4) leapJ++;
    final leapG = (gy ~/ 4) - (((gy ~/ 100) + 1) * 3 ~/ 4) - 150;
    return 20 + leapJ - leapG;
  }

  static DateTime _newYearUtc(int jy) =>
      DateTime.utc(jy + 621, 3, _farvardinMarchDay(jy));

  static bool isLeapYear(int year) =>
      _newYearUtc(year + 1).difference(_newYearUtc(year)).inDays == 366;

  static int monthLength(int year, int month) {
    if (month < 1 || month > 12) throw const FormatException('ماه نامعتبر است.');
    if (month <= 6) return 31;
    if (month <= 11) return 30;
    return isLeapYear(year) ? 30 : 29;
  }

  static PersianDate fromGregorian(DateTime date) {
    final local = date.toLocal();
    final value = DateTime.utc(local.year, local.month, local.day);
    var jy = local.year - 621;
    var first = _newYearUtc(jy);
    if (value.isBefore(first)) {
      jy--;
      first = _newYearUtc(jy);
    }
    final index = value.difference(first).inDays;
    if (index < 186) return PersianDate(jy, index ~/ 31 + 1, index % 31 + 1);
    final remaining = index - 186;
    return PersianDate(jy, remaining ~/ 30 + 7, remaining % 30 + 1);
  }

  DateTime toGregorian() {
    if (day < 1 || day > monthLength(year, month)) {
      throw const FormatException('روز با ماه و سال انتخاب‌شده سازگار نیست.');
    }
    final offset = month <= 6 ? (month - 1) * 31 : 186 + (month - 7) * 30;
    final utcDate = _newYearUtc(year).add(Duration(days: offset + day - 1));
    return DateTime(utcDate.year, utcDate.month, utcDate.day);
  }

  static String latinDigits(String value) {
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    return value.split('').map((char) {
      final pi = persian.indexOf(char);
      if (pi >= 0) return pi.toString();
      final ai = arabic.indexOf(char);
      return ai < 0 ? char : ai.toString();
    }).join();
  }

  static String persianDigits(String value) => value.replaceAllMapped(
      RegExp('[0-9]'), (match) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(match.group(0)!)]);

  static PersianDate parse(String input) {
    final normalized = latinDigits(input).trim();
    final match = RegExp(r'^(\d{4})[/-](\d{1,2})[/-](\d{1,2})$')
        .firstMatch(normalized);
    if (match == null) {
      throw const FormatException('تاریخ را به شکل ۱۴۰۵/۰۸/۲۶ وارد کنید.');
    }
    final date = PersianDate(int.parse(match[1]!), int.parse(match[2]!),
        int.parse(match[3]!));
    date.toGregorian();
    return date;
  }

  @override
  String toString() => '$year/${month.toString().padLeft(2, '0')}/'
      '${day.toString().padLeft(2, '0')}';
}

String persianDateLabel(DateTime date, {bool showTime = false}) {
  final local = date.toLocal();
  final shamsi = PersianDate.fromGregorian(local);
  final clock = showTime
      ? '  ${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}'
      : '';
  return PersianDate.persianDigits('$shamsi$clock');
}

String gregorianDateLabel(DateTime date) {
  final local = date.toLocal();
  return '${local.year}/${local.month.toString().padLeft(2, '0')}/'
      '${local.day.toString().padLeft(2, '0')}';
}
