import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/inventory/data/inventory_repository.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
import 'package:medication_companion/features/medications/presentation/medication_home.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';

void main() {
  void configureSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(950, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> openHome(
    WidgetTester tester,
    MedicationRepository medications,
    ProfileRepository profiles,
  ) async {
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
  }

  Future<void> tapTaken(WidgetTester tester) async {
    final button = find.text('مصرف کردم');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('without inventory, Taken is one tap, tracking only, with undo',
      (tester) async {
    configureSize(tester);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profiles = ProfileRepository(db);
    final medications = MedicationRepository(db);
    final profile = await profiles.createGuestProfile(forSelf: true);
    await medications.addDailyMedication(
      profileId: profile.id, name: 'ویتامین آزمایشی', doseText: '۱ عدد',
      time: const TimeOfDayValue(8, 0),
    );
    await openHome(tester, medications, profiles);
    await tapTaken(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('مصرف ثبت شد'), findsOneWidget);
    expect(find.text('مصرف ثبت شد؛ موجودی تغییر نکرد.'), findsOneWidget);
    expect((await medications.dosesForDay(profile.id, DateTime.now()))
        .single.stockDebited, isFalse);

    await tester.tap(find.text('بازگرداندن ثبت'));
    await tester.pumpAndSettle();
    expect(find.text('ثبت نشده'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one tap deducts exact saved fractional amount, undo restores',
      (tester) async {
    configureSize(tester);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profiles = ProfileRepository(db);
    final medications = MedicationRepository(db);
    final inventory = InventoryRepository(db);
    final profile = await profiles.createGuestProfile(forSelf: true);
    final medId = await medications.addDailyMedication(
      profileId: profile.id, name: 'داروی تست کسری', doseText: '۲٫۵ عدد',
      time: const TimeOfDayValue(8, 0),
    );
    await inventory.addPackage(
      profileId: profile.id, medicationId: medId, unit: 'عدد',
      initialMilliunits: 10000, selectForUse: true,
    );
    await inventory.setDoseDebitPreset(
      profileId: profile.id, medicationId: medId,
      unit: 'عدد', quantityMilliunits: 2500,
    );
    await openHome(tester, medications, profiles);
    expect(find.textContaining('کسر خودکار: ۲٫۵ عدد'), findsOneWidget);
    await tapTaken(tester);
    expect(find.text('ثبت مصرف و موجودی'), findsNothing);
    expect((await inventory.summary(profile.id, medId))
        .selected!.balanceMilliunits, 7500);
    final dose = (await medications.dosesForDay(profile.id, DateTime.now())).single;
    expect(dose.stockDebited, isTrue);
    await tester.tap(find.text('بازگرداندن ثبت'));
    await tester.pumpAndSettle();
    expect((await inventory.summary(profile.id, medId))
        .selected!.balanceMilliunits, 10000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('insufficient stock stops the dose and suggests stock repair',
      (tester) async {
    configureSize(tester);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profiles = ProfileRepository(db);
    final medications = MedicationRepository(db);
    final inventory = InventoryRepository(db);
    final profile = await profiles.createGuestProfile(forSelf: true);
    final medId = await medications.addDailyMedication(
      profileId: profile.id, name: 'داروی کم‌موجودی', doseText: '۲ عدد',
      time: const TimeOfDayValue(8, 0),
    );
    await inventory.addPackage(
      profileId: profile.id, medicationId: medId, unit: 'عدد',
      initialMilliunits: 1000, selectForUse: true,
    );
    await inventory.setDoseDebitPreset(
      profileId: profile.id, medicationId: medId,
      unit: 'عدد', quantityMilliunits: 2000,
    );
    await openHome(tester, medications, profiles);
    await tapTaken(tester);
    expect(find.textContaining('موجودی بسته برای این نوبت کافی نیست'), findsWidgets);
    expect((await medications.dosesForDay(profile.id, DateTime.now()))
        .single.status, 'pending');
    expect((await inventory.summary(profile.id, medId))
        .selected!.balanceMilliunits, 1000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unit mismatch blocks normal Taken; overflow allows exceptional manual no-debit',
      (tester) async {
    configureSize(tester);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profiles = ProfileRepository(db);
    final medications = MedicationRepository(db);
    final inventory = InventoryRepository(db);
    final profile = await profiles.createGuestProfile(forSelf: true);
    final medId = await medications.addDailyMedication(
      profileId: profile.id, name: 'داروی با واحد متفاوت', doseText: '۱ عدد',
      time: const TimeOfDayValue(8, 0),
    );
    await inventory.addPackage(
      profileId: profile.id, medicationId: medId, unit: 'بسته',
      initialMilliunits: 3000, selectForUse: true,
    );
    await inventory.setDoseDebitPreset(
      profileId: profile.id, medicationId: medId,
      unit: 'عدد', quantityMilliunits: 1000,
    );
    await openHome(tester, medications, profiles);
    await tapTaken(tester);
    expect((await medications.dosesForDay(profile.id, DateTime.now()))
        .single.status, 'pending');
    final menu = find.byTooltip('گزینه‌های بیشتر این نوبت');
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text('مصرف نکردم'), findsOneWidget);
    expect(find.text('مطمئن نیستم'), findsOneWidget);
    expect(find.text('ثبت مصرف بدون کسر موجودی'), findsOneWidget);
    await tester.tap(find.text('ثبت مصرف بدون کسر موجودی'));
    await tester.pumpAndSettle();
    final dose = (await medications.dosesForDay(profile.id, DateTime.now())).single;
    expect(dose.status, 'taken');
    expect(dose.stockDebited, isFalse);
    expect((await inventory.summary(profile.id, medId))
        .selected!.balanceMilliunits, 3000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overflow contains skipped and unknown, no extra confirmation',
      (tester) async {
    configureSize(tester);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profiles = ProfileRepository(db);
    final medications = MedicationRepository(db);
    final profile = await profiles.createGuestProfile(forSelf: true);
    await medications.addDailyMedication(
      profileId: profile.id, name: 'داروی گزینه‌های بیشتر', doseText: '۱ عدد',
      time: const TimeOfDayValue(8, 0),
    );
    await openHome(tester, medications, profiles);
    await tester.tap(find.byTooltip('گزینه‌های بیشتر این نوبت'));
    await tester.pumpAndSettle();
    expect(find.text('ثبت مصرف بدون کسر موجودی'), findsNothing);
    await tester.tap(find.text('مصرف نکردم'));
    await tester.pumpAndSettle();
    expect((await medications.dosesForDay(profile.id, DateTime.now()))
        .single.status, 'skipped');
    await tester.tap(find.text('بازگرداندن ثبت'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('گزینه‌های بیشتر این نوبت'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مطمئن نیستم'));
    await tester.pumpAndSettle();
    expect((await medications.dosesForDay(profile.id, DateTime.now()))
        .single.status, 'unknown');
    expect(tester.takeException(), isNull);
  });
}
