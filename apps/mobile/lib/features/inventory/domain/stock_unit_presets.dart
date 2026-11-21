import 'stock_quantity.dart';

/// Only user-selectable, explicitly labelled units. There is deliberately no
/// automatic conversion from sheets or boxes to individual tablets.
class StockUnitPresets {
  static const units = <String>['عدد', 'ورق', 'بسته', 'دوز', 'سی‌سی'];

  static const amountsMilliunits = <int>[
    250, 500, 750, 1000, 1500, 2000, 2500, 3000, 4000, 5000,
    7000, 10000, 15000, 20000, 25000, 30000, 50000,
    60000, 90000, 100000, 120000, 200000, 250000, 500000,
    750000, 1000000, 2000000, 5000000,
  ];

  static String canonical(String unit) => switch (unit.trim().toLowerCase()) {
        'ml' || 'cc' || 'میلی‌لیتر' || 'سی سی' => 'سی‌سی',
        'tablet' || 'tab' || 'قرص' => 'عدد',
        _ => unit.trim(),
      };

  static bool matches(String left, String right) =>
      canonical(left) == canonical(right);

  static String quantityLabel(int value, String unit) =>
      '${StockQuantity.format(value)} $unit';
}
