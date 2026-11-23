import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:medication_companion/features/medications/presentation/medication_history_range_dialog.dart';

void main() {
  testWidgets('history range offers Jalali and Gregorian labels and 6-month preset',
      (tester) async {
    tester.view.physicalSize = const Size(430, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    DateTimeRange? selected;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => FilledButton(
        onPressed: () async {
          selected = await showMedicationHistoryRangeDialog(context: context);
        },
        child: const Text('فیلتر بازه'),
      )),
    )));
    await tester.tap(find.text('فیلتر بازه'));
    await tester.pumpAndSettle();
    expect(find.text('انتخاب بازه گزارش'), findsOneWidget);
    expect(find.text('از تاریخ'), findsOneWidget);
    expect(find.text('تا تاریخ'), findsOneWidget);
    await tester.tap(find.text('میلادی'));
    await tester.pumpAndSettle();
    expect(find.text('از تاریخ'), findsOneWidget);
    expect(find.text('تا تاریخ'), findsOneWidget);
    await tester.tap(find.text('۶ ماه اخیر'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('نمایش گزارش'));
    await tester.pumpAndSettle();
    expect(selected, isNotNull);
    expect(selected!.start.isBefore(selected!.end), isTrue);
    expect(selected!.end.isAfter(DateTime.now()), isFalse);
    expect(tester.takeException(), isNull);
  });
}
