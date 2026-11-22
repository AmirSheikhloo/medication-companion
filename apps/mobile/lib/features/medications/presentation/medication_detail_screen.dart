import 'package:material_ui/material_ui.dart';

import '../../../core/calendar/persian_date.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_design.dart';
import '../../../core/ui/redesign_widgets.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/stock_quantity.dart';
import '../data/medication_repository.dart';
import '../data/medication_setup_repository.dart';
import 'medication_artwork.dart';
import 'medication_history_panel.dart';

/// A dedicated details page, rather than expanding the beta medicine card.
class MedicationDetailScreen extends StatelessWidget {
  const MedicationDetailScreen({super.key, required this.medication,
    required this.slots, required this.todaySlots, required this.stock,
    this.setup,
    required this.medicationRepository, required this.inventoryRepository,
    required this.pendingSchedule, required this.archived,
    required this.onEdit, required this.onStock,
    required this.onArchive, required this.onRestore,
    required this.onPackageAction});

  final Medication medication;
  final List<DailyDose> slots;
  final List<DailyDose> todaySlots;
  final StockSummary? stock;
  final MedicationSetup? setup;
  final MedicationRepository medicationRepository;
  final InventoryRepository inventoryRepository;
  final bool pendingSchedule;
  final bool archived;
  final VoidCallback onEdit;
  final VoidCallback onStock;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final void Function(PackageBalance balance, String action) onPackageAction;

  String _clock(DateTime date) => PersianDate.persianDigits(
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}');

  String _expiryLabel(PackageBalance balance) {
    final iso = balance.package.expiryIso;
    if (iso == null) return 'بدون تاریخ انقضا';
    final date = PersianDate.fromGregorian(StockQuantity.parseIso(iso));
    final prefix = balance.package.expiryPrecision == 'month'
        ? 'انقضا (ماه)'
        : 'انقضا';
    return PersianDate.persianDigits('$prefix: $date');
  }

  Widget _packageRow(PackageBalance balance, bool isSelected) {
    final expired = balance.expired;
    final color = balance.archived ? AppColors.muted : expired
        ? const Color(0xFFBB4356)
        : isSelected ? AppColors.primary : AppColors.muted;
    final fill = balance.archived ? const Color(0xFFF0F2F3) : expired
        ? const Color(0xFFFFF0F1)
        : isSelected ? const Color(0xFFE0F5F0) : const Color(0xFFF5F8F9);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(children: [
        Icon(expired ? Icons.warning_amber_rounded :
            isSelected ? Icons.check_circle_rounded : Icons.inventory_2_outlined,
          color: color, size: 22),
        const SizedBox(width: 9),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(balance.package.label, style: const TextStyle(
              color: AppColors.primaryDark, fontWeight: FontWeight.w800,
              fontSize: 14)),
            const SizedBox(height: 2),
            Text(PersianDate.persianDigits(
              '${StockQuantity.format(balance.balanceMilliunits)} ${balance.package.unit} باقی‌مانده'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(_expiryLabel(balance), style: TextStyle(
              color: expired ? color : AppColors.muted, fontSize: 11)),
            if (isSelected) const Text('بسته انتخاب‌شده برای مصرف',
              style: TextStyle(color: AppColors.primary, fontSize: 11,
                fontWeight: FontWeight.w700)),
            if (balance.archived) const Text('بایگانی‌شده؛ در مصرف و موجودی فعال استفاده نمی‌شود',
              style: TextStyle(color: AppColors.muted, fontSize: 11)),
            if (expired) const Text('منقضی‌شده؛ قابل انتخاب برای مصرف نیست',
              style: TextStyle(color: Color(0xFFBB4356), fontSize: 11,
                fontWeight: FontWeight.w700)),
          ],
        )),
        if (!archived) PopupMenuButton<String>(
          tooltip: 'گزینه‌های بسته',
          icon: const Icon(Icons.more_vert_rounded, color: AppColors.primaryDark),
          onSelected: (action) => onPackageAction(balance, action),
          itemBuilder: (_) => balance.archived ? const [
            PopupMenuItem(value: 'restore', child: Text('بازیابی بسته')),
            PopupMenuItem(value: 'delete', child: Text('حذف بستهٔ بدون سابقه')),
          ] : const [
            PopupMenuItem(value: 'edit', child: Text('ویرایش نام و انقضا')),
            PopupMenuItem(value: 'stock', child: Text('اصلاح موجودی و انتخاب بسته')),
            PopupMenuItem(value: 'archive', child: Text('بایگانی بسته')),
            PopupMenuItem(value: 'delete', child: Text('حذف بستهٔ بدون سابقه')),
          ],
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = stock?.selected;
    final statusColor = stock?.lowStock == true ? const Color(0xFFB16D06) : AppColors.primary;
    // FEFO ordering for visibility; changing the selected stock is an
    // explicit user action from the stock management screen.
    final packages = <PackageBalance>[...?stock?.packages];
    packages.sort((a, b) {
      if (a.archived != b.archived) return a.archived ? 1 : -1;
      final left = a.package.expiryIso;
      final right = b.package.expiryIso;
      if (left == null) return right == null ? 0 : 1;
      if (right == null) return -1;
      return left.compareTo(right);
    });
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('جزئیات دارو'),
        backgroundColor: AppColors.background),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 15, 16, 32), children: [
        Row(children: [
          MedicationArtwork(name: medication.name, setup: setup, size: 82),
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
        AppPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const AppSectionHeading('موجودی و بسته‌ها',
            icon: Icons.inventory_2_outlined),
          const SizedBox(height: 9),
          Text(selected == null
              ? 'هنوز بسته‌ای برای مصرف انتخاب نشده است.'
              : PersianDate.persianDigits(
                  '${StockQuantity.format(selected.balanceMilliunits)} '
                  '${selected.package.unit} در بستهٔ انتخاب‌شده'),
            style: TextStyle(color: statusColor, fontSize: 15,
              fontWeight: FontWeight.w900)),
          if (stock?.lowStock == true) ...[
            const SizedBox(height: 7),
            const AppStatusPill(text: 'هشدار کم‌موجودی',
              icon: Icons.warning_amber_rounded, color: Color(0xFFB16D06)),
          ],
          const SizedBox(height: 12),
          for (final pack in packages)
            _packageRow(pack, pack.package.id == stock?.selectedPackageId),
          if (packages.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('برای این دارو هنوز بسته‌ای ثبت نشده است.',
                style: TextStyle(color: AppColors.muted))),
          OutlinedButton.icon(onPressed: archived ? null : onStock,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('افزودن بسته یا مدیریت موجودی')),
        ])),
        const SizedBox(height: 12),
        if (setup?.reminderNote.isNotEmpty == true) ...[
          AppPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppSectionHeading('توضیح همراه یادآور',
                icon: Icons.notifications_active_outlined),
              const SizedBox(height: 8),
              Text(setup!.reminderNote),
            ])),
          const SizedBox(height: 12),
        ],
        MedicationHistoryPanel(medication: medication,
          medicationRepository: medicationRepository,
          inventoryRepository: inventoryRepository,
          stock: stock),
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
