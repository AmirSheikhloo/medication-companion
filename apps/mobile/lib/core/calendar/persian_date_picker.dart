import 'package:material_ui/material_ui.dart';

import 'persian_date.dart';

/// Accepts Persian/Arabic/Latin digits. Gregorian picker remains available.
/// All callers receive a normal local Gregorian DateTime at midnight.
Future<DateTime?> showPersianDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = 'انتخاب تاریخ',
}) => showDialog<DateTime>(
      context: context,
      builder: (_) => _PersianDateDialog(
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
        title: title,
      ),
    );

class _PersianDateDialog extends StatefulWidget {
  const _PersianDateDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.title,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;

  @override
  State<_PersianDateDialog> createState() => _PersianDateDialogState();
}

class _PersianDateDialogState extends State<_PersianDateDialog> {
  late final TextEditingController _date;
  String? _error;

  @override
  void initState() {
    super.initState();
    _date = TextEditingController(
      text: persianDateLabel(widget.initialDate),
    );
  }

  @override
  void dispose() {
    _date.dispose();
    super.dispose();
  }

  bool _inRange(DateTime date) =>
      !date.isBefore(DateUtils.dateOnly(widget.firstDate)) &&
      !date.isAfter(DateUtils.dateOnly(widget.lastDate));

  void _confirm() {
    try {
      final date = PersianDate.parse(_date.text).toGregorian();
      if (!_inRange(date)) {
        setState(() => _error = 'تاریخ خارج از بازهٔ مجاز این فرم است.');
        return;
      }
      Navigator.of(context).pop(date);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    } on RangeError {
      setState(() => _error = 'سال شمسی خارج از محدوده است.');
    }
  }

  Future<void> _pickGregorian() async {
    final first = DateUtils.dateOnly(widget.firstDate);
    final last = DateUtils.dateOnly(widget.lastDate);
    final current = DateUtils.dateOnly(widget.initialDate);
    final safe = current.isBefore(first)
        ? first
        : current.isAfter(last) ? last : current;
    final chosen = await showDatePicker(
      context: context,
      initialDate: safe,
      firstDate: first,
      lastDate: last,
      helpText: 'انتخاب از تقویم میلادی',
    );
    if (!mounted || chosen == null) return;
    Navigator.of(context).pop(chosen);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('تاریخ شمسی را وارد کنید. اعداد فارسی و انگلیسی پذیرفته می‌شوند.'),
              const SizedBox(height: 12),
              TextField(
                controller: _date,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.datetime,
                decoration: InputDecoration(
                  labelText: 'سال/ماه/روز شمسی',
                  hintText: '1405/08/26',
                  border: const OutlineInputBorder(),
                  errorText: _error,
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _confirm(),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _pickGregorian,
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('انتخاب از تقویم میلادی'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(),
              child: const Text('انصراف')),
          FilledButton(onPressed: _confirm, child: const Text('تأیید تاریخ')),
        ],
      );
}
