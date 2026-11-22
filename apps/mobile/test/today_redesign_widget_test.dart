import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
import 'package:medication_companion/features/medications/presentation/medication_home.dart';
import 'package:medication_companion/features/medications/presentation/today_visuals.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';

void main() {
  test('compact Persian date and dose-outcome colors are consistent', () {
    expect(todayReadablePersianDate(DateTime(2026, 11, 22)),
      'یکشنبه، ۱ آذر');
    expect(todayDoseStatusColor('taken'), const Color(0xFF16995E));
    expect(todayDoseStatusColor('skipped'), const Color(0xFFD34E58));
    expect(todayDoseStatusColor('unknown'), const Color(0xFFDD962E));
    expect(todayDoseCardBackground('skipped'), const Color(0xFFF9DEE3));
    expect(todayDoseCardBackground('unknown'), const Color(0xFFFFE8CB));
    expect(todayDoseCardBackground('taken'), const Color(0xFFD9EFE4));
    expect(todayDoseCardBackground('pending'), Colors.white);
  });

  test('greeting and sky always agree across time boundaries', () {
    expect(todaySkyPhaseForHour(5), TodaySkyPhase.morning);
    expect(todayGreetingForHour(8), 'صبح بخیر');
    expect(todaySkyPhaseForHour(11), TodaySkyPhase.noon);
    expect(todayGreetingForHour(14), 'ظهر بخیر');
    expect(todaySkyPhaseForHour(16), TodaySkyPhase.evening);
    expect(todayGreetingForHour(17), 'عصر بخیر');
    expect(todaySkyPhaseForHour(18), TodaySkyPhase.night);
    expect(todayGreetingForHour(18), 'شب بخیر');
    expect(todaySkyPhaseForHour(0), TodaySkyPhase.night);
  });

  testWidgets('due alerts get a red dot until notifications are seen',
      (tester) async {
    // Match the Android emulator viewport; the default 800×600 widget-test
    // viewport puts this long schedule behind its fixed bottom navigation.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profiles = ProfileRepository(db);
    final medicines = MedicationRepository(db);
    final me = await profiles.createGuestProfile(forSelf: true);
    await medicines.addDailyMedication(
      profileId: me.id,
      name: 'قرص صبح',
      doseText: 'یک عدد',
      time: const TimeOfDayValue(8, 0),
    );
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MedicationHome(
          repository: medicines,
          profileRepository: profiles,
          clock: () => DateTime(2026, 11, 22, 18, 15),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('شب بخیر'), findsOneWidget);
    expect(find.byKey(const Key('today-unread-dot')), findsOneWidget);
    expect(find.byKey(const Key('today-date-banner')), findsNothing);
    expect(find.byKey(const Key('today-date-heading')), findsOneWidget);
    expect(find.byKey(const Key('today-multistatus-ring')), findsOneWidget);
    await tester.tap(find.byKey(const Key('today-notifications-button')));
    await tester.pumpAndSettle();
    expect(find.text('اعلان‌های امروز'), findsOneWidget);
    // The notification panel is a modal sheet without an AppBar back button.
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('today-unread-dot')), findsNothing);

    await tester.ensureVisible(find.text('قرص صبح'));
    await tester.drag(find.byKey(const Key('today-scroll-list')),
      const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('قرص صبح'));
    await tester.pumpAndSettle();
    expect(find.text('مصرف کردم'), findsOneWidget);
    expect(find.text('مصرف نکردم'), findsOneWidget);
    expect(find.text('مطمئن نیستم'), findsOneWidget);
    // Inline expansion must not open the old dose-action bottom sheet.
    expect(find.text('ثبت مصرف دارو'), findsNothing);
    await tester.ensureVisible(find.text('مصرف نکردم'));
    await tester.drag(find.byKey(const Key('today-scroll-list')),
      const Offset(0, -80));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مصرف نکردم'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('ثبت‌شده‌ها'), 120);
    await tester.pumpAndSettle();
    expect(find.text('ثبت‌شده‌ها'), findsOneWidget);
    expect(find.text('مصرف نشد'), findsOneWidget);
    final recordedCard = find.ancestor(
      of: find.text('قرص صبح'), matching: find.byType(AnimatedContainer));
    final animated = tester.widget<AnimatedContainer>(recordedCard);
    expect((animated.decoration! as BoxDecoration).color,
      todayDoseCardBackground('skipped'));
  });

  testWidgets('future doses have no unread alert dot and picker is rounded',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profiles = ProfileRepository(db);
    final medicines = MedicationRepository(db);
    final me = await profiles.createGuestProfile(forSelf: true,
      displayName: 'امیر');
    await medicines.addDailyMedication(
      profileId: me.id,
      name: 'قرص شب',
      doseText: 'دو عدد',
      time: const TimeOfDayValue(23, 0),
    );
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MedicationHome(
          repository: medicines,
          profileRepository: profiles,
          clock: () => DateTime(2026, 11, 22, 9, 30),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('صبح بخیر'), findsOneWidget);
    expect(find.byKey(const Key('today-unread-dot')), findsNothing);
    await tester.tap(find.byKey(const Key('today-profile-selector')));
    await tester.pumpAndSettle();
    expect(find.text('انتخاب شخص'), findsOneWidget);
    expect(find.text('امیر'), findsWidgets);
  });
}
