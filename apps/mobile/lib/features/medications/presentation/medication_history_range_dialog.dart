import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/calendar/persian_date.dart';
import '../../../core/ui/app_design.dart';
import '../../../core/ui/english_digits_input_formatter.dart';

/// An explicit two-calendar custom range editor, independent of platform
/// date pickers. It stores Gregorian civil dates but renders the chosen
/// calendar throughout the editor.
Future<DateTimeRange?> showMedicationHistoryRangeDialog({
  required BuildContext context,
  DateTimeRange? initial,
}) => showDialog<DateTimeRange>(
  context: context,
  builder: (_) => _RangeDialog(initial: initial),
);

class _DateInputs {
  _DateInputs(DateTime date, bool jalali)
      : year = TextEditingController(),
        month = TextEditingController(),
        day = TextEditingController() {
    fill(date, jalali);
  }

  final TextEditingController year;
  final TextEditingController month;
  final TextEditingController day;

  void fill(DateTime date, bool jalali) {
    final p = jalali ? PersianDate.fromGregorian(date) : null;
    year.text = (p?.year ?? date.year).toString();
    month.text = (p?.month ?? date.month).toString().padLeft(2, '0');
    day.text = (p?.day ?? date.day).toString().padLeft(2, '0');
  }

  DateTime? parse(bool jalali) {
    final y = int.tryParse(PersianDate.latinDigits(year.text));
    final m = int.tryParse(PersianDate.latinDigits(month.text));
    final d = int.tryParse(PersianDate.latinDigits(day.text));
    if (year.text.length != 4 || y == null || m == null || d == null ||
        m < 1 || m > 12 || d < 1 || d > 31) {
      return null;
    }
    try {
      if (jalali) return PersianDate(y, m, d).toGregorian();
      if (y < 1900 || y > 2100) return null;
      final result = DateTime(y, m, d);
      if (result.year != y || result.month != m || result.day != d) {
        return null;
      }
      return result;
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  void dispose() {
    year.dispose();
    month.dispose();
    day.dispose();
  }
}

class _RangeDialog extends StatefulWidget {
  const _RangeDialog({this.initial});
  final DateTimeRange? initial;

  @override
  State<_RangeDialog> createState() => _RangeDialogState();
}

class _RangeDialogState extends State<_RangeDialog> {
  late _DateInputs _from;
  late _DateInputs _to;
  bool _jalali = true;
  String? _error;

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    final now = _today;
    _from = _DateInputs(widget.initial?.start ??
      DateTime(now.year, now.month - 6, now.day), _jalali);
    _to = _DateInputs(widget.initial?.end ?? now, _jalali);
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _switchCalendar(bool jalali) {
    if (jalali == _jalali) return;
    final from = _from.parse(_jalali) ??
        widget.initial?.start ?? DateTime(_today.year, _today.month - 6, 1);
    final to = _to.parse(_jalali) ?? widget.initial?.end ?? _today;
    setState(() {
      _jalali = jalali;
      _from.fill(from, jalali);
      _to.fill(to, jalali);
      _error = null;
    });
  }

  void _presetMonths(int months) {
    final today = _today;
    // DateTime normalizes month underflow, including crossing year boundaries.
    final start = DateTime(today.year, today.month - months, 1);
    setState(() {
      _from.fill(start, _jalali);
      _to.fill(today, _jalali);
      _error = null;
    });
  }

  void _save() {
    final from = _from.parse(_jalali);
    final to = _to.parse(_jalali);
    if (from == null || to == null) {
      setState(() => _error = _jalali
        ? 'تاریخ شمسی معتبر با سال چهاررقمی وارد کنید.'
        : 'تاریخ میلادی معتبر با سال چهاررقمی وارد کنید.');
      return;
    }
    if (from.isAfter(to)) {
      setState(() => _error = _jalali
        ? 'تاریخ شروع نباید بعد از تاریخ پایان باشد.'
        : 'تاریخ شروع نباید بعد از تاریخ پایان باشد.');
      return;
    }
    if (to.isAfter(_today)) {
      setState(() => _error = _jalali
        ? 'تاریخ پایان نمی‌تواند در آینده باشد.'
        : 'تاریخ پایان نمی‌تواند در آینده باشد.');
      return;
    }
    Navigator.pop(context, DateTimeRange(start: from, end: to));
  }

  Widget _part(TextEditingController ctl, String label, int maxLength) =>
    Expanded(child: TextField(
      controller: ctl,
      onTap: () {
        final field = ctl;
        field.selection = TextSelection(
          baseOffset: 0, extentOffset: field.text.length);
      },
      maxLength: maxLength,
      keyboardType: TextInputType.number,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      inputFormatters: [
        const EnglishDigitsInputFormatter(),
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(maxLength),
      ],
      onEditingComplete: () {
        if (maxLength == 2 && ctl.text.length == 1) {
          ctl.text = ctl.text.padLeft(2, '0');
        }
        FocusScope.of(context).nextFocus();
      },
      onChanged: (_) => setState(() => _error = null),
      decoration: InputDecoration(
        labelText: label, counterText: '',
        filled: true, fillColor: AppPalette.surface(context, AppColors.mint),
        isDense: true,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: AppPalette.ink(context, AppColors.primary), width: 1.5)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide.none),
      ),
    ));

