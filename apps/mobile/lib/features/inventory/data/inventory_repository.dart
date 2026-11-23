import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/app_database.dart';
import '../domain/stock_quantity.dart';

class PackageBalance {
  const PackageBalance(this.package, this.balanceMilliunits, {this.archived = false});

  final StockPackage package;
  final int balanceMilliunits;
  final bool archived;

  bool get expired =>
      StockQuantity.isExpired(package.expiryIso, package.expiryPrecision, DateTime.now());
}

class StockSummary {
  const StockSummary({
    required this.packages,
    required this.selectedPackageId,
    required this.thresholdMilliunits,
  });

  final List<PackageBalance> packages;
  final String? selectedPackageId;
  final int? thresholdMilliunits;

  PackageBalance? get selected {
    for (final pack in packages) {
      if (pack.package.id == selectedPackageId && !pack.archived) return pack;
    }
    return null;
  }

  bool get lowStock {
    final chosen = selected;
    final threshold = thresholdMilliunits;
    return chosen != null && threshold != null &&
        chosen.balanceMilliunits <= threshold;
  }
}

/// All writes are scoped to a profile and medication and run in SQLite
/// transactions. The signed movement ledger is never overwritten or deleted.
class InventoryRepository {
  InventoryRepository(this.db);

  final AppDatabase db;
  final Uuid _uuid = Uuid();

  String _archiveKey(String profileId, String medicationId, String packageId) =>
      'stock-package-archived:v1:$profileId:$medicationId:$packageId';

  Future<bool> _isArchived(String profileId, String medicationId,
      String packageId) async =>
      await (db.select(db.appSettings)..where((s) => s.key.equals(
        _archiveKey(profileId, medicationId, packageId)))).getSingleOrNull()
          != null;

  Future<Medication> _ownedMedication(String profileId, String medicationId) async {
    final med = await (db.select(db.medications)
          ..where((t) => t.id.equals(medicationId) & t.profileId.equals(profileId)))
        .getSingleOrNull();
    if (med == null || med.archived) {
      throw StateError('داروی فعال متعلق به این پروفایل پیدا نشد.');
    }
    return med;
  }

  /// History and summaries remain readable after a medicine is archived.
  /// Mutations continue to require `_ownedMedication` (active-only).
  Future<void> _assertReadableMedication(
      String profileId, String medicationId) async {
    final medication = await (db.select(db.medications)
          ..where((t) => t.id.equals(medicationId) &
              t.profileId.equals(profileId)))
        .getSingleOrNull();
    if (medication == null) {
      throw StateError('دارو متعلق به این پروفایل نیست.');
    }
  }

  Future<StockPackage> _ownedPackage(
      String profileId, String medicationId, String packageId) async {
    await _ownedMedication(profileId, medicationId);
    final pack = await (db.select(db.stockPackages)
          ..where((t) => t.id.equals(packageId) &
              t.profileId.equals(profileId) &
              t.medicationId.equals(medicationId)))
        .getSingleOrNull();
    if (pack == null) throw StateError('بسته متعلق به این دارو و پروفایل نیست.');
    return pack;
  }

  Future<int> _balanceForPackage(String packageId) async {
    final movements = await (db.select(db.stockMovements)
          ..where((t) => t.packageId.equals(packageId)))
        .get();
    return movements.fold<int>(
        0, (sum, movement) => sum + movement.deltaMilliunits);
  }

