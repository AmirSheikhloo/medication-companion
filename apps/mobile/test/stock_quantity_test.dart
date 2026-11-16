import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/features/inventory/domain/stock_quantity.dart';

void main() {
  test('Persian and Arabic decimal inputs are exact thousandths', () {
    expect(StockQuantity.parsePositive('۱۲٫۵'), 12500);
    expect(StockQuantity.parsePositive('٢.٢٥'), 2250);
    expect(StockQuantity.format(12500), '12.5');
    expect(StockQuantity.format(-1250), '-1.25');
    expect(StockQuantity.parseNonNegative('۰'), 0);
    expect(() => StockQuantity.parsePositive('۰'), throwsArgumentError);
    expect(() => StockQuantity.parsePositive('1.2345'), throwsArgumentError);
    expect(() => StockQuantity.parsePositive('-1'), throwsArgumentError);
    expect(() => StockQuantity.parsePositive('nan'), throwsArgumentError);
  });

  test('expiry precision respects the local calendar day', () {
    final now = DateTime(2026, 11, 16, 22);
    expect(StockQuantity.isExpired('2026-11-15', 'day', now), isTrue);
    expect(StockQuantity.isExpired('2026-11-16', 'day', now), isFalse);
    expect(StockQuantity.isExpired('2026-11-01', 'month', now), isFalse);
    expect(StockQuantity.isExpired('2026-10-01', 'month', now), isTrue);
    expect(StockQuantity.isExpired(null, 'none', now), isFalse);
    expect(() => StockQuantity.parseIso('2026-02-30'), throwsArgumentError);
  });
}
