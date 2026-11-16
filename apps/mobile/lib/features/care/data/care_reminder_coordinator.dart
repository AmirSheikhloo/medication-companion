import 'package:drift/drift.dart';

import '../../../core/storage/app_database.dart';
import '../../profiles/data/profile_repository.dart';
import '../domain/care_schedule.dart';
import 'android_care_reminder_port.dart';
import 'care_repository.dart';

/// The OS only displays scheduled reminders. The database remains the source
/// of truth, even if permission is denied or a notification is dismissed.
class CareReminderCoordinator {
  CareReminderCoordinator({
    required this.database,
    required this.care,
    required this.profiles,
    required this.notifications,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const settingKey = 'm3_care_reminders_enabled';
  final AppDatabase database;
  final CareRepository care;
  final ProfileRepository profiles;
  final CareReminderNotificationPort notifications;
  final DateTime Function() _clock;
  final CareReminderPlanner _planner = const CareReminderPlanner();

  Future<bool> isEnabled() async {
    final row = await (database.select(database.appSettings)
          ..where((t) => t.key.equals(settingKey)))
        .getSingleOrNull();
    return row?.value == 'true';
  }

  Future<void> _setEnabled(bool enabled) async {
    await database.into(database.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: settingKey,
            value: enabled ? 'true' : 'false',
          ),
        );
  }

  Future<int> enable() async {
    await notifications.initialize();
    if (!await notifications.requestPermissions()) {
      throw StateError('مجوز اعلان و آلارم دقیق را در تنظیمات اندروید بدهید.');
    }
    try {
      final count = await _replaceFromDatabase();
      await _setEnabled(true);
      return count;
    } catch (_) {
      try {
        await notifications.replaceManaged(const []);
      } catch (_) {
        // Preserve the original error; the next refresh can reconcile jobs.
      }
      rethrow;
    }
  }

  Future<void> disable() async {
    await notifications.initialize();
    await notifications.replaceManaged(const []);
    await _setEnabled(false);
  }

  Future<int?> refreshIfEnabled() async {
    if (!await isEnabled()) return null;
    await notifications.initialize();
    if (!await notifications.hasPermissions()) {
      throw StateError('مجوز اعلان‌های پیگیری غیرفعال است؛ دوباره بررسی کنید.');
    }
    return _replaceFromDatabase();
  }

  Future<void> demoInFiveSeconds() async {
    if (!await isEnabled()) throw StateError('ابتدا اعلان‌های پیگیری را فعال کنید.');
    await notifications.initialize();
    if (!await notifications.hasPermissions()) {
      throw StateError('مجوز اعلان یا آلارم دقیق فعال نیست.');
    }
    await notifications.scheduleDemo();
  }

  Future<int> _replaceFromDatabase() async {
    final now = _clock();
    final candidates = <CareReminderCandidate>[];
    for (final profile in await profiles.profiles()) {
      final visits = await care.visitsFor(profile.id);
      final tasks = await care.tasksFor(profile.id);
      for (final visit in visits) {
        if (visit.status != 'scheduled') continue;
        final due = visit.scheduledAt.toLocal();
        if (visit.reminderMinutesBefore != null) {
          candidates.add(CareReminderCandidate(
            key: 'visit:${visit.id}:main',
            localAt: due.subtract(Duration(minutes: visit.reminderMinutesBefore!)),
            title: 'یادآوری ویزیت',
            body: 'برای مشاهده زمان مراجعه، برنامه همراه دارو را باز کنید.',
          ));
        }
        if (visit.showChecklistDayBefore) {
          candidates.add(CareReminderCandidate(
            key: 'visit:${visit.id}:checklist',
            localAt: DateTime(due.year, due.month, due.day - 1,
                due.hour, due.minute),
            title: 'چک‌لیست پیش از ویزیت',
            body: 'وسایل و سؤال‌های ویزیت را در همراه دارو مرور کنید.',
          ));
        }
      }
      for (final task in tasks) {
        final before = task.reminderMinutesBefore;
        final dueAt = task.dueAt?.toLocal();
        if (task.status != 'open' || dueAt == null || before == null) continue;
        if (task.repeatRule == 'none') {
          candidates.add(_taskCandidate(task.id, dueAt, before));
        } else {
          var due = CareSchedule.nextAfter(
            dueAt, task.repeatRule, now.add(Duration(minutes: before)),
            anchorDay: task.repeatAnchorDay,
          );
          for (var i = 0; i < 8; i++) {
            candidates.add(_taskCandidate(task.id, due, before));
            due = CareSchedule.advance(
              due, task.repeatRule, anchorDay: task.repeatAnchorDay,
            );
          }
        }
      }
    }
    final jobs = _planner.plan(now: now, candidates: candidates);
    await notifications.replaceManaged(jobs);
    return jobs.length;
  }

  CareReminderCandidate _taskCandidate(
      String taskId, DateTime due, int beforeMinutes) => CareReminderCandidate(
        key: 'task:$taskId:${due.toUtc().millisecondsSinceEpoch}',
        localAt: due.subtract(Duration(minutes: beforeMinutes)),
        title: 'یادآوری کار پیگیری',
        body: 'برای بررسی کار خود وارد بخش پیگیری‌های همراه دارو شوید.',
      );
}
