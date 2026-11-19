import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';
import 'package:medication_companion/features/reminders/data/android_reminder_port.dart';
import 'package:medication_companion/features/reminders/data/reminder_coordinator.dart';
import 'package:medication_companion/features/reminders/domain/reminder_plan.dart';

class FakeReminderPort implements ReminderNotificationPort {
  bool permissions = true;
  bool requestGranted = true;
  int demoCount = 0;
  int syncCount = 0;
  List<ReminderJob> scheduled = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasPermissions() async => permissions;

  @override
  Future<bool> requestPermissions() async => requestGranted && permissions;

  @override
  Future<void> replaceManaged(List<ReminderJob> jobs) async {
    syncCount++;
    scheduled = List.of(jobs);
  }

  @override
  Future<void> scheduleDemo() async {
    demoCount++;
  }
}

void main() {
  late AppDatabase db;
  late MedicationRepository meds;
  late ProfileRepository profiles;
  late FakeReminderPort port;
  late ReminderCoordinator coordinator;
  final currentDay = DateTime.now();
  final fixedNow =
      DateTime(currentDay.year, currentDay.month, currentDay.day, 7, 0);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    meds = MedicationRepository(db);
    profiles = ProfileRepository(db);
    port = FakeReminderPort();
    coordinator = ReminderCoordinator(
      database: db,
      medications: meds,
      profiles: profiles,
      notifications: port,
      clock: () => fixedNow,
    );
  });
  tearDown(() async => db.close());

  test('opt-in schedules all profiles but never silently opts in', () async {
    final first = await profiles.createGuestProfile(forSelf: true);
    final second = await profiles.createGuestProfile(forSelf: false);
    for (final profile in [first, second]) {
      await meds.addDailyMedication(
        profileId: profile.id,
        name: 'آزمایش',
        doseText: 'متن نمونه',
        time: const TimeOfDayValue(8, 0),
      );
    }
    expect(await coordinator.isEnabled(), isFalse);
    expect(port.scheduled, isEmpty);
    expect(await coordinator.refreshIfEnabled(), isNull);
    expect(port.syncCount, 0);

    final count = await coordinator.enable();
    expect(count, 4); // two profiles, today once + tomorrow daily
    expect(await coordinator.isEnabled(), isTrue);
    expect(port.scheduled.where((job) => job.daily), hasLength(2));
    expect(port.scheduled.where((job) => !job.daily), hasLength(2));
    expect(port.scheduled.map((job) => job.id).toSet(), hasLength(4));
    expect(port.scheduled.every((job) => job.body.contains('آزمایش')), isTrue);

    await coordinator.disable();
    expect(await coordinator.isEnabled(), isFalse);
    expect(port.scheduled, isEmpty);
  });

  test('marking a dose and archiving reconcile pending reminders', () async {
    final profile = await profiles.createGuestProfile(forSelf: true);
    final id = await meds.addMedicationSchedule(
      profileId: profile.id,
      name: 'آزمایشی',
      slots: const [
        DoseSlotInput(doseText: 'صبح', time: TimeOfDayValue(8, 0)),
        DoseSlotInput(doseText: 'ظهر', time: TimeOfDayValue(12, 0)),
      ],
    );
    await coordinator.enable();
    expect(port.scheduled, hasLength(4));

    final today = (await meds.dosesForDay(profile.id, fixedNow)).first;
    await meds.recordDose(
      dose: today,
      profileId: profile.id,
      action: 'taken',
    );
    await coordinator.refreshIfEnabled();
    expect(port.scheduled.where((job) => !job.daily), hasLength(1));
    expect(port.scheduled.where((job) => job.daily), hasLength(2));

    await meds.setArchived(
      profileId: profile.id,
      medicationId: id,
      archived: true,
    );
    await coordinator.refreshIfEnabled();
    expect(port.scheduled, isEmpty);
    await meds.setArchived(
      profileId: profile.id,
      medicationId: id,
      archived: false,
    );
    await coordinator.refreshIfEnabled();
    expect(port.scheduled, hasLength(3));
  });

  test('tomorrow uses the new immutable version after an edit', () async {
    final profile = await profiles.createGuestProfile(forSelf: true);
    final id = await meds.addDailyMedication(
      profileId: profile.id,
      name: 'قبل',
      doseText: 'قبلی',
      time: const TimeOfDayValue(8, 0),
    );
    await meds.updateMedicationSchedule(
      profileId: profile.id,
      medicationId: id,
      name: 'بعد',
      slots: const [
        DoseSlotInput(doseText: 'جدید', time: TimeOfDayValue(10, 0)),
      ],
    );
    await coordinator.enable();
    final today = port.scheduled.singleWhere((job) => !job.daily);
    final recurring = port.scheduled.singleWhere((job) => job.daily);
    expect(today.localAt.hour, 8);
    expect(recurring.localAt.hour, 10);
  });

  test('revoked permission is reported, without claiming reminders exist',
      () async {
    await profiles.createGuestProfile(forSelf: true);
    port.requestGranted = false;
    await expectLater(coordinator.enable(), throwsStateError);
    expect(await coordinator.isEnabled(), isFalse);
    expect(port.syncCount, 0);

    port.requestGranted = true;
    await coordinator.enable();
    port.permissions = false;
    await expectLater(coordinator.refreshIfEnabled(), throwsStateError);
  });


  test('repeated reminder reconciliation is idempotent and writes no history',
      () async {
    final profile = await profiles.createGuestProfile(forSelf: true);
    await meds.addDailyMedication(
      profileId: profile.id,
      name: 'نمونه',
      doseText: 'نمونه',
      time: const TimeOfDayValue(8, 0),
    );
    await coordinator.enable();
    final before = port.scheduled.map((job) =>
        '${job.id}:${job.localAt.millisecondsSinceEpoch}:${job.daily}').toList();
    Future<int> rowCount(String table) async {
      final rows = await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle();
      return rows.read<int>('n');
    }
    final events = await rowCount('dose_events');
    final stock = await rowCount('stock_movements');
    final settings = await rowCount('app_settings');

    for (var i = 0; i < 3; i++) {
      expect(await coordinator.refreshIfEnabled(), before.length);
      expect(port.scheduled.map((job) =>
          '${job.id}:${job.localAt.millisecondsSinceEpoch}:${job.daily}').toList(),
          before);
    }
    expect(await rowCount('dose_events'), events);
    expect(await rowCount('stock_movements'), stock);
    expect(await rowCount('app_settings'), settings);
    final replacements = port.syncCount;
    port.permissions = false;
    await expectLater(coordinator.refreshIfEnabled(), throwsStateError);
    expect(port.syncCount, replacements);
    expect(await coordinator.isEnabled(), isTrue);
  });

  test('five-second demo requires opt-in and does not change plan', () async {
    await expectLater(coordinator.demoInFiveSeconds(), throwsStateError);
    await coordinator.enable();
    await coordinator.demoInFiveSeconds();
    expect(port.demoCount, 1);
    expect(port.scheduled, isEmpty);
  });
}
