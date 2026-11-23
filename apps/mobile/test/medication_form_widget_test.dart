import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
import 'package:medication_companion/features/inventory/data/inventory_repository.dart';
import 'package:medication_companion/features/medications/presentation/medication_home.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';

void main() {
  testWidgets('save a demo medication through the actual form', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profiles = ProfileRepository(db);
    final medications = MedicationRepository(db);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: MedicationHome(
            repository: medications,
            profileRepository: profiles,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('ورود به عنوان مهمان'));
    await tester.tap(find.text('ورود به عنوان مهمان'));
    await tester.pumpAndSettle();
    final active = await profiles.activeProfile();
    expect(active, isNotNull);

    await tester.tap(find.text('داروها'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('افزودن دارو').first);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('medication-name-field')),
      'داروی آزمایشی');
    await tester.scrollUntilVisible(
      find.byKey(const Key('med-stock-1')), 220,
      scrollable: find.descendant(of: find.byType(ListView).first,
        matching: find.byType(Scrollable)).first);
    await tester.enterText(find.byKey(const Key('med-stock-1')), '10');
    await tester.tap(find.text('ثبت دارو'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      (await medications.medicationsFor(active!.id)).map((m) => m.name),
      contains('داروی آزمایشی'),
    );
    expect(find.text('داروی آزمایشی'), findsWidgets);

    await tester.tap(find.text('امروز'));
    await tester.pumpAndSettle();
    expect(find.text('داروی آزمایشی'), findsWidgets);
    // The approved Today layout has a greeting and grouped appointments;
    // the dose action can sit below the fold on a short test viewport.
    await tester.ensureVisible(find.text('داروی آزمایشی').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('داروی آزمایشی').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('مصرف کردم'));
    await tester.pumpAndSettle();
    expect(find.text('ثبت مصرف و موجودی'), findsNothing);
    expect(find.text('مصرف شد'), findsOneWidget);
    final medicine = (await medications.medicationsFor(active.id)).single;
    final stockAfter = await InventoryRepository(db).summary(active.id, medicine.id);
    expect(stockAfter.selected?.balanceMilliunits, 9000);

    await tester.tap(find.text('داروی آزمایشی').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('بازگرداندن ثبت'));
    await tester.pumpAndSettle();
    final stockUndone = await InventoryRepository(db).summary(active.id, medicine.id);
    expect(stockUndone.selected?.balanceMilliunits, 10000);
    // The inline action panel stays expanded after an undo so the user can
    // choose the correct state immediately, without opening another sheet.
    expect(find.text('مصرف کردم'), findsOneWidget);
    await tester.ensureVisible(find.text('مصرف کردم، بدون کسر موجودی'));
    await tester.pumpAndSettle();
    // The fixed bottom navigation can overlay the button's lower edge.
    await tester.drag(find.byType(ListView).first, const Offset(0, -220));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مصرف کردم، بدون کسر موجودی'));
    await tester.pumpAndSettle();
    expect(find.text('مصرف شد'), findsOneWidget);
    final stockNoDebit = await InventoryRepository(db).summary(active.id, medicine.id);
    expect(stockNoDebit.selected?.balanceMilliunits, 10000);
    expect(tester.takeException(), isNull);
  });
  testWidgets('managed profile dialog safely persists its entered name', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profiles = ProfileRepository(db);

    await tester.pumpWidget(
      MaterialApp(
        home: MedicationHome(
          repository: MedicationRepository(db),
          profileRepository: profiles,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('برای یکی از عزیزانم'));
    await tester.tap(find.text('برای یکی از عزیزانم'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ادامه'));
    await tester.pumpAndSettle();
    expect(find.text('برای ادامه، نام عزیزت رو بنویس.'), findsOneWidget);
    expect(await profiles.activeProfile(), isNull);
    await tester.enterText(find.byType(TextField).last, 'مادر آزمایشی');
    await tester.tap(find.text('ادامه'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect((await profiles.activeProfile())?.displayName, 'مادر آزمایشی');
  });

  testWidgets('manage two daily slots, edit, archive and restore in UI', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profiles = ProfileRepository(db);
    final medications = MedicationRepository(db);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: MedicationHome(
            repository: medications,
            profileRepository: profiles,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ورود به عنوان مهمان'));
    await tester.tap(find.text('ورود به عنوان مهمان'));
    await tester.pumpAndSettle();
    final profile = (await profiles.activeProfile())!;

    await tester.tap(find.text('داروها'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('افزودن دارو').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('medication-name-field')),
      'داروی تست چندنوبتی');
    await tester.enterText(find.byKey(const Key('med-dose-1')), '2');
    await tester.ensureVisible(find.text('افزودن ساعت مصرف'));
    await tester.tap(find.text('افزودن ساعت مصرف'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('med-dose-2')), '3');
    await tester.ensureVisible(find.byKey(const Key('med-stock-1')));
    await tester.enterText(find.byKey(const Key('med-stock-1')), '30');
    await tester.tap(find.text('ثبت دارو'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      await medications.dosesForDay(profile.id, DateTime.now()),
      hasLength(2),
    );

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ویرایش'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('medication-name-field')), 'داروی اصلاح‌شده');
    await tester.enterText(find.byKey(const Key('med-dose-1')), '4');
    await tester.ensureVisible(find.text('ذخیره تغییرات'));
    await tester.tap(find.text('ذخیره تغییرات'));
    await tester.pumpAndSettle();
    expect(
      (await medications.medicationsFor(profile.id)).single.name,
      'داروی اصلاح‌شده',
    );
    expect(find.text('برنامه جدید — از فردا'), findsOneWidget);
    expect(find.textContaining('4 عدد'), findsWidgets);
    final today = DateTime.now();
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    expect(
      (await medications.dosesForDay(profile.id, today)).first.plan.doseText,
      '2 عدد',
    );
    expect(
      (await medications.dosesForDay(profile.id, tomorrow)).first.plan.doseText,
      '4 عدد',
    );

    // A second edit must pre-fill and replace the *pending* schedule, not
    // accidentally revert to today's older plan.
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ویرایش'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byKey(const Key('med-dose-1'))).controller?.text,
      '4',
    );
    await tester.enterText(find.byKey(const Key('med-dose-1')), '5');
    await tester.ensureVisible(find.text('ذخیره تغییرات'));
    await tester.tap(find.text('ذخیره تغییرات'));
    await tester.pumpAndSettle();
    expect(find.textContaining('5 عدد'), findsWidgets);
    expect(find.textContaining('4 عدد'), findsNothing);
    expect(
      (await medications.dosesForDay(profile.id, tomorrow)).first.plan.doseText,
      '5 عدد',
    );

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    // The segmented archive filter and the open popup both use this label.
    // Target the popup action, not the archive filter behind the overlay.
    await tester.tap(find.text('بایگانی').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('بایگانی شود'));
    await tester.pumpAndSettle();
    expect(await medications.medicationsFor(profile.id), isEmpty);
    await tester.tap(find.text('نمایش بایگانی (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('بازیابی'));
    await tester.pumpAndSettle();
    expect(await medications.medicationsFor(profile.id), hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
