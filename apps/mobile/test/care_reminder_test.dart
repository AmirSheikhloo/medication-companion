import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/care/data/android_care_reminder_port.dart';
import 'package:medication_companion/features/care/data/care_reminder_coordinator.dart';
import 'package:medication_companion/features/care/data/care_repository.dart';
import 'package:medication_companion/features/care/domain/care_schedule.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';
import 'package:medication_companion/features/reminders/domain/reminder_plan.dart';

class _FakePort implements CareReminderNotificationPort {
  bool permitted = true;
  bool initialized = false;
  int demoCount = 0;
  List<CareReminderJob> jobs = [];

  @override
  Future<void> initialize() async { initialized = true; }

  @override
  Future<bool> hasPermissions() async => permitted;

  @override
  Future<bool> requestPermissions() async => permitted;

  @override
  Future<void> replaceManaged(List<CareReminderJob> next) async {
    jobs = [...next];
  }

  @override
  Future<void> scheduleDemo() async { demoCount++; }
}

void main() {
  test('calendar follow-up clamps month end without changing medication', () {
    final jan31 = DateTime(2027, 1, 31, 9, 0);
    expect(CareSchedule.monthsAfter(jan31, 3), DateTime(2027, 4, 30, 9));
    final feb = CareSchedule.advance(jan31, 'monthly', anchorDay: 31);
    expect(feb, DateTime(2027, 2, 28, 9));
    expect(CareSchedule.advance(feb, 'monthly', anchorDay: 31),
        DateTime(2027, 3, 31, 9));
  });

  test('old recurring dates fast-forward without a four-year iteration limit', () {
    final stale = DateTime(2020, 1, 31, 9);
    final now = DateTime(2027, 2, 15, 12);
    expect(CareSchedule.nextAfter(stale, 'daily', now),
        DateTime(2027, 2, 16, 9));
    expect(CareSchedule.nextAfter(stale, 'monthly', now, anchorDay: 31),
        DateTime(2027, 2, 28, 9));
    expect(CareSchedule.nextAfter(stale, 'weekly', now).isAfter(now), isTrue);
  });

  test('care notification IDs are stable and never overlap M0/M2 IDs', () {
    const planner = CareReminderPlanner();
    final candidate = CareReminderCandidate(
      key: 'visit:abc', localAt: DateTime(2027, 6, 1, 12),
      title: 'ویزیت', body: 'اعلان',
    );
    final jobs = planner.plan(now: DateTime(2027, 5, 1), candidates: [candidate]);
    expect(jobs, hasLength(1));
    expect(jobs.single.id, CareReminderPlanner.stableId('visit:abc'));
    expect(jobs.single.id, greaterThan(ReminderPlanner.lastManagedId));
    expect(jobs.single.id, lessThanOrEqualTo(CareReminderPlanner.lastManagedId));
    expect(jobs.single.id, isNot(ReminderPlanner.demoNotificationId));
    expect(jobs.single.id, isNot(101));
    expect(jobs.single.id, isNot(202));
  });

  test('planner rejects ID collision and ignores past reminders', () {
    const planner = CareReminderPlanner();
    final now = DateTime(2027, 5, 1, 12);
    CareReminderCandidate item(String key, DateTime due) =>
        CareReminderCandidate(key: key, localAt: due,
            title: 'کار', body: 'بدون جزئیات پزشکی');
    expect(planner.plan(now: now, candidates: [
      item('past', now.subtract(const Duration(minutes: 2))),
    ]), isEmpty);
    expect(() => planner.plan(now: now, candidates: [
      item('same', now.add(const Duration(minutes: 1))),
      item('same', now.add(const Duration(minutes: 2))),
    ]), throwsStateError);
  });

  group('care reminder coordinator', () {
    late AppDatabase db;
    late CareRepository care;
    late ProfileRepository profiles;
    late _FakePort port;
    late CareReminderCoordinator coordinator;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      care = CareRepository(db);
      profiles = ProfileRepository(db);
      port = _FakePort();
      coordinator = CareReminderCoordinator(
        database: db, care: care, profiles: profiles,
        notifications: port,
        clock: () => DateTime(2027, 5, 8, 12),
      );
    });
    tearDown(() async => db.close());

    test('does not schedule before explicit opt-in', () async {
      final p = await profiles.createGuestProfile(forSelf: true);
      await care.addVisit(profileId: p.id, title: 'ویزیت',
        scheduledAt: DateTime(2027, 5, 10, 12), reminderMinutesBefore: 0);
      expect(await coordinator.refreshIfEnabled(), isNull);
      expect(await coordinator.isEnabled(), isFalse);
      expect(port.jobs, isEmpty);
      await expectLater(coordinator.demoInFiveSeconds(), throwsStateError);
    });

    test('permission refusal never opts in or schedules', () async {
      port.permitted = false;
      await expectLater(coordinator.enable(), throwsStateError);
      expect(await coordinator.isEnabled(), isFalse);
      expect(port.jobs, isEmpty);
    });

    test('visit, checklist and tasks schedule; complete and disable reconcile', () async {
      final first = await profiles.createGuestProfile(forSelf: true);
      final second = await profiles.createGuestProfile(forSelf: false,
        displayName: 'مراقبت');
      final visit = await care.addVisit(
        profileId: first.id, title: 'ویزیت',
        scheduledAt: DateTime(2027, 5, 10, 12),
        reminderMinutesBefore: 60, showChecklistDayBefore: true,
      );
      final taskId = await care.addTask(
        profileId: second.id, title: 'کار',
        dueAt: DateTime(2027, 5, 11, 12), reminderMinutesBefore: 15,
      );
      expect(await coordinator.enable(), 3);
      expect(await coordinator.isEnabled(), isTrue);
      expect(port.jobs, hasLength(3));
      await coordinator.demoInFiveSeconds();
      expect(port.demoCount, 1);
      await care.setVisitStatus(
        profileId: first.id, visitId: visit, status: 'completed');
      await care.setTaskStatus(
        profileId: second.id, taskId: taskId, status: 'done');
      expect(await coordinator.refreshIfEnabled(), 0);
      expect(port.jobs, isEmpty);
      await coordinator.disable();
      expect(await coordinator.isEnabled(), isFalse);
    });

    test('repeating task advances independently and schedules future cycles', () async {
      final p = await profiles.createGuestProfile(forSelf: true);
      final id = await care.addTask(
        profileId: p.id, title: 'کار هفتگی',
        dueAt: DateTime(2027, 5, 9, 9),
        repeatRule: 'weekly', reminderMinutesBefore: 0,
      );
      expect(await coordinator.enable(), 8);
      final first = port.jobs.first.localAt;
      await care.setTaskStatus(profileId: p.id, taskId: id, status: 'done');
      final task = (await care.tasksFor(p.id)).single;
      expect(task.status, 'open');
      expect(task.dueAt!.toLocal(), DateTime(2027, 5, 16, 9));
      // Completing a cycle always advances beyond the previous due date;
      // the database keeps the event without changing medication state.
      expect((await care.eventsFor(p.id, id)).last.action, 'completed_cycle');
      expect(await coordinator.refreshIfEnabled(), 8);
      expect(port.jobs.first.localAt.isBefore(first) ||
          port.jobs.first.localAt.isAtSameMomentAs(first), isFalse);
    });
  });
}
