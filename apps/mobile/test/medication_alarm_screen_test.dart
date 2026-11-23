import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:medication_companion/features/reminders/presentation/medication_alarm_screen.dart';

void main() {
  testWidgets('opted-in alarm shows medication text and optional instructions',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MedicationAlarmScreen(
        title: 'یادآور دارو',
        body: 'برای بیمار: استامینوفن 500\nبا آب کافی مصرف شود.',
      ),
    ));
    expect(find.text('یادآور دارو'), findsOneWidget);
    expect(find.textContaining('استامینوفن 500'), findsOneWidget);
    expect(find.textContaining('با آب کافی'), findsOneWidget);
    expect(find.text('متوجه شدم'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
