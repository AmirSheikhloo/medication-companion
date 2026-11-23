import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/calendar/persian_date.dart';
import '../../../core/ui/english_digits_input_formatter.dart';
import '../../../core/ui/app_design.dart';
import '../../../core/ui/redesign_widgets.dart';
import '../../inventory/domain/stock_quantity.dart';
import '../data/medication_setup_repository.dart';
import 'medication_expiry_dialog.dart';

/// Each slot is an exact user-entered quantity; historical free-text slots
/// remain displayable, but are never used for automatic stock deduction.
class MedicationSlotDraft {
  const MedicationSlotDraft({required this.dose, required this.time,
    this.quantity});

  final String dose;
  final TimeOfDay time;
  final ScheduledQuantity? quantity;
}

class MedicationPackageDraft {
  const MedicationPackageDraft({required this.label, required this.unit,
    required this.initialMilliunits, this.expiry});

  final String label;
  final String unit;
  final int initialMilliunits;
  final DateTime? expiry;
}

class MedicationDraft {
  const MedicationDraft({required this.name, required this.slots,
    required this.packages, required this.reminderNote,
    required this.artwork, this.imagePath});

  final String name;
  final List<MedicationSlotDraft> slots;
  final List<MedicationPackageDraft> packages;
  final String reminderNote;
  final String artwork;
  final String? imagePath;
}

Future<MedicationDraft?> showMedicationEntrySheet(
  BuildContext context, {
  required String profileName,
  String? initialName,
  List<MedicationSlotDraft>? initialSlots,
  MedicationSetup? initialSetup,
}) => Navigator.of(context).push<MedicationDraft>(MaterialPageRoute(
  builder: (_) => _MedicationEntryScreen(
    profileName: profileName,
    initialName: initialName,
    initialSlots: initialSlots,
    initialSetup: initialSetup,
  ),
));

class _SlotEditor {
  _SlotEditor({required TimeOfDay time, String quantity = '1',
    this.unit = 'عدد'})
    : hour = TextEditingController(text: time.hour.toString().padLeft(2, '0')),
      minute = TextEditingController(text: time.minute.toString().padLeft(2, '0')),
      amount = TextEditingController(text: quantity);

  final TextEditingController hour;
  final TextEditingController minute;
  final TextEditingController amount;
  String unit;

  void dispose() {
    hour.dispose();
    minute.dispose();
    amount.dispose();
  }
}

class _PackageEditor {
  _PackageEditor({required this.number, this.unit = 'عدد'})
    : quantity = TextEditingController();

  final int number;
  final TextEditingController quantity;
  String unit;
  DateTime? expiry;

  void dispose() => quantity.dispose();
}

class _MedicationEntryScreen extends StatefulWidget {
  const _MedicationEntryScreen({required this.profileName,
    this.initialName, this.initialSlots, this.initialSetup});

  final String profileName;
  final String? initialName;
  final List<MedicationSlotDraft>? initialSlots;
  final MedicationSetup? initialSetup;

  @override
  State<_MedicationEntryScreen> createState() => _MedicationEntryScreenState();
}

class _MedicationEntryScreenState extends State<_MedicationEntryScreen> {
  late final TextEditingController _name;
  late final TextEditingController _reminderNote;
  late final List<_SlotEditor> _slots;
  final List<_SlotEditor> _retiredSlots = [];
  final List<_PackageEditor> _packages = [];
  final List<_PackageEditor> _retiredPackages = [];
  String _artwork = 'capsule';
  String? _imagePath;
  int _currentStep = 0;
  static const _stepLabels = <String>[
    'اطلاعات دارو', 'برنامه مصرف', 'موجودی', 'هشدار کمبود', 'یادآور',
  ];
  bool _lowStockEnabled = false;
  late final TextEditingController _lowStock;
  int? _calculatorPackage;
  final _strips = TextEditingController(text: '5');
  final _tabletsPerStrip = TextEditingController(text: '10');
  bool _notify = false;
  bool _alarm = false;
  bool _requestingPermission = false;

