import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/core/ui/app_design.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
import 'package:medication_companion/features/medications/presentation/medication_home.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';
import 'package:medication_companion/main.dart';

/// Writes real Flutter-rendered reference previews during CI, so the visual
/// review can compare PNGs to the approved Persian design instead of relying
/// on the source code or a green widget test alone.
void main() {
  testWidgets('render full-screen previews of four rebuilt tabs and medicine details',
      (tester) async {
    // Widget tests default to Ahem (all text looks like square glyphs). Load
    // the bundled Persian UI font so these artifacts are legitimate visual
    // references, not unreadable test placeholders.
    final persianFont = FontLoader('NotoSansArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    await persianFont.load();
    final fallbackFont = FontLoader('Vazirmatn')
      ..addFont(rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf'));
    await fallbackFont.load();
    // Flutter bundles MaterialIcons when uses-material-design is enabled.
    final iconFont = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconFont.load();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profile = await ProfileRepository(db).createGuestProfile(forSelf: true);
    final medicines = MedicationRepository(db, clock: () { final now = DateTime.now(); return DateTime(now.year, now.month, now.day); });
    for (final data in [
      ('متفورمین ۵۰۰', '۱ عدد', 8),
      ('آملودیپین ۵', '۱ عدد', 9),
      ('ویتامین D', '۱ کپسول', 13),
      ('آهن', '۱ عدد', 20),
    ]) {
      await medicines.addDailyMedication(profileId: profile.id,
        name: data.$1, doseText: data.$2, time: TimeOfDayValue(data.$3, 0));
    }

    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key, child: MedicationBetaApp(databaseFactory: () => db)));
    await tester.pumpAndSettle();
    final folder = Directory('build/ui-previews');
    folder.createSync(recursive: true);

    Future<void> save(String filename) async {
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final render = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final picture = await render.toImage(pixelRatio: 2);
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        picture.dispose();
        await File('${folder.path}/$filename.png').writeAsBytes(bytes!.buffer.asUint8List());
      });
    }

    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!
      .extension<AppAppearance>()?.choice, AppThemeChoice.cyan);
    await save('01-today');
    await tester.tap(find.text('داروها'));
    await save('02-medicines');
    await tester.tap(find.text('افزودن دارو'));
    await tester.pumpAndSettle();
    expect(tester.widget<AppBar>(find.byType(AppBar)).foregroundColor,
      const Color(0xFF1E293B),
      reason: 'The new medication form uses a light, high-contrast app bar');
    await save('06-medication-form');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('متفورمین 500'));
    await save('03-medicine-detail');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('موجودی و بسته‌ها'));
    await tester.pumpAndSettle();
    expect(tester.widget<AppBar>(find.byType(AppBar)).titleTextStyle?.color,
      Colors.white);
    await save('07-stock');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('سلامت'));
    await save('04-health');
    await tester.scrollUntilVisible(find.text('ثبت فشار خون'), 240);
    await tester.tap(find.text('ثبت فشار خون'));
    await tester.pumpAndSettle();
    expect(tester.widget<AppBar>(find.byType(AppBar)).titleTextStyle?.color,
      Colors.white);
    await save('08-health-entry');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('بیشتر'));
    await save('05-more');
    await tester.tap(find.text('پروفایل‌ها'));
    await save('09-profiles');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('یادآوری‌ها'));
    await save('10-reminders');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('پشتیبان‌گیری'));
    await tester.pumpAndSettle();
    expect(tester.widget<AppBar>(find.byType(AppBar)).titleTextStyle?.color,
      Colors.white);
    await save('11-backup');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('پیگیری‌ها و ویزیت‌ها'));
    await tester.tap(find.text('پیگیری‌ها و ویزیت‌ها'));
    await tester.pumpAndSettle();
    expect(tester.widget<AppBar>(find.byType(AppBar)).titleTextStyle?.color,
      Colors.white);
    await save('12-care');

    // Keep real Flutter-rasterized daytime and nighttime Today examples for
    // design review. Use a separate database because the original app closes
    // its owned database when the first MaterialApp is unmounted.
    final daypartDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(daypartDb.close);
    final daypartProfiles = ProfileRepository(daypartDb);
    final daypartProfile = await daypartProfiles.createGuestProfile(
      forSelf: true, displayName: 'امیر');
    final daypartMedicines = MedicationRepository(daypartDb, clock: () => DateTime(2026, 11, 22));
    for (final data in [
      ('متفورمین ۵۰۰', '۱ عدد', 8),
      ('آملودیپین ۵', '۱ عدد', 9),
      ('ویتامین D', '۱ کپسول', 13),
      ('آهن', '۱ عدد', 20),
    ]) {
      await daypartMedicines.addDailyMedication(
        profileId: daypartProfile.id,
        name: data.$1, doseText: data.$2,
        time: TimeOfDayValue(data.$3, 0),
      );
    }
    Future<void> saveTodayAt(int hour, String name) async {
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: ThemeData(fontFamily: 'Vazirmatn'),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MedicationHome(
              repository: daypartMedicines,
              profileRepository: daypartProfiles,
              clock: () => DateTime(2026, 11, 22, hour),
            ),
          ),
        ),
      ));
      await save(name);
    }

    await saveTodayAt(9, '13-today-morning');
    await saveTodayAt(19, '14-today-night');
  });
}
