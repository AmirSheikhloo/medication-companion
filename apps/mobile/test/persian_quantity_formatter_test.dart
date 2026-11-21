import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/core/input/persian_quantity_formatter.dart';
import 'package:medication_companion/features/inventory/domain/stock_quantity.dart';

void main() {
  const formatter = PersianQuantityFormatter();

  TextEditingValue value(String text) => TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );

  test('English and Arabic keyboards always display Persian digits', () {
    expect(formatter.formatEditUpdate(value(''), value('20.5')).text, '۲۰٫۵');
    expect(formatter.formatEditUpdate(value(''), value('٢٠٫٥')).text, '۲۰٫۵');
    expect(formatter.formatEditUpdate(value(''), value('۲۰٫۵')).text, '۲۰٫۵');
    expect(PersianQuantityFormatter.display('123.50'), '۱۲۳٫۵۰');
    expect(StockQuantity.parsePositive('۲۰٫۵'), 20500);
    expect(PersianQuantityFormatter.display('۵ عدد، 12.5 cc'),
        '۵ عدد، ۱۲٫۵ cc');
  });

  test('letters, negative values and oversized or malformed amounts are refused', () {
    final previous = value('۱۲');
    for (final invalid in ['12a', '-1', '100000', '01', '2.1234',
      '1.2.3', '۱٬۰۰۰', '999999999', '۱٫۵ml']) {
      expect(formatter.formatEditUpdate(previous, value(invalid)), previous,
          reason: invalid);
    }
    expect(formatter.formatEditUpdate(previous, value('۰')).text, '۰');
    expect(() => StockQuantity.parsePositive('۰'), throwsArgumentError);
    expect(formatter.formatEditUpdate(value('۰'), value('0.5')).text, '۰٫۵');
  });
}
