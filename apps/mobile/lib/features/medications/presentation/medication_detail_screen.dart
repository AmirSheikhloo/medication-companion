import 'package:material_ui/material_ui.dart';

import '../../../core/calendar/persian_date.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_design.dart';
import '../../../core/ui/redesign_widgets.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/stock_quantity.dart';
import '../data/medication_repository.dart';

/// A dedicated details page, rather than expanding the beta medicine card.
class MedicationDetailScreen extends StatelessWidget {
  const MedicationDetailScreen({super.key, required this.medication,
    required this.slots, required this.todaySlots, required this.stock,
    required this.pendingSchedule, required this.archived,
    required this.onEdit, required this.onStock,
    required this.onArchive, required this.onRestore});

  final Medication medication;
  final List<DailyDose> slots;
  final List<DailyDose> todaySlots;
  final StockSummary? stock;
  final bool pendingSchedule;
  final bool archived;
  final VoidCallback onEdit;
  final VoidCallback onStock;
  final VoidCallback onArchive;
  final VoidCallback onRestore;

  String _clock(DateTime date) => PersianDate.persianDigits(
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}');

  @override
  Widget build(BuildContext context) {
    final selected = stock?.selected;
    final statusColor = stock?.lowStock == true ? const Color(0xFFB16D06) : AppColors.primary;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('جزئیات دارو'),
        backgroundColor: AppColors.background),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 15, 16, 32), children: [
        Row(children: [
          MedicineArtwork(seed: medication.name, size: 82),
          const SizedBox(width: 15),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(medication.name, style: const TextStyle(fontWeight: FontWeight.w900,
              fontSize: 23, color: AppColors.primaryDark)),
            const SizedBox(height: 5),
            AppStatusPill(text: archived ? 'بایگانی‌شده' : 'فعال',
              icon: archived ? Icons.archive_outlined : Icons.check, color: AppColors.primary),
          ])),
        ]),
        const SizedBox(height: 22),
        AppPanel(padding: const EdgeInsets.all(12), child: Column(children: [
          const AppSoftHeader(title: 'برنامه مصرف', icon: Icons.calendar_month_outlined),
          if (pendingSchedule) const Padding(padding: EdgeInsets.only(top: 8),
            child: Text('برنامه جدید — از فردا؛ نوبت‌های امروز تغییر نمی‌کنند.',
              style: TextStyle(fontSize: 11, color: AppColors.primary))),
          const SizedBox(height: 6),
          if (slots.isEmpty) const Padding(padding: EdgeInsets.all(13),
            child: Text('برای این روز نوبتی ثبت نشده است.')),
          for (var i = 0; i < slots.length; i++) ...[
            if (i != 0) const Divider(height: 1, color: AppColors.outline),
            Padding(padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(children: [
                Icon(slots[i].scheduledAt.hour >= 17 ? Icons.nightlight_outlined :
                  Icons.wb_sunny_outlined, size: 20, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(slots[i].scheduledAt.hour < 11 ? 'صبح' :
                  slots[i].scheduledAt.hour < 17 ? 'ظهر' : 'شب',
                  style: const TextStyle(fontWeight: FontWeight.bold))),
                AppStatusPill(text: _clock(slots[i].scheduledAt), color: AppColors.primary),
                const SizedBox(width: 9),
                Flexible(child: Text(PersianDate.persianDigits(slots[i].plan.doseText),
                  maxLines: 2, textAlign: TextAlign.end)),
              ])),
          ],
        ])),
        const SizedBox(height: 12),
        AppPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const AppSectionHeading('موجودی', icon: Icons.inventory_2_outlined),
          const SizedBox(height: 8),
          Text(selected == null ? 'هنوز بسته‌ای برای این دارو انتخاب نشده است.' :
            PersianDate.persianDigits('${StockQuantity.format(selected.balanceMilliunits)} '
              '${selected.package.unit} باقی‌مانده از بستهٔ «${selected.package.label}»'),
            style: TextStyle(color: statusColor, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (stock?.lowStock == true)
            const AppStatusPill(text: 'هشدار کم‌موجودی',
              icon: Icons.warning_amber_rounded, color: Color(0xFFB16D06)),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: archived ? null : onStock,
            icon: const Icon(Icons.add), label: const Text('مدیریت موجودی و بسته‌ها')),
        ])),
        const SizedBox(height: 12),
        AppPanel(child: Column(children: [
          const AppSectionHeading('سوابق مصرف امروز', icon: Icons.history),
          const SizedBox(height: 7),
          if (todaySlots.isEmpty)
            const Text('هنوز نوبت یا سابقه‌ای برای امروز وجود ندارد.'),
          for (var i = 0; i < todaySlots.length; i++) ...[
            if (i != 0) const Divider(height: 1),
            Padding(padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(children: [
                Icon(todaySlots[i].status == 'taken' ? Icons.check_circle :
                    Icons.schedule_outlined,
                  color: todaySlots[i].status == 'taken'
                    ? AppColors.success : AppColors.muted, size: 19),
                const SizedBox(width: 8),
                Expanded(child: Text(_clock(todaySlots[i].scheduledAt))),
                Text(switch (todaySlots[i].status) {
                  'taken' => 'مصرف ثبت شده',
                  'skipped' => 'مصرف نشده',
                  'unknown' => 'نامشخص',
                  _ => 'در انتظار ثبت',
                }),
              ])),
          ],
        ])),
        const SizedBox(height: 16),
        if (archived)
          AppGradientButton(label: 'بازیابی دارو', icon: Icons.restore,
            onPressed: onRestore)
        else ...[
          AppGradientButton(label: 'ویرایش دارو', icon: Icons.edit_outlined,
            onPressed: onEdit),
          const SizedBox(height: 9),
          OutlinedButton.icon(onPressed: onArchive,
            icon: const Icon(Icons.archive_outlined), label: const Text('بایگانی')),
        ],
      ]),
    );
  }
}
