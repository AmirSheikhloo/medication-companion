import 'package:material_ui/material_ui.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/calendar/persian_date.dart';
import '../../../core/calendar/persian_date_picker.dart';
import '../data/inventory_repository.dart';
import '../domain/stock_quantity.dart';
import '../domain/stock_unit_presets.dart';

Future<void> showStockManagementSheet(
  BuildContext context, {
  required InventoryRepository repository,
  required Medication medication,
  required String profileId,
}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StockManagementSheet(
        repository: repository,
        medication: medication,
        profileId: profileId,
      ),
    );

class _StockManagementSheet extends StatefulWidget {
  const _StockManagementSheet({
    required this.repository,
    required this.medication,
    required this.profileId,
  });

  final InventoryRepository repository;
  final Medication medication;
  final String profileId;

  @override
  State<_StockManagementSheet> createState() => _StockManagementSheetState();
}

class _StockManagementSheetState extends State<_StockManagementSheet> {
  final _threshold = TextEditingController();
  final _adjustQuantity = TextEditingController();
  final _adjustReason = TextEditingController();

  StockSummary? _summary;
  final Set<String> _historyOpen = <String>{};
  Map<String, List<StockMovement>> _history = {};
  String? _feedbackMessage;
  String? _operationError;
  bool _busy = false;
  bool _initializedThreshold = false;
  String? _lastSelectedPackageId;
  bool _selectNew = true;
  bool _adjustIncrease = true;
  String? _adjustingPackageId;
  String _precision = 'day';
  String _selectedUnit = 'عدد';
  int _initialAmount = 1000;
  int _dailyUsageAmount = 0;
  DateTime? _expiry;
  String? _error;

  List<int> get _dailyUsageOptions => <int>{
        ...StockUnitPresets.amountsMilliunits,
        if (_dailyUsageAmount > 0) _dailyUsageAmount,
      }.toList()..sort();

  @override
  void initState() {
    super.initState();
    final savedUnit = StockUnitPresets.canonical(widget.medication.unit);
    if (StockUnitPresets.units.contains(savedUnit)) _selectedUnit = savedUnit;
    _load();
  }

