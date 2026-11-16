import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/health/data/health_repository.dart';
import 'package:medication_companion/features/health/presentation/health_tab.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';

void main() {
  testWidgets('user can enter a profile-scoped pressure record and see feedback',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profile = await ProfileRepository(db).createGuestProfile(forSelf: true);
    final health = HealthRepository(db);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: HealthTab(profile: profile, repository: health)),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('داده‌ای ثبت نشده'), findsOneWidget);
    await tester.tap(find.text('ثبت فشار خون'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '۱۲۵');
    await tester.enterText(fields.at(1), '۸۱');
    await tester.tap(find.text('ذخیره اندازه‌گیری'));
    await tester.pumpAndSettle();
    expect(find.textContaining('125/81'), findsOneWidget);
    expect(find.text('اندازه‌گیری ذخیره شد.'), findsOneWidget);
    expect((await health.measurementsFor(profileId: profile.id)), hasLength(1));
  });
}
