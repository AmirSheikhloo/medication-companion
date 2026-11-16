import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/care/data/care_repository.dart';
import 'package:medication_companion/features/care/presentation/care_hub_screen.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';

void main() {
  testWidgets('care planner can create an offline task and mark it done', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profile = await ProfileRepository(db).createGuestProfile(forSelf: true);
    final care = CareRepository(db);
    await tester.pumpWidget(MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl,
        child: CareHubScreen(profile: profile, repository: care)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('هنوز کاری ثبت نشده است.'), findsOneWidget);

    await tester.tap(find.text('کار جدید'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'پیگیری آزمایش');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(find.text('پیگیری آزمایش'), findsOneWidget);

    await tester.tap(find.text('پیگیری آزمایش'));
    await tester.pumpAndSettle();
    expect((await care.tasksFor(profile.id)).single.status, 'done');
  });

  testWidgets('visit details show persisted checklist and linked questions', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profile = await ProfileRepository(db).createGuestProfile(forSelf: true);
    final care = CareRepository(db);
    final visitId = await care.addVisit(
      profileId: profile.id,
      title: 'ویزیت نمونه', scheduledAt: DateTime(2027, 2, 4),
    );
    await care.addQuestion(
      profileId: profile.id, question: 'سؤال نمونه', visitId: visitId,
    );
    await tester.pumpWidget(MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl,
        child: CareHubScreen(profile: profile, repository: care)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ویزیت‌ها'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ویزیت نمونه'));
    await tester.pumpAndSettle();
    expect(find.text('پیش از ویزیت'), findsOneWidget);
    expect(find.text('پس از ویزیت'), findsOneWidget);
    expect(find.text('سؤال نمونه'), findsOneWidget);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    final items = await care.checklistFor(
      profileId: profile.id, visitId: visitId, phase: 'before',
    );
    expect(items.first.checked, isTrue);
  });
}
