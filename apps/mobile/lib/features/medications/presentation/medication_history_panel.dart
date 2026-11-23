import 'package:drift/drift.dart' hide Column;
import 'package:material_ui/material_ui.dart';

import '../../../core/calendar/persian_date.dart';
import '../../../core/calendar/persian_date_picker.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_design.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/stock_quantity.dart';
import '../data/medication_repository.dart';

enum _HistoryRange { today, week, month, year, custom }

/// Read-only, profile-scoped dose and stock ledgers. A filter changes only
/// which events are displayed; it never alters a recorded medication dose.
class MedicationHistoryPanel extends StatefulWidget {
  const MedicationHistoryPanel({super.key, required this.medication,
    required this.medicationRepository, required this.inventoryRepository,
    required this.stock});

  final Medication medication;
  final MedicationRepository medicationRepository;
  final InventoryRepository inventoryRepository;
  final StockSummary? stock;

  @override
  State<MedicationHistoryPanel> createState() => _MedicationHistoryPanelState();
}

class _MedicationHistoryPanelState extends State<MedicationHistoryPanel> {
  _HistoryRange _range = _HistoryRange.week;
  DateTimeRange? _custom;
  late Future<({List<DoseEvent> doses, List<StockMovement> movements})> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  DateTimeRange _selectedRange() {
    final today = DateTime.now();
    final end = DateTime(today.year, today.month, today.day);
    return switch (_range) {
      _HistoryRange.today => DateTimeRange(start: end, end: end),
      _HistoryRange.week => DateTimeRange(
        start: end.subtract(const Duration(days: 6)), end: end),
      _HistoryRange.month => DateTimeRange(
        start: DateTime(end.year, end.month, 1), end: end),
      _HistoryRange.year => DateTimeRange(
        start: DateTime(end.year, 1, 1), end: end),
      _HistoryRange.custom => _custom ?? DateTimeRange(start: end, end: end),
    };
  }

  Future<({List<DoseEvent> doses, List<StockMovement> movements})> _load() async {
    final med = widget.medication;
    final range = _selectedRange();
    final first = range.start.toUtc();
    final afterLast = DateTime(range.end.year, range.end.month,
        range.end.day + 1).toUtc();
    final db = widget.medicationRepository.db;
    final doses = await (db.select(db.doseEvents)
      ..where((t) => t.profileId.equals(med.profileId) &
        t.medicationId.equals(med.id) &
        t.recordedAt.isBiggerOrEqualValue(first) &
        t.recordedAt.isSmallerThanValue(afterLast))
      ..orderBy([(t) => OrderingTerm.desc(t.recordedAt)]))
        .get();
    final movements = <StockMovement>[];
    for (final package in widget.stock?.packages ?? const <PackageBalance>[]) {
      final rows = await widget.inventoryRepository.movementsForPackage(
        profileId: med.profileId, medicationId: med.id,
        packageId: package.package.id);
      for (final row in rows) {
        if (!row.createdAt.isBefore(first) && row.createdAt.isBefore(afterLast)) {
          movements.add(row);
        }
      }
    }
    movements.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return (doses: doses, movements: movements);
  }

  void _setRange(_HistoryRange value) {
    setState(() {
      _range = value;
      _future = _load();
    });
  }

  Future<void> _chooseRange() async {
    final today = DateTime.now();
    final first = await showPersianDatePicker(context: context,
      initialDate: _custom?.start ?? today.subtract(const Duration(days: 7)),
      firstDate: DateTime(2000), lastDate: today,
      title: 'ابتدای بازهٔ گزارش');
    if (first == null || !mounted) return;
    final last = await showPersianDatePicker(context: context,
      initialDate: _custom?.end ?? today,
      firstDate: first, lastDate: today,
      title: 'پایان بازهٔ گزارش');
    if (last == null || !mounted) return;
    setState(() {
      _custom = DateTimeRange(start: first, end: last);
      _range = _HistoryRange.custom;
      _future = _load();
    });
  }

  String _doseName(String action) => switch (action) {
    'taken' => 'مصرف کردم',
    'skipped' => 'مصرف نکردم',
    'unknown' => 'مطمئن نیستم',
    'undo' => 'بازگرداندن ثبت',
    _ => 'ثبت وضعیت',
  };

