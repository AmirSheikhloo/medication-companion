import '../../../core/storage/app_database.dart';
import '../../medications/data/medication_repository.dart';
import '../../medications/data/medication_setup_repository.dart';
import '../../profiles/data/profile_repository.dart';
import '../domain/reminder_plan.dart';
import 'android_reminder_port.dart';

/// Coordinates user opt-in, profile-scoped repository reads, and the
/// replaceable Android notification port. Widgets never schedule OS alarms.
class ReminderCoordinator {
  ReminderCoordinator({
    required this.database,
    required this.medications,
    required this.profiles,
    required this.notifications,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const settingKey = 'm2_reminders_enabled';
  final AppDatabase database;
  final MedicationRepository medications;
  final ProfileRepository profiles;
  final ReminderNotificationPort notifications;
  final DateTime Function() _clock;
  final ReminderPlanner _planner = const ReminderPlanner();

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

  Future<bool> requestPermissionsForDraft({bool fullScreen = false}) async {
    await notifications.initialize();
    if (!await notifications.requestPermissions()) return false;
    if (fullScreen) return notifications.requestFullScreenPermission();
    return true;
  }

  Future<int> enable() async {
    await notifications.initialize();
    if (!await notifications.requestPermissions()) {
      throw StateError(
        'برای فعال‌سازی، مجوز اعلان و آلارم دقیق را در تنظیمات اندروید بدهید.',
      );
    }
    final count = await _replaceFromDatabase();
    await _setEnabled(true);
    return count;
  }

  Future<void> disable() async {
    await notifications.initialize();
    await notifications.replaceManaged(const []);
    await _setEnabled(false);
  }

  /// Called on entry, resume, and every medication/dose mutation.
  /// Revoked OS permissions must surface as a visible error, never success.
  Future<int?> refreshIfEnabled() async {
    if (!await isEnabled()) return null;
    await notifications.initialize();
    if (!await notifications.hasPermissions()) {
      throw StateError(
        'مجوز یادآورهای دقیق غیرفعال شده؛ لطفاً دوباره فعال کنید.',
      );
    }
    return _replaceFromDatabase();
  }

  Future<void> demoInFiveSeconds() async {
    if (!await isEnabled()) {
      throw StateError('ابتدا یادآورهای دارو را فعال کنید.');
    }
    await notifications.initialize();
    if (!await notifications.hasPermissions()) {
      throw StateError('مجوز اعلان یا آلارم دقیق فعال نیست.');
    }
    await notifications.scheduleDemo();
  }

  Future<int> _replaceFromDatabase() async {
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final todaySlots = <ReminderSlot>[];
    final tomorrowSlots = <ReminderSlot>[];
    final setupRepository = MedicationSetupRepository(database);
    for (final profile in await profiles.profiles()) {
      final todayDoses = await medications.dosesForDay(profile.id, today);
      final tomorrowDoses = await medications.dosesForDay(profile.id, tomorrow);
      final setups = <String, MedicationSetup>{};
      for (final dose in [...todayDoses, ...tomorrowDoses]) {
        final id = dose.medication.id;
        if (!setups.containsKey(id)) {
          setups[id] = await setupRepository.read(profile.id, id);
        }
      }
      todaySlots.addAll([
        for (final dose in todayDoses)
          if (setups[dose.medication.id]?.notificationsEnabled != false ||
              setups[dose.medication.id]?.fullScreenAlert == true)
          ReminderSlot(
            occurrenceKey: dose.occurrenceKey,
            planId: dose.plan.id,
            profileName: profile.displayName,
            medicationName: dose.medication.name,
            doseText: dose.plan.doseText,
            scheduledAt: dose.scheduledAt,
            status: dose.status,
            reminderNote: setups[dose.medication.id]?.reminderNote ?? '',
            fullScreenAlert: setups[dose.medication.id]?.fullScreenAlert == true,
          ),
      ]);
      tomorrowSlots.addAll([
        for (final dose in tomorrowDoses)
          if (setups[dose.medication.id]?.notificationsEnabled != false ||
              setups[dose.medication.id]?.fullScreenAlert == true)
          ReminderSlot(
            occurrenceKey: dose.occurrenceKey,
            planId: dose.plan.id,
            profileName: profile.displayName,
            medicationName: dose.medication.name,
            doseText: dose.plan.doseText,
            scheduledAt: dose.scheduledAt,
            status: dose.status,
            reminderNote: setups[dose.medication.id]?.reminderNote ?? '',
            fullScreenAlert: setups[dose.medication.id]?.fullScreenAlert == true,
          ),
      ]);
    }
    final jobs = _planner.plan(
      now: now,
      today: todaySlots,
      tomorrow: tomorrowSlots,
    );
    await notifications.replaceManaged(jobs);
    return jobs.length;
  }
}
