import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/inventory/data/inventory_repository.dart';
import 'package:medication_companion/features/medications/data/medication_course_repository.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
import 'package:medication_companion/features/medications/data/medication_setup_repository.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';

void main() {
  late AppDatabase db;
  late MedicationRepository meds;
  late MedicationCourseRepository courses;
  late InventoryRepository stock;
  late ProfileRepository profiles;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    meds = MedicationRepository(db);
    courses = MedicationCourseRepository(db);
    stock = InventoryRepository(db);
    profiles = ProfileRepository(db);
  });
  tearDown(() async => db.close());

  test('same name after end creates a separate course with no event mixing',
      () async {
    final owner = await profiles.createGuestProfile(forSelf: true);
    final other = await profiles.createGuestProfile(forSelf: false);
    Future<String> add(String profile, String name) =>
      meds.addDailyMedication(profileId: profile, name: name,
        doseText: '1 عدد', time: const TimeOfDayValue(8, 0));

    final earlier = await add(owner.id, 'استامينوفن ۵۰۰');
    final differentStrength = await add(owner.id, 'استامینوفن 250');
    final otherProfile = await add(other.id, 'استامینوفن 500');
    await meds.setArchived(profileId: owner.id, medicationId: earlier,
      archived: true);
    final current = await add(owner.id, 'استامینوفن 500');
    final matching = await courses.sameNameCourses(
      (await meds.medicationsFor(owner.id)).singleWhere((m) => m.id == current));
    expect(matching.map((m) => m.id).toSet(), {earlier, current});
    expect(matching.map((m) => m.id), isNot(contains(otherProfile)));
    expect(matching.map((m) => m.id), isNot(contains(differentStrength)));

    final historical = (await meds.medicationsFor(owner.id, archived: true))
      .singleWhere((m) => m.id == earlier);
    final report = await courses.report(historical);
    expect(report.ended, isNotNull);
    expect(report.days, greaterThanOrEqualTo(1));
    expect((await courses.report(matching.first)).recordedDoses, 0);
  });

  test('report uses effective statuses and only actual signed stock debits',
      () async {
    final profile = await profiles.createGuestProfile(forSelf: true);
    final id = await meds.addDailyMedication(profileId: profile.id,
      name: 'داروی تست دوره', doseText: '1 عدد',
      time: const TimeOfDayValue(8, 0));
    final pack = await stock.addPackage(profileId: profile.id,
      medicationId: id, label: 'بسته', unit: 'عدد',
      initialMilliunits: 20000, selectForUse: true);
    final dose = (await meds.dosesForDay(profile.id, DateTime.now())).single;
    await meds.recordDose(dose: dose, profileId: profile.id, action: 'taken',
      stockPackageId: pack, stockQuantityMilliunits: 2000);
    var report = await courses.report((await meds.medicationsFor(profile.id)).single);
    expect(report.taken, 1);
    expect(report.recordedDoses, 1);
    expect(report.stockDebitedMilliunits, 2000);

    final taken = (await meds.dosesForDay(profile.id, DateTime.now())).single;
    await meds.recordDose(dose: taken, profileId: profile.id, action: 'undo');
    report = await courses.report((await meds.medicationsFor(profile.id)).single);
    expect(report.taken, 0);
    expect(report.recordedDoses, 0);
    expect(report.stockDebitedMilliunits, 0);

    final pending = (await meds.dosesForDay(profile.id, DateTime.now())).single;
    await meds.recordDose(dose: pending, profileId: profile.id, action: 'taken');
    report = await courses.report((await meds.medicationsFor(profile.id)).single);
    expect(report.taken, 1);
    expect(report.stockDebitedMilliunits, 0);
    expect((await db.select(db.doseEvents).get()), hasLength(3));
  });

  test('strip metadata is optional and remains bounded', () async {
    final profile = await profiles.createGuestProfile(forSelf: true);
    final id = await meds.addDailyMedication(profileId: profile.id,
      name: 'قرص تست', doseText: '1 عدد',
      time: const TimeOfDayValue(9, 0));
    final repository = MedicationSetupRepository(db);
    await repository.save(profileId: profile.id, medicationId: id,
      setup: const MedicationSetup(tabletsPerStrip: 10));
    final report = await courses.report((await meds.medicationsFor(profile.id)).single);
    expect(report.tabletsPerStrip, 10);
  });
}
