import 'package:material_ui/material_ui.dart';

import '../../../core/storage/app_database.dart';
import '../data/inventory_repository.dart';
import '../domain/stock_quantity.dart';

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
  final _label = TextEditingController();
  final _unit = TextEditingController();
  final _initial = TextEditingController();
  final _threshold = TextEditingController();
  final _adjustQuantity = TextEditingController();
  final _adjustReason = TextEditingController();

  StockSummary? _summary;
  bool _busy = false;
  bool _initializedThreshold = false;
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
        widget.profileId, widget.medication.id);
      if (!mounted) return;
      if (!_initializedThreshold) {
        _threshold.text = current.thresholdMilliunits == null
            ? ''
            : StockQuantity.format(current.thresholdMilliunits!);
        _initializedThreshold = true;
      }
      setState(() {
        _summary = current;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ثبت نشد: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseExpiry() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _expiry ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'تاریخ انقضا (میلادی)',
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
            : StockQuantity.isoDate(_precision == 'month'
                ? DateTime(_expiry!.year, _expiry!.month) : _expiry!),
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
    });
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
              const SizedBox(height: 12),
              if (summary == null)
                const Center(child: CircularProgressIndicator())
              else ...[
                if (summary.packages.isEmpty)
                  const ListTile(title: Text('هنوز بسته‌ای ثبت نشده است.')),
                for (final item in summary.packages) _packageCard(item, summary),
                const SizedBox(height: 16),
                Text('هشدار کمبود بسته انتخاب‌شده',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                TextField(
                  controller: _threshold,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'حد هشدار (خالی = خاموش)',
                    helperText: 'برای مثال ۵؛ تعداد روز تخمین زده نمی‌شود.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 6),
                OutlinedButton(
                  onPressed: _busy ? null : _saveThreshold,
                  child: const Text('ذخیره حد هشدار'),
                ),
                const Divider(height: 32),
                Text('افزودن بسته جدید',
                    style: Theme.of(context).textTheme.titleMedium),
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
                Row(children: [
                  Expanded(child: TextField(
                    controller: _initial,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'موجودی واقعی اولیه',
                      border: OutlineInputBorder(),
                    ),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(
                    controller: _unit,
                    decoration: const InputDecoration(
                      labelText: 'واحد (مثلاً عدد یا ml)',
                      border: OutlineInputBorder(),
                    ),
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
                          : StockQuantity.isoDate(_expiry!)),
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
                      labelText: 'دقت تاریخ (میلادی)',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'day', child: Text('روز دقیق')),
                      DropdownMenuItem(value: 'month', child: Text('فقط ماه و سال')),
                    ],
                    onChanged: _busy ? null : (value) {
                      if (value != null) setState(() => _precision = value);
                    },
                  ),
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
            ]),
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
