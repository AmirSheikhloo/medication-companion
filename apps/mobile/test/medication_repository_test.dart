import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';

void main() {
  late AppDatabase db;
  late MedicationRepository repo;
  late ProfileRepository profiles;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = MedicationRepository(db, clock: () => DateTime(2026, 11, 15));
    profiles = ProfileRepository(db);
  });
  tearDown(() async => db.close());

  test('local profile selection is persisted and isolates medications', () async {
    final self = await profiles.createGuestProfile(forSelf: true, displayName: 'امیر');
    final cared = await profiles.createGuestProfile(forSelf: false, displayName: 'مادر');
    expect((await profiles.activeProfile())?.id, cared.id);

    await repo.addDailyMedication(
      profileId: cared.id,
      name: 'داروی نمونه',
      doseText: '۱ عدد طبق نسخه',
      time: const TimeOfDayValue(8, 15),
    );
    expect(await repo.medicationsFor(self.id), isEmpty);
    expect((await repo.medicationsFor(cared.id)).length, 1);

    await profiles.selectActiveProfile(self.id);
    expect((await profiles.activeProfile())?.id, self.id);
  });

  test('double tap has one effective dose event; undo appends history', () async {
    final profile = await profiles.createGuestProfile(forSelf: true);
    await repo.addDailyMedication(
      profileId: profile.id,
      name: 'داروی آزمایشی',
      doseText: 'طبق نسخه',
      time: const TimeOfDayValue(10, 30),
    );
    final doses = await repo.dosesForDay(profile.id, DateTime(2026, 11, 16));
    expect(doses, hasLength(1));
    final dose = doses.single;

    expect(await repo.recordDose(
      dose: dose, profileId: profile.id, action: 'taken',
    ), isTrue);
    expect(await repo.recordDose(
      dose: dose, profileId: profile.id, action: 'taken',
    ), isFalse);
    expect((await db.select(db.doseEvents).get()).length, 1);
    expect((await repo.dosesForDay(profile.id, DateTime(2026, 11, 16)))
        .single.status, 'taken');

    expect(await repo.recordDose(
      dose: dose, profileId: profile.id, action: 'undo',
    ), isTrue);
    expect((await db.select(db.doseEvents).get()).length, 2);
    expect((await repo.dosesForDay(profile.id, DateTime(2026, 11, 16)))
        .single.status, 'pending');
  });

  test('new schedule skips all earlier civil minutes and keeps future slots', () async {
    final profile = await profiles.createGuestProfile(forSelf: true);
    final now = DateTime(2026, 11, 25, 19, 0, 30);
    final service = MedicationRepository(db, clock: () => now);
    await service.addMedicationSchedule(profileId: profile.id, name: 'داروی جدید',
      slots: const [
        DoseSlotInput(doseText: 'صبح', time: TimeOfDayValue(8, 0)),
        DoseSlotInput(doseText: 'همین دقیقه', time: TimeOfDayValue(19, 0)),
        DoseSlotInput(doseText: 'شب', time: TimeOfDayValue(21, 0)),
      ]);
    expect(await service.dosesForDay(profile.id, DateTime(2026, 11, 24)), isEmpty);
    expect((await service.dosesForDay(profile.id, now)).map((d) => d.scheduledAt.hour), [19, 21]);
    expect((await service.dosesForDay(profile.id, DateTime(2026, 11, 26))).map((d) => d.scheduledAt.hour), [8, 19, 21]);
  });

  test('historic archived course is reviewable without inventing suspended doses', () async {
    final profile = await profiles.createGuestProfile(forSelf: true);
    var clock = DateTime(2026, 11, 20, 7);
    final service = MedicationRepository(db, clock: () => clock);
    final id = await service.addDailyMedication(profileId: profile.id,
      name: 'تست دوره', doseText: '1 عدد', time: const TimeOfDayValue(8, 0));
    clock = DateTime(2026, 11, 21, 12);
    await service.setArchived(profileId: profile.id, medicationId: id, archived: true);
    clock = DateTime(2026, 11, 24, 12);
    final rows = await service.dosesForDay(profile.id, DateTime(2026, 11, 20), historical: true);
    expect(rows, hasLength(1));
    expect(await service.dosesForDay(profile.id, DateTime(2026, 11, 22), historical: true), isEmpty);
    expect(await service.recordDose(dose: rows.single, profileId: profile.id,
      action: 'skipped'), isTrue);
    expect((await service.dosesForDay(profile.id, DateTime(2026, 11, 20), historical: true)).single.status, 'skipped');
    await service.setArchived(profileId: profile.id, medicationId: id, archived: false);
    expect(await service.dosesForDay(profile.id, DateTime(2026, 11, 22), historical: true), isEmpty);
    expect(await service.dosesForDay(profile.id, DateTime(2026, 11, 25)), hasLength(1));
  });

  test('wrong profile cannot record another person\'s dose', () async {
    final first = await profiles.createGuestProfile(forSelf: true);
    final second = await profiles.createGuestProfile(forSelf: false);
    await repo.addDailyMedication(
      profileId: first.id,
      name: 'نمونه',
      doseText: 'طبق نسخه',
      time: const TimeOfDayValue(11, 0),
    );
    final dose = (await repo.dosesForDay(first.id, DateTime.now())).single;
    await expectLater(
      repo.recordDose(dose: dose, profileId: second.id, action: 'taken'),
      throwsStateError,
    );
    expect((await db.select(db.doseEvents).get()), isEmpty);
  });
}
