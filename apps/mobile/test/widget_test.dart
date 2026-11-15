import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/main.dart';

void main() {
  testWidgets('The M0 screen presents both core tests', (tester) async {
    await tester.pumpWidget(const MedicationM0App());

    expect(find.text('همراه دارو — آزمون M0'), findsOneWidget);
    expect(find.text('۱. مجوزها'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
