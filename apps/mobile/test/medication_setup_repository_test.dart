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