  Color _doseColor(String action) => switch (action) {
    'taken' => AppColors.success,
    'skipped' => const Color(0xFFD24B56),
    'unknown' => const Color(0xFFBA7812),
    _ => AppColors.muted,
  };

  String _movementName(String kind) => switch (kind) {
    'initial' => 'موجودی اولیه',
    'taken' => 'کسر بابت مصرف',
    'undo' => 'بازگشت موجودی',
    'adjustment' => 'اصلاح دستی موجودی',
    'metadata' => 'ویرایش یا بایگانی بسته',
    _ => 'تغییر موجودی',
  };

  String _movementTitle(StockMovement movement) {
    if (movement.kind == 'metadata') return _movementName(movement.kind);
    final sign = movement.deltaMilliunits > 0 ? '+' : '';
    return '${_movementName(movement.kind)}: $sign'
        '${StockQuantity.format(movement.deltaMilliunits)}';
  }

  Widget _eventRow({required String title, required String subtitle,
      required Color color, required IconData icon}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          CircleAvatar(radius: 17, backgroundColor: color.withValues(alpha: .12),
            child: Icon(icon, size: 18, color: color)),
          const SizedBox(width: 9),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800,
                color: AppColors.primaryDark, fontSize: 12)),
              Text(subtitle, style: const TextStyle(
                color: AppColors.muted, fontSize: 11)),
            ])),
        ]),
      );

  @override
  Widget build(BuildContext context) => AppPanel(
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
      const AppSectionHeading('سوابق مصرف و تغییرات موجودی',
        icon: Icons.history_rounded),
      const SizedBox(height: 9),
      SingleChildScrollView(scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final item in const [
            (_HistoryRange.today, 'امروز'),
            (_HistoryRange.week, 'هفتگی'),
            (_HistoryRange.month, 'ماهانه'),
            (_HistoryRange.year, 'سالانه'),
          ]) Padding(padding: const EdgeInsets.only(left: 6),
            child: ChoiceChip(label: Text(item.$2),
              selected: _range == item.$1,
              onSelected: (_) => _setRange(item.$1))),
          ActionChip(avatar: const Icon(Icons.date_range_outlined, size: 17),
            label: const Text('انتخاب تاریخ'),
            onPressed: _chooseRange),
        ])),
      const SizedBox(height: 6),
      Text(PersianDate.displayDigits(
        '${persianDateLabel(_selectedRange().start)} تا '
        '${persianDateLabel(_selectedRange().end)}'),
        style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      const SizedBox(height: 12),
      FutureBuilder<({List<DoseEvent> doses, List<StockMovement> movements})>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text('بارگذاری سوابق انجام نشد. دوباره وارد این صفحه شو.');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.requireData;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Text('تاریخچهٔ مصرف (${PersianDate.displayDigits('${data.doses.length}')})',
              style: const TextStyle(fontWeight: FontWeight.w800,
                color: AppColors.primaryDark)),
            if (data.doses.isEmpty) const Padding(
              padding: EdgeInsets.symmetric(vertical: 9),
              child: Text('در این بازه مصرفی ثبت نشده است.',
                style: TextStyle(color: AppColors.muted))),
            for (final dose in data.doses) _eventRow(
              title: _doseName(dose.action),
              subtitle: persianDateLabel(dose.recordedAt, showTime: true),
              color: _doseColor(dose.action),
              icon: dose.action == 'taken' ? Icons.check_circle_outline
                  : Icons.info_outline),
            const Divider(height: 22),
            Text('تاریخچهٔ موجودی (${PersianDate.displayDigits('${data.movements.length}')})',
              style: const TextStyle(fontWeight: FontWeight.w800,
                color: AppColors.primaryDark)),
            if (data.movements.isEmpty) const Padding(
              padding: EdgeInsets.symmetric(vertical: 9),
              child: Text('در این بازه تغییری در موجودی ثبت نشده است.',
                style: TextStyle(color: AppColors.muted))),
            for (final move in data.movements) _eventRow(
              title: PersianDate.displayDigits(_movementTitle(move)),
              subtitle: '${persianDateLabel(move.createdAt, showTime: true)}'
                  '${move.kind == 'metadata' && move.note != null
                    ? ' — ${move.note}' : ''}',
              color: move.deltaMilliunits < 0
                ? const Color(0xFFB55B32) : AppColors.primary,
              icon: Icons.inventory_2_outlined),
          ]);
        },
      ),
    ]),
  );
}
