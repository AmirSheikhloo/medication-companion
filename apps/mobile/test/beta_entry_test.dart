import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/medications/presentation/medication_home.dart';
import 'package:medication_companion/main.dart';

void main() {
  testWidgets('beta starts in the real medication workspace, not M0 diagnostics',
      (tester) async {
    await tester.pumpWidget(
      MedicationBetaApp(
        databaseFactory: () => AppDatabase.forTesting(NativeDatabase.memory()),
      ),
    );

    expect(find.byType(MedicationHome), findsOneWidget);
    expect(find.text('همراه دارو — آزمون M0'), findsNothing);

    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
