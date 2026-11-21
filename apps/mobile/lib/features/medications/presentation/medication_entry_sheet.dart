import 'package:material_ui/material_ui.dart';
import '../../../core/input/persian_quantity_formatter.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/stock_quantity.dart';
import '../../inventory/domain/stock_unit_presets.dart';

/// A user's own description for one daily occurrence.
class MedicationSlotDraft {
  const MedicationSlotDraft({required this.dose, required this.time});
  final String dose;
  final TimeOfDay time;
}

class MedicationDraft {
  const MedicationDraft({required this.name, required this.slots,
    required this.debitUnit, required this.debitQuantityMilliunits});

  final String name;
  final List<MedicationSlotDraft> slots;
  final String debitUnit;
  final int debitQuantityMilliunits;
}

Future<MedicationDraft?> showMedicationEntrySheet(
  BuildContext context, {
  required String profileName,
  String? initialName,
  List<MedicationSlotDraft>? initialSlots,
  DoseDebitPreset? initialDebitPreset,
}) =>
    showModalBottomSheet<MedicationDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MedicationEntrySheet(
        profileName: profileName,
        initialName: initialName,
        initialSlots: initialSlots,
        initialDebitPreset: initialDebitPreset,
      ),
    );

class _SlotEditor {
  _SlotEditor({required this.time, String dose = ''})
      : doseController = TextEditingController(text: dose);

  TimeOfDay time;
  final TextEditingController doseController;
}

/// Controllers are owned for the entire lifetime of the bottom-sheet route.
/// Removing a row only retires its controller until the route unmounts.
class _MedicationEntrySheet extends StatefulWidget {
  const _MedicationEntrySheet({
    required this.profileName,
    this.initialName,
    this.initialSlots,
    this.initialDebitPreset,
  });

  final String profileName;
  final String? initialName;
  final List<MedicationSlotDraft>? initialSlots;
  final DoseDebitPreset? initialDebitPreset;

  @override
  State<_MedicationEntrySheet> createState() => _MedicationEntrySheetState();
}

class _MedicationEntrySheetState extends State<_MedicationEntrySheet> {
  late final TextEditingController _name;
  late final TextEditingController _debitQuantityController;
  late final List<_SlotEditor> _slots;
  final List<_SlotEditor> _retired = [];
  String _debitUnit = 'عدد';
  String? _formError;

