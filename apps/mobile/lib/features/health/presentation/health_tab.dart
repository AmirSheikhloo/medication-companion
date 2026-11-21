import 'package:material_ui/material_ui.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/calendar/persian_date.dart';
import '../../../core/calendar/persian_date_picker.dart';
import '../data/health_repository.dart';
import '../domain/health_metric.dart';
import 'health_chart.dart';
import 'health_report_screen.dart';

class HealthTab extends StatefulWidget {
  const HealthTab({super.key, required this.profile, required this.repository});

  final Profile profile;
  final HealthRepository repository;

  @override
  State<HealthTab> createState() => _HealthTabState();
}

class _HealthTabState extends State<HealthTab> {
  HealthMetric _metric = HealthMetric.pressure;
  int _days = 30;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<HealthMeasurement> _records = [];
  int _ticket = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(HealthTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id) {
      _records = [];
      _reload();
    }
  }

  Future<void> _reload() async {
    final ticket = ++_ticket;
    if (mounted) setState(() => _loading = true);
    try {
      final entries = await widget.repository.measurementsFor(
        profileId: widget.profile.id,
        metric: _metric,
        days: _days,
      );
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _records = entries;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _error = 'خواندن اندازه‌گیری‌ها ممکن نشد: $error';
        _loading = false;
      });
    }
  }

  Future<void> _edit([HealthMeasurement? original]) async {
    if (_busy) return;
    final profileId = widget.profile.id;
    final draft = await showModalBottomSheet<HealthMeasurementDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _HealthEntryForm(
          initialMetric: original == null
              ? _metric
              : HealthMetric.fromCode(original.metric),
          original: original,
        ),
      ),
    );
    if (!mounted || draft == null) return;
    setState(() => _busy = true);
    try {
      if (original == null) {
        await widget.repository.addMeasurement(
          profileId: profileId,
          draft: draft,
        );
      } else {
        await widget.repository.correctMeasurement(
          profileId: profileId,
          measurementId: original.id,
          draft: draft,
        );
      }
      if (!mounted) return;
      setState(() => _metric = draft.metric);
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('اندازه‌گیری ذخیره شد.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('ذخیره انجام نشد: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive(HealthMeasurement record) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('بایگانی اندازه‌گیری'),
        content: const Text(
          'ثبت از فهرست فعال پنهان می‌شود؛ نسخه‌ها و سابقه اصلاح آن محفوظ می‌مانند.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('بایگانی'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.repository.archiveMeasurement(
        profileId: widget.profile.id,
        measurementId: record.id,
      );
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ثبت بایگانی شد؛ سوابق محفوظ‌اند.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('بایگانی انجام نشد: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _history(HealthMeasurement record) async {
    try {
      final versions = await widget.repository.versionsFor(
        profileId: widget.profile.id,
        measurementId: record.id,
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  'تاریخچه اصلاحات',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                for (final v in versions)
                  ListTile(
                    title: Text(
                      'نسخه ${v.version} — ${switch (v.action) {
                        'created' => 'ایجاد',
                        'corrected' => 'اصلاح',
                        _ => 'بایگانی',
                      }}',
                    ),
                    subtitle: Text(
                      '${_reading(v.metric, v.primaryMilliunits, v.secondaryMilliunits)}\n'
                      'اندازه‌گیری: ${healthDateTimeLabel(v.observedAt)}\n'
                      'تغییر: ${healthDateTimeLabel(v.changedAt)}'
                      '${v.note == null || v.note!.isEmpty ? '' : '\nیادداشت: ${v.note}'}',
                    ),
                    isThreeLine: true,
                  ),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خواندن تاریخچه ممکن نشد: $error')),
      );
    }
  }

  static String _reading(String metric, int first, int? second) {
    final type = HealthMetric.fromCode(metric);
    final value = HealthNumber.format(first);
    final extra = second == null ? '' : '/${HealthNumber.format(second)}';
    return PersianDate.persianDigits('$value$extra ${type.unit}');
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Text(
          'دفترچه سلامت ${widget.profile.displayName}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text('فقط اطلاعات ثبت‌شده توسط شما؛ بدون تشخیص یا تفسیر پزشکی.'),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final metric in HealthMetric.values)
              ChoiceChip(
                label: Text(metric.label),
                selected: _metric == metric,
                onSelected: _busy
                    ? null
                    : (_) {
                        setState(() => _metric = metric);
                        _reload();
                      },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('بازه:'),
            const SizedBox(width: 12),
            for (final days in [7, 30, 90])
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 7),
                child: ChoiceChip(
                  label: Text(PersianDate.persianDigits('$days روز')),
                  selected: _days == days,
                  onSelected: _busy
                      ? null
                      : (_) {
                          setState(() => _days = days);
                          _reload();
                        },
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _busy ? null : () => _edit(),
          icon: const Icon(Icons.add),
          label: Text('ثبت ${_metric.label}'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => HealthReportScreen(
                      profile: widget.profile,
                      metric: _metric,
                      repository: widget.repository,
                      initialDays: _days,
                    ),
                  ),
                ),
          icon: const Icon(Icons.monitor_heart_outlined),
          label: const Text('نمودار و نمایش به پزشک'),
        ),
        const SizedBox(height: 10),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_error != null)
          ListTile(
            title: Text(_error!),
            trailing: IconButton(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
          )
        else if (_records.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                PersianDate.persianDigits(
                  'در $_days روز گذشته برای ${_metric.label} داده‌ای ثبت نشده است.',
                ),
              ),
            ),
          )
        else ...[
          Text(
            PersianDate.persianDigits(
              '${_records.length} ثبت در $_days روز گذشته',
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: HealthChart(metric: _metric, records: _records),
            ),
          ),
          const SizedBox(height: 6),
          for (final record in _records)
            Card(
              child: ListTile(
                title: Text(
                  _reading(
                    record.metric,
                    record.primaryMilliunits,
                    record.secondaryMilliunits,
                  ),
                ),
                subtitle: Text(
                  '${healthDateTimeLabel(record.observedAt)}'
                  '${record.context == null ? '' : '\n${_contextLabel(record.context!)}'}'
                  '${record.note == null || record.note!.isEmpty ? '' : '\n${record.note}'}',
                ),
                isThreeLine:
                    record.context != null ||
                    (record.note?.isNotEmpty ?? false),
                trailing: PopupMenuButton<String>(
                  tooltip: 'گزینه‌های اندازه‌گیری',
                  enabled: !_busy,
                  onSelected: (action) {
                    if (action == 'edit') _edit(record);
                    if (action == 'history') _history(record);
                    if (action == 'archive') _archive(record);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('اصلاح ثبت')),
                    PopupMenuItem(
                      value: 'history',
                      child: Text('تاریخچه اصلاحات'),
                    ),
                    PopupMenuItem(value: 'archive', child: Text('بایگانی')),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 12),
        const Text(
          'این نسخه آزمایشی هنوز رمزگذاری و پشتیبان‌گیری امن ندارد؛ '
          'فقط داده‌های ساختگی وارد کنید. برای گزارش کامل و خروجی آفلاین، «نمایش به پزشک» را باز کنید.',
          style: TextStyle(color: Colors.blueGrey),
        ),
      ],
    );
  }
}