  @override
  void dispose() {
    _threshold.dispose();
    _adjustQuantity.dispose();
    _adjustReason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final current = await widget.repository.summary(
        widget.profileId, widget.medication.id);
      final histories = <String, List<StockMovement>>{};
      for (final id in _historyOpen) {
        histories[id] = await widget.repository.movementsForPackage(
          profileId: widget.profileId,
          medicationId: widget.medication.id,
          packageId: id,
        );
      }
      if (!mounted) return;
      if (!_initializedThreshold ||
          _lastSelectedPackageId != current.selectedPackageId) {
        _threshold.text = current.thresholdMilliunits == null
            ? ''
            : StockQuantity.format(current.thresholdMilliunits!);
        _dailyUsageAmount = current.dailyUsageMilliunits ?? 0;
        _initializedThreshold = true;
        _lastSelectedPackageId = current.selectedPackageId;
      }
      setState(() {
        _summary = current;
        _history = histories;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    String successMessage = 'تغییر موجودی ذخیره شد.',
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _feedbackMessage = null;
      _operationError = null;
    });
    try {
      await action();
      await _load();
      if (mounted && _error == null) {
        setState(() => _feedbackMessage = successMessage);
        // The inline confirmation remains visible even if the modal sheet
        // covers the Scaffold's Snackbar area.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _operationError = 'انجام نشد: $error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ثبت نشد: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleHistory(String packageId) async {
    setState(() {
      if (!_historyOpen.add(packageId)) _historyOpen.remove(packageId);
    });
    await _load();
  }

  String _movementName(StockMovement item) => switch (item.kind) {
    'initial' => 'موجودی اولیه',
    'taken' => 'کسر بابت مصرف ثبت‌شده',
    'undo' => 'جبران کسر هنگام بازگرداندن مصرف',
    'adjustment' => 'اصلاح دستی',
    _ => 'تغییر موجودی',
  };

  Future<void> _chooseExpiry() async {
    final date = await showPersianDatePicker(
      context: context,
      initialDate: _expiry ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      title: 'تاریخ انقضای بسته',
    );
    if (mounted && date != null) setState(() => _expiry = date);
  }

  Future<void> _add() async {
    await _run(() async {
      await widget.repository.addPackage(
        profileId: widget.profileId,
        medicationId: widget.medication.id,
        unit: _selectedUnit,
        initialMilliunits: _initialAmount,
        selectForUse: _selectNew,
        expiryIso: _expiry == null
            ? null
            : StockQuantity.isoDate(_precision == 'month'
                ? DateTime(_expiry!.year, _expiry!.month) : _expiry!),
        expiryPrecision: _expiry == null ? 'none' : _precision,
      );
      if (mounted) {
        setState(() => _expiry = null);
      }
    });
  }

  Future<void> _saveThreshold() async {
    await _run(() async {
      final threshold = _threshold.text.trim().isEmpty
          ? null
          : StockQuantity.parseNonNegative(_threshold.text);
      await widget.repository.setLowStockThreshold(
        profileId: widget.profileId,
        medicationId: widget.medication.id,
        thresholdMilliunits: threshold,
      );
    }, successMessage: 'حد هشدار با موفقیت ذخیره شد.');

  }

  Future<void> _saveDailyUsage() async {
    await _run(() => widget.repository.setEstimatedDailyUse(
          profileId: widget.profileId,
          medicationId: widget.medication.id,
          dailyUsageMilliunits: _dailyUsageAmount == 0
              ? null : _dailyUsageAmount,
        ), successMessage: 'مبنای برآورد موجودی ذخیره شد.');
  }

  Future<void> _adjust(String packageId) async {
    await _run(() async {
      final amount = StockQuantity.parsePositive(_adjustQuantity.text);
      final delta = _adjustIncrease ? amount : -amount;
      await widget.repository.adjustPackage(
        profileId: widget.profileId,
        medicationId: widget.medication.id,
        packageId: packageId,
        deltaMilliunits: delta,
        reason: _adjustReason.text,
      );
      if (mounted) {
        _adjustQuantity.clear();
        _adjustReason.clear();
        setState(() => _adjustingPackageId = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.82,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
            children: [
              Text('موجودی: ${widget.medication.name}',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('موجودی هر بسته جداست؛ مقدار مصرف را خودتان اعلام می‌کنید. '
                  'این بخش توصیه دارویی یا کنترل اصالت تاریخ انقضا نیست.'),
              if (_error != null) Text(_error!,
                  style: const TextStyle(color: Colors.deepOrange)),
              if (_feedbackMessage != null)
                Text(_feedbackMessage!,
                    style: const TextStyle(color: Colors.green)),
              if (_operationError != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBE8),
                    borderRadius: BorderRadius.circular(10)),
                  child: Text(_operationError!,
                      style: const TextStyle(color: Colors.redAccent)),
                ),
              const SizedBox(height: 12),
              if (summary == null)
                const Center(child: CircularProgressIndicator())
              else ...[
                if (summary.packages.isEmpty)
                  const ListTile(title: Text('هنوز بسته‌ای ثبت نشده است.')),
                if (summary.packages.isNotEmpty)
                  const Text('بسته‌ها براساس تاریخ انقضا مرتب شده‌اند؛ '
                      'بسته‌های بدون تاریخ در انتهای فهرست هستند.',
                      style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                for (final item in summary.packages) _packageCard(item, summary),
                const SizedBox(height: 16),
                Text('هشدار کمبود بسته انتخاب‌شده'
                    '${summary.selected == null ? '' : ' (${summary.selected!.package.unit})'}',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                TextField(
                  controller: _threshold,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'حد هشدار (خالی = خاموش)',
                    helperText: 'بر حسب واحد بستهٔ انتخابی؛ بدون تبدیل واحد یا تخمین روز.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 6),
                OutlinedButton(
                  onPressed: _busy ? null : _saveThreshold,
                  child: const Text('ذخیره حد هشدار'),
                ),
                if (summary.thresholdMilliunits != null && summary.selected != null)
                  Text(
                    'حد فعال: ${StockQuantity.format(summary.thresholdMilliunits!)} '
                    '${summary.selected!.package.unit} — '
                    '${summary.lowStock ? 'موجودی در محدودهٔ هشدار است.' : 'موجودی فعلی بالاتر از حد هشدار است.'}',
                    style: TextStyle(
                      color: summary.lowStock ? Colors.deepOrange : Colors.green,
                    ),
                  ),
                if (_feedbackMessage == 'حد هشدار با موفقیت ذخیره شد.')
                  const Text('حد هشدار با موفقیت ذخیره شد.',
                      style: TextStyle(color: Colors.green)),
                const Divider(height: 32),
                Card(
                  color: const Color(0xFFE1F8F6),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('روزهای تقریبی باقی‌مانده',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Text(summary.selected == null
                            ? 'برای تخمین، ابتدا یک بسته را انتخاب کنید.'
                            : summary.selected!.expired
                                ? 'بستهٔ انتخابی منقضی است؛ برآورد نمایش داده نمی‌شود.'
                                : summary.estimatedWholeDaysLeft == null
                                    ? 'میانگین مصرف روزانه را وارد کنید تا تخمین نمایش داده شود.'
                                    : summary.estimatedWholeDaysLeft == 0 &&
                                            summary.selected!.balanceMilliunits > 0
                                        ? 'کمتر از یک روز با الگوی واردشده'
                                        : 'حدود ${summary.estimatedWholeDaysLeft} روز با الگوی واردشده'),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          key: ValueKey('daily-use-${summary.selectedPackageId}'),
                          initialValue: _dailyUsageAmount,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'میانگین مصرف روزانه (اختیاری)',
                            helperText: summary.selected == null
                                ? 'ابتدا بسته را انتخاب کنید.'
                                : 'واحد: ${summary.selected!.package.unit} در روز؛ خاموش = حذف تخمین',
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(value: 0,
                                child: Text('خاموش / بدون تخمین')),
                            for (final amount in _dailyUsageOptions)
                              DropdownMenuItem(
                                value: amount,
                                child: Text(StockUnitPresets.quantityLabel(
                                    amount, summary.selected?.package.unit ?? '')),
                              ),
                          ],
                          onChanged: _busy || summary.selected == null
                              ? null : (value) {
                                if (value != null) {
                                  setState(() => _dailyUsageAmount = value);
                                }
                              },
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: _busy || summary.selected == null
                              ? null : _saveDailyUsage,
                          child: const Text('ذخیره مبنای تخمین'),
                        ),
                        const Text(
                          'فقط موجودی بستهٔ انتخابی محاسبه می‌شود؛ مصرف واقعی، تغییر برنامه و بسته‌های دیگر ممکن است نتیجه را تغییر دهند. این عدد توصیهٔ دوز نیست.',
                          style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text('افزودن بسته جدید',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                const Text('نام بسته به‌صورت خودکار ساخته می‌شود '
                    '(بسته اول، بسته دوم و ...).'),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: DropdownButtonFormField<int>(
                    initialValue: _initialAmount,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'موجودی واقعی اولیه',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: 0, child: Text('۰')),
                      for (final amount in StockUnitPresets.amountsMilliunits)
                        DropdownMenuItem(value: amount,
                          child: Text(StockQuantity.format(amount))),
                    ],
                    onChanged: _busy ? null : (value) {
                      if (value != null) setState(() => _initialAmount = value);
                    },
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: DropdownButtonFormField<String>(
                    initialValue: _selectedUnit,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'واحد بسته',
                      border: OutlineInputBorder(),
                    ),
                    items: [for (final unit in StockUnitPresets.units)
                      DropdownMenuItem(value: unit, child: Text(unit))],
                    onChanged: _busy ? null : (value) {
                      if (value != null) setState(() => _selectedUnit = value);
                    },
                  )),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _chooseExpiry,
                      icon: const Icon(Icons.event),
                      label: Text(_expiry == null
                          ? 'تاریخ انقضا (اختیاری)'
                          : _precision == 'month'
                              ? 'ماه میلادی ${gregorianDateLabel(_expiry!)}'
                              : 'روز شمسی ${persianDateLabel(_expiry!)}'),
                    ),
                  ),
                  if (_expiry != null)
                    IconButton(
                      tooltip: 'حذف تاریخ',
                      onPressed: () => setState(() => _expiry = null),
                      icon: const Icon(Icons.close),
                    ),
                ]),
                if (_expiry != null)
                  DropdownButtonFormField<String>(
                    initialValue: _precision,
                    decoration: const InputDecoration(
                      labelText: 'دقت تاریخ (ماه فقط میلادی)',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'day', child: Text('روز دقیق')),
                      DropdownMenuItem(value: 'month', child: Text('فقط ماه و سال')),
                    ],
                    onChanged: _busy ? null : (value) {
                      if (value != null) setState(() => _precision = value);
                    },
                  ),
                if (_expiry != null && _precision == 'month')
                  const Text('برای تاریخ با دقت ماه، همان ماه میلادیِ تاریخ انتخابی ثبت می‌شود.'),
                CheckboxListTile(
                  value: _selectNew,
                  title: const Text('این بسته برای کسر موجودی انتخاب شود'),
                  subtitle: const Text('بسته منقضی قابل انتخاب نیست.'),
                  onChanged: _busy ? null : (value) =>
                      setState(() => _selectNew = value ?? false),
                  contentPadding: EdgeInsets.zero,
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _add,
                  icon: const Icon(Icons.add),
                  label: const Text('ثبت بسته و موجودی اولیه'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _packageCard(PackageBalance item, StockSummary summary) {
    final pack = item.package;
    final selected = summary.selectedPackageId == pack.id;
    final expired = item.expired;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(pack.label,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              if (selected) const Chip(label: Text('انتخاب‌شده')),
            ]),
            Text('باقی‌مانده: ${StockQuantity.format(item.balanceMilliunits)} ${pack.unit}'),
            Text(pack.expiryIso == null
                ? 'انقضا ثبت نشده'
                : 'انقضا (میلادی): ${pack.expiryIso} '
                  '${pack.expiryPrecision == 'month' ? '(ماه/سال)' : '(روز)'}'),
            if (expired)
              const Text('هشدار: تاریخ انقضای ثبت‌شده گذشته است.',
                  style: TextStyle(color: Colors.deepOrange)),
            if (selected && summary.lowStock)
              const Text('هشدار: موجودی بسته انتخاب‌شده کم است.',
                  style: TextStyle(color: Colors.deepOrange)),
            Wrap(spacing: 8, children: [
              if (!selected && !expired)
                TextButton(
                  onPressed: _busy ? null : () => _run(() =>
                      widget.repository.selectPackage(
                        profileId: widget.profileId,
                        medicationId: widget.medication.id,
                        packageId: pack.id,
                      )),
                  child: const Text('انتخاب برای مصرف'),
                ),
              if (selected)
                TextButton(
                  onPressed: _busy ? null : () => _run(() =>
                      widget.repository.clearSelection(
                        profileId: widget.profileId,
                        medicationId: widget.medication.id,
                      )),
                  child: const Text('لغو انتخاب'),
                ),
              TextButton(
                onPressed: _busy ? null : () => setState(() {
                  _adjustingPackageId =
                      _adjustingPackageId == pack.id ? null : pack.id;
                  _adjustQuantity.clear();
                  _adjustReason.clear();
                }),
                child: const Text('اصلاح موجودی'),
              ),
              TextButton.icon(
                onPressed: _busy ? null : () => _toggleHistory(pack.id),
                icon: Icon(_historyOpen.contains(pack.id)
                    ? Icons.expand_less : Icons.history),
                label: const Text('تاریخچه موجودی'),
              ),
            ]),
            if (_historyOpen.contains(pack.id)) ...[
              const Divider(),
              Text('تاریخچه تغییرات این بسته',
                  style: Theme.of(context).textTheme.titleSmall),
              if (_history[pack.id] == null)
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(),
                )
              else if (_history[pack.id]!.isEmpty)
                const Text('هنوز تغییری برای این بسته ثبت نشده است.')
              else
                for (final entry in _history[pack.id]!)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(_movementName(entry)),
                    subtitle: Text(
                      '${entry.createdAt.toLocal().toString().substring(0, 16)}'
                      '${entry.note == null ? '' : ' — ${entry.note}'}',
                    ),
                    trailing: Text(
                      '${entry.deltaMilliunits > 0 ? '+' : ''}'
                      '${StockQuantity.format(entry.deltaMilliunits)} ${pack.unit}',
                      style: TextStyle(color: entry.deltaMilliunits < 0
                          ? Colors.deepOrange : Colors.green),
                    ),
                  ),
            ],
            if (_adjustingPackageId == pack.id) ...[
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('افزایش')),
                  ButtonSegment(value: false, label: Text('کاهش/دورریز')),
                ],
                selected: {_adjustIncrease},
                onSelectionChanged: _busy ? null :
                    (value) => setState(() => _adjustIncrease = value.first),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _adjustQuantity,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'مقدار اصلاح',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _adjustReason,
                maxLength: 240,
                decoration: const InputDecoration(
                  labelText: 'دلیل (الزامی)',
                  border: OutlineInputBorder(),
                ),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _adjust(pack.id),
                child: const Text('ثبت اصلاح در سوابق'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
