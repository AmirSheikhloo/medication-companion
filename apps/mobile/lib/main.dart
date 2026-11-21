import 'dart:async' show unawaited;

import 'package:material_ui/material_ui.dart';

import 'core/storage/app_database.dart';
import 'core/ui/app_design.dart';
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
    return MaterialApp(
      title: 'همراه دارو',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'NotoSansArabic',
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          onPrimary: Colors.white,
          secondary: AppColors.accent,
          surface: Colors.white,
          onSurface: AppColors.ink,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          foregroundColor: AppColors.primaryDark,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontFamily: 'NotoSansArabic',
            color: AppColors.primaryDark,
            fontSize: 21,
            fontWeight: FontWeight.bold,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.outline),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
            textStyle: const TextStyle(
              fontFamily: 'NotoSansArabic',
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            minimumSize: const Size(0, 44),
            side: const BorderSide(color: AppColors.primary),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: AppColors.mint,
          elevation: 0,
          height: 70,
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(
              fontFamily: 'NotoSansArabic',
              fontSize: 11,
              color: AppColors.primaryDark,
            ),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          showDragHandle: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.lightMint,
          selectedColor: AppColors.mint,
          side: const BorderSide(color: AppColors.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
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
      _startupError =
          'بازکردن اطلاعات محلی انجام نشد. '
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
              Text(
                _startupError ?? 'اطلاعات محلی آماده نیست.',
                textAlign: TextAlign.center,
              ),
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
