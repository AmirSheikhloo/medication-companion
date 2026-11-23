import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/app_database.dart';
import '../../inventory/data/inventory_repository.dart';
import '../domain/occurrence.dart';
import 'medication_course_repository.dart';

class DailyDose {
  const DailyDose({
    required this.medication,
    required this.plan,
    required this.occurrenceKey,
    required this.scheduledAt,
    required this.status,
    this.stockDebited = false,
  });

  final Medication medication;
  final MedicationPlanVersion plan;
  final String occurrenceKey;
  final DateTime scheduledAt;
  final String status;
  final bool stockDebited;
}

/// User-entered dose description for exactly one wall-clock time.
/// No medical dosage is inferred from other slots.
class DoseSlotInput {
  const DoseSlotInput({required this.doseText, required this.time});

  final String doseText;
  final TimeOfDayValue time;
}

/// Owns all offline medication mutations and append-only dose history.
/// All operations involving a medication verify its profile ownership.
class MedicationRepository {
  MedicationRepository(this.db);

  final AppDatabase db;
  final Uuid _uuid = Uuid();

  Future<List<Medication>> medicationsFor(String profileId,
      {bool archived = false}) =>
      (db.select(db.medications)
            ..where((t) =>
                t.profileId.equals(profileId) & t.archived.equals(archived))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  Future<String> addDailyMedication({
    required String profileId,
    required String name,
    required String doseText,
    required TimeOfDayValue time,
  }) =>
      addMedicationSchedule(
        profileId: profileId,
        name: name,
        slots: [DoseSlotInput(doseText: doseText, time: time)],
      );

  Future<String> addMedicationSchedule({
    required String profileId,
    required String name,
    required List<DoseSlotInput> slots,
  }) async {
    final cleanedName = _validateName(name);
    final validatedSlots = _validateSlots(slots);
    final medicationId = _uuid.v4();
    final now = DateTime.now().toUtc();
    await db.transaction(() async {
      final profile = await (db.select(db.profiles)
            ..where((t) => t.id.equals(profileId)))
          .getSingleOrNull();
      if (profile == null) throw StateError('پروفایل وجود ندارد.');
      await db.into(db.medications).insert(MedicationsCompanion.insert(
            id: medicationId,
            profileId: profileId,
            name: cleanedName,
            createdAt: now,
          ));
      await _appendPlan(
        medicationId: medicationId,
        version: 1,
        effectiveFrom: now,
        slots: validatedSlots,
      );
    });
    return medicationId;
  }

  /// Edits take effect at the next local midnight, keeping today's recorded
  /// occurrences intact. Re-editing on the same day supersedes the pending
  /// version for tomorrow without deleting earlier versions or dose events.
  Future<void> updateMedicationSchedule({
    required String profileId,
    required String medicationId,
    required String name,
    required List<DoseSlotInput> slots,
  }) async {
    final cleanedName = _validateName(name);
    final validatedSlots = _validateSlots(slots);
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1).toUtc();
    await db.transaction(() async {
      final medication = await _ownedMedication(profileId, medicationId);
      if (medication == null || medication.archived) {
        throw StateError('داروی فعال متعلق به این پروفایل پیدا نشد.');
      }
      final plans = await (db.select(db.medicationPlanVersions)
            ..where((t) => t.medicationId.equals(medicationId)))
          .get();
      if (plans.isEmpty) throw StateError('برنامه قبلی دارو پیدا نشد.');
      final nextVersion = plans
              .map((plan) => plan.version)
              .reduce((a, b) => a > b ? a : b) +
          1;
      await (db.update(db.medications)
            ..where((t) =>
                t.id.equals(medicationId) & t.profileId.equals(profileId)))
          .write(MedicationsCompanion(name: Value(cleanedName)));
      await _appendPlan(
        medicationId: medicationId,
        version: nextVersion,
        effectiveFrom: tomorrow,
        slots: validatedSlots,
      );
    });
  }

