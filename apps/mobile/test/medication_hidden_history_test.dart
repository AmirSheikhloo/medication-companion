import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
import 'package:medication_companion/features/medications/data/medication_course_repository.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';

void main() {
  test('removing from the list is reversible and never erases dose events', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profiles = ProfileRepository(db);
    final medRepo = MedicationRepository(db);
    final profile = await profiles.createGuestProfile(forSelf: true);
    final medId = await medRepo.addDailyMedication(
      profileId: profile.id, name: 'تست حذف ایمن',
      doseText: 'طبق نسخه', time: const TimeOfDayValue(9, 0));
    final dose = (await medRepo.dosesForDay(profile.id, DateTime.now())).single;
    await medRepo.recordDose(dose: dose, profileId: profile.id,
      action: 'taken');
    await medRepo.setHidden(profileId: profile.id,
      medicationId: medId, hidden: true);
    expect(await medRepo.medicationsFor(profile.id), isEmpty);
    expect(await medRepo.medicationsFor(profile.id, archived: true), isEmpty);
    expect((await medRepo.hiddenMedicationsFor(profile.id)).single.id, medId);
    expect((await db.select(db.doseEvents).get()), hasLength(1));
    final course = MedicationCourseRepository(db);
    expect((await course.report(
      (await medRepo.hiddenMedicationsFor(profile.id)).single)).taken, 1);
    await medRepo.setHidden(profileId: profile.id,
      medicationId: medId, hidden: false);
    expect((await medRepo.medicationsFor(profile.id, archived: true)).single.id,
      medId);
    expect((await db.select(db.medicationPlanVersions).get()), hasLength(1));
    expect((await db.select(db.doseEvents).get()), hasLength(1));
  });
}
