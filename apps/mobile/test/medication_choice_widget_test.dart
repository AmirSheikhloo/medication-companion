import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:medication_companion/core/ui/medication_controls.dart';

void main() {
  testWidgets('rounded selector opens a soft bottom sheet and chooses a value',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = 'عدد';
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: StatefulBuilder(builder: (context, setState) =>
        Center(child: SizedBox(width: 210,
          child: MedicationChoiceField(
            value: selected,
            label: 'واحد مصرف',
            options: const ['عدد', 'میلی‌لیتر', 'لیتر'],
            optionLabels: const {'میلی‌لیتر': 'میلی‌لیتر (سی‌سی)'},
            commonOptions: const {'میلی‌لیتر'},
            onChanged: (v) => setState(() => selected = v),
          )),
        )),
    )));
    expect(find.text('عدد'), findsOneWidget);
    await tester.tap(find.text('عدد'));
    await tester.pumpAndSettle();
    expect(find.text('لیتر'), findsOneWidget);
    expect(find.text('میلی‌لیتر (سی‌سی)'), findsOneWidget);
    expect(find.text('پرکاربرد'), findsOneWidget);
    await tester.tap(find.text('لیتر'));
    await tester.pumpAndSettle();
    expect(selected, 'لیتر');
    expect(tester.takeException(), isNull);
  });
}
