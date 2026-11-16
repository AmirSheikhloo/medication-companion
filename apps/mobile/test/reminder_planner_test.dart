import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/features/reminders/domain/reminder_plan.dart';

void main() {
  const planner = ReminderPlanner();

  ReminderSlot slot(String plan, DateTime day, String status) =>
      ReminderSlot(
        occurrenceKey: '$plan:${day.year}${day.month}${day.day}',
        planId: plan,
        profileName: 'آزمایشی',
        medicationName: 'داروی نمونه',
        doseText: 'طبق نسخه',
        scheduledAt: DateTime(day.year, day.month, day.day, 8, 0),
        status: status,
      );

  test('separate today one-shot and tomorrow daily repeat', () {
    final today = DateTime(2026, 11, 16);
    final tomorrow = DateTime(2026, 11, 17);
    final jobs = planner.plan(
      now: DateTime(2026, 11, 16, 7),
      today: [slot('old-plan', today, 'pending')],
      tomorrow: [slot('new-plan', tomorrow, 'pending')],
    );
    expect(jobs, hasLength(2));
    expect(jobs.where((job) => !job.daily).single.localAt.day, 16);
    expect(jobs.where((job) => job.daily).single.localAt.day, 17);
    expect(jobs.map((job) => job.id).toSet(), hasLength(2));
    expect(jobs.every((job) =>
        job.id >= ReminderPlanner.firstManagedId &&
        job.id <= ReminderPlanner.lastManagedId), isTrue);
    expect(jobs.every((job) =>
        job.id != ReminderPlanner.demoNotificationId), isTrue);
  });

  test('recorded or past today dose does not get a new one-shot alarm', () {
    final today = DateTime(2026, 11, 16);
    final tomorrow = DateTime(2026, 11, 17);
    final jobs = planner.plan(
      now: DateTime(2026, 11, 16, 9),
      today: [
        slot('taken', today, 'taken'),
        slot('expired', today, 'pending'),
      ],
      tomorrow: [slot('next', tomorrow, 'pending')],
    );
    expect(jobs, hasLength(1));
    expect(jobs.single.daily, isTrue);
  });

  test('a pre-marked future day starts recurring the following day', () {
    final tomorrow = DateTime(2026, 11, 17);
    final jobs = planner.plan(
      now: DateTime(2026, 11, 16, 18),
      today: const [],
      tomorrow: [slot('next', tomorrow, 'taken')],
    );
    expect(jobs.single.localAt.day, 18);
    expect(jobs.single.daily, isTrue);
  });

  test('stable IDs do not depend on the current process clock', () {
    expect(ReminderPlanner.stableId('daily:plan1'),
        ReminderPlanner.stableId('daily:plan1'));
    expect(ReminderPlanner.stableId('once:plan1:20261116'),
        isNot(ReminderPlanner.stableId('daily:plan1')));
  });

  test('managed notification count is bounded before Android scheduling', () {
    final tomorrow = DateTime(2026, 11, 17);
    final many = [
      for (var i = 0; i < ReminderPlanner.maxJobs + 1; i++)
        slot('slot-$i', tomorrow, 'pending'),
    ];
    expect(
      () => planner.plan(
        now: DateTime(2026, 11, 16),
        today: const [],
        tomorrow: many,
      ),
      throwsStateError,
    );
  });
}