String _contextLabel(String value) => switch (value) {
  'fasting' => 'ناشتا',
  'before_meal' => 'قبل غذا',
  'after_meal' => 'بعد غذا',
  _ => 'سایر شرایط',
};

class _HealthEntryForm extends StatefulWidget {
  const _HealthEntryForm({required this.initialMetric, this.original});

  final HealthMetric initialMetric;
  final HealthMeasurement? original;

  @override
  State<_HealthEntryForm> createState() => _HealthEntryFormState();
}

class _HealthEntryFormState extends State<_HealthEntryForm> {
  late HealthMetric _metric;
  late DateTime _observedAt;
  late String _glucoseContext;
  late final TextEditingController _first;
  late final TextEditingController _second;
  late final TextEditingController _note;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    final original = widget.original;
    _metric = widget.initialMetric;
    _observedAt = original?.observedAt.toLocal() ?? DateTime.now();
    _glucoseContext = original?.context ?? 'other';
    _first = TextEditingController(
      text: original == null
          ? ''
          : HealthNumber.format(original.primaryMilliunits),
    );
    _second = TextEditingController(
      text: original?.secondaryMilliunits == null
          ? ''
          : HealthNumber.format(original!.secondaryMilliunits!),
    );
    _note = TextEditingController(text: original?.note ?? '');
  }

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showPersianDatePicker(
      context: context,
      initialDate: _observedAt,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      title: 'تاریخ اندازه‌گیری',
    );
    if (!mounted || date == null) return;
    setState(
      () => _observedAt = DateTime(
        date.year,
        date.month,
        date.day,
        _observedAt.hour,
        _observedAt.minute,
      ),
    );
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_observedAt),
    );
    if (!mounted || time == null) return;
    setState(
      () => _observedAt = DateTime(
        _observedAt.year,
        _observedAt.month,
        _observedAt.day,
        time.hour,
        time.minute,
      ),
    );
  }

  void _save() {
    try {
      final first = HealthNumber.parseMilliunits(_first.text);
      final second = _metric.hasSecondValue
          ? HealthNumber.parseMilliunits(_second.text)
          : null;
      final draft = HealthMeasurementDraft(
        metric: _metric,
        primaryMilliunits: first,
        secondaryMilliunits: second,
        observedAt: _observedAt,
        context: _metric == HealthMetric.glucose ? _glucoseContext : null,
        note: _note.text.trim(),
      );
      if (_observedAt.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
        throw FormatException('زمان اندازه‌گیری نباید در آینده باشد.');
      }
      if (draft.note!.length > 500) {
        throw FormatException('یادداشت حداکثر ۵۰۰ نویسه است.');
      }
      Navigator.of(context).pop(draft);
    } catch (error) {
      setState(() => _validationError = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.original == null ? 'ثبت اندازه‌گیری' : 'اصلاح اندازه‌گیری',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          if (widget.original == null)
            DropdownButton<HealthMetric>(
              value: _metric,
              isExpanded: true,
              items: [
                for (final metric in HealthMetric.values)
                  DropdownMenuItem(value: metric, child: Text(metric.label)),
              ],
              onChanged: (metric) {
                if (metric != null) setState(() => _metric = metric);
              },
            )
          else
            Text('شاخص: ${_metric.label} (ثابت)'),
          const SizedBox(height: 8),
          TextField(
            controller: _first,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: _metric == HealthMetric.pressure
                  ? 'عدد بالایی فشار (mmHg)'
                  : '${_metric.label} (${_metric.unit})',
            ),
          ),
          if (_metric.hasSecondValue) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _second,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'عدد پایینی فشار (mmHg)',
              ),
            ),
          ],
          if (_metric == HealthMetric.glucose) ...[
            const SizedBox(height: 10),
            DropdownButton<String>(
              value: _glucoseContext,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'fasting', child: Text('ناشتا')),
                DropdownMenuItem(value: 'before_meal', child: Text('قبل غذا')),
                DropdownMenuItem(value: 'after_meal', child: Text('بعد غذا')),
                DropdownMenuItem(value: 'other', child: Text('سایر شرایط')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _glucoseContext = value);
              },
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: const Text('تاریخ (شمسی/میلادی)'),
              ),
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule),
                label: const Text('ساعت'),
              ),
            ],
          ),
          Text(
            'شمسی: ${persianDateLabel(_observedAt, showTime: true)}'
            ' · میلادی: ${healthDateTimeLabel(_observedAt)}',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLength: 500,
            maxLines: 2,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'یادداشت اختیاری',
            ),
          ),
          if (_validationError != null)
            Text(_validationError!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 8),
          const Text('اطلاعات ثبت‌شده توسط کاربر؛ تأیید پزشکی نشده.'),
          const SizedBox(height: 14),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('انصراف'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('ذخیره اندازه‌گیری'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
