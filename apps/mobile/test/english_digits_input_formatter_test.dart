import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/core/ui/english_digits_input_formatter.dart';
import 'package:medication_companion/core/calendar/persian_date.dart';

void main() {
  test('display always uses Latin numerals while Jalali dates stay Jalali', () {
    expect(PersianDate.displayDigits('۱۲۳٤٥٦ | 08:00'), '123456 | 08:00');
    expect(PersianDate.parse('۱۴۰۵/۰۹/۰۲').toString(), '1405/09/02');
  });

  test('typing Persian or Arabic digits displays ASCII and preserves caret', () {
    const formatter = EnglishDigitsInputFormatter();
    const oldValue = TextEditingValue(text: '');
    const typed = TextEditingValue(
      text: '۱۲٣٤٫۵',
      selection: TextSelection.collapsed(offset: 6),
    );
    final result = formatter.formatEditUpdate(oldValue, typed);
    expect(result.text, '1234.5');
    expect(result.selection.baseOffset, 6);
    expect(result.selection.extentOffset, 6);
  });
}
