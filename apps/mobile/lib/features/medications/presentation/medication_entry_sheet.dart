import 'package:material_ui/material_ui.dart';

/// User-entered information only; no prescription or dosage inference.
class MedicationDraft {
  const MedicationDraft({
    required this.name,
    required this.dose,
    required this.time,
  });

  final String name;
  final String dose;
  final TimeOfDay time;
}

Future<MedicationDraft?> showMedicationEntrySheet(
  BuildContext context, {
  required String profileName,
}) =>
    showModalBottomSheet<MedicationDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MedicationEntrySheet(profileName: profileName),
    );

/// Keep controllers alive until the bottom-sheet route has fully unmounted.
/// Disposing controllers immediately after Navigator.pop breaks exit animation.
class _MedicationEntrySheet extends StatefulWidget {
  const _MedicationEntrySheet({required this.profileName});

  final String profileName;

  @override
  State<_MedicationEntrySheet> createState() => _MedicationEntrySheetState();
}

class _MedicationEntrySheetState extends State<_MedicationEntrySheet> {
  final _name = TextEditingController();
  final _dose = TextEditingController();
  TimeOfDay _selected = const TimeOfDay(hour: 8, minute: 0);

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selected,
    );
    if (picked != null && mounted) {
      setState(() => _selected = picked);
    }
  }

  void _submit() {
    final name = _name.text.trim();
    final dose = _dose.text.trim();
    if (name.isEmpty || dose.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('نام و شرح مصرف را کامل کنید.')),
      );
      return;
    }
    Navigator.of(context).pop(MedicationDraft(
      name: name,
      dose: dose,
      time: _selected,
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'افزودن دارو برای ${widget.profileName}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'فقط اطلاعات تجویزشده را ثبت کنید؛ برنامه مقدار مصرفی پیشنهاد نمی‌کند.',
              ),
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
              const SizedBox(height: 10),
              TextField(
                controller: _dose,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'شرح مصرف طبق نسخه',
                  hintText: 'مثلاً ۱ عدد؛ مقدار را خودتان وارد کنید',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.access_time),
                label: Text(
                  'زمان روزانه: ${_selected.hour.toString().padLeft(2, '0')}:'
                  '${_selected.minute.toString().padLeft(2, '0')}',
                ),
                onPressed: _pickTime,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.save_outlined),
                label: const Text('ذخیره دارو'),
                onPressed: _submit,
              ),
            ],
          ),
        ),
      );
}
