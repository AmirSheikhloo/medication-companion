import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/health/data/health_repository.dart';
import 'package:medication_companion/features/health/domain/health_metric.dart';
import 'package:medication_companion/features/health/presentation/health_report_screen.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';

void main() {
  testWidgets('doctor view shows selected profile, graph, descriptive stats',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profile = await ProfileRepository(db).createGuestProfile(forSelf: true);
    final health = HealthRepository(db);
    await health.addMeasurement(
      profileId: profile.id,
      draft: HealthMeasurementDraft(
        metric: HealthMetric.pulse,
        primaryMilliunits: 72000,
        observedAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: HealthReportScreen(
        profile: profile, metric: HealthMetric.pulse, repository: health,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('نمایش به پزشک'), findsOneWidget);
    expect(find.text('پروفایل: ${profile.displayName}'), findsOneWidget);
    expect(find.text('تعداد ثبت‌ها: 1'), findsOneWidget);
    expect(find.text('آمار توصیفی'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('report with no records clearly says no measurements',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profile = await ProfileRepository(db).createGuestProfile(forSelf: true);
    await tester.pumpWidget(MaterialApp(
      home: HealthReportScreen(
        profile: profile,
        metric: HealthMetric.weight,
        repository: HealthRepository(db),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('تعداد ثبت‌ها: 0'), findsOneWidget);
    expect(find.textContaining('نمودار یا میانگین ساختگی'), findsOneWidget);
  });
}
