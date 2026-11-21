import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
import 'package:medication_companion/features/medications/presentation/medication_home.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';

void main() {
  testWidgets('beta searches Persian medicine names and summarizes today',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profiles = ProfileRepository(db);
    final medications = MedicationRepository(db);
    final profile = await profiles.createGuestProfile(forSelf: true);
    await medications.addDailyMedication(
      profileId: profile.id,
      name: 'ایبوپروفن',
      doseText: 'طبق نسخه',
      time: const TimeOfDayValue(8, 0),
    );
    await medications.addDailyMedication(
      profileId: profile.id,
      name: 'استامینوفن',
      doseText: 'طبق نسخه',
      time: const TimeOfDayValue(20, 0),
    );

    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MedicationHome(
          repository: medications,
          profileRepository: profiles,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('خلاصه امروز'), findsOneWidget);
    expect(find.textContaining('ثبت‌نشده: ۲'), findsOneWidget);

    await tester.tap(find.text('داروها'));
    await tester.pumpAndSettle();
    expect(find.text('ایبوپروفن'), findsOneWidget);
    expect(find.text('استامینوفن'), findsOneWidget);

    await tester.tap(find.byTooltip('جست‌وجوی دارو'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('medication-search-field')),
      'ايبو',
    );
    await tester.pumpAndSettle();
    expect(find.text('ایبوپروفن'), findsOneWidget);
    expect(find.text('استامینوفن'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('medication-search-field')),
      'ناموجود',
    );
    await tester.pumpAndSettle();
    expect(find.text('دارویی با این نام پیدا نشد.'), findsOneWidget);

    await tester.tap(find.byTooltip('بستن جست‌وجوی دارو'));
    await tester.pumpAndSettle();
    expect(find.text('ایبوپروفن'), findsOneWidget);
    expect(find.text('استامینوفن'), findsOneWidget);
    await tester.tap(find.text('بیشتر'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('تنظیمات زبان و صفحه‌کلید'), 160,
      scrollable: find.byType(Scrollable).last);
    // On a 600px test viewport this tile otherwise sits behind the fixed
    // bottom navigation bar, even though it is within the scroll viewport.
    await tester.drag(find.byType(ListView).last, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تنظیمات زبان و صفحه‌کلید'));
    await tester.pumpAndSettle();
    expect(find.text('بازکردن تنظیمات زبان کیبورد'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
