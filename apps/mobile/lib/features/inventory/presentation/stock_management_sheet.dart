import 'package:material_ui/material_ui.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/calendar/persian_date.dart';
import '../../../core/calendar/persian_date_picker.dart';
import '../../../core/ui/app_design.dart';
import '../data/inventory_repository.dart';
import '../domain/stock_quantity.dart';

Future<void> showStockManagementSheet(
  BuildContext context, {
  required InventoryRepository repository,
  required Medication medication,
  required String profileId,
}) => Navigator.of(context).push<void>(MaterialPageRoute(
  builder: (_) => _StockManagementSheet(
    repository: repository,
    medication: medication,
    profileId: profileId,
  ),
));

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
  final _label = TextEditingController();
  final _unit = TextEditingController();
  final _initial = TextEditingController();
  final _threshold = TextEditingController();
  final _adjustQuantity = TextEditingController();
  final _adjustReason = TextEditingController();

  StockSummary? _summary;
  final Set<String> _historyOpen = <String>{};
  Map<String, List<StockMovement>> _history = {};
  String? _feedbackMessage;
  bool _busy = false;
  bool _initializedThreshold = false;
  String? _lastSelectedPackageId;
  bool _selectNew = true;
  bool _adjustIncrease = true;
  String? _adjustingPackageId;
  String _precision = 'day';
  DateTime? _expiry;
  String? _error;

  @override
  void initState() {
    super.initState();
    _unit.text = widget.medication.unit;
    _load();
  }

  @override
  void dispose() {
    _label.dispose();
    _unit.dispose();
    _initial.dispose();
    _threshold.dispose();
    _adjustQuantity.dispose();
    _adjustReason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final current = await widget.repository.summary(
        widget.profileId,
        widget.medication.id,
      );
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
    });
    try {
      await action();
      await _load();
      if (mounted && _error == null) {
        setState(() => _feedbackMessage = successMessage);
        // The inline confirmation remains visible even if the modal sheet
        // covers the Scaffold's Snackbar area.
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ثبت نشد: $error')));
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
      final initial = StockQuantity.parseNonNegative(_initial.text);
      await widget.repository.addPackage(
        profileId: widget.profileId,
        medicationId: widget.medication.id,
        label: _label.text,
        unit: _unit.text,
        initialMilliunits: initial,
        selectForUse: _selectNew,
        expiryIso: _expiry == null
            ? null
            : StockQuantity.isoDate(
                _precision == 'month'
                    ? DateTime(_expiry!.year, _expiry!.month)
                    : _expiry!,
              ),
        expiryPrecision: _expiry == null ? 'none' : _precision,
      );
      if (mounted) {
        _label.clear();
        _initial.clear();
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('موجودی دارو'),
        backgroundColor: AppColors.primary, foregroundColor: Colors.white),
      body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              AppSectionHeading(
                'موجودی: ${widget.medication.name}',
                icon: Icons.inventory_2_outlined,
              ),
              const SizedBox(height: 8),
              const Text(
                'موجودی هر بسته جداست؛ مقدار مصرف را خودتان اعلام می‌کنید. '
                'این بخش توصیه دارویی یا کنترل اصالت تاریخ انقضا نیست.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.deepOrange)),
              if (_feedbackMessage != null)
                Text(
                  _feedbackMessage!,
                  style: const TextStyle(color: Colors.green),
                ),
              const SizedBox(height: 12),
              if (summary == null)
                const Center(child: CircularProgressIndicator())
              else ...[
                AppPanel(
                  color: AppColors.mint,
                  child: Row(
                    children: [
                      const AppIconTile(Icons.inventory_2_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'موجودی بستهٔ منتخب',
                              style: TextStyle(color: AppColors.primaryDark),
                            ),
                            Text(
                              summary.selected == null
                                  ? 'بسته‌ای انتخاب نشده است'
                                  : PersianDate.persianDigits(
                                      '${StockQuantity.format(summary.selected!.balanceMilliunits)} '
                                      '${summary.selected!.package.unit}',
                                    ),
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryDark,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (summary.lowStock)
                        const Icon(Icons.warning_amber_rounded,
                            color: Colors.deepOrange),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const AppSectionHeading('بسته‌های دارو', icon: Icons.widgets_outlined),
                const SizedBox(height: 7),
                if (summary.packages.isEmpty)
                  const ListTile(title: Text('هنوز بسته‌ای ثبت نشده است.')),
                for (final item in summary.packages)
                  _packageCard(item, summary),
                const SizedBox(height: 16),
                AppSectionHeading(
                  'هشدار کمبود بسته انتخاب‌شده'
                  '${summary.selected == null ? '' : ' (${summary.selected!.package.unit})'}',
                  icon: Icons.notification_important_outlined,
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _threshold,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
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
                if (summary.thresholdMilliunits != null &&
                    summary.selected != null)
                  Text(
                    PersianDate.persianDigits(
                      'حد فعال: ${StockQuantity.format(summary.thresholdMilliunits!)} '
                      '${summary.selected!.package.unit} — '
                      '${summary.lowStock ? 'موجودی در محدودهٔ هشدار است.' : 'موجودی فعلی بالاتر از حد هشدار است.'}',
                    ),
                    style: TextStyle(
                      color: summary.lowStock
                          ? Colors.deepOrange
                          : Colors.green,
                    ),
                  ),
                if (_feedbackMessage == 'حد هشدار با موفقیت ذخیره شد.')
                  const Text(
                    'حد هشدار با موفقیت ذخیره شد.',
                    style: TextStyle(color: Colors.green),
                  ),
                const Divider(height: 32),
                const AppSectionHeading(
                  'افزودن بسته جدید',
                  icon: Icons.add_box_outlined,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _label,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'نام/مشخصه بسته (مثلاً جعبه دوم)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _initial,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'موجودی واقعی اولیه',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _unit,
                        decoration: const InputDecoration(
                          labelText: 'واحد (مثلاً عدد یا ml)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _chooseExpiry,
                        icon: const Icon(Icons.event),
                        label: Text(
                          _expiry == null
                              ? 'تاریخ انقضا (اختیاری)'
                              : _precision == 'month'
                              ? 'ماه میلادی ${gregorianDateLabel(_expiry!)}'
                              : 'روز شمسی ${persianDateLabel(_expiry!)}',
                        ),
                      ),
                    ),
                    if (_expiry != null)
                      IconButton(
                        tooltip: 'حذف تاریخ',
                        onPressed: () => setState(() => _expiry = null),
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
                if (_expiry != null)
                  DropdownButtonFormField<String>(
                    initialValue: _precision,
                    decoration: const InputDecoration(
                      labelText: 'دقت تاریخ (ماه فقط میلادی)',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'day', child: Text('روز دقیق')),
                      DropdownMenuItem(
                        value: 'month',
                        child: Text('فقط ماه و سال'),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _precision = value);
                            }
                          },
                  ),
                if (_expiry != null && _precision == 'month')
                  const Text(
                    'برای تاریخ با دقت ماه، همان ماه میلادیِ تاریخ انتخابی ثبت می‌شود.',
                  ),
                CheckboxListTile(
                  value: _selectNew,
                  title: const Text('این بسته برای کسر موجودی انتخاب شود'),
                  subtitle: const Text('بسته منقضی قابل انتخاب نیست.'),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _selectNew = value ?? false),
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
            Row(
              children: [
                const AppIconTile(Icons.inventory_2_outlined),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    pack.label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (selected) const Chip(label: Text('انتخاب‌شده')),
              ],
            ),
            Text(
              PersianDate.persianDigits(
                'باقی‌مانده: ${StockQuantity.format(item.balanceMilliunits)} ${pack.unit}',
              ),
            ),
            Text(
              PersianDate.persianDigits(
                pack.expiryIso == null
                    ? 'انقضا ثبت نشده'
                    : 'انقضا (میلادی): ${pack.expiryIso} '
                          '${pack.expiryPrecision == 'month' ? '(ماه/سال)' : '(روز)'}',
              ),
            ),
            if (expired)
              const Text(
                'هشدار: تاریخ انقضای ثبت‌شده گذشته است.',
                style: TextStyle(color: Colors.deepOrange),
              ),
            if (selected && summary.lowStock)
              const Text(
                'هشدار: موجودی بسته انتخاب‌شده کم است.',
                style: TextStyle(color: Colors.deepOrange),
              ),
            Wrap(
              spacing: 8,
              children: [
                if (!selected && !expired)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => widget.repository.selectPackage(
                              profileId: widget.profileId,
                              medicationId: widget.medication.id,
                              packageId: pack.id,
                            ),
                          ),
                    child: const Text('انتخاب برای مصرف'),
                  ),
                if (selected)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => widget.repository.clearSelection(
                              profileId: widget.profileId,
                              medicationId: widget.medication.id,
                            ),
                          ),
                    child: const Text('لغو انتخاب'),
                  ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _adjustingPackageId = _adjustingPackageId == pack.id
                              ? null
                              : pack.id;
                          _adjustQuantity.clear();
                          _adjustReason.clear();
                        }),
                  child: const Text('اصلاح موجودی'),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : () => _toggleHistory(pack.id),
                  icon: Icon(
                    _historyOpen.contains(pack.id)
                        ? Icons.expand_less
                        : Icons.history,
                  ),
                  label: const Text('تاریخچه موجودی'),
                ),
              ],
            ),
            if (_historyOpen.contains(pack.id)) ...[
              const Divider(),
              Text(
                'تاریخچه تغییرات این بسته',
                style: Theme.of(context).textTheme.titleSmall,
              ),
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
                      PersianDate.persianDigits(
                        '${entry.createdAt.toLocal().toString().substring(0, 16)}'
                        '${entry.note == null ? '' : ' — ${entry.note}'}',
                      ),
                    ),
                    trailing: Text(
                      PersianDate.persianDigits(
                        '${entry.deltaMilliunits > 0 ? '+' : ''}'
                        '${StockQuantity.format(entry.deltaMilliunits)} ${pack.unit}',
                      ),
                      style: TextStyle(
                        color: entry.deltaMilliunits < 0
                            ? Colors.deepOrange
                            : Colors.green,
                      ),
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
                onSelectionChanged: _busy
                    ? null
                    : (value) => setState(() => _adjustIncrease = value.first),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _adjustQuantity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
