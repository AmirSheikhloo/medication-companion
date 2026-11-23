import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/inventory/data/inventory_repository.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';

void main() {
  late AppDatabase db;
  late InventoryRepository inventory;
  late MedicationRepository medications;
  late ProfileRepository profiles;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    inventory = InventoryRepository(db);
    medications = MedicationRepository(db);
    profiles = ProfileRepository(db);
  });

  tearDown(() async => db.close());

  Future<(String, String)> setupMedication() async {
    final profile = await profiles.createGuestProfile(forSelf: true);
    final medId = await medications.addDailyMedication(
      profileId: profile.id,
      name: 'داروی فرضی',
      doseText: 'صرفاً آزمایشی',
      time: const TimeOfDayValue(8, 0),
    );
    return (profile.id, medId);
  }

  test('independent packages, selected stock and per-unit threshold', () async {
    final (profileId, medId) = await setupMedication();
    final first = await inventory.addPackage(
      profileId: profileId,
      medicationId: medId,
      label: 'جعبه اول',
      unit: 'عدد',
      initialMilliunits: 10000,
      selectForUse: true,
    );
    final second = await inventory.addPackage(
      profileId: profileId,
      medicationId: medId,
      label: 'شربت جداگانه',
      unit: 'ml',
      initialMilliunits: 30000,
    );
    var summary = await inventory.summary(profileId, medId);
    expect(summary.packages, hasLength(2));
    expect(summary.selectedPackageId, first);
    expect(summary.selected?.balanceMilliunits, 10000);
    await inventory.setLowStockThreshold(
      profileId: profileId,
      medicationId: medId,
      thresholdMilliunits: 9000,
    );
    expect((await inventory.summary(profileId, medId)).lowStock, isFalse);
    await inventory.selectPackage(
      profileId: profileId, medicationId: medId, packageId: second);
    summary = await inventory.summary(profileId, medId);
    expect(summary.selected?.package.unit, 'ml');
    expect(summary.selected?.balanceMilliunits, 30000);
    expect(summary.thresholdMilliunits, isNull); // No unit conversion.
    await inventory.clearSelection(profileId: profileId, medicationId: medId);
    expect((await inventory.summary(profileId, medId)).selected, isNull);
  });

  test('debit/undo is atomic, exactly once and preserves append-only history',
      () async {
    final (profileId, medId) = await setupMedication();
    final packId = await inventory.addPackage(
      profileId: profileId, medicationId: medId,
      label: 'آزمایشی', unit: 'عدد',
      initialMilliunits: 4000, selectForUse: true,
    );
    final dose = (await medications.dosesForDay(profileId, DateTime.now())).single;
    expect(await medications.recordDose(
      dose: dose, profileId: profileId, action: 'taken',
      stockPackageId: packId, stockQuantityMilliunits: 1250,
    ), isTrue);
    expect(await medications.recordDose(
      dose: dose, profileId: profileId, action: 'taken',
      stockPackageId: packId, stockQuantityMilliunits: 1250,
    ), isFalse);
    var summary = await inventory.summary(profileId, medId);
    expect(summary.selected?.balanceMilliunits, 2750);
    var latest = (await medications.dosesForDay(profileId, DateTime.now())).single;
    expect(latest.status, 'taken');
    expect(latest.stockDebited, isTrue);
    expect(await medications.recordDose(
      dose: latest, profileId: profileId, action: 'undo',
    ), isTrue);
    expect(await medications.recordDose(
      dose: latest, profileId: profileId, action: 'undo',
    ), isFalse);
    summary = await inventory.summary(profileId, medId);
    expect(summary.selected?.balanceMilliunits, 4000);
    latest = (await medications.dosesForDay(profileId, DateTime.now())).single;
    expect(latest.status, 'pending');
    expect(latest.stockDebited, isFalse);
    expect((await db.select(db.stockMovements).get()).map((e) => e.kind).toSet(),
        {'initial', 'taken', 'undo'});
    expect(await medications.recordDose(
      dose: latest, profileId: profileId, action: 'taken',
    ), isTrue);
    latest = (await medications.dosesForDay(profileId, DateTime.now())).single;
    expect(latest.stockDebited, isFalse);
    expect(await medications.recordDose(
      dose: latest, profileId: profileId, action: 'undo',
    ), isTrue);
    expect((await inventory.summary(profileId, medId))
        .selected?.balanceMilliunits, 4000);
  });

  test('insufficient stock never changes dose state or writes a debit',
      () async {
    final (profileId, medId) = await setupMedication();
    final packId = await inventory.addPackage(
      profileId: profileId, medicationId: medId,
      label: 'یک عدد', unit: 'عدد',
      initialMilliunits: 1000, selectForUse: true,
    );
    final dose = (await medications.dosesForDay(profileId, DateTime.now())).single;
    await expectLater(
      medications.recordDose(
        dose: dose, profileId: profileId, action: 'taken',
        stockPackageId: packId, stockQuantityMilliunits: 1500,
      ),
      throwsStateError,
    );
    final latest = (await medications.dosesForDay(profileId, DateTime.now())).single;
    expect(latest.status, 'pending');
    expect((await inventory.summary(profileId, medId))
        .selected?.balanceMilliunits, 1000);
    expect((await db.select(db.stockMovements).get()), hasLength(1));
    expect(await db.select(db.doseEvents).get(), isEmpty);
  });

  test('adjustment requires reason, cannot go negative, history remains', () async {
    final (profileId, medId) = await setupMedication();
    final packId = await inventory.addPackage(
      profileId: profileId, medicationId: medId,
      label: 'اصلاح', unit: 'عدد',
      initialMilliunits: 2000, selectForUse: true,
    );
    await expectLater(inventory.adjustPackage(
      profileId: profileId, medicationId: medId,
      packageId: packId, deltaMilliunits: -3000, reason: 'دورریز',
    ), throwsStateError);
    await expectLater(inventory.adjustPackage(
      profileId: profileId, medicationId: medId,
      packageId: packId, deltaMilliunits: -1000, reason: '',
    ), throwsArgumentError);
    await inventory.adjustPackage(
      profileId: profileId, medicationId: medId,
      packageId: packId, deltaMilliunits: -1000, reason: 'یک عدد دور ریخته شد',
    );
    await inventory.setLowStockThreshold(
      profileId: profileId, medicationId: medId, thresholdMilliunits: 1000);
    expect((await inventory.summary(profileId, medId)).lowStock, isTrue);
    expect((await db.select(db.stockMovements).get()), hasLength(2));
  });

  test('expired package cannot be selected or debited', () async {
    final (profileId, medId) = await setupMedication();
    final packId = await inventory.addPackage(
      profileId: profileId, medicationId: medId,
      label: 'منقضی', unit: 'عدد',
      initialMilliunits: 4000,
      expiryIso: '2001-01-01', expiryPrecision: 'day',
    );
    await expectLater(inventory.selectPackage(
      profileId: profileId, medicationId: medId, packageId: packId,
    ), throwsStateError);
    await expectLater(inventory.addPackage(
      profileId: profileId, medicationId: medId,
      label: 'منقضی انتخابی', unit: 'عدد', initialMilliunits: 1000,
      expiryIso: '2001-01-01', expiryPrecision: 'day', selectForUse: true,
    ), throwsStateError);
    expect((await inventory.summary(profileId, medId)).selected, isNull);
  });

  test('package history is read-only and blocked across profiles', () async {
    final (profileId, medId) = await setupMedication();
    final packageId = await inventory.addPackage(
      profileId: profileId, medicationId: medId,
      label: 'بسته دفترکل', unit: 'عدد',
      initialMilliunits: 6000, selectForUse: true,
    );
    await inventory.adjustPackage(
      profileId: profileId, medicationId: medId,
      packageId: packageId, deltaMilliunits: -1000,
      reason: 'دورریز ثبت‌شده',
    );
    final dose = (await medications.dosesForDay(
        profileId, DateTime.now())).single;
    await medications.recordDose(
      dose: dose, profileId: profileId, action: 'taken',
      stockPackageId: packageId, stockQuantityMilliunits: 1500,
    );
    await medications.recordDose(
      dose: dose, profileId: profileId, action: 'undo',
    );
    final history = await inventory.movementsForPackage(
      profileId: profileId, medicationId: medId, packageId: packageId,
    );
    expect(history.map((m) => m.kind).toSet(),
        {'initial', 'adjustment', 'taken', 'undo'});
    expect(history, hasLength(4));
    expect(history.singleWhere((m) => m.kind == 'adjustment').note,
        'دورریز ثبت‌شده');
    expect(history.singleWhere((m) => m.kind == 'undo').deltaMilliunits, 1500);
    expect((await inventory.summary(profileId, medId))
        .selected?.balanceMilliunits, 5000);
    final other = await profiles.createGuestProfile(forSelf: false);
    await expectLater(
      inventory.movementsForPackage(
        profileId: other.id, medicationId: medId, packageId: packageId),
      throwsStateError,
    );
    // Reading history never creates new ledger records.
    expect(await db.select(db.stockMovements).get(), hasLength(4));
  });

  test('cannot modify or read other profile inventory via repository', () async {
    final (profileId, medId) = await setupMedication();
    final other = await profiles.createGuestProfile(forSelf: false);
    final packId = await inventory.addPackage(
      profileId: profileId, medicationId: medId, label: 'خصوصی',
      unit: 'عدد', initialMilliunits: 1000,
    );
    await expectLater(
      inventory.summary(other.id, medId), throwsStateError);
    await expectLater(inventory.adjustPackage(
      profileId: other.id, medicationId: medId,
      packageId: packId, deltaMilliunits: 1000, reason: 'سوءاستفاده',
    ), throwsStateError);
    expect((await inventory.summary(profileId, medId))
        .packages.single.balanceMilliunits, 1000);
  });

  test('package edit has audit history, archive blocks stock use, restore works', () async {
    final (profileId, medId) = await setupMedication();
    final packId = await inventory.addPackage(profileId: profileId,
      medicationId: medId, label: 'بسته یک', unit: 'عدد',
      initialMilliunits: 5000, selectForUse: true);
    await inventory.editPackage(profileId: profileId,
      medicationId: medId, packageId: packId,
      label: 'بسته اصلاح‌شده', expiryIso: '2099-05-10',
      expiryPrecision: 'day');
    var state = await inventory.summary(profileId, medId);
    expect(state.selected?.package.label, 'بسته اصلاح‌شده');
    expect(state.selected?.package.expiryIso, '2099-05-10');

    await inventory.archivePackage(profileId: profileId,
      medicationId: medId, packageId: packId);
    state = await inventory.summary(profileId, medId);
    expect(state.packages.single.archived, isTrue);
    expect(state.selected, isNull);
    expect(state.packages.single.balanceMilliunits, 5000);
    await expectLater(inventory.selectPackage(profileId: profileId,
      medicationId: medId, packageId: packId), throwsStateError);
    await expectLater(inventory.deleteUnusedPackage(profileId: profileId,
      medicationId: medId, packageId: packId), throwsStateError);
    await inventory.restorePackage(profileId: profileId,
      medicationId: medId, packageId: packId);
    state = await inventory.summary(profileId, medId);
    expect(state.packages.single.archived, isFalse);
    await inventory.selectPackage(profileId: profileId,
      medicationId: medId, packageId: packId);
    expect((await inventory.summary(profileId, medId)).selected?.package.id, packId);
    final movements = await inventory.movementsForPackage(profileId: profileId,
      medicationId: medId, packageId: packId);
    expect(movements.where((m) => m.kind == 'metadata'), hasLength(3));
  });

  test('eligible package auto-selection never overrides a current choice', () async {
    final (profileId, medId) = await setupMedication();
    final first = await inventory.addPackage(profileId: profileId,
      medicationId: medId, label: 'اول', unit: 'عدد',
      initialMilliunits: 3000);
    expect((await inventory.summary(profileId, medId)).selectedPackageId, first);
    final second = await inventory.addPackage(profileId: profileId,
      medicationId: medId, label: 'دوم', unit: 'عدد',
      initialMilliunits: 5000);
    expect((await inventory.summary(profileId, medId)).selectedPackageId, first);
    await inventory.archivePackage(profileId: profileId,
      medicationId: medId, packageId: first);
    expect((await inventory.summary(profileId, medId)).selected, isNull);
    await inventory.restorePackage(profileId: profileId,
      medicationId: medId, packageId: first);
    expect((await inventory.summary(profileId, medId)).selectedPackageId, first);
    await inventory.selectPackage(profileId: profileId,
      medicationId: medId, packageId: second);
    await inventory.archivePackage(profileId: profileId,
      medicationId: medId, packageId: first);
    await inventory.restorePackage(profileId: profileId,
      medicationId: medId, packageId: first);
    expect((await inventory.summary(profileId, medId)).selectedPackageId, second);
  });

  test('depleting selected package switches only to eligible same-unit stock', () async {
    final (profileId, medId) = await setupMedication();
    final first = await inventory.addPackage(profileId: profileId,
      medicationId: medId, label: 'اول', unit: 'عدد',
      initialMilliunits: 1000);
    final second = await inventory.addPackage(profileId: profileId,
      medicationId: medId, label: 'دوم', unit: 'عدد',
      initialMilliunits: 3000);
    final dose = (await medications.dosesForDay(
      profileId, DateTime.now())).single;
    expect(await medications.recordDose(
      dose: dose, profileId: profileId, action: 'taken',
      stockPackageId: first, stockQuantityMilliunits: 1000), isTrue);
    final stock = await inventory.summary(profileId, medId);
    expect(stock.selectedPackageId, second);
    expect(stock.packages.first.balanceMilliunits, 0);
    expect(stock.selected?.balanceMilliunits, 3000);
  });

  test('zero stock without replacement clears selection but keeps ledger', () async {
    final (profileId, medId) = await setupMedication();
    final first = await inventory.addPackage(profileId: profileId,
      medicationId: medId, label: 'تنها', unit: 'عدد',
      initialMilliunits: 1000);
    final dose = (await medications.dosesForDay(
      profileId, DateTime.now())).single;
    expect(await medications.recordDose(
      dose: dose, profileId: profileId, action: 'taken',
      stockPackageId: first, stockQuantityMilliunits: 1000), isTrue);
    final stock = await inventory.summary(profileId, medId);
    expect(stock.selectedPackageId, isNull);
    expect(stock.packages.single.balanceMilliunits, 0);
    expect(await inventory.movementsForPackage(
      profileId: profileId, medicationId: medId, packageId: first),
      hasLength(2));
  });

  test('empty package without movements can be deleted', () async {
    final (profileId, medId) = await setupMedication();
    final packId = await inventory.addPackage(profileId: profileId,
      medicationId: medId, label: 'بسته خالی', unit: 'عدد',
      initialMilliunits: 0);
    await inventory.deleteUnusedPackage(profileId: profileId,
      medicationId: medId, packageId: packId);
    expect((await inventory.summary(profileId, medId)).packages, isEmpty);
  });
}
