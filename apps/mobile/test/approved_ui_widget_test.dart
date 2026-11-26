import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/core/ui/app_design.dart';
import 'package:medication_companion/core/ui/redesign_widgets.dart';
import 'package:medication_companion/features/inventory/data/inventory_repository.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
import 'package:medication_companion/features/medications/presentation/medication_home.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';
import 'package:medication_companion/main.dart';

void main() {
  testWidgets('shared motion honors reduced animations', (tester) async {
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Builder(builder: (context) {
        expect(AppMotion.duration(context), Duration.zero);
        const child = SizedBox();
        expect(AppMotion.routeTransition(context, const AlwaysStoppedAnimation<double>(0), child), same(child));
        return child;
      }),
    )));
  });

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

  testWidgets('mixed stock alerts retain distinct colors and critical edge in RTL',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profiles = ProfileRepository(db);
    final now = DateTime.now();
    final medicines = MedicationRepository(db,
      clock: () => DateTime(now.year, now.month, now.day));
    final profile = await profiles.createGuestProfile(forSelf: true);
    final med = await medicines.addDailyMedication(profileId: profile.id,
      name: 'داروی آزمایشی', doseText: '1 عدد',
      time: const TimeOfDayValue(8, 0));
    final inventory = InventoryRepository(db);
    await inventory.addPackage(profileId: profile.id, medicationId: med,
      label: 'منقضی', unit: 'عدد', initialMilliunits: 4000,
      expiryIso: '2000-01-01', expiryPrecision: 'day');
    await inventory.addPackage(profileId: profile.id, medicationId: med,
      label: 'معتبر', unit: 'عدد', initialMilliunits: 2000,
      selectForUse: true);
    final healthy = await inventory.addPackage(profileId: profile.id,
      medicationId: med, label: 'بسته کافی', unit: 'عدد', initialMilliunits: 12000);
    await inventory.setLowStockThreshold(profileId: profile.id,
      medicationId: med, thresholdMilliunits: 5000);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppAppearance(AppThemeChoice.cyan)]),
      home: Directionality(textDirection: TextDirection.rtl,
        child: MedicationHome(repository: medicines, profileRepository: profiles))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('داروها'));
    await tester.pumpAndSettle();
    final card = find.byKey(ValueKey('medicine-card-$med'));
    expect(card, findsOneWidget);
    final pills = tester.widgetList<AppStatusPill>(
      find.descendant(of: card, matching: find.byType(AppStatusPill))).toList();
    expect(pills.singleWhere((p) => p.text == 'بسته منقضی شده').color,
      AppPalette.danger);
    expect(pills.singleWhere((p) => p.text == 'رو به اتمام').color,
      AppPalette.warning);
    final edge = tester.widgetList<Container>(
      find.descendant(of: card, matching: find.byType(Container)))
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .map((d) => d.border)
      .whereType<BorderDirectional>()
      .single;
    expect(edge.start.width, 6);
    expect(edge.start.color, AppPalette.dangerStripe);
    expect(Directionality.of(tester.element(card)), TextDirection.rtl);
    expect(edge.end.width, 0);
    await tester.tap(card);
    await tester.pumpAndSettle();
    final scheduleHeader = find.byKey(const Key('detail-schedule-header'));
    final stockHeader = find.byKey(const Key('detail-stock-header'));
    final scheduleSection = find.byKey(const Key('detail-schedule-section'));
    final stockSection = find.byKey(const Key('detail-stock-section'));
    for (final (section, header) in [(scheduleSection, scheduleHeader),
      (stockSection, stockHeader)]) {
      expect(find.descendant(of: section, matching: header), findsOneWidget);
      expect(find.descendant(of: section, matching: find.byType(AppPanel)), findsOneWidget);
      expect(tester.widget<Container>(header).decoration, isA<BoxDecoration>());
      expect((tester.widget<Container>(header).decoration! as BoxDecoration).gradient,
        isA<LinearGradient>());
    }
    expect(tester.widget<Container>(scheduleHeader).decoration,
      tester.widget<Container>(stockHeader).decoration);
    expect(find.descendant(of: stockSection,
      matching: find.byKey(ValueKey('package-row-$healthy'))), findsOneWidget);
    expect(find.descendant(of: stockSection,
      matching: find.text('افزودن بسته جدید')), findsOneWidget);
    final secondary = find.byKey(const Key('stock-alert-secondary-actions'));
    expect(secondary, findsNWidgets(2));
    for (final row in tester.widgetList<Row>(secondary)) {
      expect(row.children.whereType<Expanded>(), hasLength(2));
    }
    expect(tester.widgetList<AppPanel>(find.byType(AppPanel))
      .any((p) => p.color == AppPalette.warningSurface), isTrue);
    final radio = find.byKey(Key('select-package-$healthy'));
    await tester.ensureVisible(radio);
    await tester.pumpAndSettle();
    await tester.tap(radio);
    await tester.pumpAndSettle();
    expect((await inventory.summary(profile.id, med)).selectedPackageId, healthy);
    expect(find.text('کمبود: معتبر'), findsNothing);
    expect(find.byKey(const Key('stock-alert-secondary-actions')), findsOneWidget);
    expect(find.descendant(of: find.byKey(ValueKey('package-row-$healthy')),
      matching: find.byType(AnimatedContainer)), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
