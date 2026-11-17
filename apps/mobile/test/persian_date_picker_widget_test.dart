import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/core/calendar/persian_date_picker.dart';

void main() {
  testWidgets('accepts a Persian date and returns Gregorian without time shifts', (tester) async {
    DateTime? selected;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => FilledButton(
        onPressed: () async => selected = await showPersianDatePicker(
          context: context,
          initialDate: DateTime(2026, 11, 17),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        ),
        child: const Text('open'),
      ),
    ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('انتخاب از تقویم میلادی'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '۱۴۰۵/۰۱/۰۱');
    await tester.tap(find.text('تأیید تاریخ'));
    await tester.pumpAndSettle();
    expect(selected, DateTime(2026, 3, 21));
  });

  testWidgets('invalid Esfand date remains open with visible error', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => FilledButton(
        onPressed: () => showPersianDatePicker(
          context: context,
          initialDate: DateTime(2026, 11, 17),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        ),
        child: const Text('open'),
      ),
    ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '۱۴۰۴/۱۲/۳۰');
    await tester.tap(find.text('تأیید تاریخ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('سازگار نیست'), findsOneWidget);
    expect(find.text('تأیید تاریخ'), findsOneWidget);
  });
}
