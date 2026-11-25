import 'dart:convert';
import '../../../core/storage/app_database.dart';
import '../domain/stock_quantity.dart';
import 'inventory_repository.dart';

class StockAttention {
  const StockAttention(this.key, this.title, this.message, this.priority);
  final String key;
  final String title;
  final String message;
  final int priority;

  bool get urgent => priority <= 1;

  static List<StockAttention> evaluate(
      StockSummary? stock, int? expiryLeadDays, DateTime now) {
    if (stock == null || stock.packages.isEmpty) return [];
    final alerts = <StockAttention>[];
    final today = DateTime.utc(now.year, now.month, now.day);
    final eligible = stock.packages.where((p) =>
      !p.archived && !StockQuantity.isExpired(p.package.expiryIso,
        p.package.expiryPrecision, now) && p.balanceMilliunits > 0);
    final selected = stock.selected;
    if (eligible.isEmpty) {
      alerts.add(const StockAttention('no-usable-stock', 'موجودی تمام شده',
        'بسته جدید اضافه کن یا وضعیت بسته‌ها را بررسی کن. این هشدار به معنی پایان درمان نیست.', 0));
    } else if (selected == null || selected.balanceMilliunits <= 0 ||
        StockQuantity.isExpired(selected.package.expiryIso,
          selected.package.expiryPrecision, now)) {
      alerts.add(const StockAttention('choose-package', 'نیاز به انتخاب بسته',
        'یک بسته معتبر برای ثبت کسر موجودی انتخاب کن.', 1));
    }
    if (selected != null && stock.lowStock && selected.balanceMilliunits > 0 &&
        !StockQuantity.isExpired(selected.package.expiryIso,
          selected.package.expiryPrecision, now)) {
      alerts.add(StockAttention(
        'low:${selected.package.id}:${stock.thresholdMilliunits}',
        'رو به اتمام', '${selected.package.label} — ${StockQuantity.format(selected.balanceMilliunits)} ${selected.package.unit} باقی مانده است.', 3));
    }
    for (final pack in stock.packages) {
      final iso = pack.package.expiryIso;
      if (pack.archived || pack.balanceMilliunits <= 0 || iso == null) continue;
      final expiry = StockQuantity.expiryDay(iso, pack.package.expiryPrecision);
      final days = DateTime.utc(expiry.year, expiry.month, expiry.day)
        .difference(today).inDays;
      final identity = '${pack.package.id}:$iso:${pack.package.expiryPrecision}';
      if (days < 0) {
        alerts.add(StockAttention('expired:$identity', 'بسته منقضی شده',
          '${pack.package.label}: این بسته برای کسر موجودی قابل انتخاب نیست.', 0));
      } else if (expiryLeadDays != null && days <= expiryLeadDays) {
        alerts.add(StockAttention('expiry:$identity:$expiryLeadDays',
          'نزدیک انقضا', '${pack.package.label}: $days روز تا انقضا باقی مانده است.', 2));
      }
    }
    // A primary inventory problem already explains why selection is needed.
    final expiredIndex = alerts.indexWhere((a) => a.key.startsWith('expired:'));
    if (expiredIndex >= 0) {
      final primary = alerts[expiredIndex];
      final action = alerts.any((a) => a.key == 'choose-package')
        ? ' یک بسته معتبر دیگر انتخاب کن.'
        : alerts.any((a) => a.key == 'no-usable-stock')
          ? ' بسته قابل مصرف دیگری وجود ندارد؛ موجودی را بررسی کن.' : '';
      alerts[expiredIndex] = StockAttention(primary.key, primary.title,
        '${primary.message}$action', primary.priority);
      alerts.removeWhere((a) => a.key == 'choose-package' ||
        a.key == 'no-usable-stock');
    }
    alerts.sort((a, b) => a.priority.compareTo(b.priority));
    return alerts;
  }
}

/// Dismissal applies to a condition episode, not the underlying safety state.
/// Once a condition resolves, its suppression is removed so a later recurrence
/// becomes visible again.
class StockAttentionRepository {
  const StockAttentionRepository(this.db);
  final AppDatabase db;

  String _key(String profileId, String medicationId) =>
    'stock-attention-dismissed:v1:$profileId:$medicationId';

  Future<Set<String>> read(String profileId, String medicationId) async {
    final row = await (db.select(db.appSettings)
      ..where((t) => t.key.equals(_key(profileId, medicationId))))
      .getSingleOrNull();
    try {
      final value = jsonDecode(row?.value ?? '[]');
      return value is List ? value.whereType<String>().toSet() : <String>{};
    } catch (_) { return <String>{}; }
  }

  Future<void> _save(String profileId, String medicationId, Set<String> keys) async {
    await db.into(db.appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(key: _key(profileId, medicationId),
        value: jsonEncode(keys.toList()..sort())));
  }

  Future<Set<String>> reconcile(String profileId, String medicationId,
      List<StockAttention> current) async {
    final before = await read(profileId, medicationId);
    final valid = current.map((a) => a.key).toSet();
    final retained = before.intersection(valid);
    if (retained.length != before.length) {
      await _save(profileId, medicationId, retained);
    }
    return retained;
  }

  Future<void> dismiss(String profileId, String medicationId, String key) async {
    await db.transaction(() async {
      final before = await read(profileId, medicationId);
      before.add(key);
      await _save(profileId, medicationId, before);
    });
  }
}
