import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/core/ui/app_design.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
import 'package:medication_companion/features/medications/presentation/medication_home.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';
import 'package:medication_companion/main.dart';

void main() {
  testWidgets('approved UI tokens and Persian font are used by the app', (
    tester,
  ) async {
    await tester.pumpWidget(
      MedicationBetaApp(
        databaseFactory: () => AppDatabase.forTesting(NativeDatabase.memory()),
      ),
    );
    final theme = tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Vazirmatn');
    expect(theme.appBarTheme.titleTextStyle?.fontFamily, 'Vazirmatn');
    expect(theme.colorScheme.primary, AppThemeChoice.cyan.primary);
    expect(theme.scaffoldBackgroundColor, AppThemeChoice.cyan.page);
    expect(theme.extension<AppAppearance>()?.choice, AppThemeChoice.cyan);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('today groups appointments and medicines filter keeps data', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profiles = ProfileRepository(db);
    final medicines = MedicationRepository(db, clock: () { final now = DateTime.now(); return DateTime(now.year, now.month, now.day); });
    final profile = await profiles.createGuestProfile(forSelf: true);
    await medicines.addDailyMedication(
      profileId: profile.id,
      name: 'داروی صبح',
      doseText: 'یک عدد',
      time: const TimeOfDayValue(8, 0),
    );
    await medicines.addDailyMedication(
      profileId: profile.id,
      name: 'داروی شب',
      doseText: 'دو عدد',
      time: const TimeOfDayValue(21, 0),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: MedicationHome(
            repository: medicines,
            profileRepository: profiles,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('برنامهٔ مصرف امروز'), findsOneWidget);
    expect(find.text('صبح'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('عصر و شب'), 180);
    await tester.pumpAndSettle();
    expect(find.text('عصر و شب'), findsOneWidget);

    await tester.tap(find.text('داروها'));
    await tester.pumpAndSettle();
    expect(find.text('داروی صبح'), findsOneWidget);
    expect(find.text('داروی شب'), findsOneWidget);
    final rows = await medicines.medicationsFor(profile.id);
    for (final med in rows) {
      final card = find.byKey(ValueKey('medicine-card-${med.id}'));
      expect(card, findsOneWidget);
      expect(tester.widget<Material>(card).elevation, greaterThan(0));
      expect(find.ancestor(of: card, matching: find.byType(AppPanel)), findsNothing);
    }
    await tester.tap(find.text('کم‌موجودی'));
    await tester.pumpAndSettle();
    expect(find.text('دارویی با این نام پیدا نشد.'), findsOneWidget);
    await tester.tap(find.text('همه'));
    await tester.pumpAndSettle();
    expect(find.text('داروی صبح'), findsOneWidget);
    expect(find.text('داروی شب'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
