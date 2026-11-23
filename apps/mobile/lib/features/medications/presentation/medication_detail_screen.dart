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
import 'medication_package_editor_screen.dart';
import 'medication_course_timeline.dart';
import 'medication_plan_history_panel.dart';
import '../data/medication_course_repository.dart';
import '../../../core/ui/medication_controls.dart';

/// A dedicated details page, rather than expanding the beta medicine card.
class MedicationDetailScreen extends StatefulWidget {
  const MedicationDetailScreen({super.key, required this.medication,
    required this.slots, required this.todaySlots, required this.stock,
    this.setup,
    required this.medicationRepository, required this.inventoryRepository,
    required this.pendingSchedule, required this.archived,
    required this.onEdit, required this.onStock,
    required this.onArchive, required this.onRestore,
    required this.onPackageAction, this.onOpenCourse,
    this.hidden = false, this.onHide, this.onUnhide});

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
  final ValueChanged<Medication>? onOpenCourse;
  final bool hidden;
  final VoidCallback? onHide;
  final VoidCallback? onUnhide;

  @override
  State<MedicationDetailScreen> createState() =>
      _MedicationDetailScreenState();
}

class _MedicationDetailScreenState extends State<MedicationDetailScreen> {
  StockSummary? _reloadedStock;
  Medication get medication => widget.medication;
  List<DailyDose> get slots => widget.slots;
  StockSummary? get stock => _reloadedStock ?? widget.stock;
  MedicationSetup? get setup => widget.setup;
  bool get archived => widget.archived;
  bool get hidden => widget.hidden;
  InventoryRepository get inventoryRepository => widget.inventoryRepository;
  MedicationRepository get medicationRepository => widget.medicationRepository;
  bool get pendingSchedule => widget.pendingSchedule;
  VoidCallback get onEdit => widget.onEdit;
  VoidCallback get onArchive => widget.onArchive;
  VoidCallback get onRestore => widget.onRestore;

  Future<void> _openPackage(PackageBalance? package) async {
    final summary = stock;
    final result = await Navigator.of(context).push<bool>(
      medicationPageRoute(context, MedicationPackageEditorScreen(
        repository: inventoryRepository,
        profileId: medication.profileId,
        medicationId: medication.id,
        packageNumber: (summary?.packages.length ?? 0) + 1,
        unit: package?.package.unit ??
            summary?.selected?.package.unit ?? medication.unit,
        existing: package,
        selected: package == null ? summary?.selectedPackageId == null :
            package.package.id == summary?.selectedPackageId,
      )));
    if (!mounted || result != true) return;
    final latest = await inventoryRepository.summary(
      medication.profileId, medication.id);
    if (mounted) setState(() => _reloadedStock = latest);
  }

