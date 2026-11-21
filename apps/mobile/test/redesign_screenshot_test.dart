import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';
import 'package:medication_companion/main.dart';

/// Writes real Flutter-rendered reference previews during CI, so the visual
/// review can compare PNGs to the approved Persian design instead of relying
/// on the source code or a green widget test alone.
void main() {
  testWidgets('render full-screen previews of four rebuilt tabs and medicine details',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profile = await ProfileRepository(db).createGuestProfile(forSelf: true);
    final medicines = MedicationRepository(db);
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
      final render = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final picture = await render.toImage(pixelRatio: 2);
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      picture.dispose();
      await File('${folder.path}/$filename.png').writeAsBytes(bytes!.buffer.asUint8List());
    }

    await save('01-today');
    await tester.tap(find.text('داروها'));
    await save('02-medicines');
    await tester.tap(find.text('متفورمین ۵۰۰'));
    await save('03-medicine-detail');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('سلامت'));
    await save('04-health');
    await tester.tap(find.text('بیشتر'));
    await save('05-more');
  });
}
