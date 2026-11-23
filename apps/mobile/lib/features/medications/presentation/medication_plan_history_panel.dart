import 'package:drift/drift.dart' hide Column;
import 'package:material_ui/material_ui.dart';

import '../../../core/calendar/persian_date.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_design.dart';

/// Versioned, read-only schedule audit. Removed clock times from a newer
/// schedule remain in their older versions and historical dose events.
class MedicationPlanHistoryPanel extends StatefulWidget {
  const MedicationPlanHistoryPanel({
    super.key, required this.medication, required this.db});
  final Medication medication;
  final AppDatabase db;

  @override
  State<MedicationPlanHistoryPanel> createState() =>
      _MedicationPlanHistoryPanelState();
}

class _MedicationPlanHistoryPanelState
    extends State<MedicationPlanHistoryPanel> {
  late Future<List<MedicationPlanVersion>> _history;

  @override
  void initState() {
    super.initState();
    _history = (widget.db.select(widget.db.medicationPlanVersions)
      ..where((t) => t.medicationId.equals(widget.medication.id))
      ..orderBy([
        (t) => OrderingTerm.desc(t.version),
        (t) => OrderingTerm.asc(t.hour),
        (t) => OrderingTerm.asc(t.minute),
      ])).get();
  }

  @override
  Widget build(BuildContext context) =>
    FutureBuilder<List<MedicationPlanVersion>>(
      future: _history,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final history = snapshot.requireData;
        final versions = <int, List<MedicationPlanVersion>>{};
        for (final plan in history) {
          versions.putIfAbsent(plan.version, () => []).add(plan);
        }
        if (versions.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('تاریخچهٔ تغییر برنامه',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900,
              color: AppColors.primaryDark)),
          const SizedBox(height: 5),
          const Text('ساعت‌ها و مقدارهای دوره‌های قبلی حذف نمی‌شوند.',
            style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 8),
          for (final entry in versions.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                initiallyExpanded: entry.key == versions.keys.first,
                backgroundColor: AppColors.lightMint,
                collapsedBackgroundColor: AppColors.mint,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
                collapsedShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
                title: Text('برنامهٔ نسخه ${entry.key}',
                  style: const TextStyle(color: AppColors.primaryDark,
                    fontWeight: FontWeight.w800)),
                subtitle: Text('از ${persianDateLabel(entry.value.first.effectiveFrom)}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                children: [
                  for (final plan in entry.value)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                      child: Row(children: [
                        const Icon(Icons.access_time,
                          size: 18, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text(
                          '${plan.hour.toString().padLeft(2,'0')}:'
                          '${plan.minute.toString().padLeft(2,'0')}',
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(PersianDate.displayDigits(plan.doseText),
                          textAlign: TextAlign.end)),
                      ]),
                    ),
                ],
              ),
            ),
        ]);
      },
    );
}
