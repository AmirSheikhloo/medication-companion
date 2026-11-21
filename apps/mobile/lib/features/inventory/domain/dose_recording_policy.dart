import '../data/inventory_repository.dart';
import 'stock_unit_presets.dart';

/// Resolves a one-tap dose without interpreting free-text dose instructions.
/// An empty inventory means dose tracking only. Once packages exist, an
/// invalid stock setup must never silently turn into a stock-free dose.
class AutomaticDoseDecision {
  const AutomaticDoseDecision._({
    this.packageId,
    this.quantityMilliunits,
    this.problem,
  });

  const AutomaticDoseDecision.recordOnly() : this._();

  const AutomaticDoseDecision.debit(String packageId, int quantityMilliunits)
      : this._(packageId: packageId, quantityMilliunits: quantityMilliunits);

  const AutomaticDoseDecision.blocked(String problem)
      : this._(problem: problem);

  final String? packageId;
  final int? quantityMilliunits;
  final String? problem;

  bool get canRecord => problem == null;
  bool get deductsStock => packageId != null;
}

AutomaticDoseDecision decideAutomaticDose(StockSummary stock) {
  if (stock.packages.isEmpty) {
    return const AutomaticDoseDecision.recordOnly();
  }

  final selected = stock.selected;
  if (selected == null) {
    return const AutomaticDoseDecision.blocked(
      'بسته‌ای برای مصرف انتخاب نشده است. از «مدیریت موجودی» یک بسته را انتخاب کنید.',
    );
  }
  if (selected.expired) {
    return const AutomaticDoseDecision.blocked(
      'بسته انتخاب‌شده منقضی است. بسته دیگری را انتخاب کنید.',
    );
  }

  final preset = stock.debitPreset;
  if (preset == null || preset.quantityMilliunits <= 0) {
    return const AutomaticDoseDecision.blocked(
      'مقدار کسر خودکار تنظیم نشده است. از «ویرایش دارو» مقدار هر مصرف را تعیین کنید.',
    );
  }
  if (!StockUnitPresets.matches(selected.package.unit, preset.unit)) {
    return AutomaticDoseDecision.blocked(
      'واحد مصرف «${preset.unit}» با واحد بسته «${selected.package.unit}» '
      'یکسان نیست. بسته یا مقدار مصرف را اصلاح کنید.',
    );
  }
  if (selected.balanceMilliunits < preset.quantityMilliunits) {
    return const AutomaticDoseDecision.blocked(
      'موجودی بسته برای این نوبت کافی نیست. موجودی را اصلاح یا بسته را عوض کنید.',
    );
  }
  return AutomaticDoseDecision.debit(
    selected.package.id,
    preset.quantityMilliunits,
  );
}
