import 'dart:convert';
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
  MedicationRepository(this.db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final DateTime Function() _clock;
  final Uuid _uuid = Uuid();

  String _hiddenKey(String profileId, String medicationId) =>
    'medication-hidden:v1:$profileId:$medicationId';

  Future<Set<String>> _hiddenIds(String profileId) async {
    final prefix = 'medication-hidden:v1:$profileId:';
    final rows = await (db.select(db.appSettings)
      ..where((t) => t.key.like('$prefix%'))).get();
    return rows.where((r) => r.value == 'true')
      .map((r) => r.key.substring(prefix.length)).toSet();
  }

  Future<List<Medication>> medicationsFor(String profileId,
      {bool archived = false, bool includeHidden = false}) async {
    final rows = await (db.select(db.medications)
      ..where((t) =>
        t.profileId.equals(profileId) & t.archived.equals(archived))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();
    if (includeHidden) return rows;
    final hidden = await _hiddenIds(profileId);
    return rows.where((m) => !hidden.contains(m.id)).toList();
  }

  Future<List<Medication>> hiddenMedicationsFor(String profileId) async {
    final hidden = await _hiddenIds(profileId);
    if (hidden.isEmpty) return [];
    return (db.select(db.medications)
      ..where((t) =>
        t.profileId.equals(profileId) & t.id.isIn(hidden.toList()))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();
  }

  /// "Delete from list" is reversible. Historical events and reports remain.
  Future<void> setHidden({
    required String profileId,
    required String medicationId,
    required bool hidden,
  }) async {
    await db.transaction(() async {
      final med = await _ownedMedication(profileId, medicationId);
      if (med == null) {
        throw StateError('این دارو متعلق به پروفایل فعال نیست.');
      }
      if (hidden) {
        if (!med.archived) {
          await setArchived(profileId: profileId,
            medicationId: medicationId, archived: true);
        }
        await db.into(db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: _hiddenKey(profileId, medicationId), value: 'true'));
      } else {
        await (db.delete(db.appSettings)
          ..where((t) => t.key.equals(
            _hiddenKey(profileId, medicationId)))).go();
      }
    });
  }

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
    final now = _clock().toUtc();
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

  /// Change only future, unrecorded occurrences today. Protected or changed
  /// past occurrences defer the complete edit to the following local day.
  /// Every plan row and every historical dose event remains immutable.
  Future<void> updateMedicationSchedule({
    required String profileId,
    required String medicationId,
    required String name,
    required List<DoseSlotInput> slots,
  }) async {
    final cleanedName = _validateName(name);
    final validatedSlots = _validateSlots(slots);
    final now = _clock().toLocal();
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
      final latestVersion = plans.map((p) => p.version)
        .reduce((a, b) => a > b ? a : b);
      final latest = plans.where((p) => p.version == latestVersion).toList();
      final nextByClock = {
        for (final slot in validatedSlots)
          slot.time.hour * 60 + slot.time.minute: slot.doseText,
      };
      final unchanged = latest.length == nextByClock.length &&
        latest.every((p) => nextByClock[p.hour * 60 + p.minute] == p.doseText);
      if (medication.name != cleanedName) {
        // Keep the actual old name and new name in a separate append-only log.
        await db.into(db.appSettings).insert(AppSettingsCompanion.insert(
          key: 'medication-name-audit:v1:$profileId:$medicationId:${_uuid.v4()}',
          value: jsonEncode({
            'from': medication.name, 'to': cleanedName,
            'at': now.toUtc().toIso8601String(),
          })));
        await (db.update(db.medications)
          ..where((t) => t.id.equals(medicationId) &
            t.profileId.equals(profileId)))
          .write(MedicationsCompanion(name: Value(cleanedName)));
      }
      if (unchanged) return;
      final today = await dosesForMedicationOnDay(profileId, medicationId, now);
      final past = {
        for (final dose in today)
          if (!dose.scheduledAt.isAfter(now))
            dose.plan.hour * 60 + dose.plan.minute: dose.plan.doseText,
      };
      final proposedPast = {
        for (final slot in validatedSlots)
          if (!DateTime(now.year, now.month, now.day,
              slot.time.hour, slot.time.minute).isAfter(now))
            slot.time.hour * 60 + slot.time.minute: slot.doseText,
      };
      final pastConflict = past.length != proposedPast.length ||
        past.entries.any((e) => proposedPast[e.key] != e.value);
      final futureKeys = today.where((d) => d.scheduledAt.isAfter(now))
        .map((d) => d.occurrenceKey).toList();
      // Even a reverted future event remains a protected historical record.
      final futureEvents = futureKeys.isEmpty ? <DoseEvent>[] :
        await (db.select(db.doseEvents)
          ..where((t) => t.profileId.equals(profileId) &
            t.medicationId.equals(medicationId) &
            t.occurrenceKey.isIn(futureKeys))..limit(1)).get();
      await _appendPlan(
        medicationId: medicationId,
        version: latestVersion + 1,
        effectiveFrom: pastConflict || futureEvents.isNotEmpty
          ? tomorrow : now.toUtc(),
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
      if (archived != medication.archived) {
        final lifecycleKey = 'medication-lifecycle:v1:$profileId:$medicationId';
        final previous = await (db.select(db.appSettings)
          ..where((t) => t.key.equals(lifecycleKey))).getSingleOrNull();
        final changes = previous == null ? <dynamic>[] :
          jsonDecode(previous.value) as List<dynamic>;
        changes.add({'archived': archived, 'at': _clock().toUtc().toIso8601String()});
        await db.into(db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: lifecycleKey, value: jsonEncode(changes)));
      }
      if (archived && !medication.archived) {
        await db.into(db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: MedicationCourseRepository.endKey(profileId, medicationId),
            value: _clock().toUtc().toIso8601String(),
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

    // A plan version is effective from a civil timestamp. For a same-day
    // edit retain the old occurrence IDs before that timestamp; after it use
    // the most recent eligible version. Version 1 remains readable for
    // historical compatibility with existing local data.
    final versions = <String, Map<int, DateTime>>{};
    for (final plan in plans) {
      versions.putIfAbsent(plan.medicationId, () => {})[plan.version] =
        plan.effectiveFrom;
    }
    final byMedication = {for (final med in meds) med.id: med};
    final dayStart = DateTime(day.year, day.month, day.day);
    // Legacy builds could create a recorded occurrence before the first plan
    // became effective. Preserve those records; never synthesize new ones.
    final earlyKeys = <String>{};
    for (final plan in plans.where((p) => p.version == 1)) {
      final localStart = plan.effectiveFrom.toLocal();
      final startMinute = DateTime(localStart.year, localStart.month,
        localStart.day, localStart.hour, localStart.minute);
      final scheduled = DateTime(day.year, day.month, day.day, plan.hour, plan.minute);
      if (scheduled.isBefore(startMinute)) {
        earlyKeys.add(OccurrenceKey.forDailyPlan(plan.id, dayStart));
      }
    }
    final recordedEarly = earlyKeys.isEmpty ? <String>{} :
      (await (db.select(db.doseEvents)
        ..where((t) => t.profileId.equals(profileId) &
          t.occurrenceKey.isIn(earlyKeys))).get()).map((e) => e.occurrenceKey).toSet();
    final lifecycle = <String, List<dynamic>>{};
    for (final med in meds) {
      final row = await (db.select(db.appSettings)
        ..where((t) => t.key.equals('medication-lifecycle:v1:$profileId:${med.id}')))
        .getSingleOrNull();
      if (row != null) { lifecycle[med.id] = jsonDecode(row.value) as List<dynamic>; }
    }
    final candidates = <DailyDose>[];
    for (final plan in plans) {
      final med = byMedication[plan.medicationId];
      if (med == null) continue;
      final scheduledAt =
          DateTime(day.year, day.month, day.day, plan.hour, plan.minute);
      var chosen = 0;
      for (final version in versions[plan.medicationId]!.entries) {
        if (version.key == 1 ||
            !version.value.isAfter(scheduledAt.toUtc())) {
          if (version.key > chosen) { chosen = version.key; }
        }
      }
      if (chosen != plan.version) continue;
      final occurrenceKey = OccurrenceKey.forDailyPlan(plan.id, dayStart);
      if (earlyKeys.contains(occurrenceKey) &&
          !recordedEarly.contains(occurrenceKey)) { continue; }
      var suspended = false;
      for (final change in lifecycle[med.id] ?? const []) {
        final at = DateTime.parse(change['at'] as String);
        if (!at.isAfter(scheduledAt.toUtc())) {
          suspended = change['archived'] as bool;
        }
      }
      if (suspended) { continue; }
      candidates.add(DailyDose(
        medication: med,
        plan: plan,
        occurrenceKey: occurrenceKey,
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