  bool get _editing => widget.initialName != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName ?? '');
    final preset = widget.initialDebitPreset;
    _debitQuantityController = TextEditingController(
      text: PersianQuantityFormatter.display(
          StockQuantity.format(preset?.quantityMilliunits ?? 1000)),
    );
    if (preset != null) {
      _debitUnit = preset.unit;
    }
    final initial = widget.initialSlots;
    _slots = (initial == null || initial.isEmpty)
        ? [
            _SlotEditor(time: const TimeOfDay(hour: 8, minute: 0)),
          ]
        : [
            for (final slot in initial)
              _SlotEditor(time: slot.time, dose: slot.dose),
          ];
  }

  @override
  void dispose() {
    _name.dispose();
    _debitQuantityController.dispose();
    for (final slot in [..._slots, ..._retired]) {
      slot.doseController.dispose();
    }
    super.dispose();
  }

  Future<void> _pickTime(int index) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _slots[index].time,
    );
    if (picked != null && mounted && index < _slots.length) {
      setState(() => _slots[index].time = picked);
    }
  }

  void _addSlot() {
    if (_slots.length == 12) {
      _showError('حداکثر ۱۲ نوبت در روز قابل ثبت است.');
      return;
    }
    final used = {
      for (final slot in _slots) slot.time.hour * 60 + slot.time.minute,
    };
    final last = _slots.last.time;
    var next = (last.hour * 60 + last.minute + 8 * 60) % (24 * 60);
    while (used.contains(next)) {
      next = (next + 1) % (24 * 60);
    }
    setState(() => _slots.add(_SlotEditor(
          time: TimeOfDay(hour: next ~/ 60, minute: next % 60),
          dose: _slots.last.doseController.text,
        )));
  }

  void _removeSlot(int index) {
    if (_slots.length <= 1) return;
    setState(() => _retired.add(_slots.removeAt(index)));
  }

  void _showError(String message) {
    setState(() => _formError = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 160) {
      _showError('نام دارو باید بین ۱ تا ۱۶۰ نویسه باشد.');
      return;
    }
    late final int debitQuantity;
    try {
      debitQuantity = StockQuantity.parsePositive(_debitQuantityController.text);
      if (debitQuantity > PersianQuantityFormatter.maxMilliunits) {
        throw const FormatException('Quantity too large');
      }
    } catch (_) {
      _showError('مقدار مصرف باید عددی، بزرگ‌تر از صفر و حداکثر '
          '۵ رقم صحیح با ۳ رقم اعشار باشد.');
      return;
    }
    final used = <int>{};
    final values = <MedicationSlotDraft>[];
    for (final slot in _slots) {
      final dose = slot.doseController.text.trim();
      if (dose.length > 120) {
        _showError('توضیح هر نوبت نباید بیشتر از ۱۲۰ نویسه باشد.');
        return;
      }
      if (!used.add(slot.time.hour * 60 + slot.time.minute)) {
        _showError('ساعت نوبت‌ها نباید تکراری باشد.');
        return;
      }
      values.add(MedicationSlotDraft(
        dose: dose.isEmpty
            ? StockUnitPresets.quantityLabel(debitQuantity, _debitUnit)
            : dose,
        time: slot.time,
      ));
    }
    Navigator.of(context).pop(MedicationDraft(
      name: name, slots: values,
      debitUnit: _debitUnit, debitQuantityMilliunits: debitQuantity,
    ));
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _editing
                      ? 'ویرایش داروی ${widget.profileName}'
                      : 'افزودن دارو برای ${widget.profileName}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(_editing
                    ? 'ویرایش ساعت‌ها و شرح نوبت‌ها از فردا اعمال می‌شود. سوابق امروز حفظ می‌شوند.'
                    : 'ساعت و شرح هر نوبت را فقط طبق نسخه ثبت کنید؛ برنامه مقدار مصرف پیشنهاد نمی‌کند.'),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  maxLength: 160,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'نام دارو',
                    hintText: 'نام روی نسخه یا جعبه',
                  ),
                ),
                const SizedBox(height: 6),
                Text('مقدار پیش‌فرض در هر ثبت مصرف',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _debitUnit,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'واحد مصرف', border: OutlineInputBorder()),
                      items: [
                        for (final unit in StockUnitPresets.units)
                          DropdownMenuItem(value: unit, child: Text(unit)),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _debitUnit = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('medication-quantity-input'),
                      controller: _debitQuantityController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: const [PersianQuantityFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'مقدار کسر',
                        hintText: 'مثلاً ۱ یا ۲۰٫۵',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        if (_formError != null) setState(() => _formError = null);
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                const Text('مقدار باید بزرگ‌تر از صفر باشد؛ حروف و اعداد خیلی بزرگ پذیرفته نمی‌شوند. '
                    'این مقدار فقط پیش‌فرض کسر موجودی است؛ '
                    'هنگام ثبت مصرف قابل بازبینی است و باید با واحد بسته یکسان باشد.',
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                const SizedBox(height: 8),
                for (var i = 0; i < _slots.length; i++) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text('نوبت ${i + 1}',
                            style: Theme.of(context).textTheme.titleSmall),
                      ),
                      if (_slots.length > 1)
                        IconButton(
                          tooltip: 'حذف نوبت ${i + 1}',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => _removeSlot(i),
                        ),
                    ],
                  ),
                  TextField(
                    controller: _slots[i].doseController,
                    maxLength: 120,
                    decoration: InputDecoration(
                      labelText: 'توضیح اختیاری نوبت ${i + 1}',
                      hintText: 'در صورت نیاز؛ مقدار مصرف بالا انتخاب شده است',
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.access_time),
                    label: Text(
                      'زمان نوبت ${i + 1}: '
                      '${_slots[i].time.hour.toString().padLeft(2, '0')}:'
                      '${_slots[i].time.minute.toString().padLeft(2, '0')}',
                    ),
                    onPressed: () => _pickTime(i),
                  ),
                  const SizedBox(height: 12),
                ],
                TextButton.icon(
                  onPressed: _addSlot,
                  icon: const Icon(Icons.add_alarm),
                  label: const Text('افزودن نوبت دیگر'),
                ),
                if (_formError != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBE8),
                      borderRadius: BorderRadius.circular(10)),
                    child: Text(_formError!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_editing ? 'ذخیره تغییرات' : 'ذخیره دارو'),
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      );
}
