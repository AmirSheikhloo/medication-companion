import 'package:material_ui/material_ui.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_design.dart';
import '../data/health_repository.dart';
import '../data/health_report_export.dart';
import '../domain/health_metric.dart';
import '../domain/health_report.dart';
import 'health_chart.dart';

/// Separate, full-screen, read-only doctor-facing route.
class HealthReportScreen extends StatefulWidget {
  const HealthReportScreen({
    super.key,
    required this.profile,
    required this.metric,
    required this.repository,
    this.initialDays = 30,
  });

  final Profile profile;
  final HealthMetric metric;
  final HealthRepository repository;
  final int initialDays;

  @override
  State<HealthReportScreen> createState() => _HealthReportScreenState();
}

class _HealthReportScreenState extends State<HealthReportScreen> {
  final _export = const HealthReportExport();
  late int _days;
  DateTimeRange? _custom;
  List<HealthMeasurement> _records = [];
  bool _loading = true;
  bool _sharing = false;
  String? _error;
  int _ticket = 0;

  @override
  void initState() {
    super.initState();
    _days = widget.initialDays;
    _reload();
  }

  (DateTime, DateTime) get _range {
    if (_custom case final range?) {
      return (range.start, range.end);
    }
    final now = DateTime.now();
    return (
      DateTime(now.year, now.month, now.day - _days + 1),
      DateTime(now.year, now.month, now.day),
    );
  }

  Future<void> _reload() async {
    final ticket = ++_ticket;
    if (mounted) setState(() => _loading = true);
    try {
      final all = await widget.repository.measurementsFor(
        profileId: widget.profile.id,
        metric: widget.metric,
      );
      final (from, to) = _range;
      final filtered = selectHealthDateRange(
        records: all,
        startLocal: from,
        endLocal: to,
      );
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _records = filtered;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _error = 'بارگذاری گزارش انجام نشد: $error';
        _loading = false;
      });
    }
  }

  Future<void> _customDates() async {
    final current = _range;
    final dates = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: current.$1, end: current.$2),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: 'انتخاب بازه گزارش (میلادی)',
    );
    if (!mounted || dates == null) return;
    setState(() => _custom = dates);
    await _reload();
  }

  Future<void> _share({required bool pdf}) async {
    if (_sharing || _loading || _error != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اشتراک گزارش سلامت'),
        content: Text(
          'فایل شامل نام پروفایل «${widget.profile.displayName}»، '
          'اندازه‌گیری‌ها و یادداشت‌های همین شاخص است. '
          'فقط اگر گیرنده مورد اعتماد شماست ادامه دهید. '
          'فایل پس از باز شدن منوی اشتراک در کنترل شماست.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('انتخاب گیرنده'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _sharing = true);
    final (start, end) = _range;
    try {
      if (pdf) {
        await _export.sharePdf(
          profile: widget.profile,
          metric: widget.metric,
          start: start,
          end: end,
          records: _records,
        );
      } else {
        await _export.shareCsv(
          profile: widget.profile,
          metric: widget.metric,
          start: start,
          end: end,
          records: _records,
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ساخت/اشتراک فایل انجام نشد: $error')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (start, end) = _range;
    final stats = HealthReportSummary.calculate(widget.metric, _records);
    return Scaffold(
      appBar: AppBar(
        title: Text('نمایش به پزشک — ${widget.metric.label}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppSectionHeading('پروفایل: ${widget.profile.displayName}',
              icon: Icons.assignment_ind_outlined),
          const SizedBox(height: 6),
          const Text(
            'اطلاعات ثبت‌شده توسط کاربر/مراقب؛ تأیید پزشکی نشده.',
            style: TextStyle(color: Colors.blueGrey),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final days in [7, 30, 90])
                ChoiceChip(
                  label: Text('$days روز'),
                  selected: _custom == null && _days == days,
                  onSelected: _sharing
                      ? null
                      : (_) {
                          setState(() {
                            _custom = null;
                            _days = days;
                          });
                          _reload();
                        },
                ),
              ActionChip(
                avatar: const Icon(Icons.date_range_outlined),
                label: const Text('بازه سفارشی'),
                onPressed: _sharing ? null : _customDates,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('بازه: ${healthDateTimeLabel(start)} تا '
              '${healthDateTimeLabel(end)}'),
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            TextButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: Text(_error!),
            )
          else ...[
            Text('تعداد ثبت‌ها: ${_records.length}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            if (_records.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'در این بازه داده‌ای ثبت نشده است. '
                    'نمودار یا میانگین ساختگی نمایش داده نمی‌شود.',
                  ),
                ),
              )
            else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: HealthChart(metric: widget.metric, records: _records),
                ),
              ),
              const SizedBox(height: 10),
              Text('آمار توصیفی',
                  style: Theme.of(context).textTheme.titleMedium),
              if (stats.hasQualityWarning)
                Text(
                  '${stats.excludedCount} ثبت ناقص یا با واحد/شرایط ناسازگار '
                  'در محاسبات وارد نشده است؛ سوابق اصلی حفظ شده‌اند.',
                  style: const TextStyle(color: Colors.deepOrange),
                ),
              if (stats.stats.isEmpty)
                const Text('برای این بازه آمار معتبر وجود ندارد.'),
              for (final group in stats.stats.entries)
                Card(
                  child: ListTile(
                    title: Text(group.key),
                    subtitle: Text(
                      'تعداد: ${group.value.count}\n'
                      'کمینه: ${HealthNumber.format(group.value.minMilliunits)} '
                      '${widget.metric.unit} | '
                      'بیشینه: ${HealthNumber.format(group.value.maxMilliunits)} '
                      '${widget.metric.unit}\n'
                      'میانگین توصیفی: '
                      '${HealthNumber.format(group.value.meanMilliunits)} '
                      '${widget.metric.unit}',
                    ),
                    isThreeLine: true,
                  ),
                ),
              const SizedBox(height: 14),
              Text('جدول ثبت‌ها',
                  style: Theme.of(context).textTheme.titleMedium),
              for (final record in _records)
                Card(
                  child: ListTile(
                    title: Text(
                      '${HealthNumber.format(record.primaryMilliunits)}'
                      '${record.secondaryMilliunits == null ? '' : '/${HealthNumber.format(record.secondaryMilliunits!)}'}'
                      ' ${record.unit}',
                    ),
                    subtitle: Text(
                      'اندازه‌گیری: ${healthDateTimeLabel(record.observedAt)}\n'
                      'ثبت: ${healthDateTimeLabel(record.recordedAt)}'
                      '${record.context == null ? '' : '\n${healthContextLabel(record.context!)}'}'
                      '${record.note?.isNotEmpty == true ? '\n${record.note}' : ''}',
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 14),
            const Text('فایل‌ها فقط پس از تأیید شما وارد منوی اشتراک می‌شوند.'),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _sharing ? null : () => _share(pdf: true),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('خروجی PDF فارسی'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _sharing ? null : () => _share(pdf: false),
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text('خروجی CSV سازگار با Excel'),
            ),
            if (_sharing)
              const Center(child: CircularProgressIndicator()),
          ],
          const SizedBox(height: 20),
          const Text(
            'این نمایش گزارش ثبت‌های شخصی است و تفسیر پزشکی، تشخیص یا درمان ارائه نمی‌کند.',
            style: TextStyle(color: Colors.blueGrey),
          ),
        ],
      ),
    );
  }
}
