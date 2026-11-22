import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
import 'package:medication_companion/features/medications/presentation/medication_home.dart';
import 'package:medication_companion/features/medications/presentation/today_visuals.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';

void main() {
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
    expect(find.byKey(const Key('today-date-banner')), findsOneWidget);
    await tester.tap(find.byKey(const Key('today-notifications-button')));
    await tester.pumpAndSettle();
    expect(find.text('اعلان‌های امروز'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('today-unread-dot')), findsNothing);

    await tester.ensureVisible(find.text('قرص صبح'));
    await tester.tap(find.text('قرص صبح'));
    await tester.pumpAndSettle();
    expect(find.text('مصرف کردم'), findsOneWidget);
    expect(find.text('مصرف نکردم'), findsOneWidget);
    expect(find.text('مطمئن نیستم'), findsOneWidget);
    // Inline expansion must not open the old dose-action bottom sheet.
    expect(find.text('ثبت مصرف دارو'), findsNothing);
    await tester.ensureVisible(find.text('مصرف نکردم'));
    await tester.tap(find.text('مصرف نکردم'));
    await tester.pumpAndSettle();
    expect(find.text('ثبت‌شده‌ها'), findsOneWidget);
    expect(find.text('مصرف نشد'), findsOneWidget);
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
