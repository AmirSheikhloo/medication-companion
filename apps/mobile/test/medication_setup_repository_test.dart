import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
import 'package:medication_companion/features/medications/data/medication_setup_repository.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';

void main() {
  test('liquid units are converted exactly; count units are never guessed', () {
    const thirtyCc = ScheduledQuantity(milliunits: 30000, unit: 'سی‌سی');
    expect(MedicationUnits.toPackageMilliunits(thirtyCc, 'میلی‌لیتر'), 30000);
    expect(MedicationUnits.toPackageMilliunits(thirtyCc, 'لیتر'), 30);
    const oneLitre = ScheduledQuantity(milliunits: 1000, unit: 'لیتر');
    expect(MedicationUnits.toPackageMilliunits(oneLitre, 'میلی‌لیتر'), 1000000);
    const oneStrip = ScheduledQuantity(milliunits: 1000, unit: 'ورق');
    expect(MedicationUnits.toPackageMilliunits(oneStrip, 'عدد'), isNull);
    const tinyDrop = ScheduledQuantity(milliunits: 1, unit: 'میلی‌لیتر');
    expect(MedicationUnits.toPackageMilliunits(tinyDrop, 'لیتر'), isNull);
  });

  test('base unit categories are disjoint and preserve canonical storage keys', () {
    expect(MedicationUnits.choicesFor(0).first, 'عدد');
    expect(MedicationUnits.choicesFor(1).first, 'میلی‌لیتر');
    expect(MedicationUnits.choicesFor(1), isNot(contains('عدد')));
    expect(MedicationUnits.choicesFor(0), isNot(contains('میلی‌لیتر')));
    expect(MedicationUnits.categoryOf(MedicationUnits.teaSpoon), 1);
    expect(MedicationUnits.categoryOf('میلی‌گرم'), 2);
    expect(MedicationUnits.stockUnitForDose(MedicationUnits.teaSpoon), 'میلی‌لیتر');
    const dose = ScheduledQuantity(milliunits: 1000, unit: MedicationUnits.teaSpoon);
    expect(5000000 - MedicationUnits.toPackageMilliunits(dose, 'میلی‌لیتر')!, 4995000);
  });

  test('spoon calibration, discrete units, and dimensional boundaries', () {
    const tea = ScheduledQuantity(milliunits: 1500,
      unit: MedicationUnits.teaSpoon);
    expect(MedicationUnits.toPackageMilliunits(tea, 'میلی‌لیتر'), 7500);
    const table = ScheduledQuantity(milliunits: 1000,
      unit: MedicationUnits.tableSpoon);
    expect(MedicationUnits.toPackageMilliunits(table, 'میلی‌لیتر'), 15000);
    const calibrated = ScheduledQuantity(milliunits: 2000,
      unit: MedicationUnits.dessertSpoon, calibratedMlMilliunits: 7500);
    expect(MedicationUnits.toPackageMilliunits(calibrated, 'میلی‌لیتر'), 15000);
    final restored = ScheduledQuantity.fromJson(calibrated.toJson())!;
    expect(restored.calibratedMlMilliunits, 7500);
    const uncalibrated = ScheduledQuantity(milliunits: 1000,
      unit: MedicationUnits.dessertSpoon);
    expect(MedicationUnits.toPackageMilliunits(uncalibrated, 'میلی‌لیتر'), isNull);
    const drop = ScheduledQuantity(milliunits: 3000, unit: 'قطره');
    expect(MedicationUnits.toPackageMilliunits(drop, 'قطره'), 3000);
    expect(MedicationUnits.toPackageMilliunits(drop, 'میلی‌لیتر'), isNull);
    const fraction = ScheduledQuantity(milliunits: 1500, unit: 'پاف');
    expect(MedicationUnits.toPackageMilliunits(fraction, 'پاف'), isNull);
    const mass = ScheduledQuantity(milliunits: 5000, unit: 'میلی‌گرم');
    expect(MedicationUnits.toPackageMilliunits(mass, 'میلی‌لیتر'), isNull);
  });

  test('typed quantities and optional reminder note persist without v6 migration',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profiles = ProfileRepository(db);
    await profiles.createGuestProfile(forSelf: true, displayName: 'امیر');
    final profile = (await profiles.activeProfile())!;
    final medications = MedicationRepository(db);
    final medicationId = await medications.addMedicationSchedule(
      profileId: profile.id, name: 'داروی تست', slots: [
      const DoseSlotInput(doseText: '2 عدد', time: TimeOfDayValue(8, 0)),
    ]);
    final plan = (await medications.dosesForDay(profile.id, DateTime.now()))
        .single.plan;
    final setup = MedicationSetupRepository(db);
    await setup.save(profileId: profile.id, medicationId: medicationId,
      setup: MedicationSetup(
        reminderNote: 'طبق نسخه و با آب فراوان', artwork: 'tablet',
        doses: {plan.id: const ScheduledQuantity(
          milliunits: 2000, unit: 'عدد')},
      ));
    final restored = await setup.read(profile.id, medicationId);
    expect(restored.doses[plan.id]?.milliunits, 2000);
    expect(restored.reminderNote, 'طبق نسخه و با آب فراوان');
    expect(restored.artwork, 'tablet');
    expect((await db.customSelect('PRAGMA user_version').getSingle())
        .read<int>('user_version'), 5);
  });
}