  /// Archive is reversible: no medication, plan, or dose event is deleted.
  Future<void> setArchived({
    required String profileId,
    required String medicationId,
    required bool archived,
  }) async {
    await db.transaction(() async {
      final medication = await _ownedMedication(profileId, medicationId);
      if (medication == null) {
        throw StateError('دارو متعلق به این پروفایل نیست.');
      }
      await (db.update(db.medications)
            ..where((t) =>
                t.id.equals(medicationId) & t.profileId.equals(profileId)))
          .write(MedicationsCompanion(archived: Value(archived)));
      if (archived && !medication.archived) {
        await db.into(db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: MedicationCourseRepository.endKey(profileId, medicationId),
            value: DateTime.now().toUtc().toIso8601String(),
          ),
        );
      }
    });
  }

  Future<Medication?> _ownedMedication(
      String profileId, String medicationId) =>
      (db.select(db.medications)
            ..where((t) =>
                t.id.equals(medicationId) & t.profileId.equals(profileId)))
          .getSingleOrNull();

  String _validateName(String name) {
    final cleaned = name.trim();
    if (cleaned.isEmpty || cleaned.length > 160) {
      throw ArgumentError('نام دارو باید بین 1 تا 160 نویسه باشد.');
    }
    return cleaned;
  }

  List<DoseSlotInput> _validateSlots(List<DoseSlotInput> slots) {
    if (slots.isEmpty || slots.length > 24 * 60) {
      throw ArgumentError('دست‌کم یک نوبت و حداکثر یک نوبت در هر دقیقه مجاز است.');
    }
    final clockKeys = <int>{};
    final validated = <DoseSlotInput>[];
    for (final slot in slots) {
      final dose = slot.doseText.trim();
      if (dose.isEmpty || dose.length > 120) {
        throw ArgumentError('شرح هر نوبت باید بین 1 تا 120 نویسه باشد.');
      }
      final hour = slot.time.hour;
      final minute = slot.time.minute;
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
        throw ArgumentError('زمان دارو معتبر نیست.');
      }
      if (!clockKeys.add(hour * 60 + minute)) {
        throw ArgumentError('یک ساعت تکراری برای یک دارو ثبت شده است.');
      }
      validated.add(DoseSlotInput(
        doseText: dose,
        time: TimeOfDayValue(hour, minute),
      ));
    }
    validated.sort((a, b) =>
        (a.time.hour * 60 + a.time.minute)
            .compareTo(b.time.hour * 60 + b.time.minute));
    return validated;
  }

  Future<void> _appendPlan({
    required String medicationId,
    required int version,
    required DateTime effectiveFrom,
    required List<DoseSlotInput> slots,
  }) async {
    // Rows with the same version are one immutable daily schedule.
    // Each slot has its own stable occurrence key via its unique plan ID.
    for (final slot in slots) {
      await db.into(db.medicationPlanVersions).insert(
            MedicationPlanVersionsCompanion.insert(
              id: _uuid.v4(),
              medicationId: medicationId,
              version: version,
              doseText: slot.doseText,
              hour: slot.time.hour,
              minute: slot.time.minute,
              effectiveFrom: effectiveFrom,
            ),
          );
    }
  }

  Future<List<DailyDose>> dosesForDay(String profileId, DateTime day) async {
    final meds = await medicationsFor(profileId);
    if (meds.isEmpty) return [];
    final ids = meds.map((m) => m.id).toList();
    final plans = await (db.select(db.medicationPlanVersions)
          ..where((t) => t.medicationId.isIn(ids)))
        .get();

    // First versions remain available for existing M1 test and historical
    // data, even when the queried local day predates first installation.
    // Later versions activate from the next local day after an edit.
    final endOfDay = DateTime(day.year, day.month, day.day + 1).toUtc();
    final chosenVersions = <String, int>{};
    for (final plan in plans) {
      if (plan.version != 1 && !plan.effectiveFrom.isBefore(endOfDay)) {
        continue;
      }
      final previous = chosenVersions[plan.medicationId] ?? 0;
      if (plan.version > previous) {
        chosenVersions[plan.medicationId] = plan.version;
      }
    }
    final byMedication = {for (final med in meds) med.id: med};
    final candidates = <DailyDose>[];
    for (final plan in plans) {
      if (chosenVersions[plan.medicationId] != plan.version) continue;
      final med = byMedication[plan.medicationId];
      if (med == null) continue;
      final scheduledAt =
          DateTime(day.year, day.month, day.day, plan.hour, plan.minute);
      candidates.add(DailyDose(
        medication: med,
        plan: plan,
        occurrenceKey: OccurrenceKey.forDailyPlan(plan.id, day),
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
    final movements = await (db.select(db.stockMovements)
          ..where((t) => t.occurrenceKey.isIn(keys)))
        .get();
    final reversed = {
      for (final movement in movements)
        if (movement.reversesMovementId != null)
          movement.reversesMovementId!,
    };
    final debitedKeys = {
      for (final movement in movements)
        if (movement.kind == 'taken' && !reversed.contains(movement.id))
          movement.occurrenceKey!,
    };
    final result = [
      for (final dose in candidates)
        DailyDose(
          medication: dose.medication,
          plan: dose.plan,
          occurrenceKey: dose.occurrenceKey,
          scheduledAt: dose.scheduledAt,
          status: byKey[dose.occurrenceKey] ?? 'pending',
          stockDebited: debitedKeys.contains(dose.occurrenceKey),
        ),
    ];
    result.sort((a, b) {
      final timeComparison = a.scheduledAt.compareTo(b.scheduledAt);
      return timeComparison != 0
          ? timeComparison
          : a.medication.id.compareTo(b.medication.id);
    });
    return result;
  }

  Future<List<DailyDose>> dosesForMedicationOnDay(
      String profileId, String medicationId, DateTime day) async {
    final all = await dosesForDay(profileId, day);
    return all.where((dose) => dose.medication.id == medicationId).toList();
  }

  /// An undo is a new event, never deletion of earlier dose history.
  /// A stale schedule cannot create a dose event after it has been replaced.
  Future<bool> recordDose({
    required DailyDose dose,
    required String profileId,
    required String action,
    String? stockPackageId,
    int? stockQuantityMilliunits,
  }) async {
    if (!{'taken', 'skipped', 'unknown', 'undo'}.contains(action)) {
      throw ArgumentError('وضعیت نوبت معتبر نیست.');
    }
    if ((stockPackageId == null) != (stockQuantityMilliunits == null) ||
        (action != 'taken' && stockPackageId != null)) {
      throw ArgumentError('برای کسر موجودی، بسته و مقدار واقعی را با هم وارد کنید.');
    }
    if (dose.medication.profileId != profileId) {
      throw StateError('این دارو متعلق به پروفایل فعال نیست.');
    }
    return db.transaction(() async {
      final medication = await _ownedMedication(profileId, dose.medication.id);
      final plan = await (db.select(db.medicationPlanVersions)
            ..where((t) => t.id.equals(dose.plan.id) &
                t.medicationId.equals(dose.medication.id)))
          .getSingleOrNull();
      if (medication == null || medication.archived || plan == null) {
        throw StateError('برنامه دارو تغییر کرده است؛ صفحه را تازه کنید.');
      }
      if (dose.occurrenceKey !=
          OccurrenceKey.forDailyPlan(plan.id, dose.scheduledAt)) {
        throw StateError('شناسه نوبت معتبر نیست.');
      }
      final currentSlots =
          await dosesForMedicationOnDay(profileId, medication.id, dose.scheduledAt);
      if (!currentSlots.any((d) => d.occurrenceKey == dose.occurrenceKey)) {
        throw StateError('برنامه دارو تغییر کرده است؛ صفحه را تازه کنید.');
      }
      final key = dose.occurrenceKey;
      final state = await (db.select(db.doseCurrentStates)
            ..where((t) => t.occurrenceKey.equals(key)))
          .getSingleOrNull();
      final before = state?.status ?? 'pending';
      if (action == 'undo') {
        if (before == 'pending') return false;
      } else if (before != 'pending') {
        return false;
      }
      // Medication state and inventory movement must either both commit
      // or both roll back. Older callers can explicitly record without debit.
      final inventory = InventoryRepository(db);
      if (action == 'taken' && stockPackageId != null) {
        await inventory.consumeForDoseInTransaction(
          profileId: profileId,
          medicationId: medication.id,
          packageId: stockPackageId,
          occurrenceKey: key,
          quantityMilliunits: stockQuantityMilliunits!,
        );
      } else if (action == 'undo' && before == 'taken') {
        await inventory.reverseDoseInTransaction(
          profileId: profileId,
          medicationId: medication.id,
          occurrenceKey: key,
        );
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

class TimeOfDayValue {
  const TimeOfDayValue(this.hour, this.minute);
  final int hour;
  final int minute;
}
