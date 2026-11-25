import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
import 'package:medication_companion/features/medications/presentation/medication_home.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';
import 'package:medication_companion/features/profiles/presentation/guest_welcome_screen.dart';

void main() {
  setUpAll(() async {
    // Load once, before widget tests begin. Loading a font inside each test
    // queues a delayed system-font relayout after that test has torn down.
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader('NotoSansArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'))).load();
    await (FontLoader('Vazirmatn')
      ..addFont(rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf'))).load();
  });

  void narrowScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('Persian welcome stays scrollable on narrow enlarged screens',
      (tester) async {
    narrowScreen(tester);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: 'NotoSansArabic',
        fontFamilyFallback: const ['Vazirmatn']),
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 640),
          textScaler: TextScaler.linear(1.4),
        ),
        child: GuestWelcomeScreen(onSelf: () {}, onLovedOne: () {}),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    await tester.ensureVisible(find.text('برای یکی از عزیزانم'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('long Persian medication name and instructions do not overflow',
      (tester) async {
    narrowScreen(tester);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profiles = ProfileRepository(db);
    final meds = MedicationRepository(db, clock: () { final now = DateTime.now(); return DateTime(now.year, now.month, now.day); });
    final profile = await profiles.createGuestProfile(
      forSelf: false,
      displayName: 'بیمار آزمایشی با یک نام طولانی برای بررسی نمایش',
    );
    await meds.addDailyMedication(
      profileId: profile.id,
      name: 'نام طولانی داروی آزمایشی برای بررسی کارت‌ها و فاصله‌های متن در صفحهٔ باریک',
      doseText: 'توضیحات طولانی مصرف آزمایشی که باید بدون بریدگی یا بیرون‌زدگی در چند سطر نمایش داده شود',
      time: const TimeOfDayValue(8, 15),
    );

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: 'NotoSansArabic',
        fontFamilyFallback: const ['Vazirmatn']),
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 640),
          textScaler: TextScaler.linear(1.3),
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: MedicationHome(
            repository: meds,
            profileRepository: profiles,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('داروها'));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
