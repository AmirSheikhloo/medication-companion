import 'dart:async' show unawaited;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'core/storage/app_database.dart';
import 'features/medications/data/medication_repository.dart';
import 'features/medications/presentation/medication_home.dart';
import 'features/profiles/data/profile_repository.dart';
import 'features/reminders/data/android_reminder_port.dart';
import 'features/reminders/data/reminder_coordinator.dart';
import 'features/care/data/care_repository.dart';
import 'features/care/data/care_reminder_coordinator.dart';
import 'features/care/data/android_care_reminder_port.dart';
import 'm0/test_timings.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MedicationBetaApp());
}

/// The real offline workspace is the initial route in beta builds. The
/// historical M0 diagnostics remain available in tests, but are not presented
/// to ordinary users on every app launch.
class MedicationBetaApp extends StatelessWidget {
  const MedicationBetaApp({super.key, this.databaseFactory});

  /// Test-only injection; normal startup opens the persistent local database.
  final AppDatabase Function()? databaseFactory;

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFF40E0D0);
    return MaterialApp(
      title: 'همراه دارو',
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
      home: MedicationBetaHome(databaseFactory: databaseFactory),
    );
  }
}

class MedicationBetaHome extends StatefulWidget {
  const MedicationBetaHome({super.key, this.databaseFactory});
  final AppDatabase Function()? databaseFactory;

  @override
  State<MedicationBetaHome> createState() => _MedicationBetaHomeState();
}

class _MedicationBetaHomeState extends State<MedicationBetaHome> {
  AppDatabase? _database;
  Widget? _workspace;
  String? _startupError;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  void _initialize() {
    AppDatabase? db;
    _workspace = null;
    _startupError = null;
    try {
      db = widget.databaseFactory?.call() ?? AppDatabase();
      final medications = MedicationRepository(db);
      final profiles = ProfileRepository(db);
      final reminders = ReminderCoordinator(
        database: db,
        medications: medications,
        profiles: profiles,
        notifications: AndroidReminderPort(),
      );
      final careReminders = CareReminderCoordinator(
        database: db,
        care: CareRepository(db),
        profiles: profiles,
        notifications: AndroidCareReminderPort(),
      );
      _database = db;
      _workspace = MedicationHome(
        repository: medications,
        profileRepository: profiles,
        reminderCoordinator: reminders,
        careReminderCoordinator: careReminders,
      );
    } catch (_) {
      if (db != null) unawaited(_closeDatabase(db));
      _startupError = 'بازکردن اطلاعات محلی انجام نشد. '
          'برنامه را دوباره اجرا کنید؛ اطلاعات موجود حذف نشده‌اند.';
    }
  }

  Future<void> _closeDatabase(AppDatabase db) async {
    try {
      await db.close();
    } catch (_) {
      // App shutdown has no awaitable lifecycle hook. Never attempt to wipe
      // local files or construct a replacement database on a close failure.
    }
  }

  @override
  void dispose() {
    final db = _database;
    _database = null;
    if (db != null) unawaited(_closeDatabase(db));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspace = _workspace;
    if (workspace != null) return workspace;
    return Scaffold(
      appBar: AppBar(title: const Text('همراه دارو')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, size: 36),
              const SizedBox(height: 12),
              Text(_startupError ?? 'اطلاعات محلی آماده نیست.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => setState(_initialize),
                child: const Text('تلاش دوباره'),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
    final delay = fullScreen
        ? m0FullScreenNotificationDelay
        : m0NormalNotificationDelay;
    final scheduled = tz.TZDateTime.now(tz.local).add(delay);
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

  Future<void> _openMedicationHome() async {
    final db = AppDatabase();
    final medications = MedicationRepository(db);
    final profiles = ProfileRepository(db);
    final reminders = ReminderCoordinator(
      database: db,
      medications: medications,
      profiles: profiles,
      notifications: AndroidReminderPort(),
    );
    final careReminders = CareReminderCoordinator(
      database: db,
      care: CareRepository(db),
      profiles: profiles,
      notifications: AndroidCareReminderPort(),
    );
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => MedicationHome(
            repository: medications,
            profileRepository: profiles,
            reminderCoordinator: reminders,
            careReminderCoordinator: careReminders,
          ),
        ),
      );
    } finally {
      await db.close();
    }
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
          const Text('M1 — ثبت آفلاین پروفایل و دارو',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          _button('ورود به بخش داروهای من', _openMedicationHome),
          const Text(
            'نسخه نمایشی: داده‌ها هنوز رمزگذاری نشده‌اند. فقط اطلاعات ساختگی وارد کنید.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),
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
              'اعلان عادی — ۵ ثانیه دیگر',
              _ready
                  ? () => _act('اعلان برای ۵ ثانیه دیگر ثبت شد.',
                      () => _schedule(fullScreen: false))
                  : null),
          _button(
              'زنگ تمام‌صفحه — ۱۰ ثانیه دیگر',
              _ready
                  ? () => _act('زنگ برای ۱۰ ثانیه دیگر ثبت شد.',
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
