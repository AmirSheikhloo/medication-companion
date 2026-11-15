import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MedicationM0App());
}

class MedicationM0App extends StatelessWidget {
  const MedicationM0App({super.key});

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFF40E0D0);
    return MaterialApp(
      title: 'آزمایش فنی همراه دارو',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: brand),
        scaffoldBackgroundColor: const Color(0xFFF8FCFC),
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const M0HomeScreen(),
    );
  }
}

class M0HomeScreen extends StatefulWidget {
  const M0HomeScreen({super.key});

  @override
  State<M0HomeScreen> createState() => _M0HomeScreenState();
}

class _M0HomeScreenState extends State<M0HomeScreen> {
  final _notifications = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _busy = false;
  String _status = 'در حال آماده‌سازی آزمایش…';
  String _zone = 'نامشخص';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      tzdata.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
      await _notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      if (!mounted) return;
      setState(() {
        _zone = info.identifier;
        _ready = true;
        _status = 'آماده؛ ابتدا مجوزها را فعال کنید.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'خطا در آماده‌سازی: $e');
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _notifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<void> _act(
    String successMessage,
    Future<void> Function() action,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      setState(() => _status = successMessage);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'انجام نشد: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestNotifications() async {
    final granted = await _android?.requestNotificationsPermission();
    if (granted == false) {
      throw StateError('مجوز اعلان داده نشد؛ آن را در تنظیمات گوشی فعال کنید.');
    }
  }

  Future<void> _requestExactAlarms() async {
    final granted = await _android?.requestExactAlarmsPermission();
    if (granted == false) {
      throw StateError('مجوز آلارم دقیق هنوز فعال نشده است.');
    }
  }

  Future<void> _requestFullScreen() async {
    final granted = await _android?.requestFullScreenIntentPermission();
    if (granted == false) {
      throw StateError('مجوز نمایش تمام‌صفحه هنوز فعال نشده است.');
    }
  }

  Future<void> _schedule({required bool fullScreen}) async {
    final seconds = fullScreen ? 120 : 60;
    final scheduled = tz.TZDateTime.now(tz.local).add(
      Duration(seconds: seconds),
    );
    await _notifications.zonedSchedule(
      id: fullScreen ? 202 : 101,
      title: fullScreen ? 'آزمایش زنگ تمام‌صفحه' : 'آزمایش یادآور دارو',
      body: fullScreen
          ? 'این فقط آزمایش فنی زنگ است؛ دارویی مصرف نکنید.'
          : 'این فقط یک اعلان آزمایشی است.',
      scheduledDate: scheduled,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          fullScreen ? 'm0_fullscreen_v1' : 'm0_normal_v1',
          fullScreen ? 'آزمایش زنگ' : 'آزمایش اعلان',
          channelDescription: 'آزمون فنی یادآور همراه دارو',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          fullScreenIntent: fullScreen,
          category: AndroidNotificationCategory.alarm,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> _cancelTests() async {
    await _notifications.cancel(id: 101);
    await _notifications.cancel(id: 202);
  }

  Future<void> _sharePersianPdf() async {
    // Every PDF font is bundled inside the APK: no network request is made.
    final regularBytes = await rootBundle.load(
      'assets/fonts/NotoSansArabic-Regular.ttf',
    );
    final boldBytes = await rootBundle.load(
      'assets/fonts/NotoSansArabic-Bold.ttf',
    );
    final regular = pw.Font.ttf(regularBytes);
    final bold = pw.Font.ttf(boldBytes);
    final pdf = pw.Document();
    const teal = PdfColor(0.0, 0.56, 0.53);
    const dark = PdfColor(0.11, 0.22, 0.23);

    pw.Widget label(String value, {bool isBold = false, double size = 12}) =>
        pw.Text(
          value,
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(
            font: isBold ? bold : regular,
            // Noto Sans Arabic omits common Latin punctuation such as '/' and '—'.
            // PDF's built-in Helvetica supplies those glyphs without a download.
            fontFallback: [pw.Font.helvetica()],
            fontSize: size,
            color: dark,
          ),
        );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(34),
        build: (context) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: const PdfColor(0.88, 0.97, 0.96),
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'گزارش آزمایشی برای ویزیت',
                      style: pw.TextStyle(
                        font: bold,
                        fontFallback: [pw.Font.helvetica()],
                        fontSize: 20,
                        color: teal,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    label('پروفایل فعال: مادر — فقط داده‌های نمونه'),
                  ],
                ),
              ),
              pw.SizedBox(height: 24),
              label('فشار خون ثبت‌شده', isBold: true, size: 15),
              pw.SizedBox(height: 10),
              label('شنبه ۲۴ آبان — ۱۲۵/۸۰ میلی‌متر جیوه'),
              label('یکشنبه ۲۵ آبان — ۱۲۱/۷۹ میلی‌متر جیوه'),
              label('دوشنبه ۲۶ آبان — ۱۲۸/۸۲ میلی‌متر جیوه'),
              pw.SizedBox(height: 22),
              label('داروهای ثبت‌شده', isBold: true, size: 15),
              pw.SizedBox(height: 10),
              label('داروی نمونه الف — طبق برنامه ثبت‌شده توسط کاربر'),
              label('داروی نمونه ب — پایان دوره ثبت‌شده'),
              pw.Spacer(),
              pw.Divider(color: teal),
              label(
                'این گزارش صرفاً نمایش اطلاعات ثبت‌شده است و تفسیر پزشکی ندارد.',
                size: 10,
              ),
            ],
          ),
        ),
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'm0_persian_visit_report.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF40E0D0),
        title: const Text('همراه دارو — آزمون M0'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('وضعیت آزمایش',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(_status),
                  Text('منطقه زمانی گوشی: $_zone'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text('۱. مجوزها',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          _button('فعال‌سازی اعلان‌ها',
              _ready ? () => _act('مجوز اعلان بررسی شد.', _requestNotifications) : null),
          _button('مجوز آلارم دقیق',
              _ready ? () => _act('صفحه مجوز آلارم بررسی شد.', _requestExactAlarms) : null),
          _button('مجوز نمایش تمام‌صفحه',
              _ready ? () => _act('مجوز نمایش تمام‌صفحه بررسی شد.', _requestFullScreen) : null),
          const SizedBox(height: 16),
          const Text('۲. آزمایش زنگ (بدون اینترنت)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          _button(
              'اعلان عادی — ۶۰ ثانیه دیگر',
              _ready
                  ? () => _act('اعلان برای ۶۰ ثانیه دیگر ثبت شد.',
                      () => _schedule(fullScreen: false))
                  : null),
          _button(
              'زنگ تمام‌صفحه — ۱۲۰ ثانیه دیگر',
              _ready
                  ? () => _act('زنگ برای ۱۲۰ ثانیه دیگر ثبت شد.',
                      () => _schedule(fullScreen: true))
                  : null),
          _button('لغو هر دو آزمایش',
              _ready ? () => _act('آزمایش‌های زمان‌بندی‌شده لغو شدند.', _cancelTests) : null),
          const SizedBox(height: 16),
          const Text('۳. آزمایش PDF فارسی',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          _button('ساخت و اشتراک گزارش PDF',
              _ready ? () => _act('PDF ساخته شد و صفحه اشتراک باز شد.', _sharePersianPdf) : null),
          const SizedBox(height: 16),
          const Text(
            'هشدار: این صفحه فقط آزمایش فنی است. هیچ پیشنهاد یا دستور مصرف دارویی ارائه نمی‌کند.',
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _button(String text, VoidCallback? onPressed) => Padding(
        padding: const EdgeInsets.only(top: 9),
        child: FilledButton.tonal(
          onPressed: _busy ? null : onPressed,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            alignment: Alignment.center,
          ),
          child: Text(text),
        ),
      );
}
