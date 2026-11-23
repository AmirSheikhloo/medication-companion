import 'package:material_ui/material_ui.dart';

import '../../../core/calendar/persian_date.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_design.dart';
import '../../inventory/domain/stock_quantity.dart';
import '../data/medication_course_repository.dart';

/// A longitudinal read-only view of separate courses with the exact same
/// normalized name and strength. Never combines their records in storage.
class MedicationCourseTimeline extends StatefulWidget {
  const MedicationCourseTimeline({super.key, required this.medication,
    required this.repository, this.onOpenCourse});

  final Medication medication;
  final MedicationCourseRepository repository;
  final ValueChanged<Medication>? onOpenCourse;

  @override
  State<MedicationCourseTimeline> createState() =>
      _MedicationCourseTimelineState();
}

class _MedicationCourseTimelineState extends State<MedicationCourseTimeline> {
  late Future<List<MedicationCourseReport>> _reports;

  @override
  void initState() {
    super.initState();
    _reports = _fetch();
  }

  Future<List<MedicationCourseReport>> _fetch() async {
    final meds = await widget.repository.sameNameCourses(widget.medication);
    final values = <MedicationCourseReport>[];
    for (final med in meds) {
      values.add(await widget.repository.report(med));
    }
    return values;
  }

  Widget _metric(String label, String value, IconData icon) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 7),
      decoration: BoxDecoration(
        color: AppColors.mint,
        borderRadius: BorderRadius.circular(13)),
      child: Column(children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(height: 5),
        Text(value, textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16, color: AppColors.primaryDark,
            fontWeight: FontWeight.w900)),
        Text(label, maxLines: 2, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      ]),
    ),
  );

  Widget _course(MedicationCourseReport report, int index) {
    final current = report.medication.id == widget.medication.id;
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: current ? const Color(0xFFE8F8F4) : Colors.white,
        border: Border.all(color: current
          ? const Color(0xFF8CDBCB) : AppColors.outline),
        borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(current ? 'این دورهٔ مصرف' :
              'دورهٔ مصرف ${index + 1}',
            style: const TextStyle(
              color: AppColors.primaryDark, fontWeight: FontWeight.w900))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: report.medication.archived
                ? const Color(0xFFFFE6BE) : const Color(0xFFD3F2E8),
              borderRadius: BorderRadius.circular(20)),
            child: Text(report.medication.archived ? 'پایان‌یافته' : 'فعال',
              style: TextStyle(
                color: report.medication.archived
                  ? const Color(0xFF815519) : AppColors.primaryDark,
                fontWeight: FontWeight.w800, fontSize: 11)),
          ),
        ]),
        const SizedBox(height: 8),
        Text('از ${persianDateLabel(report.started)} تا '
            '${report.ended == null ? 'اکنون / تاریخ پایان نامشخص' : persianDateLabel(report.ended!)}',
          style: const TextStyle(color: AppColors.ink,
            fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(children: [
          _metric('روز از شروع', '${report.days}', Icons.date_range_outlined),
          const SizedBox(width: 7),
          _metric('نوبت مصرف‌شده', '${report.taken}',
            Icons.check_circle_outline),
          const SizedBox(width: 7),
          _metric('مصرف‌نشده', '${report.skipped}',
            Icons.remove_circle_outline),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.inventory_2_outlined,
            color: AppColors.primary, size: 19),
          const SizedBox(width: 7),
          Expanded(child: Text(
            'کسر ثبت‌شده از موجودی: '
            '${StockQuantity.format(report.stockDebitedMilliunits)} '
            '${report.medication.unit}',
            style: const TextStyle(color: AppColors.primaryDark,
              fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 5),
        const Text('این مقدار فقط کسرهای واقعی موجودی را شامل می‌شود؛ '
          'مصرف‌های ثبت‌شده بدون کسر، در این عدد محاسبه نمی‌شوند.',
          style: TextStyle(color: AppColors.muted, fontSize: 11)),
        if (report.unknown > 0) ...[
          const SizedBox(height: 5),
          Text('نوبت‌های نامطمئن: ${report.unknown}',
            style: const TextStyle(color: AppColors.muted)),
        ],
        if (!current && widget.onOpenCourse != null) ...[
          const SizedBox(height: 9),
          FilledButton.tonalIcon(
            onPressed: () => widget.onOpenCourse!(report.medication),
            icon: const Icon(Icons.history_outlined),
            label: const Text('مشاهدهٔ سوابق این دوره'),
          ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) =>
    FutureBuilder<List<MedicationCourseReport>>(
      future: _reports,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('گزارش دوره‌های مصرف در دسترس نیست.');
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final courses = snapshot.requireData;
        if (courses.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('پرونده و دوره‌های مصرف',
            style: TextStyle(fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppColors.primaryDark)),
          const SizedBox(height: 5),
          Text('برای این نام دقیق ${courses.length} دوره ثبت شده؛ '
            'سوابق هر دوره مستقل است.',
            style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          for (var i = 0; i < courses.length; i++)
            _course(courses[i], courses.length - i - 1),
        ]);
      },
    );
}
