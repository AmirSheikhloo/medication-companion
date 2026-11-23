import 'package:drift/drift.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/calendar/persian_date.dart';
import 'medication_setup_repository.dart';

/// One medication DB row is one treatment course. Never merge dose events,
/// inventory ledgers, or plan-version IDs between courses, even for identical
/// names. Only a read-only, profile-scoped timeline groups exact names.
class MedicationCourseReport {
  const MedicationCourseReport({
    required this.medication,
    required this.started,
    required this.ended,
    required this.taken,
    required this.skipped,
    required this.unknown,
    required this.stockDebitedMilliunits,
    required this.recordedDoses,
    this.tabletsPerStrip,
  });

  final Medication medication;
  final DateTime started;
  final DateTime? ended;
  final int taken;
  final int skipped;
  final int unknown;
  final int recordedDoses;
  /// From signed stock ledger. Does NOT include "taken without deduction".
  final int stockDebitedMilliunits;
  final int? tabletsPerStrip;

  int get days => ((ended ?? DateTime.now()).difference(
    DateTime(started.year, started.month, started.day)).inDays + 1).clamp(1, 999999);
}

class MedicationCourseRepository {
  const MedicationCourseRepository(this.db);
  final AppDatabase db;

  static String normalizeName(String name) => PersianDate.latinDigits(name)
      .trim().toLowerCase()
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll(RegExp(r'\s+'), ' ');

  static String endKey(String profileId, String medicationId) =>
    'medication-course-ended:v1:$profileId:$medicationId';

  Future<DateTime?> endedAt(String profileId, String medicationId) async {
    final row = await (db.select(db.appSettings)
      ..where((t) => t.key.equals(endKey(profileId, medicationId))))
      .getSingleOrNull();
    final text = row?.value;
    return text == null ? null : DateTime.tryParse(text)?.toLocal();
  }

  /// Exact strength/name matches only; a fuzzy suggestion must never create a
  /// clinical identity link (e.g. 250 mg versus 500 mg).
  Future<List<Medication>> sameNameCourses(Medication selected) async {
    final rows = await (db.select(db.medications)
      ..where((t) => t.profileId.equals(selected.profileId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();
    final normalized = normalizeName(selected.name);
    return rows.where((m) => normalizeName(m.name) == normalized).toList();
  }

  Future<MedicationCourseReport> report(Medication med) async {
    final ends = await endedAt(med.profileId, med.id);
    final events = await (db.select(db.doseEvents)
      ..where((t) => t.profileId.equals(med.profileId) &
        t.medicationId.equals(med.id))
      ..orderBy([(t) => OrderingTerm.asc(t.recordedAt)]))
      .get();
    final state = <String, String>{};
    for (final event in events) {
      if (event.action == 'undo') {
        state.remove(event.occurrenceKey);
      } else {
        state[event.occurrenceKey] = event.action;
      }
    }
    final movements = await (db.select(db.stockMovements)
      ..where((t) => t.profileId.equals(med.profileId) &
        t.medicationId.equals(med.id))).get();
    var deducted = 0;
    for (final entry in movements) {
      if (entry.kind == 'taken' || entry.kind == 'undo') {
        deducted -= entry.deltaMilliunits;
      }
    }
    final setup = await MedicationSetupRepository(db).read(
      med.profileId, med.id);
    return MedicationCourseReport(
      medication: med,
      started: med.createdAt.toLocal(),
      ended: med.archived ? ends : null,
      taken: state.values.where((v) => v == 'taken').length,
      skipped: state.values.where((v) => v == 'skipped').length,
      unknown: state.values.where((v) => v == 'unknown').length,
      stockDebitedMilliunits: deducted < 0 ? 0 : deducted,
      recordedDoses: state.length,
      tabletsPerStrip: setup.tabletsPerStrip,
    );
  }
}
