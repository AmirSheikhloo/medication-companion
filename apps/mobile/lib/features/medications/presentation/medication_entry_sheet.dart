import 'package:material_ui/material_ui.dart';

import '../../../core/calendar/persian_date.dart';
import '../../../core/ui/app_design.dart';
import '../../../core/ui/redesign_widgets.dart';

/// A user's own description for one daily occurrence.
class MedicationSlotDraft {
  const MedicationSlotDraft({required this.dose, required this.time});
  final String dose;
  final TimeOfDay time;
}

class MedicationDraft {
  const MedicationDraft({required this.name, required this.slots});

  final String name;
  final List<MedicationSlotDraft> slots;
}

Future<MedicationDraft?> showMedicationEntrySheet(
  BuildContext context, {
  required String profileName,
  String? initialName,
  List<MedicationSlotDraft>? initialSlots,
}) => Navigator.of(context).push<MedicationDraft>(MaterialPageRoute(
  builder: (_) => _MedicationEntrySheet(
    profileName: profileName,
    initialName: initialName,
    initialSlots: initialSlots,
  ),
));

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
  });

  final String profileName;
  final String? initialName;
  final List<MedicationSlotDraft>? initialSlots;

  @override
  State<_MedicationEntrySheet> createState() => _MedicationEntrySheetState();
}

class _MedicationEntrySheetState extends State<_MedicationEntrySheet> {
  late final TextEditingController _name;
  late final List<_SlotEditor> _slots;
  final List<_SlotEditor> _retired = [];

  bool get _editing => widget.initialName != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName ?? '');
    final initial = widget.initialSlots;
    _slots = (initial == null || initial.isEmpty)
        ? [_SlotEditor(time: const TimeOfDay(hour: 8, minute: 0))]
        : [
            for (final slot in initial)
              _SlotEditor(time: slot.time, dose: slot.dose),
          ];
  }

  @override
  void dispose() {
    _name.dispose();
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
    setState(
      () => _slots.add(
        _SlotEditor(
          time: TimeOfDay(hour: next ~/ 60, minute: next % 60),
          dose: _slots.last.doseController.text,
        ),
      ),
    );
  }

  void _removeSlot(int index) {
    if (_slots.length <= 1) return;
    setState(() => _retired.add(_slots.removeAt(index)));
  }

  void _showError(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 160) {
      _showError('نام دارو باید بین ۱ تا ۱۶۰ نویسه باشد.');
      return;
    }
    final used = <int>{};
    final values = <MedicationSlotDraft>[];
    for (final slot in _slots) {
      final dose = slot.doseController.text.trim();
      if (dose.isEmpty || dose.length > 120) {
        _showError('شرح مصرف هر نوبت باید بین ۱ تا ۱۲۰ نویسه باشد.');
        return;
      }
      if (!used.add(slot.time.hour * 60 + slot.time.minute)) {
        _showError('ساعت نوبت‌ها نباید تکراری باشد.');
        return;
      }
      values.add(MedicationSlotDraft(dose: dose, time: slot.time));
    }
    Navigator.of(context).pop(MedicationDraft(name: name, slots: values));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      title: Text(_editing ? 'ویرایش دارو' : 'افزودن دارو'),
      actions: [TextButton(onPressed: () => Navigator.pop(context),
        child: const Text('لغو', style: TextStyle(color: Colors.white)))],
    ),
    bottomNavigationBar: SafeArea(top: false, child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 12),
      child: AppGradientButton(label: _editing ? 'ذخیره تغییرات' : 'ذخیره دارو',
        icon: Icons.check, onPressed: _submit, light: true),
    )),
    body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSoftHeader(title: _editing ? 'ویرایش برنامه دارو' : 'افزودن داروی جدید',
              subtitle: _editing
                ? 'تغییر ساعت‌ها و مقدار نوبت‌ها از فردا اعمال می‌شود.'
                : 'اطلاعات دارو را فقط طبق نسخه وارد کنید.',
              icon: Icons.medication_outlined),
            const SizedBox(height: 16),
            const Text('نام دارو *', style: TextStyle(fontWeight: FontWeight.w800,
              color: AppColors.primaryDark)),
            const SizedBox(height: 7),
            TextField(
              controller: _name,
              maxLength: 160,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'نام دارو',
                hintText: 'نام روی نسخه یا جعبه',
              ),
            ),
            const SizedBox(height: 10),
            const AppSectionHeading('زمان‌ها و شرح مصرف', icon: Icons.schedule_outlined),
            const SizedBox(height: 7),
            for (var i = 0; i < _slots.length; i++) ...[
              const Divider(height: 20, color: AppColors.outline),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      PersianDate.persianDigits('نوبت ${i + 1}'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (_slots.length > 1)
                    IconButton(
                      tooltip: PersianDate.persianDigits('حذف نوبت ${i + 1}'),
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => _removeSlot(i),
                    ),
                ],
              ),
              TextField(
                controller: _slots[i].doseController,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: PersianDate.persianDigits(
                    'شرح مصرف نوبت ${i + 1} طبق نسخه',
                  ),
                  hintText: 'مثلاً ۱ عدد؛ خودتان وارد کنید',
                ),
              ),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(
                icon: const Icon(Icons.access_time),
                label: Text(
                  PersianDate.persianDigits(
                    'زمان نوبت ${i + 1}: '
                    '${_slots[i].time.hour.toString().padLeft(2, '0')}:'
                    '${_slots[i].time.minute.toString().padLeft(2, '0')}',
                  ),
                ),
                onPressed: () => _pickTime(i),
              )),
              const SizedBox(height: 12),
            ],
            TextButton.icon(
              onPressed: _addSlot,
              icon: const Icon(Icons.add_alarm),
              label: const Text('افزودن نوبت دیگر'),
            ),
            const SizedBox(height: 14),
            const AppSoftHeader(title: 'یادآوری دارو',
              subtitle: 'زمان‌های ثبت‌شده برای یادآوری استفاده می‌شوند.',
              icon: Icons.notifications_none_outlined),
          ],
        ),
      ),
  );
}
