import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
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

    await tester.tap(find.text('شروع'));
    await tester.pumpAndSettle();
    final active = await profiles.activeProfile();
    expect(active, isNotNull);

    await tester.tap(find.text('داروها'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('افزودن دارو'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNWidgets(2));
    await tester.enterText(find.byType(TextField).at(0), 'داروی آزمایشی');
    await tester.enterText(find.byType(TextField).at(1), 'فقط برای تست');
    await tester.ensureVisible(find.text('ذخیره دارو'));
    await tester.tap(find.text('ذخیره دارو'));
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
    expect(find.text('ثبت مصرف و موجودی'), findsOneWidget);
    await tester.tap(find.text('ثبت بدون کسر'));
    await tester.pumpAndSettle();
    expect(find.text('مصرف شد'), findsOneWidget);

    await tester.tap(find.text('داروی آزمایشی').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('بازگرداندن ثبت'));
    await tester.pumpAndSettle();
    expect(find.text('ثبت مصرف'), findsOneWidget);
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
    await tester.tap(find.text('برای یکی از عزیزانم'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'مادر آزمایشی');
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
    await tester.tap(find.text('شروع'));
    await tester.pumpAndSettle();
    final profile = (await profiles.activeProfile())!;

    await tester.tap(find.text('داروها'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('افزودن دارو'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'داروی تست چندنوبتی');
    await tester.enterText(find.byType(TextField).at(1), 'صبح طبق نسخه');
    await tester.tap(find.text('افزودن نوبت دیگر'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(3));
    await tester.enterText(find.byType(TextField).at(2), 'عصر طبق نسخه');
    await tester.ensureVisible(find.text('ذخیره دارو'));
    await tester.tap(find.text('ذخیره دارو'));
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
    await tester.enterText(find.byType(TextField).at(0), 'داروی اصلاح‌شده');
    await tester.enterText(find.byType(TextField).at(1), 'دوز تازه ۲ عدد');
    await tester.ensureVisible(find.text('ذخیره تغییرات'));
    await tester.tap(find.text('ذخیره تغییرات'));
    await tester.pumpAndSettle();
    expect(
      (await medications.medicationsFor(profile.id)).single.name,
      'داروی اصلاح‌شده',
    );
    expect(find.text('برنامه جدید — از فردا'), findsOneWidget);
    expect(find.textContaining('دوز تازه ۲ عدد'), findsOneWidget);
    final today = DateTime.now();
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    expect(
      (await medications.dosesForDay(profile.id, today)).first.plan.doseText,
      'صبح طبق نسخه',
    );
    expect(
      (await medications.dosesForDay(profile.id, tomorrow)).first.plan.doseText,
      'دوز تازه ۲ عدد',
    );

    // A second edit must pre-fill and replace the *pending* schedule, not
    // accidentally revert to today's older plan.
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ویرایش'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller?.text,
      'دوز تازه ۲ عدد',
    );
    await tester.enterText(find.byType(TextField).at(1), 'دوز سوم ۳ عدد');
    await tester.ensureVisible(find.text('ذخیره تغییرات'));
    await tester.tap(find.text('ذخیره تغییرات'));
    await tester.pumpAndSettle();
    expect(find.textContaining('دوز سوم ۳ عدد'), findsOneWidget);
    expect(find.textContaining('دوز تازه ۲ عدد'), findsNothing);
    expect(
      (await medications.dosesForDay(profile.id, tomorrow)).first.plan.doseText,
      'دوز سوم ۳ عدد',
    );

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('بایگانی'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بایگانی شود'));
    await tester.pumpAndSettle();
    expect(await medications.medicationsFor(profile.id), isEmpty);
    await tester.tap(find.text('نمایش بایگانی (۱)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('بازیابی'));
    await tester.pumpAndSettle();
    expect(await medications.medicationsFor(profile.id), hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
