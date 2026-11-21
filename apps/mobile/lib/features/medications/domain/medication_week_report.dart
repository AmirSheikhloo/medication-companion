import '../data/medication_repository.dart';

/// A log of user-entered statuses, not a medical adherence assessment.
class MedicationDaySummary {
  const MedicationDaySummary({
    required this.day,
    required this.taken,
    required this.skipped,
    required this.unknown,
    required this.pending,
  });

  final DateTime day;
  final int taken;
  final int skipped;
  final int unknown;
  final int pending;

  int get total => taken + skipped + unknown + pending;
  int get registered => taken + skipped + unknown;

  /// Never label unregistered doses as medically missed doses.
  double get takenShare => total == 0 ? 0 : taken / total;
}

class MedicationWeekReport {
  const MedicationWeekReport(this.days);

  final List<MedicationDaySummary> days;

  int get taken => days.fold(0, (s, d) => s + d.taken);
  int get skipped => days.fold(0, (s, d) => s + d.skipped);
  int get unknown => days.fold(0, (s, d) => s + d.unknown);
  int get pending => days.fold(0, (s, d) => s + d.pending);
  int get total => days.fold(0, (s, d) => s + d.total);
  int get registered => taken + skipped + unknown;
}

class MedicationWeekReportRepository {
  const MedicationWeekReportRepository(this.medications);

  final MedicationRepository medications;

  Future<MedicationWeekReport> forProfile({
    required String profileId,
    DateTime? endingOn,
  }) async {
    final now = endingOn ?? DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final summaries = <MedicationDaySummary>[];

    for (var offset = 6; offset >= 0; offset--) {
      final day = DateTime(end.year, end.month, end.day - offset);
      final entries = (await medications.dosesForDay(profileId, day))
          // The legacy daily API can show first schedules before creation;
          // past days must not be inflated by newly added medications.
          .where((dose) {
        final created = dose.medication.createdAt.toLocal();
        final createdDay = DateTime(created.year, created.month, created.day);
        return !createdDay.isAfter(day);
      }).toList();
      summaries.add(MedicationDaySummary(
        day: day,
        taken: entries.where((d) => d.status == 'taken').length,
        skipped: entries.where((d) => d.status == 'skipped').length,
        unknown: entries.where((d) => d.status == 'unknown').length,
        pending: entries.where((d) => d.status == 'pending').length,
      ));
    }

    return MedicationWeekReport(summaries);
  }
}