  Future<StockSummary> summary(String profileId, String medicationId) async {
    await _assertReadableMedication(profileId, medicationId);
    final packs = await (db.select(db.stockPackages)
          ..where((t) => t.profileId.equals(profileId) &
              t.medicationId.equals(medicationId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    final movements = await (db.select(db.stockMovements)
          ..where((t) => t.profileId.equals(profileId) &
              t.medicationId.equals(medicationId)))
        .get();
    final archiveKeys = [for (final pack in packs)
      _archiveKey(profileId, medicationId, pack.id)];
    final archivedRows = archiveKeys.isEmpty ? <AppSetting>[] :
        await (db.select(db.appSettings)
          ..where((s) => s.key.isIn(archiveKeys))).get();
    final archivedKeys = archivedRows.map((row) => row.key).toSet();
    final balances = <String, int>{};
    for (final row in movements) {
      balances.update(row.packageId, (v) => v + row.deltaMilliunits,
          ifAbsent: () => row.deltaMilliunits);
    }
    final selected = await (db.select(db.stockSelections)
          ..where((t) => t.medicationId.equals(medicationId) &
              t.profileId.equals(profileId)))
        .getSingleOrNull();
    final rule = await (db.select(db.stockAlertRules)
          ..where((t) => t.medicationId.equals(medicationId) &
              t.profileId.equals(profileId)))
        .getSingleOrNull();
    final selectedPack = [
      for (final pack in packs)
        if (pack.id == selected?.packageId) pack,
    ];
    return StockSummary(
      packages: [for (final pack in packs)
        PackageBalance(pack, balances[pack.id] ?? 0,
          archived: archivedKeys.contains(_archiveKey(
            profileId, medicationId, pack.id)))],
      selectedPackageId: selected?.packageId,
      // Never re-interpret a threshold for tablets as millilitres or vice versa.
      thresholdMilliunits: rule != null &&
              selectedPack.isNotEmpty && selectedPack.single.unit == rule.unit
          ? rule.thresholdMilliunits
          : null,
    );
  }

  /// Read-only history, scoped to the owning profile and medication.
  /// Entries are immutable and ordered newest-first for the package UI.
  Future<List<StockMovement>> movementsForPackage({
    required String profileId,
    required String medicationId,
    required String packageId,
    int? limit,
  }) async {
    await _assertReadableMedication(profileId, medicationId);
    final package = await (db.select(db.stockPackages)
          ..where((t) => t.id.equals(packageId) &
              t.profileId.equals(profileId) &
              t.medicationId.equals(medicationId)))
        .getSingleOrNull();
    if (package == null) throw StateError('بسته متعلق به این دارو نیست.');
    final query = db.select(db.stockMovements)
      ..where((t) => t.profileId.equals(profileId) &
          t.medicationId.equals(medicationId) &
          t.packageId.equals(packageId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    if (limit != null) { query.limit(limit); }
    return query.get();
  }

  Future<String> addPackage({
    required String profileId,
    required String medicationId,
    required String label,
    required String unit,
    required int initialMilliunits,
    bool selectForUse = false,
    String? expiryIso,
    String expiryPrecision = 'none',
  }) async {
    final cleanLabel = label.trim();
    final cleanUnit = unit.trim();
    if (cleanLabel.isEmpty || cleanLabel.length > 80 ||
        cleanUnit.isEmpty || cleanUnit.length > 30) {
      throw ArgumentError('نام بسته یا واحد معتبر نیست.');
    }
    _validateQuantity(initialMilliunits, allowZero: true);
    if (!{'none', 'day', 'month'}.contains(expiryPrecision) ||
        (expiryPrecision == 'none') != (expiryIso == null)) {
      throw ArgumentError('تاریخ یا دقت انقضا معتبر نیست.');
    }
    if (expiryIso != null) StockQuantity.parseIso(expiryIso);
    if (selectForUse &&
        StockQuantity.isExpired(expiryIso, expiryPrecision, DateTime.now())) {
      throw StateError('بسته منقضی را نمی‌توان برای مصرف انتخاب کرد.');
    }
    final id = _uuid.v4();
    await db.transaction(() async {
      await _ownedMedication(profileId, medicationId);
      final existingSelection = await (db.select(db.stockSelections)
        ..where((t) => t.profileId.equals(profileId) &
          t.medicationId.equals(medicationId))).getSingleOrNull();
      final autoSelect = existingSelection == null &&
        initialMilliunits > 0 &&
        !StockQuantity.isExpired(expiryIso, expiryPrecision, DateTime.now());
      await db.into(db.stockPackages).insert(StockPackagesCompanion.insert(
            id: id,
            profileId: profileId,
            medicationId: medicationId,
            label: cleanLabel,
            unit: cleanUnit,
            expiryIso: Value(expiryIso),
            expiryPrecision: Value(expiryPrecision),
            createdAt: DateTime.now().toUtc(),
          ));
      if (initialMilliunits > 0) {
        await _insertMovement(
          profileId: profileId, medicationId: medicationId, packageId: id,
          kind: 'initial', delta: initialMilliunits,
          note: 'موجودی اولیه به اعلام کاربر',
        );
      }
      if (selectForUse || autoSelect) {
        await db.into(db.stockSelections).insertOnConflictUpdate(
          StockSelectionsCompanion.insert(
            medicationId: medicationId,
            profileId: profileId,
            packageId: id,
          ),
        );
      }
    });
    return id;
  }

  Future<void> selectPackage({
    required String profileId,
    required String medicationId,
    required String packageId,
  }) async {
    await db.transaction(() async {
      final pack = await _ownedPackage(profileId, medicationId, packageId);
      if (await _isArchived(profileId, medicationId, packageId)) {
        throw StateError('بستهٔ بایگانی‌شده قابل انتخاب برای مصرف نیست.');
      }
      if (StockQuantity.isExpired(
          pack.expiryIso, pack.expiryPrecision, DateTime.now())) {
        throw StateError('این بسته منقضی شده است.');
      }
      await db.into(db.stockSelections).insertOnConflictUpdate(
        StockSelectionsCompanion.insert(
          medicationId: medicationId,
          profileId: profileId,
          packageId: packageId,
        ),
      );
    });
  }

  /// Package metadata can be corrected without rewriting historic movements.
  /// Record the correction as a zero-quantity audit event.
  Future<void> editPackage({
    required String profileId,
    required String medicationId,
    required String packageId,
    required String label,
    String? expiryIso,
    String expiryPrecision = 'none',
  }) async {
    if (label.trim().isEmpty || label.trim().length > 80 ||
        !{'none', 'day', 'month'}.contains(expiryPrecision) ||
        (expiryPrecision == 'none') != (expiryIso == null)) {
      throw ArgumentError('نام بسته یا تاریخ انقضا معتبر نیست.');
    }
    if (expiryIso != null) StockQuantity.parseIso(expiryIso);
    await db.transaction(() async {
      final pack = await _ownedPackage(profileId, medicationId, packageId);
      if (await _isArchived(profileId, medicationId, packageId)) {
        throw StateError('برای ویرایش، ابتدا بسته را از بایگانی برگردان.');
      }
      if (StockQuantity.isExpired(expiryIso, expiryPrecision, DateTime.now())) {
        throw StateError('تاریخ انقضا گذشته است؛ از مصرف داروی منقضی خودداری کن.');
      }
      if (pack.label == label.trim() && pack.expiryIso == expiryIso &&
          pack.expiryPrecision == expiryPrecision) {
        return;
      }
      await (db.update(db.stockPackages)
            ..where((t) => t.id.equals(packageId) &
              t.profileId.equals(profileId) &
              t.medicationId.equals(medicationId)))
          .write(StockPackagesCompanion(
            label: Value(label.trim()), expiryIso: Value(expiryIso),
            expiryPrecision: Value(expiryPrecision)));
      await _insertMovement(profileId: profileId, medicationId: medicationId,
        packageId: packageId, kind: 'metadata', delta: 0,
        note: 'اصلاح مشخصات بسته: ${pack.label} / ${pack.expiryIso ?? 'بدون انقضا'}'
          ' ← ${label.trim()} / ${expiryIso ?? 'بدون انقضا'}');
    });
  }

  /// Soft archive keeps consumption and stock history intact.
  Future<void> archivePackage({required String profileId,
      required String medicationId, required String packageId}) async {
    await db.transaction(() async {
      await _ownedPackage(profileId, medicationId, packageId);
      await db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: _archiveKey(
            profileId, medicationId, packageId), value: '1'));
      await (db.delete(db.stockSelections)..where((s) =>
        s.profileId.equals(profileId) & s.medicationId.equals(medicationId) &
        s.packageId.equals(packageId))).go();
      await _insertMovement(profileId: profileId, medicationId: medicationId,
        packageId: packageId, kind: 'metadata', delta: 0,
        note: 'بسته بایگانی شد');
    });
  }

  Future<void> restorePackage({required String profileId,
      required String medicationId, required String packageId}) async {
    await db.transaction(() async {
      await _ownedPackage(profileId, medicationId, packageId);
      await (db.delete(db.appSettings)..where((s) => s.key.equals(
        _archiveKey(profileId, medicationId, packageId)))).go();
      final current = await (db.select(db.stockSelections)
        ..where((t) => t.profileId.equals(profileId) &
          t.medicationId.equals(medicationId))).getSingleOrNull();
      final pack = await _ownedPackage(profileId, medicationId, packageId);
      if (current == null && await _balanceForPackage(packageId) > 0 &&
          !StockQuantity.isExpired(
            pack.expiryIso, pack.expiryPrecision, DateTime.now())) {
        await db.into(db.stockSelections).insertOnConflictUpdate(
          StockSelectionsCompanion.insert(
            profileId: profileId, medicationId: medicationId,
            packageId: packageId));
      }
      await _insertMovement(profileId: profileId, medicationId: medicationId,
        packageId: packageId, kind: 'metadata', delta: 0,
        note: 'بسته از بایگانی بازگردانده شد');
    });
  }

  /// Only truly unused packages may be permanently removed. A package with
  /// ledger entries must be archived so dose/stock records are never lost.
  Future<void> deleteUnusedPackage({required String profileId,
      required String medicationId, required String packageId}) async {
    await db.transaction(() async {
      await _ownedPackage(profileId, medicationId, packageId);
      final movements = await movementsForPackage(profileId: profileId,
        medicationId: medicationId, packageId: packageId);
      if (movements.isNotEmpty) {
        throw StateError('این بسته سابقهٔ موجودی یا مصرف دارد؛ برای حفظ سوابق، '
          'به‌جای حذف آن را بایگانی کن.');
      }
      await (db.delete(db.stockSelections)..where((s) =>
        s.profileId.equals(profileId) & s.medicationId.equals(medicationId) &
        s.packageId.equals(packageId))).go();
      await (db.delete(db.appSettings)..where((s) => s.key.equals(
        _archiveKey(profileId, medicationId, packageId)))).go();
      await (db.delete(db.stockPackages)..where((p) =>
        p.profileId.equals(profileId) & p.medicationId.equals(medicationId) &
        p.id.equals(packageId))).go();
    });
  }

  Future<void> clearSelection({
    required String profileId,
    required String medicationId,
  }) async {
    await db.transaction(() async {
      await _ownedMedication(profileId, medicationId);
      await (db.delete(db.stockSelections)
            ..where((t) => t.profileId.equals(profileId) &
                t.medicationId.equals(medicationId)))
          .go();
    });
  }

  Future<void> setLowStockThreshold({
    required String profileId,
    required String medicationId,
    required int? thresholdMilliunits,
  }) async {
    if (thresholdMilliunits != null) {
      _validateQuantity(thresholdMilliunits, allowZero: true);
    }
    await db.transaction(() async {
      await _ownedMedication(profileId, medicationId);
      if (thresholdMilliunits == null) {
        await (db.delete(db.stockAlertRules)
              ..where((t) => t.profileId.equals(profileId) &
                  t.medicationId.equals(medicationId)))
            .go();
      } else {
        final selected = await (db.select(db.stockSelections)
              ..where((t) => t.medicationId.equals(medicationId) &
                  t.profileId.equals(profileId)))
            .getSingleOrNull();
        if (selected == null) {
          throw StateError('ابتدا بسته‌ای را برای مصرف انتخاب کنید.');
        }
        final pack = await _ownedPackage(
            profileId, medicationId, selected.packageId);
        await db.into(db.stockAlertRules).insertOnConflictUpdate(
          StockAlertRulesCompanion.insert(
            medicationId: medicationId,
            profileId: profileId,
            unit: pack.unit,
            thresholdMilliunits: thresholdMilliunits,
          ),
        );
      }
    });
  }

  Future<void> adjustPackage({
    required String profileId,
    required String medicationId,
    required String packageId,
    required int deltaMilliunits,
    required String reason,
  }) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty || cleanReason.length > 240) {
      throw ArgumentError('دلیل اصلاح موجودی باید ثبت شود.');
    }
    if (deltaMilliunits == 0 ||
        deltaMilliunits.abs() > StockQuantity.maxMilliunits) {
      throw ArgumentError('تغییر موجودی باید عددی غیرصفر و معتبر باشد.');
    }
    await db.transaction(() async {
      await _ownedPackage(profileId, medicationId, packageId);
      final balance = await _balanceForPackage(packageId);
      if (balance + deltaMilliunits < 0 ||
          balance + deltaMilliunits > StockQuantity.maxMilliunits) {
        throw StateError('موجودی بسته کافی نیست یا از حد مجاز عبور می‌کند.');
      }
      await _insertMovement(
        profileId: profileId, medicationId: medicationId, packageId: packageId,
        kind: 'adjustment', delta: deltaMilliunits, note: cleanReason,
      );
    });
  }

  /// Invoke ONLY inside the same transaction as DoseEvents + DoseCurrentStates.
  /// The caller supplies the actual quantity and a user-selected package.
  Future<void> consumeForDoseInTransaction({
    required String profileId,
    required String medicationId,
    required String packageId,
    required String occurrenceKey,
    required int quantityMilliunits,
  }) async {
    _validateQuantity(quantityMilliunits, allowZero: false);
    final pack = await _ownedPackage(profileId, medicationId, packageId);
    if (await _isArchived(profileId, medicationId, packageId)) {
      throw StateError('از بستهٔ بایگانی‌شده موجودی کسر نمی‌شود.');
    }
    final selection = await (db.select(db.stockSelections)
          ..where((t) => t.profileId.equals(profileId) &
              t.medicationId.equals(medicationId)))
        .getSingleOrNull();
    if (selection?.packageId != packageId) {
      throw StateError('بسته انتخاب‌شده تغییر کرده است؛ دوباره بررسی کنید.');
    }
    if (StockQuantity.isExpired(
        pack.expiryIso, pack.expiryPrecision, DateTime.now())) {
      throw StateError('از بسته منقضی موجودی کسر نمی‌شود.');
    }
    if (await _balanceForPackage(packageId) < quantityMilliunits) {
      throw StateError('موجودی بسته برای این مقدار کافی نیست.');
    }
    await _insertMovement(
      profileId: profileId, medicationId: medicationId, packageId: packageId,
      kind: 'taken', delta: -quantityMilliunits,
      occurrenceKey: occurrenceKey,
      note: 'مقدار واقعی مصرف‌شده به اعلام کاربر',
    );
  }

  /// Compensate the exact unmatched debit once; no compensating entry is
  /// written for a dose originally recorded without stock deduction.
  Future<void> reverseDoseInTransaction({
    required String profileId,
    required String medicationId,
    required String occurrenceKey,
  }) async {
    final movements = await (db.select(db.stockMovements)
          ..where((t) => t.profileId.equals(profileId) &
              t.medicationId.equals(medicationId) &
              t.occurrenceKey.equals(occurrenceKey)))
        .get();
    final reversed = <String>{
      for (final row in movements)
        if (row.reversesMovementId != null) row.reversesMovementId!,
    };
    final outstanding = movements.where((row) =>
        row.kind == 'taken' && !reversed.contains(row.id)).toList();
    if (outstanding.isEmpty) return;
    if (outstanding.length != 1) {
      throw StateError('سوابق کسر موجودی ناسازگارند؛ اصلاح دستی لازم است.');
    }
    final debit = outstanding.single;
    await _insertMovement(
      profileId: profileId, medicationId: medicationId,
      packageId: debit.packageId, kind: 'undo',
      delta: -debit.deltaMilliunits,
      occurrenceKey: occurrenceKey,
      reversesMovementId: debit.id,
      note: 'جبران دقیق کسر هنگام بازگرداندن ثبت',
    );
  }

  void _validateQuantity(int value, {required bool allowZero}) {
    if (value < 0 || value > StockQuantity.maxMilliunits ||
        (!allowZero && value == 0)) {
      throw ArgumentError('مقدار موجودی معتبر نیست.');
    }
  }

  Future<void> _insertMovement({
    required String profileId,
    required String medicationId,
    required String packageId,
    required String kind,
    required int delta,
    String? occurrenceKey,
    String? reversesMovementId,
    String? note,
  }) async {
    await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
          id: _uuid.v4(),
          profileId: profileId,
          medicationId: medicationId,
          packageId: packageId,
          kind: kind,
          deltaMilliunits: delta,
          occurrenceKey: Value(occurrenceKey),
          reversesMovementId: Value(reversesMovementId),
          note: Value(note),
          createdAt: DateTime.now().toUtc(),
        ));
  }
}
