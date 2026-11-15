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
    repo = MedicationRepository(db);
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
