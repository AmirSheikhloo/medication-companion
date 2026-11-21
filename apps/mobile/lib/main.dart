import 'dart:async' show unawaited;
import 'package:material_ui/material_ui.dart';

import 'core/storage/app_database.dart';
import 'features/medications/data/medication_repository.dart';
import 'features/medications/presentation/medication_home.dart';
import 'features/profiles/data/profile_repository.dart';
import 'features/reminders/data/android_reminder_port.dart';
import 'features/reminders/data/reminder_coordinator.dart';
import 'features/care/data/care_repository.dart';
import 'features/care/data/care_reminder_coordinator.dart';
import 'features/care/data/android_care_reminder_port.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MedicationBetaApp());
}

/// Open the offline medication workspace directly; the M0 diagnostics are
/// no longer bundled into the app's startup code.
class MedicationBetaApp extends StatelessWidget {
  const MedicationBetaApp({super.key, this.databaseFactory});

  /// Test-only injection; normal startup opens the persistent local database.
  final AppDatabase Function()? databaseFactory;

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFF075F60);
    const accent = Color(0xFF40E0D0);
    return MaterialApp(
      title: 'همراه دارو',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'NotoSansArabic',
        colorScheme: ColorScheme.fromSeed(seedColor: accent).copyWith(
          primary: brand,
          onPrimary: Colors.white,
          secondary: accent,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF8FAFA),
          surfaceTintColor: Colors.transparent,
          foregroundColor: brand,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFFF8FAFA),
          indicatorColor: const Color(0xFFCEF5F1),
          surfaceTintColor: Colors.transparent,
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontFamily: 'NotoSansArabic', fontSize: 12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE1ECEB)),
          ),
        ),
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

