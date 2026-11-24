import 'package:material_ui/material_ui.dart';

import '../../../core/calendar/persian_date.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_design.dart';
import '../../../core/ui/redesign_widgets.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/data/stock_attention_repository.dart';
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
    this.setup, this.dismissedAttentionKeys = const {},
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
  final Set<String> dismissedAttentionKeys;
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
  late Set<String> _dismissedAttention;

  @override
  void initState() {
    super.initState();
    _dismissedAttention = Set.of(widget.dismissedAttentionKeys);
  }

  List<StockAttention> get _currentAttention =>
    StockAttention.evaluate(stock, setup?.expiryLeadDays, DateTime.now());

  Future<void> _dismissAlert(StockAttention alert) async {
    try {
      await StockAttentionRepository(medicationRepository.db).dismiss(
        medication.profileId, medication.id, alert.key);
      if (mounted) setState(() => _dismissedAttention.add(alert.key));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تنظیم هشدار ذخیره نشد.')));
      }
    }
  }

  Future<void> _applyFreshStock(StockSummary fresh) async {
    final retained = await StockAttentionRepository(medicationRepository.db)
      .reconcile(medication.profileId, medication.id,
        StockAttention.evaluate(fresh, setup?.expiryLeadDays, DateTime.now()));
    if (mounted) {
      setState(() {
        _reloadedStock = fresh;
        _dismissedAttention = retained;
      });
    }
  }

  Widget _attentionPanel(StockAttention alert) {
    final tone = alert.urgent ? AppPalette.tone(context, const Color(0xFFB6354C)) : AppPalette.tone(context, const Color(0xFF996116));
    return Padding(padding: const EdgeInsets.only(bottom: 9),
      child: AppPanel(color: alert.urgent ? const Color(0xFFFFEBEF)
        : const Color(0xFFFFF5E4), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.warning_amber_rounded, color: tone),
              const SizedBox(width: 8),
              Expanded(child: Text(alert.title,
                style: TextStyle(color: tone, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 6),
            Text(alert.message),
            const SizedBox(height: 8),
            Wrap(spacing: 7, runSpacing: 6, children: [
              OutlinedButton(onPressed: () => _openPackage(null),
                child: const Text('افزودن بسته')),
              TextButton(onPressed: () => _dismissAlert(alert),
                child: const Text('عدم نمایش این هشدار')),
              TextButton(onPressed: onArchive,
                child: const Text('مدیریت پایان دوره')),
            ]),
          ])));
  }
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
    await _applyFreshStock(latest);
  }

  Future<void> _selectPackage(PackageBalance balance) async {
    if (balance.archived || balance.expired ||
        balance.balanceMilliunits <= 0) { return; }
    try {
      await inventoryRepository.selectPackage(
        profileId: medication.profileId,
        medicationId: medication.id,
        packageId: balance.package.id);
      final fresh = await inventoryRepository.summary(
        medication.profileId, medication.id);
      await _applyFreshStock(fresh);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('این بسته قابل انتخاب نیست؛ موجودی یا تاریخ انقضا را بررسی کن.')));
    }
  }

  void _openConsumptionHistory() {
    Navigator.of(context).push(medicationPageRoute<void>(context,
      Scaffold(
        appBar: AppBar(title: const Text('سوابق مصرف')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          AppPanel(child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppSoftHeader(title: medication.name, icon: Icons.history_rounded),
              const SizedBox(height: 12),
              MedicationHistoryPanel(medication: medication,
                medicationRepository: medicationRepository,
                inventoryRepository: inventoryRepository, stock: stock),
            ])),
        ]),
      )));
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
    if (!mounted) { return; }
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
    final color = balance.archived ? AppPalette.ink(context, AppColors.muted) : expired
        ? AppPalette.tone(context, const Color(0xFFBB4356))
        : isSelected ? AppPalette.ink(context, AppColors.primary) : AppPalette.ink(context, AppColors.muted);
    final fill = balance.archived ? AppPalette.tone(context, const Color(0xFFF0F2F3)) : expired
        ? AppPalette.tone(context, const Color(0xFFFFF0F1))
        : isSelected ? AppPalette.tone(context, const Color(0xFFE0F5F0)) : AppPalette.tone(context, const Color(0xFFF5F8F9));
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
        Icon(expired ? Icons.warning_amber_rounded : Icons.inventory_2_outlined,
          color: color, size: 22),
        const SizedBox(width: 9),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(PersianDate.displayDigits(balance.package.label), style: TextStyle(
              color: AppPalette.ink(context, AppColors.primaryDark), fontWeight: FontWeight.w800,
              fontSize: 14)),
            const SizedBox(height: 2),
            Text(PersianDate.displayDigits(
              '${StockQuantity.format(balance.balanceMilliunits)} ${balance.package.unit} باقی‌مانده'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(_expiryLabel(balance), style: TextStyle(
              color: expired ? color : AppPalette.ink(context, AppColors.muted), fontSize: 11)),

            if (balance.balanceMilliunits <= 0 && !balance.archived)
              Text('موجودی تمام شده',
                style: TextStyle(color: AppPalette.ink(context, const Color(0xFFB04A38)),
                  fontWeight: FontWeight.w800, fontSize: 11)),
            if (balance.archived) Text(balance.deleted
              ? 'حذف‌شده از فهرست؛ قابل بازگردانی'
              : 'بایگانی‌شده؛ خارج از موجودی فعال',
              style: TextStyle(color: AppPalette.ink(context, AppColors.muted), fontSize: 11)),
            if (expired) Text('منقضی‌شده؛ قابل انتخاب برای مصرف نیست',
              style: TextStyle(color: AppPalette.ink(context, const Color(0xFFBB4356)), fontSize: 11,
                fontWeight: FontWeight.w700)),
          ],
        )),
        SizedBox(width: 58, child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            SizedBox(height: 22, child: isSelected
              ? const AppStatusPill(text: 'منتخب',
                  color: AppColors.primary, fontSize: 10)
              : const SizedBox.shrink()),
            IconButton(
              key: Key('select-package-${balance.package.id}'),
              tooltip: isSelected ? 'بسته منتخب' : 'انتخاب برای مصرف',
              onPressed: isSelected || archived || balance.archived || expired ||
                  balance.balanceMilliunits <= 0
                ? null : () => _selectPackage(balance),
              icon: Icon(isSelected ? Icons.radio_button_checked_rounded :
                Icons.radio_button_unchecked_rounded,
                size: 23, color: isSelected || (!balance.archived && !expired)
                  ? AppPalette.ink(context, AppColors.primary) : AppPalette.ink(context, AppColors.muted))),
          ])),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final selected = stock?.selected;
    final statusColor = stock?.lowStock == true ? AppPalette.tone(context, const Color(0xFFB16D06)) : AppPalette.ink(context, AppColors.primary);
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
      backgroundColor: AppPalette.surface(context, AppColors.background),
      appBar: AppBar(title: const Text('جزئیات دارو'),
        backgroundColor: AppPalette.surface(context, AppColors.background),
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
            Text(PersianDate.displayDigits(medication.name), style: TextStyle(fontWeight: FontWeight.w900,
              fontSize: 23, color: AppPalette.ink(context, AppColors.primaryDark))),
            const SizedBox(height: 5),
            AppStatusPill(text: hidden ? 'حذف‌شده از فهرست' : archived ? 'پایان مصرف' : 'فعال',
              icon: archived ? Icons.archive_outlined : Icons.check, color: AppColors.primary),
          ])),
        ]),
        const SizedBox(height: 22),
        if (!archived && !hidden)
          for (final alert in _currentAttention)
            if (!_dismissedAttention.contains(alert.key))
              _attentionPanel(alert),
        AppPanel(padding: const EdgeInsets.all(12), child: Column(children: [
          const AppSoftHeader(title: 'برنامه مصرف', icon: Icons.calendar_month_outlined),
          if (pendingSchedule) Padding(padding: EdgeInsets.only(top: 8),
            child: Text('برنامه جدید — از فردا؛ نوبت‌های امروز تغییر نمی‌کنند.',
              style: TextStyle(fontSize: 11, color: AppPalette.ink(context, AppColors.primary)))),
          const SizedBox(height: 6),
          if (slots.isEmpty) const Padding(padding: EdgeInsets.all(13),
            child: Text('برای این روز نوبتی ثبت نشده است.')),
          for (var i = 0; i < slots.length; i++) ...[
            if (i != 0) Divider(height: 1, color: AppPalette.surface(context, AppColors.outline)),
            Padding(padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(children: [
                Icon(slots[i].scheduledAt.hour >= 17 ? Icons.nightlight_outlined :
                  Icons.wb_sunny_outlined, size: 20, color: AppPalette.ink(context, AppColors.primary)),
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
                      style: TextStyle(fontSize: 12,
                        color: AppPalette.ink(context, AppColors.muted))),
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
          for (final pack in packages.where((p) => !p.archived))
            _packageRow(pack, pack.package.id == stock?.selectedPackageId),
          if (packages.any((p) => p.archived))
            ExpansionTile(
              title: const Text('بسته‌های بایگانی و حذف‌شده'),
              children: [
                for (final pack in packages.where((p) => p.archived))
                  _packageRow(pack, false),
              ]),
          if (packages.isEmpty)
            Padding(padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('برای این دارو هنوز بسته‌ای ثبت نشده است.',
                style: TextStyle(color: AppPalette.ink(context, AppColors.muted)))),
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
        AppGradientButton(label: 'سوابق مصرف', icon: Icons.history_rounded,
          onPressed: _openConsumptionHistory, height: 52),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: _openPlanHistory,
            style: OutlinedButton.styleFrom(
              backgroundColor: AppPalette.surface(context, AppColors.mint),
              minimumSize: const Size(0, 62),
              padding: const EdgeInsets.symmetric(horizontal: 7)),
            child: const Text('تاریخچه برنامه', textAlign: TextAlign.center))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(
            onPressed: _openCourseHistory,
            style: OutlinedButton.styleFrom(
              backgroundColor: AppPalette.surface(context, AppColors.lightMint),
              minimumSize: const Size(0, 62),
              padding: const EdgeInsets.symmetric(horizontal: 7)),
            child: const Text('پرونده و دوره‌های مصرف',
              textAlign: TextAlign.center))),
        ]),
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
