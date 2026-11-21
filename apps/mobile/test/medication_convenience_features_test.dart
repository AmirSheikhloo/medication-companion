import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/medications/data/medication_list_export.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
import 'package:medication_companion/features/medications/domain/medication_week_report.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late MedicationRepository medications;
  late ProfileRepository profiles;
  late Profile profile;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    medications = MedicationRepository(db);
    profiles = ProfileRepository(db);
    profile = await profiles.createGuestProfile(forSelf: true);
  });
  tearDown(() async => db.close());

  test('seven-day report avoids retroactive schedules and respects profiles',
      () async {
    final today = DateTime.now();
    await medications.addDailyMedication(
      profileId: profile.id,
      name: 'نمونه یک', doseText: 'طبق نسخه',
      time: const TimeOfDayValue(8, 0),
    );
    await medications.addDailyMedication(
      profileId: profile.id,
      name: 'نمونه دو', doseText: 'طبق نسخه',
      time: const TimeOfDayValue(12, 0),
    );
    final someoneElse = await profiles.createGuestProfile(forSelf: false);
    await medications.addDailyMedication(
      profileId: someoneElse.id,
      name: 'داروی شخص دیگر', doseText: 'طبق نسخه',
      time: const TimeOfDayValue(16, 0),
    );

    final original = await MedicationWeekReportRepository(medications)
        .forProfile(profileId: profile.id, endingOn: today);
    expect(original.days, hasLength(7));
    expect(original.days.take(6).every((d) => d.total == 0), isTrue);
    expect(original.total, 2);
    expect(original.pending, 2);

    final doses = await medications.dosesForDay(profile.id, today);
    await medications.recordDose(
      dose: doses[0], profileId: profile.id, action: 'taken');
    await medications.recordDose(
      dose: doses[1], profileId: profile.id, action: 'skipped');
    var report = await MedicationWeekReportRepository(medications)
        .forProfile(profileId: profile.id, endingOn: today);
    expect(report.taken, 1);
    expect(report.skipped, 1);
    expect(report.pending, 0);
    expect(report.registered, 2);

    await medications.recordDose(
      dose: doses[0], profileId: profile.id, action: 'undo');
    report = await MedicationWeekReportRepository(medications)
        .forProfile(profileId: profile.id, endingOn: today);
    expect(report.taken, 0);
    expect(report.pending, 1);
    expect(report.skipped, 1);
  });

  test('Persian doctor PDF is offline and refuses cross-profile content',
      () async {
    final today = DateTime.now();
    await medications.addDailyMedication(
      profileId: profile.id,
      name: 'Omega-3 — متفورمین 💊', doseText: 'یک عدد با غذا (20cc)',
      time: const TimeOfDayValue(9, 15),
    );
    final meds = await medications.medicationsFor(profile.id);
    final doses = await medications.dosesForDay(profile.id, today);
    final pdf = await const MedicationListExport().buildPdf(
      profile: profile,
      medications: meds,
      doses: doses,
      forDay: today,
    );
    expect(pdf.length, greaterThan(1000));
    expect(ascii.decode(pdf.take(5).toList()), '%PDF-');

    final other = await profiles.createGuestProfile(forSelf: false);
    await medications.addDailyMedication(
      profileId: other.id,
      name: 'داروی محرمانه', doseText: 'اطلاعات شخص دوم',
      time: const TimeOfDayValue(17, 0),
    );
    final otherMeds = await medications.medicationsFor(other.id);
    await expectLater(
      const MedicationListExport().buildPdf(
        profile: profile,
        medications: [...meds, ...otherMeds],
        doses: doses,
        forDay: today,
      ),
      throwsStateError,
    );
  });
}
