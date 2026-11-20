import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/medications/presentation/medication_home.dart';
import 'package:medication_companion/main.dart';

void main() {
  testWidgets('beta startup error offers a non-destructive retry',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      MedicationBetaApp(
        databaseFactory: () {
          attempts++;
          if (attempts == 1) throw StateError('simulated startup failure');
          return AppDatabase.forTesting(NativeDatabase.memory());
        },
      ),
    );

    expect(find.textContaining('بازکردن اطلاعات محلی انجام نشد'),
        findsOneWidget);
    await tester.tap(find.text('تلاش دوباره'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.byType(MedicationHome), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
