import 'package:material_ui/material_ui.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/calendar/persian_date.dart';
import '../../../core/calendar/persian_date_picker.dart';
import '../../../core/ui/app_design.dart';
import '../../../core/ui/redesign_widgets.dart';
import '../data/health_repository.dart';
import '../domain/health_metric.dart';
import 'health_chart.dart';
import 'health_report_screen.dart';

class HealthTab extends StatefulWidget {
  const HealthTab({super.key, required this.profile, required this.repository,
    this.onOpenCareHub});

  final Profile profile;
  final HealthRepository repository;
  final VoidCallback? onOpenCareHub;

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
  HealthMeasurement? _lastPressure;
  HealthMeasurement? _lastWeight;
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
      final pressure = await widget.repository.measurementsFor(
        profileId: widget.profile.id, metric: HealthMetric.pressure, days: 3650);
      final weight = await widget.repository.measurementsFor(
        profileId: widget.profile.id, metric: HealthMetric.weight, days: 3650);
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _records = entries;
        _lastPressure = pressure.isEmpty ? null : pressure.first;
        _lastWeight = weight.isEmpty ? null : weight.first;
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
    final draft = await Navigator.of(context).push<HealthMeasurementDraft>(
      MaterialPageRoute(builder: (_) => _HealthEntryForm(
          initialMetric: original == null
              ? _metric
              : HealthMetric.fromCode(original.metric),
          original: original,
        )),
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
  Widget build(BuildContext context) => _healthDashboard(context);

  Widget _healthDashboard(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(15, 17, 15, 28),
    children: [
      Text('سلامت', style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        color: AppColors.primaryDark, fontWeight: FontWeight.w900)),
      const SizedBox(height: 13),
      const AppSoftHeader(title: 'سلامت من',
        icon: Icons.favorite_rounded,
        subtitle: 'اندازه‌گیری‌ها، سوابق و پیگیری‌های مراقبتی'),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: AppPanel(color: AppColors.mint,
          padding: const EdgeInsets.all(13),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [Icon(Icons.favorite_outline,
              color: AppColors.primary, size: 19), SizedBox(width: 5),
              Expanded(child: Text('فشار خون', style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 12)))]),
            const SizedBox(height: 6),
            Text(_lastPressure == null ? '—' :
              PersianDate.persianDigits('${HealthNumber.format(_lastPressure!.primaryMilliunits)}/'
                '${HealthNumber.format(_lastPressure!.secondaryMilliunits!)}'),
              maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w900,
                fontSize: 22, color: AppColors.primaryDark)),
            const Text('میلی‌متر جیوه', style: TextStyle(color: AppColors.muted,
              fontSize: 10)),
          ]))),
        const SizedBox(width: 9),
        Expanded(child: AppPanel(color: AppColors.mint,
          padding: const EdgeInsets.all(13),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [Icon(Icons.monitor_weight_outlined,
              color: AppColors.primary, size: 19), SizedBox(width: 5),
              Expanded(child: Text('وزن', style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 12)))]),
            const SizedBox(height: 6),
            Text(_lastWeight == null ? '—' :
              PersianDate.persianDigits(HealthNumber.format(_lastWeight!.primaryMilliunits)),
              maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w900,
                fontSize: 22, color: AppColors.primaryDark)),
            const Text('کیلوگرم', style: TextStyle(color: AppColors.muted,
              fontSize: 10)),
          ]))),
      ]),
      const SizedBox(height: 17),
      const AppSectionHeading('اندازه‌گیری‌های اخیر', icon: Icons.show_chart),
      const SizedBox(height: 9),
      AppPanel(padding: const EdgeInsets.all(10), child: Column(children: [
        if (!_loading && _records.isNotEmpty) ...[
          HealthChart(metric: _metric, records: _records),
          const Divider(height: 13, color: AppColors.outline),
        ],
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (_error != null) ListTile(title: Text(_error!),
          trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: _reload)),
        if (!_loading && _error == null && _records.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(children: [
              const Icon(Icons.monitor_heart_outlined, color: AppColors.primary,
                size: 39),
              const SizedBox(height: 8),
              Text(PersianDate.persianDigits(
                'در $_days روز گذشته برای ${_metric.label} داده‌ای ثبت نشده است.'),
                textAlign: TextAlign.center),
            ])),
        if (_records.isNotEmpty) ...[
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(color: AppColors.mint,
              borderRadius: BorderRadius.circular(9)),
            child: const Row(children: [
              Expanded(child: Text('تاریخ و ساعت', style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 11))),
              Expanded(child: Text('اندازه‌گیری', style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 11))),
              SizedBox(width: 36),
            ])),
          for (var i = 0; i < _records.length && i < 5; i++) ...[
            if (i != 0) const Divider(height: 1, color: AppColors.outline),
            Row(children: [
              Expanded(child: Text(healthDateTimeLabel(_records[i].observedAt),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10))),
              Expanded(child: Text(_reading(_records[i].metric,
                _records[i].primaryMilliunits, _records[i].secondaryMilliunits),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11))),
              PopupMenuButton<String>(
                tooltip: 'گزینه‌های اندازه‌گیری',
                enabled: !_busy,
                onSelected: (action) {
                  if (action == 'edit') _edit(_records[i]);
                  if (action == 'history') _history(_records[i]);
                  if (action == 'archive') _archive(_records[i]);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('اصلاح ثبت')),
                  PopupMenuItem(value: 'history', child: Text('تاریخچه اصلاحات')),
                  PopupMenuItem(value: 'archive', child: Text('بایگانی')),
                ],
              ),
            ]),
          ],
        ],
      ])),
      const SizedBox(height: 11),
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final metric in HealthMetric.values)
          ChoiceChip(label: Text(metric.label, style: const TextStyle(fontSize: 11)),
            selected: _metric == metric,
            onSelected: _busy ? null : (_) {
              setState(() => _metric = metric);
              _reload();
            }),
      ]),
      const SizedBox(height: 7),
      Wrap(spacing: 6, children: [
        for (final days in [7, 30, 90])
          ChoiceChip(label: Text(PersianDate.persianDigits('$days روز')),
            selected: _days == days,
            onSelected: _busy ? null : (_) {
              setState(() => _days = days);
              _reload();
            }),
      ]),
      const SizedBox(height: 11),
      AppGradientButton(label: 'ثبت ${_metric.label}', icon: Icons.add,
        onPressed: _busy ? null : () => _edit(), light: true),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: _busy ? null : () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => HealthReportScreen(
          profile: widget.profile, metric: _metric, repository: widget.repository,
          initialDays: _days))),
        icon: const Icon(Icons.monitor_heart_outlined),
        label: const Text('نمودار و نمایش به پزشک')),
      const SizedBox(height: 17),
      const AppSectionHeading('پیگیری‌های مراقبتی', icon: Icons.event_available_outlined),
      const SizedBox(height: 8),
      AppPanel(padding: EdgeInsets.zero, child: Column(children: [
        ListTile(leading: const AppIconTile(Icons.calendar_month_outlined),
          title: const Text('ویزیت‌ها و نوبت‌های پزشک'),
          trailing: const Icon(Icons.chevron_left),
          onTap: widget.onOpenCareHub),
        const Divider(height: 1, color: AppColors.outline),
        ListTile(leading: const AppIconTile(Icons.fact_check_outlined),
          title: const Text('کارها و چک‌لیست ویزیت'),
          trailing: const Icon(Icons.chevron_left),
          onTap: widget.onOpenCareHub),
      ])),
      const SizedBox(height: 12),
      const Text('اندازه‌گیری‌ها توسط شما ثبت شده‌اند؛ این برنامه تشخیص پزشکی نمی‌دهد.',
        style: TextStyle(fontSize: 11, color: AppColors.muted),
        textAlign: TextAlign.center),
    ],
  );

  Widget _legacyHealthTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
      children: [
        AppSectionHeading(
          'دفترچه سلامت ${widget.profile.displayName}',
          icon: Icons.favorite_border_rounded,
        ),
        const SizedBox(height: 8),
        const Text(
          'اندازه‌گیری‌های ثبت‌شده توسط شما، بدون تشخیص یا تفسیر پزشکی.',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 14),
        if (!_loading && _error == null && _records.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: AppPanel(
                  color: AppColors.mint,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'آخرین ${_metric.label}',
                        style: const TextStyle(
                          color: AppColors.primaryDark,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        healthDateTimeLabel(_records.first.observedAt),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: AppPanel(
                  color: AppColors.mint,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ثبت‌های این بازه',
                        style: TextStyle(color: AppColors.primaryDark, fontSize: 12),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        PersianDate.persianDigits('${_records.length} مورد'),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        const AppSectionHeading('نوع اندازه‌گیری'),
        const SizedBox(height: 8),
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
          AppPanel(
            child: Column(
              children: [
                const Icon(
                  Icons.monitor_heart_outlined,
                  color: AppColors.primary,
                  size: 36,
                ),
                const SizedBox(height: 10),
                Text(
                  PersianDate.persianDigits(
                    'در $_days روز گذشته برای ${_metric.label} داده‌ای ثبت نشده است.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else ...[
          AppSectionHeading(
            PersianDate.persianDigits('روند ${_metric.label} در $_days روز'),
            icon: Icons.show_chart_rounded,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: HealthChart(metric: _metric, records: _records),
            ),
          ),
          const SizedBox(height: 6),
          const AppSectionHeading('آخرین سوابق', icon: Icons.receipt_long_outlined),
          const SizedBox(height: 8),
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
          'این نسخهٔ آزمایشی گزارش و پشتیبان رمزگذاری‌شده تولید می‌کند، اما بازیابی فایل پشتیبان هنوز فعال نیست. '
          'برای گزارش کامل و خروجی آفلاین، «نمایش به پزشک» را باز کنید.',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.original == null ? 'ثبت اندازه‌گیری' : 'اصلاح اندازه‌گیری'),
        backgroundColor: AppColors.primary, foregroundColor: Colors.white),
      body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeading(
            widget.original == null ? 'ثبت اندازه‌گیری' : 'اصلاح اندازه‌گیری',
            icon: Icons.monitor_heart_outlined,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.mint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'نتیجه‌های اندازه‌گیری خودتان را ثبت کنید. این اطلاعات به معنای تأیید پزشکی نیست.',
              style: TextStyle(color: AppColors.primaryDark, fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
          if (widget.original == null)
            DropdownButtonFormField<HealthMetric>(
              initialValue: _metric,
              decoration: const InputDecoration(labelText: 'نوع اندازه‌گیری'),
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
          const Text(
            'اطلاعات ثبت‌شده توسط کاربر؛ تأیید پزشکی نشده.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
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
      ),
    );
  }
}
