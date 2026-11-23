import 'package:flutter/services.dart';

import '../calendar/persian_date.dart';

/// Converts Persian and Arabic numerals to ASCII as users type. Each numeral
/// occupies one code unit, so editing selection and composing range survive.
/// Parsing remains tolerant of all numeral scripts at the domain boundary.
class EnglishDigitsInputFormatter extends TextInputFormatter {
  const EnglishDigitsInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = PersianDate.latinDigits(newValue.text)
        .replaceAll('٫', '.');
    if (normalized == newValue.text) return newValue;
    return newValue.copyWith(text: normalized);
  }
}
