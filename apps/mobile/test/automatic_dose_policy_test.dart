import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/inventory/data/inventory_repository.dart';
import 'package:medication_companion/features/inventory/domain/dose_recording_policy.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';

void main() {
  test('automatic dose requires a valid selected package and saved preset',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profile = await ProfileRepository(db).createGuestProfile(forSelf: true);
    final medId = await MedicationRepository(db).addDailyMedication(
      profileId: profile.id,
      name: 'داروی آزمایشی',
      doseText: 'صرفاً آزمایشی',
      time: const TimeOfDayValue(9, 0),
    );
    final inventory = InventoryRepository(db);
    Future<AutomaticDoseDecision> decide() async => decideAutomaticDose(
      await inventory.summary(profile.id, medId),
    );

    var result = await decide();
    expect(result.canRecord, isTrue);
    expect(result.deductsStock, isFalse); // No inventory, tracking only.

    final packId = await inventory.addPackage(
      profileId: profile.id, medicationId: medId,
      unit: 'عدد', initialMilliunits: 3000,
    );
    result = await decide();
    expect(result.canRecord, isFalse);
    expect(result.problem, contains('انتخاب نشده'));

    await inventory.selectPackage(
      profileId: profile.id, medicationId: medId, packageId: packId,
    );
    result = await decide();
    expect(result.canRecord, isFalse);
    expect(result.problem, contains('تنظیم نشده'));

    await inventory.setDoseDebitPreset(
      profileId: profile.id, medicationId: medId,
      unit: 'سی‌سی', quantityMilliunits: 1500,
    );
    result = await decide();
    expect(result.canRecord, isFalse);
    expect(result.problem, contains('یکسان نیست'));

    await inventory.setDoseDebitPreset(
      profileId: profile.id, medicationId: medId,
      unit: 'عدد', quantityMilliunits: 4000,
    );
    result = await decide();
    expect(result.canRecord, isFalse);
    expect(result.problem, contains('کافی نیست'));

    await inventory.setDoseDebitPreset(
      profileId: profile.id, medicationId: medId,
      unit: 'عدد', quantityMilliunits: 1250,
    );
    result = await decide();
    expect(result.canRecord, isTrue);
    expect(result.deductsStock, isTrue);
    expect(result.packageId, packId);
    expect(result.quantityMilliunits, 1250);
  });
}