  bool get _editing => widget.initialName != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName ?? '');
    _reminderNote = TextEditingController(text: widget.initialSetup?.reminderNote ?? '');
    _lowStock = TextEditingController(text: '20');
    _artwork = widget.initialSetup?.artwork ?? 'capsule';
    _imagePath = widget.initialSetup?.localImagePath;
    final initial = widget.initialSlots;
    _slots = (initial == null || initial.isEmpty)
        ? [_SlotEditor(time: const TimeOfDay(hour: 8, minute: 0))]
        : [for (final slot in initial) _SlotEditor(
            time: slot.time,
            quantity: slot.quantity == null ? '1'
                : StockQuantity.format(slot.quantity!.milliunits),
            unit: slot.quantity?.unit ?? 'عدد',
          )];
    if (!_editing) _packages.add(_PackageEditor(number: 1));
  }

  @override
  void dispose() {
    _name.dispose();
    _reminderNote.dispose();
    _lowStock.dispose();
    _strips.dispose();
    _tabletsPerStrip.dispose();
    for (final slot in [..._slots, ..._retiredSlots]) { slot.dispose(); }
    for (final package in [..._packages, ..._retiredPackages]) {
      package.dispose();
    }
    super.dispose();
  }

  void _showError(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  void _normalizeClock(TextEditingController controller, int maximum) {
    final input = PersianDate.latinDigits(controller.text.trim());
    if (input.isEmpty) return;
    final number = int.tryParse(input);
    if (number == null) return;
    final normalized = number.clamp(0, maximum).toString().padLeft(2, '0');
    if (controller.text != normalized) controller.text = normalized;
  }

  int? _clockOf(_SlotEditor slot) {
    final hour = int.tryParse(PersianDate.latinDigits(slot.hour.text));
    final minute = int.tryParse(PersianDate.latinDigits(slot.minute.text));
    if (hour == null || minute == null || hour < 0 || hour > 24 ||
        minute < 0 || minute > 59 || (hour == 24 && minute != 0)) {
      return null;
    }
    return (hour == 24 ? 0 : hour) * 60 + minute;
  }

  void _addSlot() {
    if (_slots.length >= 24 * 60) {
      _showError('همهٔ ساعت‌های یکتای روز ثبت شده‌اند.');
      return;
    }
    final used = _slots.map(_clockOf).whereType<int>().toSet();
    var next = ((_clockOf(_slots.last) ?? 0) + 8 * 60) % (24 * 60);
    while (used.contains(next)) { next = (next + 1) % (24 * 60); }
    setState(() => _slots.add(_SlotEditor(
      time: TimeOfDay(hour: next ~/ 60, minute: next % 60),
      quantity: _slots.first.amount.text,
      unit: _slots.first.unit,
    )));
  }

  void _removeSlot(int index) {
    if (_slots.length == 1) return;
    setState(() => _retiredSlots.add(_slots.removeAt(index)));
  }

  void _addPackage() {
    setState(() => _packages.add(_PackageEditor(
      number: (_packages.isEmpty ? 0 : _packages.last.number) + 1,
      unit: _packages.first.unit,
    )));
  }

  void _removePackage(int index) {
    if (_packages.length == 1) return;
    setState(() => _retiredPackages.add(_packages.removeAt(index)));
  }

  Future<void> _chooseExpiry(_PackageEditor package) async {
    final date = await showMedicationExpiryDialog(context,
      initialDate: package.expiry);
    if (mounted && date != null) setState(() => package.expiry = date);
  }

  Future<void> _chooseArtwork() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('تصویر دارو', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 19, color: AppColors.primaryDark,
              fontWeight: FontWeight.w900)),
          const SizedBox(height: 9),
          const Text('انتخاب تصویر اختیاری است؛ در صورت انتخاب‌نکردن، نماد پیش‌فرض نمایش داده می‌شود.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
          const SizedBox(height: 14),
          for (final item in const [
            ('capsule', 'کپسول', Icons.medication_rounded),
            ('tablet', 'قرص', Icons.medication_outlined),
            ('liquid', 'داروی مایع', Icons.water_drop_outlined),
          ]) ListTile(
            leading: Icon(item.$3, color: AppColors.primary),
            title: Text(item.$2),
            trailing: _artwork == item.$1 && _imagePath == null
              ? const Icon(Icons.check_circle, color: AppColors.success) : null,
            onTap: () => Navigator.pop(context, item.$1),
          ),
          ListTile(
            leading: const Icon(Icons.add_photo_alternate_outlined,
              color: AppColors.primary),
            title: const Text('انتخاب عکس از گوشی'),
            onTap: () => Navigator.pop(context, 'gallery'),
          ),
        ]),
      )),
    );
    if (!mounted || choice == null) return;
    if (choice != 'gallery') {
      setState(() { _artwork = choice; _imagePath = null; });
      return;
    }
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 1200, maxHeight: 1200,
        imageQuality: 85);
      if (!mounted || image == null) return;
      if (await File(image.path).length() > 8 * 1024 * 1024) {
        _showError('عکس انتخابی بزرگ است؛ تصویری کوچک‌تر از 8 مگابایت انتخاب کن.');
        return;
      }
      setState(() => _imagePath = image.path);
    } catch (_) {
      if (mounted) _showError('انتخاب تصویر ممکن نشد؛ می‌توانی بدون عکس ادامه بدهی.');
    }
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 160) {
      _showError('نام دارو اجباری است و باید حداکثر 160 نویسه باشد.');
      return;
    }
    final packages = <MedicationPackageDraft>[];
    if (!_editing) {
      for (var index = 0; index < _packages.length; index++) {
        final item = _packages[index];
        int quantity;
        try {
          quantity = StockQuantity.parsePositive(item.quantity.text);
        } on FormatException {
          _showError('موجودی بستهٔ ${PersianDate.displayDigits('${index + 1}')} را به‌صورت عدد مثبت وارد کن.');
          return;
        } on ArgumentError {
          _showError('موجودی بستهٔ ${PersianDate.displayDigits('${index + 1}')} معتبر نیست.');
          return;
        }
        if (item.expiry != null && StockQuantity.isExpired(
            StockQuantity.isoDate(item.expiry!), 'day', DateTime.now())) {
          _showError('⚠️ تاریخ انقضا گذشته است؛ از مصرف داروی منقضی خودداری کن.');
          return;
        }
        packages.add(MedicationPackageDraft(
          label: 'بسته شماره ${PersianDate.displayDigits('${index + 1}')}',
          unit: item.unit,
          initialMilliunits: quantity,
          expiry: item.expiry,
        ));
      }
    }
    final slots = <MedicationSlotDraft>[];
    final used = <int>{};
    for (var i = 0; i < _slots.length; i++) {
      final item = _slots[i];
      _normalizeClock(item.hour, 24);
      _normalizeClock(item.minute, 59);
      final minuteOfDay = _clockOf(item);
      if (minuteOfDay == null) {
        _showError('زمان نوبت ${PersianDate.displayDigits('${i + 1}')} معتبر نیست. ساعت 24 فقط با دقیقهٔ 00 مجاز است.');
        return;
      }
      if (!used.add(minuteOfDay)) {
        _showError('ساعت مصرف تکراری است؛ هر ساعت را فقط یک‌بار وارد کن.');
        return;
      }
      int quantity;
      try {
        quantity = StockQuantity.parsePositive(item.amount.text);
      } on FormatException {
        _showError('مقدار مصرف نوبت ${PersianDate.displayDigits('${i + 1}')} معتبر نیست.');
        return;
      } on ArgumentError {
        _showError('مقدار مصرف هر نوبت باید عددی مثبت باشد.');
        return;
      }
      final dose = ScheduledQuantity(milliunits: quantity, unit: item.unit);
      for (final package in packages) {
        if (MedicationUnits.toPackageMilliunits(dose, package.unit) == null) {
          _showError('واحد مصرف «${item.unit}» با موجودی «${package.unit}» قابل تبدیل نیست. '
            'برای هر بسته و نوبت واحد سازگار انتخاب کن.');
          return;
        }
      }
      slots.add(MedicationSlotDraft(
        time: TimeOfDay(hour: minuteOfDay ~/ 60,
          minute: minuteOfDay % 60),
        quantity: dose,
        dose: '${StockQuantity.format(quantity)} ${item.unit}',
      ));
    }
    if (_reminderNote.text.trim().length > 500) {
      _showError('توضیح یادآور باید حداکثر 500 نویسه باشد.');
      return;
    }
    Navigator.of(context).pop(MedicationDraft(
      name: name, slots: slots, packages: packages,
      reminderNote: _reminderNote.text.trim(),
      artwork: _artwork, imagePath: _imagePath,
    ));
  }

  Widget _numberField(TextEditingController controller,
      {required String label, required String hint, int? maxLength,
      String? keyName}) =>
    TextField(
      controller: controller,
      key: keyName == null ? ValueKey(controller) : ValueKey(keyName),
      textDirection: TextDirection.ltr,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [const EnglishDigitsInputFormatter(), FilteringTextInputFormatter.allow(RegExp(r'[0-9۰-۹٠-٩.٫]'))],
      maxLength: maxLength,
      decoration: InputDecoration(labelText: label, hintText: hint,
        counterText: '', border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14))),
    );

  Widget _unitSelector(String value, ValueChanged<String> onChanged,
      {bool showGroup = true}) {
    final units = showGroup ? MedicationUnits.supported :
        MedicationUnits.isLiquid(value)
          ? MedicationUnits.liquid : MedicationUnits.count;
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      items: [for (final unit in units)
        DropdownMenuItem(value: unit, child: Text(unit,
          style: const TextStyle(fontSize: 13)))],
      onChanged: (unit) { if (unit != null) onChanged(unit); },
      decoration: InputDecoration(labelText: 'واحد',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
    );
  }

  Widget _packageCard(int index) {
    final item = _packages[index];
    final liquid = MedicationUnits.isLiquid(item.unit);
    return Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.lightMint,
        borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: Text(PersianDate.displayDigits('بسته شماره ${index + 1}'),
            style: const TextStyle(color: AppColors.primaryDark,
              fontWeight: FontWeight.w900, fontSize: 16))),
          if (_packages.length > 1) IconButton(
            tooltip: 'حذف این بسته',
            onPressed: () => _removePackage(index),
            icon: const Icon(Icons.delete_outline, color: Color(0xFFBD4355))),
        ]),
        const SizedBox(height: 9),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('تعدادی')),
            ButtonSegment(value: true, label: Text('حجمی / مایع')),
          ],
          selected: {liquid},
          onSelectionChanged: (values) {
            final before = item.unit;
            setState(() {
              item.unit = values.first ? 'میلی‌لیتر' : 'عدد';
              if (index == 0) {
                for (final slot in _slots) {
                  if (slot.unit == before) slot.unit = item.unit;
                }
              }
            });
          },
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(flex: 3, child: _numberField(item.quantity,
            label: 'مقدار موجودی *', hint: liquid ? 'مثلاً 1000' : 'مثلاً 100',
            keyName: 'med-stock-${index + 1}')),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: _unitSelector(item.unit,
            (value) {
              final previous = item.unit;
              setState(() {
                item.unit = value;
                if (index == 0) {
                  for (final slot in _slots) {
                    if (slot.unit == previous) slot.unit = value;
                  }
                }
              });
            },
            showGroup: false)),
        ]),
        const SizedBox(height: 8),
        if (item.expiry == null)
          Align(alignment: Alignment.centerRight, child: TextButton.icon(
            onPressed: () => _chooseExpiry(item),
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('افزودن تاریخ انقضا (اختیاری)'),
          ))
        else Row(children: [
          const Icon(Icons.event_available_outlined,
            color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text('انقضا: ${persianDateLabel(item.expiry!)}',
            style: const TextStyle(fontWeight: FontWeight.bold))),
          IconButton(onPressed: () => _chooseExpiry(item),
            tooltip: 'تغییر تاریخ', icon: const Icon(Icons.edit_outlined)),
          IconButton(onPressed: () => setState(() => item.expiry = null),
            tooltip: 'حذف تاریخ', icon: const Icon(Icons.close)),
        ]),
      ],
    ));
  }

  Widget _timeField(TextEditingController controller, String label,
      int maximum) => SizedBox(width: 74, child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        keyboardType: TextInputType.number,
        maxLength: 2,
        inputFormatters: [const EnglishDigitsInputFormatter(),
          FilteringTextInputFormatter.allow(
            RegExp(r'[0-9۰-۹٠-٩]')),
          LengthLimitingTextInputFormatter(2)],
        onChanged: (value) {
          final normalized = PersianDate.latinDigits(value);
          if (value.length == 2 && int.tryParse(normalized) != null &&
              int.parse(normalized) > maximum) {
            controller.text = maximum.toString().padLeft(2, '0');
          }
        },
        onTapOutside: (_) => _normalizeClock(controller, maximum),
        onEditingComplete: () {
          _normalizeClock(controller, maximum);
          FocusScope.of(context).nextFocus();
        },
        decoration: InputDecoration(labelText: label, counterText: '',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
      ));

  Widget _slotCard(int index) {
    final slot = _slots[index];
    return AppPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
      Row(children: [
        Expanded(child: Text(PersianDate.displayDigits('نوبت ${index + 1}'),
          style: const TextStyle(color: AppColors.primaryDark,
            fontWeight: FontWeight.w900))),
        if (_slots.length > 1) IconButton(
          tooltip: 'حذف نوبت', onPressed: () => _removeSlot(index),
          icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFBD4355))),
      ]),
      const SizedBox(height: 7),
      Row(children: [
        const Icon(Icons.schedule_rounded, color: AppColors.primary),
        const SizedBox(width: 12),
        const Expanded(child: Text('ساعت مصرف', style: TextStyle(
          fontWeight: FontWeight.bold))),
        Directionality(textDirection: TextDirection.ltr,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _timeField(slot.hour, 'ساعت', 24),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(':', style: TextStyle(fontSize: 20,
                color: AppColors.primaryDark))),
            _timeField(slot.minute, 'دقیقه', 59),
          ])),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(flex: 3, child: _numberField(slot.amount,
          label: 'مقدار مصرف این نوبت *', hint: 'مثلاً 1',
          keyName: 'med-dose-${index + 1}')),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: _unitSelector(slot.unit,
          (value) => setState(() => slot.unit = value))),
      ]),
    ]));
  }


  bool _validateCurrent() {
    if (_currentStep == 0 && _name.text.trim().isEmpty) {
      _showError('نام دارو را وارد کن.');
      return false;
    }
    if (_currentStep == 1) {
      final unique = <int>{};
      for (final slot in _slots) {
        _normalizeClock(slot.hour, 24);
        _normalizeClock(slot.minute, 59);
        final time = _clockOf(slot);
        if (time == null || !unique.add(time)) {
          _showError('ساعت تکراری یا نامعتبر است.');
          return false;
        }
        try { StockQuantity.parsePositive(slot.amount.text); }
        catch (_) {
          _showError('مقدار مصرف هر نوبت باید عددی مثبت باشد.');
          return false;
        }
      }
    }
    if (_currentStep == 2 && !_editing) {
      for (final pack in _packages) {
        try { StockQuantity.parsePositive(pack.quantity.text); }
        catch (_) {
          _showError('موجودی بسته باید عددی مثبت باشد.');
          return false;
        }
        if (pack.expiry != null && StockQuantity.isExpired(
          StockQuantity.isoDate(pack.expiry!), 'day', DateTime.now())) {
          _showError('تاریخ انقضا گذشته؛ از مصرف داروی منقضی خودداری کن.');
          return false;
        }
      }
    }
    return true;
  }

  void _nextStep() {
    if (!_validateCurrent()) return;
    FocusScope.of(context).unfocus();
    if (_currentStep == 4) { _submit(); return; }
    setState(() => _currentStep++);
  }

  Widget _wizardProgress() {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return SingleChildScrollView(
      key: const Key('medication-wizard-progress'),
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (var index = 0; index < _stepLabels.length; index++)
          SizedBox(width: scale > 1.4 ? 105 : 70,
            child: InkWell(
              onTap: index < _currentStep
                  ? () => setState(() => _currentStep = index) : null,
              borderRadius: BorderRadius.circular(14),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AnimatedContainer(duration: const Duration(milliseconds: 240),
                  height: 42, width: 42,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    color: index == _currentStep ? AppColors.primary
                      : index < _currentStep ? AppColors.mint
                      : const Color(0xFFE8F0F1)),
                  alignment: Alignment.center,
                  child: index < _currentStep
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : Text('${index + 1}', style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: index == _currentStep
                        ? Colors.white : AppColors.primaryDark))),
                const SizedBox(height: 5),
                Text(_stepLabels[index], maxLines: 2,
                  textAlign: TextAlign.center, style: TextStyle(
                    fontSize: 10,
                    fontWeight: index == _currentStep
                        ? FontWeight.bold : FontWeight.normal,
                    color: index == _currentStep
                        ? AppColors.primaryDark : AppColors.muted)),
              ]),
            )),
      ]),
    );
  }

  Widget _nameStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const AppSectionHeading('اطلاعات دارو', icon: Icons.medication_outlined),
      const SizedBox(height: 9),
      const Text('نام دارو را مانند نسخه وارد کن؛ تصویر اختیاری است.',
        style: TextStyle(color: AppColors.muted)),
      const SizedBox(height: 20),
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        InkWell(onTap: _chooseArtwork,
          key: const Key('medication-image-picker'),
          borderRadius: BorderRadius.circular(18),
          child: Stack(children: [
            ClipRRect(borderRadius: BorderRadius.circular(18),
              child: _imagePath == null
                ? MedicineArtwork(seed: _artwork, size: 76)
                : Image.file(File(_imagePath!), width: 76, height: 76,
                  fit: BoxFit.cover, errorBuilder: (_, _, _) =>
                    MedicineArtwork(seed: _artwork, size: 76))),
            const Positioned(left: 0, bottom: 0,
              child: CircleAvatar(radius: 13,
                backgroundColor: AppColors.primary,
                child: Icon(Icons.add, color: Colors.white, size: 18))),
          ])),
        const SizedBox(width: 12),
        Expanded(child: SizedBox(height: 76, child: TextField(
          key: const Key('medication-name-field'),
          controller: _name,
          maxLength: 160,
          inputFormatters: const [EnglishDigitsInputFormatter()],
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            filled: true, fillColor: AppColors.mint,
            labelText: 'نام دارو *', hintText: 'مثلاً استامینوفن 500',
            counterText: '',
            border: OutlineInputBorder(borderRadius:
              BorderRadius.circular(18), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius:
              BorderRadius.circular(18), borderSide: BorderSide.none),
          ),
        ))),
      ]),
    ],
  );

  Widget _scheduleStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const AppSectionHeading('برنامه مصرف', icon: Icons.schedule_outlined),
      const SizedBox(height: 8),
      const Text('زمان و مقدار هر نوبت را مشخص کن.',
        maxLines: 2, style: TextStyle(color: AppColors.muted)),
      const SizedBox(height: 14),
      for (var i = 0; i < _slots.length; i++) ...[
        _slotCard(i), const SizedBox(height: 10),
      ],
      FilledButton.tonalIcon(onPressed: _addSlot,
        icon: const Icon(Icons.add_alarm),
        label: const Text('افزودن ساعت مصرف')),
    ],
  );

  Widget _stockStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const AppSectionHeading('موجودی', icon: Icons.inventory_2_outlined),
      const SizedBox(height: 9),
      const Text('ورق و بسته فقط برای محاسبه هستند؛ '
        'کسر موجودی همیشه با تعداد یا حجم انجام می‌شود.',
        style: TextStyle(color: AppColors.muted)),
      const SizedBox(height: 16),
      if (_editing)
        const Text('برای حفظ سوابق موجودی، بسته‌های قبلی را از صفحهٔ '
          'جزئیات دارو مدیریت کن.')
      else ...[
        for (var i = 0; i < _packages.length; i++) ...[
          _packageCard(i), const SizedBox(height: 9),
        ],
        OutlinedButton.icon(onPressed: _addPackage,
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('افزودن بسته جدید')),
      ],
    ],
  );

  Widget _lowStockStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const AppSectionHeading('هشدار کمبود', icon: Icons.inventory_outlined),
      const SizedBox(height: 10),
      const Text('اگر موجودی بسته انتخابی به حد تعیین‌شده برسد، '
        'در برنامه با نشان کمبود مشخص می‌شود.',
        style: TextStyle(color: AppColors.muted)),
      const SizedBox(height: 13),
      SwitchListTile.adaptive(contentPadding: EdgeInsets.zero,
        title: const Text('فعال‌سازی هشدار کمبود'),
        value: _lowStockEnabled,
        onChanged: (value) => setState(() => _lowStockEnabled = value)),
      if (_lowStockEnabled) ...[
        const SizedBox(height: 10),
        _numberField(_lowStock, label: 'حد هشدار',
          hint: 'مثلاً 20', keyName: 'medication-low-stock-threshold'),
      ],
    ],
  );

  Widget _reminderStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const AppSectionHeading('یادآور', icon: Icons.notifications_active_outlined),
      const SizedBox(height: 10),
      const Text('اعلان و هشدار تمام‌صفحه اختیاری هستند؛ '
        'می‌توانی مصرف را فقط داخل برنامه ثبت کنی.',
        style: TextStyle(color: AppColors.muted)),
      const SizedBox(height: 15),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('اعلان یادآوری'),
        value: _notify,
        onChanged: _requestingPermission ? null
            : (v) => setState(() {
                _notify = v;
                if (!v) _alarm = false;
              })),
      const Divider(color: AppColors.outline),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('هشدار تمام‌صفحه'),
        subtitle: const Text('در صورت پشتیبانی گوشی و داشتن مجوز'),
        value: _alarm,
        onChanged: _requestingPermission ? null
            : (v) => setState(() {
                _alarm = v;
                if (v) _notify = true;
              })),
      if (_alarm) ...[
        const SizedBox(height: 12),
        const Text('توضیح اختیاری زیر هنگام نمایش هشدار نشان داده می‌شود.',
          style: TextStyle(color: AppColors.muted)),
        TextField(controller: _reminderNote, maxLines: 3, maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'متن هشدار (اختیاری)',
            hintText: 'مثلاً با آب فراوان مصرف شود')),
      ],
    ],
  );

  Widget _stepBody() => switch (_currentStep) {
    0 => _nameStep(),
    1 => _scheduleStep(),
    2 => _stockStep(),
    3 => _lowStockStep(),
    _ => _reminderStep(),
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      title: Text(_editing ? 'ویرایش دارو' : 'افزودن دارو'),
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.primaryDark,
    ),
    bottomNavigationBar: SafeArea(top: false, child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 12),
      child: Row(children: [
        if (_currentStep != 0) ...[
          Expanded(child: OutlinedButton.icon(
            key: const Key('medication-step-back'),
            onPressed: () => setState(() => _currentStep--),
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            label: const Text('قبلی'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: AppColors.mint),
          )),
          const SizedBox(width: 9),
        ],
        Expanded(flex: 2, child: AppGradientButton(
          label: _currentStep == 4
              ? (_editing ? 'ذخیره تغییرات' : 'ثبت دارو')
              : 'مرحله بعد',
          icon: _currentStep == 4
            ? Icons.check_circle_outline : Icons.arrow_back_rounded,
          onPressed: _nextStep, light: true, height: 50,
        )),
      ]),
    )),
    body: Column(children: [
      Padding(padding: const EdgeInsets.only(top: 10, bottom: 12),
        child: _wizardProgress()),
      const Divider(color: AppColors.outline, height: 1),
      Expanded(child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.08, 0), end: Offset.zero)
                .animate(animation),
            child: child)),
        child: SingleChildScrollView(
          key: ValueKey<int>(_currentStep),
          padding: const EdgeInsets.fromLTRB(17, 22, 17, 32),
          child: _stepBody(),
        ),
      )),
    ]),
  );
}
