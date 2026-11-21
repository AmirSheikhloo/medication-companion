import 'package:material_ui/material_ui.dart';

import '../../../core/calendar/persian_date.dart';
import '../../../core/storage/app_database.dart';
import '../data/medication_repository.dart';
import '../domain/medication_week_report.dart';

const _weekTeal = Color(0xFF075F60);
const _weekPaleMint = Color(0xFFE1F8F6);

class MedicationWeekReportScreen extends StatefulWidget {
  const MedicationWeekReportScreen({
    super.key,
    required this.profile,
    required this.repository,
  });

  final Profile profile;
  final MedicationRepository repository;

  @override
  State<MedicationWeekReportScreen> createState() =>
      _MedicationWeekReportScreenState();
}

class _MedicationWeekReportScreenState extends State<MedicationWeekReportScreen> {
  MedicationWeekReport? _report;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final report = await MedicationWeekReportRepository(widget.repository)
          .forProfile(profileId: widget.profile.id);
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'گزارش هفتگی بارگذاری نشد: $error';
      });
    }
  }

  String _weekday(DateTime date) => switch (date.weekday) {
        DateTime.saturday => 'شنبه',
        DateTime.sunday => 'یکشنبه',
        DateTime.monday => 'دوشنبه',
        DateTime.tuesday => 'سه‌شنبه',
        DateTime.wednesday => 'چهارشنبه',
        DateTime.thursday => 'پنجشنبه',
        _ => 'جمعه',
      };

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(
        title: const Text('گزارش ۷ روز گذشته'),
        actions: [
          IconButton(
            tooltip: 'تازه‌سازی گزارش',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: TextButton(onPressed: _reload, child: Text(_error!)))
              : report == null
                  ? const Center(child: Text('گزارشی برای نمایش وجود ندارد.'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                  children: [
                    Text('برای ${widget.profile.displayName}',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    const Text(
                      'این گزارش فقط وضعیت‌هایی را نشان می‌دهد که شما ثبت کرده‌اید. '
                      '«ثبت‌نشده» الزاماً به معنی مصرف‌نکردن نیست.',
                      style: TextStyle(color: Colors.blueGrey),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      color: _weekPaleMint,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('خلاصهٔ هفتگی',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, runSpacing: 7, children: [
                              Chip(label: Text('مصرف ثبت شد: ${report.taken}')),
                              Chip(label: Text('مصرف نکردم: ${report.skipped}')),
                              Chip(label: Text('نامشخص: ${report.unknown}')),
                              Chip(label: Text('ثبت‌نشده: ${report.pending}')),
                            ]),
                            const SizedBox(height: 4),
                            Text('از ${report.total} نوبت برنامه‌ریزی‌شده، '
                                '${report.registered} نوبت تعیین‌وضعیت شده است.'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('نمای روزانه',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    for (final day in report.days)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(child: Text(
                                  '${_weekday(day.day)}، ${persianDateLabel(day.day)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                )),
                                Text(day.total == 0
                                    ? 'نوبتی نداشتید'
                                    : '${day.taken} از ${day.total} مصرف ثبت‌شده'),
                              ]),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: day.takenShare,
                                  minHeight: 7,
                                  color: _weekTeal,
                                  backgroundColor: const Color(0xFFE6EEEE),
                                ),
                              ),
                              if (day.skipped + day.unknown + day.pending > 0) ...[
                                const SizedBox(height: 5),
                                Text('مصرف نکردم: ${day.skipped} · '
                                    'نامشخص: ${day.unknown} · '
                                    'ثبت‌نشده: ${day.pending}',
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.blueGrey)),
                              ],
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    const Text(
                      'محاسبات برای برنامهٔ داروهای فعال است. داروهای بایگانی‌شده '
                      'در آمار این نسخه لحاظ نمی‌شوند؛ برای روزهای پیش از '
                      'ثبت یک دارو هم نوبت ساختگی در نظر گرفته نمی‌شود.',
                      style: TextStyle(color: Colors.blueGrey),
                    ),
                  ],
                ),
    );
  }
}
