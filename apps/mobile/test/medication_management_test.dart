import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';

void main() {
  late AppDatabase db;
  late MedicationRepository medications;
  late ProfileRepository profiles;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    medications = MedicationRepository(db);
    profiles = ProfileRepository(db);
  });
  tearDown(() async => db.close());

  test('several daily slots have separate keys, instructions and states',
      () async {
    final profile = await profiles.createGuestProfile(forSelf: true);
    await medications.addMedicationSchedule(
      profileId: profile.id,
      name: 'داروی تستی',
      slots: const [
        DoseSlotInput(doseText: 'صبح طبق نسخه', time: TimeOfDayValue(8, 0)),
        DoseSlotInput(doseText: 'شب طبق نسخه', time: TimeOfDayValue(20, 30)),
      ],
    );
    final today = DateTime.now();
    final doses = await medications.dosesForDay(profile.id, today);
    expect(doses, hasLength(2));
    expect(doses.map((e) => e.plan.doseText),
        ['صبح طبق نسخه', 'شب طبق نسخه']);
    expect(doses.map((e) => e.scheduledAt.hour), [8, 20]);
    expect(doses.first.occurrenceKey, isNot(doses.last.occurrenceKey));
    expect(await medications.recordDose(
      dose: doses.first, profileId: profile.id, action: 'taken',
    ), isTrue);
    final latest = await medications.dosesForDay(profile.id, today);
    expect(latest.map((e) => e.status), ['taken', 'pending']);
  });

  test('reject duplicate times and do not write partial medication', () async {
    final profile = await profiles.createGuestProfile(forSelf: true);
    await expectLater(
      medications.addMedicationSchedule(
        profileId: profile.id,
        name: 'تستی',
        slots: const [
          DoseSlotInput(doseText: 'اول', time: TimeOfDayValue(9, 0)),
          DoseSlotInput(doseText: 'دوم', time: TimeOfDayValue(9, 0)),
        ],
      ),
      throwsArgumentError,
    );
    expect(await medications.medicationsFor(profile.id), isEmpty);
    expect(await db.select(db.medicationPlanVersions).get(), isEmpty);
  });

  test('edit next-day plan preserves today and append-only history', () async {
    final profile = await profiles.createGuestProfile(forSelf: true);
    final medicationId = await medications.addDailyMedication(
      profileId: profile.id,
      name: 'داروی اولیه',
      doseText: 'نوبت قدیمی',
      time: const TimeOfDayValue(10, 0),
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final original = (await medications.dosesForDay(profile.id, today)).single;
    expect(await medications.recordDose(
      dose: original, profileId: profile.id, action: 'taken',
    ), isTrue);

    await medications.updateMedicationSchedule(
      profileId: profile.id,
      medicationId: medicationId,
      name: 'داروی ویرایش‌شده',
      slots: const [
        DoseSlotInput(doseText: 'صبح', time: TimeOfDayValue(7, 15)),
        DoseSlotInput(doseText: 'شب', time: TimeOfDayValue(21, 0)),
      ],
    );
    final todayAfter = (await medications.dosesForDay(profile.id, today)).single;
    expect(todayAfter.occurrenceKey, original.occurrenceKey);
    expect(todayAfter.status, 'taken');
    final next = await medications.dosesForDay(profile.id, tomorrow);
    expect(next, hasLength(2));
    expect(next.map((e) => e.plan.version), [2, 2]);
    expect(next.map((e) => e.scheduledAt.hour), [7, 21]);
    expect((await db.select(db.doseEvents).get()), hasLength(1));
    expect((await db.select(db.medicationPlanVersions).get()), hasLength(3));
    await expectLater(
      medications.recordDose(
        dose: original,
        profileId: profile.id,
        action: 'taken',
      ),
      completion(isFalse),
    );
  });

  test('second edit supersedes pending schedule without deleting versions',
      () async {
    final profile = await profiles.createGuestProfile(forSelf: true);
    final medicationId = await medications.addDailyMedication(
      profileId: profile.id,
      name: 'اولیه',
      doseText: 'اولیه',
      time: const TimeOfDayValue(8, 0),
    );
    for (final time in [9, 11]) {
      await medications.updateMedicationSchedule(
        profileId: profile.id,
        medicationId: medicationId,
        name: 'تغییر',
        slots: [DoseSlotInput(
          doseText: 'نسخه جدید',
          time: TimeOfDayValue(time, 0),
        )],
      );
    }
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final active = (await medications.dosesForDay(profile.id, tomorrow)).single;
    expect(active.plan.version, 3);
    expect(active.scheduledAt.hour, 11);
    expect((await db.select(db.medicationPlanVersions).get()), hasLength(3));
  });

  test('archive and restore are profile-scoped and preserve all rows',
      () async {
    final first = await profiles.createGuestProfile(forSelf: true);
    final other = await profiles.createGuestProfile(forSelf: false);
    final medicationId = await medications.addDailyMedication(
      profileId: first.id,
      name: 'نمونه',
      doseText: 'طبق نسخه',
      time: const TimeOfDayValue(8, 0),
    );
    await expectLater(
      medications.setArchived(
        profileId: other.id,
        medicationId: medicationId,
        archived: true,
      ),
      throwsStateError,
    );
    expect(await medications.medicationsFor(first.id), hasLength(1));
    await medications.setArchived(
      profileId: first.id,
      medicationId: medicationId,
      archived: true,
    );
    expect(await medications.medicationsFor(first.id), isEmpty);
    expect(await medications.medicationsFor(first.id, archived: true),
        hasLength(1));
    expect(await medications.dosesForDay(first.id, DateTime.now()), isEmpty);
    expect(await db.select(db.medicationPlanVersions).get(), hasLength(1));

    await medications.setArchived(
      profileId: first.id,
      medicationId: medicationId,
      archived: false,
    );
    expect(await medications.medicationsFor(first.id), hasLength(1));
    expect(await medications.dosesForDay(first.id, DateTime.now()),
        hasLength(1));
    expect(await medications.medicationsFor(other.id), isEmpty);
  });
}