  Widget _dateRow(String label, _DateInputs input) {
    final parts = _jalali
      ? <Widget>[
          _part(input.day, 'روز', 2),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 5),
            child: Text('/')),
          _part(input.month, 'ماه', 2),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 5),
            child: Text('/')),
          _part(input.year, 'سال', 4),
        ]
      : <Widget>[
          _part(input.month, 'ماه', 2),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 5),
            child: Text('/')),
          _part(input.day, 'روز', 2),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 5),
            child: Text('/')),
          _part(input.year, 'سال', 4),
        ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: TextStyle(
          fontWeight: FontWeight.w800, color: AppPalette.ink(context, AppColors.primaryDark))),
        const SizedBox(height: 8),
        Directionality(
          textDirection: _jalali ? TextDirection.rtl : TextDirection.ltr,
          child: Row(children: parts)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final from = _from.parse(_jalali);
    final to = _to.parse(_jalali);
    final equivalent = from == null || to == null
      ? (_jalali ? 'با تکمیل هر دو تاریخ، معادل میلادی دیده می‌شود.'
        : 'هر دو تاریخ را وارد کن تا معادل شمسی دیده شود.')
      : (_jalali
        ? 'میلادی: ${gregorianDateLabel(from)} تا ${gregorianDateLabel(to)}'
        : 'شمسی: ${persianDateLabel(from)} — ${persianDateLabel(to)}');
    return AlertDialog(
      backgroundColor: AppPalette.surface(context, AppColors.background),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
      title: Text(_jalali ? 'انتخاب بازه گزارش' : 'انتخاب بازه گزارش',
        style: TextStyle(color: AppPalette.ink(context, AppColors.primaryDark),
          fontWeight: FontWeight.w900)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('شمسی')),
                ButtonSegment(value: false, label: Text('میلادی')),
              ],
              selected: {_jalali},
              onSelectionChanged: (value) => _switchCalendar(value.first),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ActionChip(
                label: const Text('6 ماه اخیر'),
                onPressed: () => _presetMonths(6)),
              ActionChip(
                label: const Text('12 ماه اخیر'),
                onPressed: () => _presetMonths(12)),
            ]),
            const SizedBox(height: 14),
            _dateRow(_jalali ? 'از تاریخ' : 'از تاریخ', _from),
            const SizedBox(height: 18),
            _dateRow(_jalali ? 'تا تاریخ' : 'تا تاریخ', _to),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppPalette.surface(context, AppColors.mint),
                borderRadius: BorderRadius.circular(14)),
              child: Text(equivalent,
                style: TextStyle(color: AppPalette.ink(context, AppColors.primaryDark),
                  fontWeight: FontWeight.w700))),
            if (_error != null) ...[
              const SizedBox(height: 9),
              Text(_error!, style: TextStyle(
                color: AppPalette.ink(context, const Color(0xFFB83E4D)), fontWeight: FontWeight.w700)),
            ],
          ],
        )),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
          child: Text(_jalali ? 'انصراف' : 'انصراف')),
        FilledButton(
          onPressed: _save,
          child: Text(_jalali ? 'نمایش گزارش' : 'نمایش گزارش')),
      ],
    );
  }
}
