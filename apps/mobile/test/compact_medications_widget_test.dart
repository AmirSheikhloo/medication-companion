import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
import 'package:medication_companion/features/medications/presentation/medication_home.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';

void main() {
  testWidgets('seven drugs use compact rows with on-demand details and filters',
      (tester) async {
    tester.view.physicalSize = const Size(430, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profiles = ProfileRepository(db);
    final medications = MedicationRepository(db);
    final profile = await profiles.createGuestProfile(forSelf: true);
    const names = [
      'متفورمین',
      'ویتامین دی',
      'آملودیپین',
      'لووتیروکسین',
      'امگا ۳',
      'لوزارتان',
      'آهن',
    ];
    for (var i = 0; i < names.length; i++) {
      await medications.addDailyMedication(
        profileId: profile.id,
        name: names[i],
        doseText: 'طبق نسخه',
        time: TimeOfDayValue(7 + i, 0),
      );
    }

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
    await tester.tap(find.text('داروها'));
    await tester.pumpAndSettle();

    expect(find.text('همه (7)'), findsOneWidget);
    expect(find.text('متفورمین'), findsOneWidget);
    expect(find.text('آهن'), findsOneWidget);
    expect(find.text('موجودی'), findsNothing);

    await tester.tap(find.text('متفورمین'));
    await tester.pumpAndSettle();
    expect(find.text('موجودی'), findsOneWidget);
    expect(find.text('ویرایش'), findsOneWidget);

    await tester.tap(find.text('ویتامین دی'));
    await tester.pumpAndSettle();
    expect(find.text('موجودی'), findsOneWidget);

    await tester.tap(find.text('کم‌موجودی'));
    await tester.pumpAndSettle();
    expect(find.text('داروی کم‌موجودی در فهرست فعال پیدا نشد.'),
        findsOneWidget);

    await tester.tap(find.text('همه (7)'));
    await tester.pumpAndSettle();
    expect(find.text('متفورمین'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
