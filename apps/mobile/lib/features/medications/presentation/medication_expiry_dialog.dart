import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/calendar/persian_date.dart';
import '../../../core/ui/english_digits_input_formatter.dart';
import '../../../core/ui/app_design.dart';

/// A keyboard-friendly expiry editor. The selected calendar is presentation
/// only; all saved dates are validated Gregorian date-only values.
Future<DateTime?> showMedicationExpiryDialog(BuildContext context,
    {DateTime? initialDate}) => showDialog<DateTime>(
      context: context,
      builder: (_) => _ExpiryDialog(initial: initialDate),
    );

class _ExpiryDialog extends StatefulWidget {
  const _ExpiryDialog({this.initial});

  final DateTime? initial;

  @override
  State<_ExpiryDialog> createState() => _ExpiryDialogState();
}

class _ExpiryDialogState extends State<_ExpiryDialog> {
  final _year = TextEditingController();
  final _month = TextEditingController();
  final _day = TextEditingController();
  bool _persian = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fill(widget.initial ?? DateTime.now());
  }

  @override
  void dispose() {
    _year.dispose();
    _month.dispose();
    _day.dispose();
    super.dispose();
  }

  void _fill(DateTime date) {
    if (_persian) {
      final p = PersianDate.fromGregorian(date);
      _year.text = p.year.toString();
      _month.text = p.month.toString().padLeft(2, '0');
      _day.text = p.day.toString().padLeft(2, '0');
    } else {
      _year.text = date.year.toString();
      _month.text = date.month.toString().padLeft(2, '0');
      _day.text = date.day.toString().padLeft(2, '0');
    }
  }

  DateTime? _decode() {
    final year = int.tryParse(PersianDate.latinDigits(_year.text));
    final month = int.tryParse(PersianDate.latinDigits(_month.text));
    final day = int.tryParse(PersianDate.latinDigits(_day.text));
    if (_year.text.length != 4 || year == null || month == null || day == null ||
        month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    try {
      if (_persian) return PersianDate(year, month, day).toGregorian();
      if (year < 1900 || year > 2100) return null;
      final date = DateTime(year, month, day);
      if (date.year != year || date.month != month || date.day != day) {
        return null;
      }
      return date;
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  void _toggle(bool value) {
    if (value == _persian) return;
    final current = _decode() ?? widget.initial ?? DateTime.now();
    setState(() {
      _persian = value;
      _fill(current);
      _error = null;
    });
  }

  void _submit() {
    final date = _decode();
    if (date == null) {
      setState(() => _error = 'تاریخ معتبر را با سال چهاررقمی وارد کن.');
      return;
    }
    final now = DateTime.now();
    if (date.isBefore(DateTime(now.year, now.month, now.day))) {
      setState(() => _error = '⚠️ تاریخ انقضا گذشته است. '
          'اگر اشتباه تایپی نیست، از مصرف این دارو خودداری کن.');
      return;
    }
    Navigator.pop(context, date);
  }

  Widget _numberField(String name, TextEditingController controller,
      {required int length}) => Expanded(
        flex: length == 4 ? 2 : 1,
        child: TextField(
          controller: controller,
      onTap: () {
        final field = controller;
        field.selection = TextSelection(
          baseOffset: 0, extentOffset: field.text.length);
      },
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.number,
          maxLength: length,
          inputFormatters: [const EnglishDigitsInputFormatter(),
            FilteringTextInputFormatter.allow(
              RegExp(r'[0-9۰-۹٠-٩]')),
            LengthLimitingTextInputFormatter(length)],
          onChanged: (_) => setState(() => _error = null),
          onEditingComplete: () {
            if (length == 2 && controller.text.length == 1) {
              controller.text = controller.text.padLeft(2, '0');
            }
            FocusScope.of(context).nextFocus();
          },
          decoration: InputDecoration(
            labelText: name,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8, vertical: 18),
            counterText: '',
            filled: true, fillColor: AppColors.mint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final converted = _decode();
    final helper = converted == null
        ? 'با تکمیل تاریخ، معادل تقویم دیگر اینجا دیده می‌شود.'
        : _persian
            ? 'میلادی: ${gregorianDateLabel(converted)}'
            : 'شمسی: ${persianDateLabel(converted)}';
    return AlertDialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('تاریخ انقضای بسته', style: TextStyle(
          color: AppColors.primaryDark, fontWeight: FontWeight.w900)),
      content: SizedBox(width: 350, child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('میلادی')),
              ButtonSegment(value: true, label: Text('شمسی')),
            ],
            selected: {_persian},
            onSelectionChanged: (values) => _toggle(values.first),
          ),
          const SizedBox(height: 12),
          const Text('تاریخ را به تقویم موردنظر وارد کنید.',
            style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 12),
          // Right-to-left: day (right), month (middle), year (left).
          Row(children: [
            _numberField('روز', _day, length: 2),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 5),
              child: Text('/')),
            _numberField('ماه', _month, length: 2),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 5),
              child: Text('/')),
            _numberField('سال', _year, length: 4),
          ]),
          const SizedBox(height: 12),
          AnimatedSwitcher(duration: const Duration(milliseconds: 200),
            child: Container(key: ValueKey(helper),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: AppColors.mint,
                borderRadius: BorderRadius.circular(13)),
              child: Row(children: [
                const Icon(Icons.sync_alt, color: AppColors.primary, size: 19),
                const SizedBox(width: 8),
                Expanded(child: Text(helper, style: const TextStyle(
                  color: AppColors.primaryDark, fontSize: 14,
                  fontWeight: FontWeight.w800))),
              ]))),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(
              color: Color(0xFFC3353A), fontSize: 12)),
          ],
        ],
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('انصراف')),
        FilledButton(onPressed: _submit, child: const Text('تأیید تاریخ')),
      ],
    );
  }
}
