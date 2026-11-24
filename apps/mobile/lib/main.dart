import 'dart:async' show unawaited;

import 'package:material_ui/material_ui.dart';

import 'core/storage/app_database.dart';
import 'core/ui/app_design.dart';
import 'features/medications/data/medication_repository.dart';
import 'features/medications/presentation/medication_home.dart';
import 'features/profiles/data/profile_repository.dart';
import 'features/reminders/data/android_reminder_port.dart';
import 'features/reminders/data/reminder_coordinator.dart';
import 'features/reminders/presentation/medication_alarm_screen.dart';
import 'features/care/data/care_repository.dart';
import 'features/care/data/care_reminder_coordinator.dart';
import 'features/care/data/android_care_reminder_port.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MedicationBetaApp());
}

/// Open the offline medication workspace directly; the M0 diagnostics are
/// no longer bundled into the app's startup code.
class MedicationBetaApp extends StatefulWidget {
  const MedicationBetaApp({super.key, this.databaseFactory});

  /// Test-only injection; normal startup opens the persistent local database.
  final AppDatabase Function()? databaseFactory;

  @override
  State<MedicationBetaApp> createState() => _MedicationBetaAppState();
}

class _MedicationBetaAppState extends State<MedicationBetaApp> {
  bool _darkMode = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'همراه دارو',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Vazirmatn',
        // One consistent Persian text font; Latin digits keep their ASCII shape.
        fontFamilyFallback: const ['NotoSansArabic'],
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
            fontFamily: 'Vazirmatn',
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
              fontFamily: 'Vazirmatn',
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
              fontFamily: 'Vazirmatn',
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
      darkTheme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Vazirmatn',
        fontFamilyFallback: const ['NotoSansArabic'],
        colorScheme: ColorScheme.fromSeed(seedColor: AppPalette.darkAccent,
          brightness: Brightness.dark,
          primary: AppPalette.darkAccent,
          onPrimary: AppPalette.darkBackground,
          surface: AppPalette.darkSurface,
          onSurface: AppPalette.darkInk),
        scaffoldBackgroundColor: AppPalette.darkBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppPalette.darkBackground,
          foregroundColor: AppPalette.darkInk,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(fontFamily: 'Vazirmatn',
            fontSize: 21, color: AppPalette.darkInk, fontWeight: FontWeight.bold)),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: AppPalette.darkSurface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppPalette.darkOutline)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppPalette.darkOutline)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppPalette.darkAccent, width: 1.5))),
        filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF176B68), foregroundColor: Colors.white,
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)))),
        outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
          foregroundColor: AppPalette.darkAccent,
          side: const BorderSide(color: AppPalette.darkOutline),
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)))),
        cardTheme: CardThemeData(color: AppPalette.darkSurface,
          elevation: 0, surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppPalette.darkOutline))),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppPalette.darkSurface,
          surfaceTintColor: Colors.transparent, showDragHandle: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)))),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: AppPalette.darkSurface,
          indicatorColor: AppPalette.darkMint, elevation: 0, height: 70),
      ),
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: MedicationBetaHome(databaseFactory: widget.databaseFactory,
        onThemeChanged: (dark) {
          if (mounted && _darkMode != dark) setState(() => _darkMode = dark);
        }),
    );
  }
}

class MedicationBetaHome extends StatefulWidget {
  const MedicationBetaHome({super.key, this.databaseFactory,
    this.onThemeChanged});
  final AppDatabase Function()? databaseFactory;
  final ValueChanged<bool>? onThemeChanged;

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

  void _showMedicationAlarm(String title, String body) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => MedicationAlarmScreen(title: title, body: body),
      ));
    });
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
        notifications: AndroidReminderPort(onAlarmOpen: _showMedicationAlarm),
      );
      final careReminders = CareReminderCoordinator(
        database: db,
        care: CareRepository(db),
        profiles: profiles,
        notifications: AndroidCareReminderPort(),
      );
      _database = db;
      unawaited(_restoreTheme(db));
      _workspace = MedicationHome(
        repository: medications,
        profileRepository: profiles,
        reminderCoordinator: reminders,
        careReminderCoordinator: careReminders,
        onThemeChanged: _saveTheme,
      );
    } catch (_) {
      if (db != null) unawaited(_closeDatabase(db));
      _startupError =
          'بازکردن اطلاعات محلی انجام نشد. '
          'برنامه را دوباره اجرا کنید؛ اطلاعات موجود حذف نشده‌اند.';
    }
  }

  Future<void> _restoreTheme(AppDatabase db) async {
    try {
      final row = await (db.select(db.appSettings)
        ..where((t) => t.key.equals('ui-dark-mode:v1'))).getSingleOrNull();
      if (mounted) widget.onThemeChanged?.call(row?.value == 'true');
    } catch (_) {
      // Appearance settings never block access to the user's records.
    }
  }

  Future<void> _saveTheme(bool dark) async {
    final db = _database;
    if (db == null) return;
    await db.into(db.appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(key: 'ui-dark-mode:v1', value: '$dark'));
    if (mounted) widget.onThemeChanged?.call(dark);
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
