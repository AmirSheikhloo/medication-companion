import '../../../core/calendar/persian_date.dart';
import 'stock_quantity.dart';

/// Only user-selectable, explicitly labelled units. There is deliberately no
/// automatic conversion from sheets or boxes to individual tablets.
class StockUnitPresets {
  static const units = <String>['عدد', 'ورق', 'بسته', 'دوز', 'سی‌سی'];

  static String canonical(String unit) => switch (unit.trim().toLowerCase()) {
        'ml' || 'cc' || 'میلی‌لیتر' || 'سی سی' => 'سی‌سی',
        'tablet' || 'tab' || 'قرص' => 'عدد',
        _ => unit.trim(),
      };

  static bool matches(String left, String right) =>
      canonical(left) == canonical(right);

  static String quantityLabel(int value, String unit) =>
      '${PersianDate.persianDigits(StockQuantity.format(value)).replaceAll('.', '٫')} $unit';
}
