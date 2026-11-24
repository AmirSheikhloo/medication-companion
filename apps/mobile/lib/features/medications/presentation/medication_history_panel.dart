import 'package:drift/drift.dart' hide Column;
import 'package:material_ui/material_ui.dart';

import '../../../core/calendar/persian_date.dart';
import 'medication_history_range_dialog.dart';
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
  int _visibleLimit = 20;
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
        start: end.subtract(const Duration(days: 29)), end: end),
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
      ..orderBy([(t) => OrderingTerm.desc(t.recordedAt)])
      ..limit(_visibleLimit + 1)).get();
    final movements = await (db.select(db.stockMovements)
      ..where((t) => t.profileId.equals(med.profileId) &
        t.medicationId.equals(med.id) &
        t.createdAt.isBiggerOrEqualValue(first) &
        t.createdAt.isSmallerThanValue(afterLast))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(_visibleLimit + 1)).get();
    return (doses: doses, movements: movements);
  }

  void _setRange(_HistoryRange value) {
    setState(() {
      _range = value;
      _visibleLimit = 20;
      _future = _load();
    });
  }

  Future<void> _chooseRange() async {
    final custom = await showMedicationHistoryRangeDialog(
      context: context, initial: _custom);
    if (!mounted || custom == null) return;
    setState(() {
      _custom = custom;
      _range = _HistoryRange.custom;
      _visibleLimit = 20;
      _future = _load();
    });
  }

  String _doseName(String action) => switch (action) {
    'taken' => 'مصرف کردم',
    'skipped' => 'مصرف نکردم',
    'unknown' => 'مطمئن نیستم · نیازمند بازبینی',
    'undo' => 'بازگرداندن ثبت',
    _ => 'ثبت وضعیت',
  };

  Color _doseColor(String action) => switch (action) {
    'taken' => AppPalette.ink(context, AppColors.success),
    'skipped' => AppPalette.tone(context, const Color(0xFFD24B56)),
    'unknown' => AppPalette.tone(context, const Color(0xFFBA7812)),
    _ => AppPalette.ink(context, AppColors.muted),
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
              Text(title, style: TextStyle(fontWeight: FontWeight.w800,
                color: AppPalette.ink(context, AppColors.primaryDark), fontSize: 12)),
              Text(subtitle, style: TextStyle(
                color: AppPalette.ink(context, AppColors.muted), fontSize: 11)),
            ])),
        ]),
      );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
      const SizedBox(height: 2),
      const SizedBox(height: 9),
      Wrap(spacing: 5, runSpacing: 5, children: [
        for (final item in const [
          (_HistoryRange.today, 'امروز'),
          (_HistoryRange.week, '۷ روز'),
          (_HistoryRange.month, '۳۰ روز'),
          (_HistoryRange.year, 'سال'),
        ])
          ChoiceChip(
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            label: Text(item.$2, style: const TextStyle(fontSize: 11)),
            selected: _range == item.$1,
            onSelected: (_) => _setRange(item.$1)),
        ActionChip(
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: _range == _HistoryRange.custom
            ? AppPalette.surface(context, AppColors.mint) : Colors.white,
          side: BorderSide(color: AppPalette.surface(context, AppColors.outline)),
          label: const Text('بازه', style: TextStyle(fontSize: 11)),
          onPressed: _chooseRange),
      ]),
      const SizedBox(height: 6),
      Text(PersianDate.displayDigits(
        '${persianDateLabel(_selectedRange().start)} تا '
        '${persianDateLabel(_selectedRange().end)}'),
        style: TextStyle(fontSize: 11, color: AppPalette.ink(context, AppColors.muted))),
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
          final hasMore = data.doses.length > _visibleLimit ||
              data.movements.length > _visibleLimit;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Text('تاریخچهٔ مصرف (${PersianDate.displayDigits('${data.doses.take(_visibleLimit).length}')}${data.doses.length > _visibleLimit ? '+' : ''})',
              style: TextStyle(fontWeight: FontWeight.w800,
                color: AppPalette.ink(context, AppColors.primaryDark))),
            if (data.doses.isEmpty) Padding(
              padding: EdgeInsets.symmetric(vertical: 9),
              child: Text('در این بازه مصرفی ثبت نشده است.',
                style: TextStyle(color: AppPalette.ink(context, AppColors.muted)))),
            for (final dose in data.doses.take(_visibleLimit)) _eventRow(
              title: _doseName(dose.action),
              subtitle: persianDateLabel(dose.recordedAt, showTime: true),
              color: _doseColor(dose.action),
              icon: dose.action == 'taken' ? Icons.check_circle_outline
                  : Icons.info_outline),
            const Divider(height: 22),
            Text('تاریخچهٔ موجودی (${PersianDate.displayDigits('${data.movements.take(_visibleLimit).length}')}${data.movements.length > _visibleLimit ? '+' : ''})',
              style: TextStyle(fontWeight: FontWeight.w800,
                color: AppPalette.ink(context, AppColors.primaryDark))),
            if (data.movements.isEmpty) Padding(
              padding: EdgeInsets.symmetric(vertical: 9),
              child: Text('در این بازه تغییری در موجودی ثبت نشده است.',
                style: TextStyle(color: AppPalette.ink(context, AppColors.muted)))),
            for (final move in data.movements.take(_visibleLimit)) _eventRow(
              title: PersianDate.displayDigits(_movementTitle(move)),
              subtitle: '${persianDateLabel(move.createdAt, showTime: true)}'
                  '${move.kind == 'metadata' && move.note != null
                    ? ' — ${move.note}' : ''}',
              color: move.deltaMilliunits < 0
                ? AppPalette.tone(context, const Color(0xFFB55B32)) : AppPalette.ink(context, AppColors.primary),
              icon: Icons.inventory_2_outlined),
            if (hasMore) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _visibleLimit += 20;
                  _future = _load();
                }),
                icon: const Icon(Icons.expand_more_rounded),
                label: const Text('نمایش ۲۰ مورد بیشتر')),
            ],
          ]);
        },
      ),
    ]);
}