  Future<void> _selectPackage(PackageBalance balance) async {
    if (balance.archived || balance.expired ||
        balance.balanceMilliunits <= 0) return;
    try {
      await inventoryRepository.selectPackage(
        profileId: medication.profileId,
        medicationId: medication.id,
        packageId: balance.package.id);
      final fresh = await inventoryRepository.summary(
        medication.profileId, medication.id);
      if (mounted) setState(() => _reloadedStock = fresh);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('این بسته قابل انتخاب نیست؛ موجودی یا تاریخ انقضا را بررسی کن.')));
    }
  }

  void _openPlanHistory() {
    Navigator.of(context).push(medicationPageRoute<void>(context,
      Scaffold(
        appBar: AppBar(title: const Text('تاریخچه تغییر برنامه')),
        body: ListView(padding: const EdgeInsets.all(16),
          children: [
            AppPanel(child: MedicationPlanHistoryPanel(
              medication: medication, db: medicationRepository.db)),
          ]),
      )));
  }

  void _openCourseHistory() {
    Navigator.of(context).push(medicationPageRoute<void>(context,
      Scaffold(
        appBar: AppBar(title: const Text('پرونده و دوره‌های مصرف')),
        body: ListView(padding: const EdgeInsets.all(16),
          children: [
            AppPanel(child: MedicationCourseTimeline(
              medication: medication,
              repository: MedicationCourseRepository(medicationRepository.db),
              onOpenCourse: _openRelatedCourse)),
          ]),
      )));
  }

  Future<void> _openRelatedCourse(Medication related) async {
    final relatedStock = await inventoryRepository.summary(
      related.profileId, related.id);
    if (!mounted) return;
    Navigator.of(context).push(medicationPageRoute<void>(context,
      Scaffold(
        appBar: AppBar(title: const Text('سوابق دوره مصرف')),
        body: ListView(padding: const EdgeInsets.all(16),
          children: [
            Padding(padding: const EdgeInsets.only(bottom: 12),
              child: Text(PersianDate.displayDigits(related.name),
                style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w800))),
            MedicationHistoryPanel(
              medication: related,
              medicationRepository: medicationRepository,
              inventoryRepository: inventoryRepository,
              stock: relatedStock),
          ]),
      )));
  }

  String _clock(DateTime date) => PersianDate.displayDigits(
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}');

  String _expiryLabel(PackageBalance balance) {
    final iso = balance.package.expiryIso;
    if (iso == null) return 'بدون تاریخ انقضا';
    final date = PersianDate.fromGregorian(StockQuantity.parseIso(iso));
    final prefix = balance.package.expiryPrecision == 'month'
        ? 'انقضا (ماه)'
        : 'انقضا';
    return PersianDate.displayDigits('$prefix: $date');
  }

  Widget _packageRow(PackageBalance balance, bool isSelected) {
    final expired = balance.expired;
    final color = balance.archived ? AppColors.muted : expired
        ? const Color(0xFFBB4356)
        : isSelected ? AppColors.primary : AppColors.muted;
    final fill = balance.archived ? const Color(0xFFF0F2F3) : expired
        ? const Color(0xFFFFF0F1)
        : isSelected ? const Color(0xFFE0F5F0) : const Color(0xFFF5F8F9);
    return InkWell(onTap: () => _openPackage(balance),
      borderRadius: BorderRadius.circular(15),
      child: Container(
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
            Text(PersianDate.displayDigits(balance.package.label), style: const TextStyle(
              color: AppColors.primaryDark, fontWeight: FontWeight.w800,
              fontSize: 14)),
            const SizedBox(height: 2),
            Text(PersianDate.displayDigits(
              '${StockQuantity.format(balance.balanceMilliunits)} ${balance.package.unit} باقی‌مانده'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(_expiryLabel(balance), style: TextStyle(
              color: expired ? color : AppColors.muted, fontSize: 11)),
            if (isSelected) const Align(
              alignment: Alignment.centerRight,
              child: AppStatusPill(text: 'منتخب', icon: Icons.check_rounded,
                color: AppColors.primary, fontSize: 10)),
            if (balance.balanceMilliunits <= 0 && !balance.archived)
              const Text('موجودی تمام شده',
                style: TextStyle(color: Color(0xFFB04A38),
                  fontWeight: FontWeight.w800, fontSize: 11)),
            if (balance.archived) const Text('بایگانی‌شده؛ در مصرف و موجودی فعال استفاده نمی‌شود',
              style: TextStyle(color: AppColors.muted, fontSize: 11)),
            if (expired) const Text('منقضی‌شده؛ قابل انتخاب برای مصرف نیست',
              style: TextStyle(color: Color(0xFFBB4356), fontSize: 11,
                fontWeight: FontWeight.w700)),
          ],
        )),
        if (!isSelected && !balance.archived && !expired &&
            balance.balanceMilliunits > 0)
          IconButton(
            key: Key('select-package-${balance.package.id}'),
            tooltip: 'انتخاب برای مصرف',
            onPressed: () => _selectPackage(balance),
            icon: const Icon(Icons.radio_button_unchecked_rounded,
              size: 22, color: AppColors.primary))
        else
          Icon(isSelected ? Icons.check_circle_rounded :
            Icons.chevron_left_rounded,
            color: isSelected ? AppColors.primary : AppColors.muted,
            size: 21),
      ]),
    ));
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
        backgroundColor: AppColors.background,
        actions: [
          PopupMenuButton<String>(
            key: const Key('medication-detail-actions'),
            tooltip: 'مدیریت دارو',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (action) {
              if (action == 'edit') onEdit();
              if (action == 'finish') onArchive();
              if (action == 'restore') onRestore();
              if (action == 'hide') widget.onHide?.call();
              if (action == 'unhide') widget.onUnhide?.call();
            },
            itemBuilder: (_) => [
              if (!hidden && !archived)
                const PopupMenuItem(value: 'edit',
                  child: Text('ویرایش دارو')),
              if (!hidden && !archived)
                const PopupMenuItem(value: 'finish',
                  child: Text('پایان دوره مصرف')),
              if (archived && !hidden)
                const PopupMenuItem(value: 'restore',
                  child: Text('شروع دوباره دوره')),
              if (hidden)
                const PopupMenuItem(value: 'unhide',
                  child: Text('بازگرداندن به فهرست'))
              else
                const PopupMenuItem(value: 'hide',
                  child: Text('حذف دارو از فهرست')),
            ],
          ),
        ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 15, 16, 32), children: [
        Row(children: [
          MedicationArtwork(name: medication.name, setup: setup, size: 82),
          const SizedBox(width: 15),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(PersianDate.displayDigits(medication.name), style: const TextStyle(fontWeight: FontWeight.w900,
              fontSize: 23, color: AppColors.primaryDark)),
            const SizedBox(height: 5),
            AppStatusPill(text: hidden ? 'حذف‌شده از فهرست' : archived ? 'پایان مصرف' : 'فعال',
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
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(slots[i].scheduledAt.hour < 11 ? 'صبح' :
                      slots[i].scheduledAt.hour < 16 ? 'ظهر' :
                      slots[i].scheduledAt.hour < 19 ? 'عصر' : 'شب',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('ساعت: ${_clock(slots[i].scheduledAt)}',
                      style: const TextStyle(fontSize: 12,
                        color: AppColors.muted)),
                    Text('مقدار: ${PersianDate.displayDigits(slots[i].plan.doseText)}',
                      style: const TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w700)),
                  ],
                )),
              ])),
          ],
        ])),
        const SizedBox(height: 12),
        AppPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const AppSoftHeader(title: 'موجودی و بسته‌ها',
            icon: Icons.inventory_2_outlined),
          const SizedBox(height: 9),
          Text(selected == null
              ? 'هنوز بسته‌ای برای مصرف انتخاب نشده است.'
              : PersianDate.displayDigits(
                  '${StockQuantity.format(selected.balanceMilliunits)} '
                  '${selected.package.unit} در بستهٔ انتخاب‌شده'),
            style: TextStyle(color: statusColor, fontSize: 15,
              fontWeight: FontWeight.w900)),
          if (selected != null && selected.balanceMilliunits <= 0) ...[
            const SizedBox(height: 8),
            const AppStatusPill(text: 'موجودی این بسته تمام شده',
              icon: Icons.inventory_2_outlined,
              color: Color(0xFFB35A2C)),
          ],
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
          OutlinedButton.icon(onPressed: archived ? null : () => _openPackage(null),
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('افزودن بسته جدید')),
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
        AppPanel(child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const AppSoftHeader(title: 'سوابق مصرف',
              icon: Icons.history_rounded),
            const SizedBox(height: 11),
            MedicationHistoryPanel(medication: medication,
              medicationRepository: medicationRepository,
              inventoryRepository: inventoryRepository,
              stock: stock),
          ])),
        const SizedBox(height: 12),
        AppPanel(child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const AppSoftHeader(title: 'پرونده و تغییرات',
              icon: Icons.folder_copy_outlined),
            const SizedBox(height: 11),
            OutlinedButton.icon(
              onPressed: _openPlanHistory,
              icon: const Icon(Icons.history_toggle_off_rounded),
              label: const Text('تاریخچه تغییر برنامه')),
            const SizedBox(height: 9),
            OutlinedButton.icon(
              onPressed: _openCourseHistory,
              icon: const Icon(Icons.medical_information_outlined),
              label: const Text('پرونده و دوره‌های مصرف')),
          ])),
        if (hidden)
          Padding(padding: const EdgeInsets.only(top: 14),
            child: FilledButton.tonalIcon(
              onPressed: widget.onUnhide,
              icon: const Icon(Icons.restore_rounded),
              label: const Text('بازگرداندن دارو به فهرست'))),
      ]),
    );
  }
}
