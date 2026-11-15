import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../domain/occurrence.dart';
import '../../../core/storage/app_database.dart';

class DailyDose {
  const DailyDose({
    required this.medication,
    required this.plan,
    required this.occurrenceKey,
    required this.scheduledAt,
    required this.status,
  });

  final Medication medication;
  final MedicationPlanVersion plan;
  final String occurrenceKey;
  final DateTime scheduledAt;
  final String status;
}

/// All reads/writes remain local to the device. This layer alone owns the
/// idempotent dose transaction; widgets must not write tables directly.
class MedicationRepository {
  MedicationRepository(this.db);

  final AppDatabase db;
  final Uuid _uuid = Uuid();

  Future<List<Medication>> medicationsFor(String profileId) =>
      (db.select(db.medications)
            ..where((t) =>
                t.profileId.equals(profileId) & t.archived.equals(false))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  Future<String> addDailyMedication({
    required String profileId,
    required String name,
    required String doseText,
    required TimeOfDayValue time,
  }) async {
    final cleanedName = name.trim();
    final cleanedDose = doseText.trim();
    if (cleanedName.isEmpty || cleanedName.length > 160) {
      throw ArgumentError('نام دارو باید بین ۱ تا ۱۶۰ نویسه باشد.');
    }
    if (cleanedDose.isEmpty || cleanedDose.length > 120) {
      throw ArgumentError('شرح مصرف باید بین ۱ تا ۱۲۰ نویسه باشد.');
    }
    if (time.hour < 0 || time.hour > 23 ||
        time.minute < 0 || time.minute > 59) {
      throw ArgumentError('زمان دارو معتبر نیست.');
    }
    final existingProfile = await (db.select(db.profiles)
          ..where((t) => t.id.equals(profileId)))
        .getSingleOrNull();
    if (existingProfile == null) throw StateError('پروفایل وجود ندارد.');

    final medicationId = _uuid.v4();
    final planId = _uuid.v4();
    final now = DateTime.now().toUtc();
    await db.transaction(() async {
      await db.into(db.medications).insert(MedicationsCompanion.insert(
            id: medicationId,
            profileId: profileId,
            name: cleanedName,
            createdAt: now,
          ));
      await db.into(db.medicationPlanVersions).insert(
            MedicationPlanVersionsCompanion.insert(
              id: planId,
              medicationId: medicationId,
              version: 1,
              doseText: cleanedDose,
              hour: time.hour,
              minute: time.minute,
              effectiveFrom: now,
            ),
          );
    });
    return medicationId;
  }

  Future<List<DailyDose>> dosesForDay(String profileId, DateTime day) async {
    final meds = await medicationsFor(profileId);
    if (meds.isEmpty) return [];
    final ids = meds.map((m) => m.id).toList();
    final plans = await (db.select(db.medicationPlanVersions)
          ..where((t) => t.medicationId.isIn(ids))
          ..orderBy([(t) => OrderingTerm.desc(t.version)]))
        .get();
    final newestByMedication = <String, MedicationPlanVersion>{};
    for (final plan in plans) {
      newestByMedication.putIfAbsent(plan.medicationId, () => plan);
    }
    final candidates = <DailyDose>[];
    for (final medication in meds) {
      final plan = newestByMedication[medication.id];
      if (plan == null) continue;
      final scheduledAt = DateTime(
        day.year, day.month, day.day, plan.hour, plan.minute,
      );
      final key = OccurrenceKey.forDailyPlan(plan.id, day);
      candidates.add(DailyDose(
        medication: medication,
        plan: plan,
        occurrenceKey: key,
        scheduledAt: scheduledAt,
        status: 'pending',
      ));
    }
    if (candidates.isEmpty) return [];
    final keys = candidates.map((e) => e.occurrenceKey).toList();
    final states = await (db.select(db.doseCurrentStates)
          ..where((t) => t.occurrenceKey.isIn(keys)))
        .get();
    final byKey = {for (final s in states) s.occurrenceKey: s.status};
    final result = [
      for (final dose in candidates)
        DailyDose(
          medication: dose.medication,
          plan: dose.plan,
          occurrenceKey: dose.occurrenceKey,
          scheduledAt: dose.scheduledAt,
          status: byKey[dose.occurrenceKey] ?? 'pending',
        ),
    ];
    result.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return result;
  }

  /// Returns true only if an effective status transition was written.
  /// An undo is a *new* event, never deletion of earlier dose history.
  Future<bool> recordDose({
    required DailyDose dose,
    required String profileId,
    required String action,
  }) async {
    if (!{'taken', 'skipped', 'unknown', 'undo'}.contains(action)) {
      throw ArgumentError('وضعیت نوبت معتبر نیست.');
    }
    if (dose.medication.profileId != profileId) {
      throw StateError('این دارو متعلق به پروفایل فعال نیست.');
    }
    return db.transaction(() async {
      final medication = await (db.select(db.medications)
            ..where((t) => t.id.equals(dose.medication.id) &
                t.profileId.equals(profileId) &
                t.archived.equals(false)))
          .getSingleOrNull();
      final plan = await (db.select(db.medicationPlanVersions)
            ..where((t) => t.id.equals(dose.plan.id) &
                t.medicationId.equals(dose.medication.id)))
          .getSingleOrNull();
      if (medication == null || plan == null) {
        throw StateError('برنامه دارو تغییر کرده است؛ صفحه را تازه کنید.');
      }
      if (dose.occurrenceKey !=
          OccurrenceKey.forDailyPlan(plan.id, dose.scheduledAt)) {
        throw StateError('شناسه نوبت معتبر نیست.');
      }
      final key = dose.occurrenceKey;
      final state = await (db.select(db.doseCurrentStates)
            ..where((t) => t.occurrenceKey.equals(key)))
          .getSingleOrNull();
      final before = state?.status ?? 'pending';
      if (action == 'undo') {
        if (before == 'pending') return false;
      } else if (before != 'pending') {
        // To change an earlier answer, first append an explicit undo event.
        return false;
      }
      final now = DateTime.now().toUtc();
      await db.into(db.doseEvents).insert(DoseEventsCompanion.insert(
            id: _uuid.v4(),
            occurrenceKey: key,
            profileId: profileId,
            medicationId: medication.id,
            action: action,
            recordedAt: now,
          ));
      await db.into(db.doseCurrentStates).insertOnConflictUpdate(
            DoseCurrentStatesCompanion.insert(
              occurrenceKey: key,
              status: action == 'undo' ? 'pending' : action,
              updatedAt: now,
            ),
          );
      return true;
    });
  }
}

/// Presentation-independent representation of a locally selected wall-clock
/// daily reminder. Actual OS notification scheduling is introduced in M2.
class TimeOfDayValue {
  const TimeOfDayValue(this.hour, this.minute);
  final int hour;
  final int minute;
}
