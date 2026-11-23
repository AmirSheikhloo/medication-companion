import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/core/calendar/persian_date.dart';

void main() {
  group('Jalali civil calendar boundaries', () {
    test('known Nowruz anchors (including leap year 1403)', () {
      expect(
        PersianDate.fromGregorian(DateTime(2024, 3, 20)).toString(),
        '1403/01/01',
      );
      expect(
        PersianDate.fromGregorian(DateTime(2025, 3, 21)).toString(),
        '1404/01/01',
      );
      expect(
        PersianDate.fromGregorian(DateTime(2026, 3, 21)).toString(),
        '1405/01/01',
      );
      expect(PersianDate(1405, 1, 1).toGregorian(), DateTime(2026, 3, 21));
    });

    test('last day before Nowruz belongs to previous year', () {
      expect(
        PersianDate.fromGregorian(DateTime(2026, 3, 20)).toString(),
        '1404/12/29',
      );
      expect(
        PersianDate.fromGregorian(DateTime(2025, 3, 20)).toString(),
        '1403/12/30',
      );
    });

    test('Esfand validation: leap and non-leap years', () {
      expect(PersianDate.isLeapYear(1403), isTrue);
      expect(PersianDate.isLeapYear(1404), isFalse);
      expect(PersianDate.monthLength(1403, 12), 30);
      expect(PersianDate.monthLength(1404, 12), 29);
      expect(() => PersianDate.parse('۱۴۰۴/۱۲/۳۰'), throwsFormatException);
      expect(
        PersianDate.parse('۱۴۰۳/۱۲/۳۰').toGregorian(),
        DateTime(2025, 3, 20),
      );
    });

    test('six 31-day and five 30-day months', () {
      for (var month = 1; month <= 6; month++) {
        expect(PersianDate.monthLength(1405, month), 31);
      }
      for (var month = 7; month <= 11; month++) {
        expect(PersianDate.monthLength(1405, month), 30);
      }
      expect(() => PersianDate.parse('1405/07/31'), throwsFormatException);
      expect(() => PersianDate.parse('1405/13/01'), throwsFormatException);
      expect(() => PersianDate.parse('1405/00/01'), throwsFormatException);
      expect(() => PersianDate.parse('1405/02/00'), throwsFormatException);
    });

    test('Persian, Arabic and Latin numeral input', () {
      expect(PersianDate.parse('۱۴۰۵/۰۸/۲۶').toString(), '1405/08/26');
      expect(PersianDate.parse('١٤٠٥/٠٨/٢٦').toString(), '1405/08/26');
      expect(PersianDate.parse(' 1405-8-26 ').toString(), '1405/08/26');
      expect(PersianDate.displayDigits('1405/08/26'), '1405/08/26');
      expect(() => PersianDate.parse('abc'), throwsFormatException);
    });

    test('display conversion handles doses, times and counts without altering values', () {
      expect(PersianDate.displayDigits('08:05 — 2.5 mg'), '08:05 — 2.5 mg');
      expect(PersianDate.displayDigits('۱۲ قرص'), '12 قرص');
      expect(PersianDate.latinDigits('۲.۵'), '2.5');
      expect(PersianDate.displayDigits('CI118'), 'CI118');
    });

    test('round-trip across the entire product date range at month edges', () {
      for (var year = 1900; year <= 2100; year++) {
        for (var month = 1; month <= 12; month++) {
          final first = DateTime(year, month, 1);
          final last = DateTime(year, month + 1, 0);
          for (final date in [first, last]) {
            final jalali = PersianDate.fromGregorian(date);
            expect(jalali.toGregorian(), date, reason: '$date -> $jalali');
          }
        }
      }
    });

    test('date arithmetic never shifts at daylight saving transitions', () {
      final a = PersianDate.fromGregorian(DateTime(2026, 3, 21, 23, 45));
      expect(a.toString(), '1405/01/01');
      expect(a.toGregorian(), DateTime(2026, 3, 21));
    });

    test('display explicitly distinguishes Jalali date from time', () {
      expect(
        persianDateLabel(DateTime(2026, 3, 21, 9, 5), showTime: true),
        '1405/01/01  09:05',
      );
      expect(gregorianDateLabel(DateTime(2026, 3, 21)), '2026/03/21');
    });
  });
}
