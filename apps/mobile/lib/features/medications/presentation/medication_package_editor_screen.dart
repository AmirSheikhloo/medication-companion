
import 'package:material_ui/material_ui.dart';

import '../../../core/calendar/persian_date.dart';
import '../../../core/ui/app_design.dart';
import '../../../core/ui/english_digits_input_formatter.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/stock_quantity.dart';
import 'medication_expiry_dialog.dart';

/// All package corrections retain the existing append-only stock ledger.
class MedicationPackageEditorScreen extends StatefulWidget {
  const MedicationPackageEditorScreen({super.key,
    required this.repository, required this.profileId,
    required this.medicationId, required this.packageNumber,
    required this.unit, this.existing, this.selected = false});

  final InventoryRepository repository;
  final String profileId;
  final String medicationId;
  final int packageNumber;
  final String unit;
  final PackageBalance? existing;
  final bool selected;

  @override
  State<MedicationPackageEditorScreen> createState() =>
      _MedicationPackageEditorScreenState();
}

class _MedicationPackageEditorScreenState
    extends State<MedicationPackageEditorScreen> {
  late final TextEditingController _label;
  late final TextEditingController _quantity;
  final TextEditingController _reason = TextEditingController();
  DateTime? _expiry;
  bool _selectForUse = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: widget.existing?.package.label ??
        'بسته شماره ${widget.packageNumber}');
    _quantity = TextEditingController(text: widget.existing == null ? '' :
        StockQuantity.format(widget.existing!.balanceMilliunits));
    final rawExpiry = widget.existing?.package.expiryIso;
    _expiry = rawExpiry == null ? null : StockQuantity.parseIso(rawExpiry);
    _selectForUse = widget.selected;
  }

  @override
  void dispose() {
    _label.dispose();
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _chooseExpiry() async {
    final result = await showMedicationExpiryDialog(context, initialDate: _expiry);
    if (mounted && result != null) setState(() => _expiry = result);
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await work();
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error =
        'عملیات انجام نشد؛ مقدارها و مجوز این بسته را بررسی کن. $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final label = _label.text.trim();
    if (label.isEmpty || label.length > 80) {
      setState(() => _error = 'نام بسته باید بین 1 تا 80 نویسه باشد.');
      return;
    }
    int quantity;
    try { quantity = StockQuantity.parseNonNegative(_quantity.text); }
    catch (_) {
      setState(() => _error = 'موجودی معتبر با حداکثر سه رقم اعشار وارد کن.');
      return;
    }
    final now = DateTime.now();
    if (_expiry != null &&
        _expiry!.isBefore(DateTime(now.year, now.month, now.day))) {
      setState(() => _error =
          'این تاریخ گذشته است؛ از مصرف داروی منقضی خودداری کن.');
      return;
    }
    final existing = widget.existing;
    final delta = existing == null ? 0 : quantity - existing.balanceMilliunits;
    if (delta != 0 && _reason.text.trim().isEmpty) {
      setState(() => _error = 'برای تغییر موجودی، دلیل اصلاح را بنویس.');
      return;
    }
    await _run(() => widget.repository.db.transaction(() async {
      if (existing == null) {
        await widget.repository.addPackage(
          profileId: widget.profileId, medicationId: widget.medicationId,
          label: label, unit: widget.unit, initialMilliunits: quantity,
          expiryIso: _expiry == null ? null : StockQuantity.isoDate(_expiry!),
          expiryPrecision: _expiry == null ? 'none' : 'day',
          selectForUse: _selectForUse,
        );
      } else {
        await widget.repository.editPackage(
          profileId: widget.profileId, medicationId: widget.medicationId,
          packageId: existing.package.id, label: label,
          expiryIso: _expiry == null ? null : StockQuantity.isoDate(_expiry!),
          expiryPrecision: _expiry == null ? 'none' : 'day');
        if (delta != 0) {
          await widget.repository.adjustPackage(
            profileId: widget.profileId, medicationId: widget.medicationId,
            packageId: existing.package.id, deltaMilliunits: delta,
            reason: _reason.text.trim());
        }
        if (!_selectForUse && widget.selected) {
          await widget.repository.clearSelection(profileId: widget.profileId,
            medicationId: widget.medicationId);
        }
        if (_selectForUse && !widget.selected && !existing.archived) {
          await widget.repository.selectPackage(
            profileId: widget.profileId, medicationId: widget.medicationId,
            packageId: existing.package.id);
        }
      }
    }));
  }

  Future<void> _archiveOrRestore() async {
    final pack = widget.existing;
    if (pack == null) return;
    await _run(() => pack.archived
      ? widget.repository.restorePackage(profileId: widget.profileId,
          medicationId: widget.medicationId, packageId: pack.package.id)
      : widget.repository.archivePackage(profileId: widget.profileId,
          medicationId: widget.medicationId, packageId: pack.package.id));
  }

  Future<void> _delete() async {
    final pack = widget.existing;
    if (pack == null) return;
    final agreed = await showDialog<bool>(context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف بسته'),
        content: const Text('فقط بستهٔ بدون سابقهٔ موجودی یا مصرف '
          'قابل حذف است. بسته‌های دارای سابقه باید بایگانی شوند.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف بسته')),
        ]));
    if (!mounted || agreed != true) return;
    await _run(() => widget.repository.deleteUnusedPackage(
      profileId: widget.profileId, medicationId: widget.medicationId,
      packageId: pack.package.id));
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(existing == null
          ? 'افزودن بسته جدید' : 'جزئیات بسته')),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
        children: [
          const Text('مشخصات بسته', style: TextStyle(
            fontSize: 21, fontWeight: FontWeight.w900,
            color: AppColors.primaryDark)),
          const SizedBox(height: 7),
          const Text('هر اصلاح موجودی به‌صورت رویداد جداگانه ثبت می‌شود؛ '
            'مصرف‌های قبلی تغییر نمی‌کنند.',
            style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 20),
          TextField(controller: _label,
            inputFormatters: const [EnglishDigitsInputFormatter()],
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'نام بسته')),
          const SizedBox(height: 12),
          TextField(controller: _quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [EnglishDigitsInputFormatter()],
            decoration: InputDecoration(
              labelText: 'موجودی فعلی (${widget.unit})')),
          if (existing != null) ...[
            const SizedBox(height: 10),
            TextField(controller: _reason, maxLength: 240,
              decoration: const InputDecoration(
                labelText: 'دلیل اصلاح موجودی (در صورت تغییر)')),
          ],
          const SizedBox(height: 12),
          FilledButton.tonalIcon(onPressed: _busy ? null : _chooseExpiry,
            icon: const Icon(Icons.event_outlined),
            label: Text(_expiry == null ? 'افزودن تاریخ انقضا (اختیاری)'
              : 'انقضا: ${persianDateLabel(_expiry!)}')),
          if (_expiry != null)
            Align(alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _busy ? null : () => setState(() => _expiry = null),
                icon: const Icon(Icons.close),
                label: const Text('حذف تاریخ انقضا'))),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('انتخاب برای مصرف'),
            subtitle: const Text('کسر موجودی از این بسته انجام شود.'),
            value: _selectForUse,
            onChanged: _busy || existing?.archived == true ? null
              : (v) => setState(() => _selectForUse = v)),
          if (existing?.expired == true)
            const Text('این بسته منقضی شده است و برای مصرف قابل انتخاب نیست.',
              style: TextStyle(color: Color(0xFFB43B4D))),
          if (_error != null)
            Padding(padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_error!, style:
                const TextStyle(color: Color(0xFFC3353A)))),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: _busy ? null : _save,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('ذخیره تغییرات')),
          if (existing != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(onPressed: _busy ? null : _archiveOrRestore,
              icon: Icon(existing.archived ? Icons.unarchive_outlined
                : Icons.inventory_outlined),
              label: Text(existing.archived ? 'بازیابی بسته'
                : 'پایان استفاده از این بسته')),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline),
              style: FilledButton.styleFrom(backgroundColor:
                const Color(0xFFFBE5E7), foregroundColor:
                const Color(0xFFB43B4D)),
              label: const Text('حذف بستهٔ بدون سابقه')),
          ],
        ]),
    );
  }
}
