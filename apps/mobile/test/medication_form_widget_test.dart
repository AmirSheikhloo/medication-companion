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

    await tester.tap(find.text('برای خودم'));
    await tester.pumpAndSettle();
    final active = await profiles.activeProfile();
    expect(active, isNotNull);

    await tester.tap(find.text('داروها'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNWidgets(2));
    await tester.enterText(find.byType(TextField).at(0), 'داروی آزمایشی');
    await tester.enterText(find.byType(TextField).at(1), 'فقط برای تست');
    await tester.tap(find.text('ذخیره دارو'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect((await medications.medicationsFor(active!.id)).map((m) => m.name),
        contains('داروی آزمایشی'));
    expect(find.text('داروی آزمایشی'), findsWidgets);

    await tester.tap(find.text('امروز'));
    await tester.pumpAndSettle();
    expect(find.text('داروی آزمایشی'), findsWidgets);
    await tester.tap(find.text('مصرف کردم'));
    await tester.pumpAndSettle();
    expect(find.text('مصرف ثبت شد'), findsOneWidget);

    await tester.tap(find.text('بازگرداندن ثبت'));
    await tester.pumpAndSettle();
    expect(find.text('ثبت نشده'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
