import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:medication_companion/features/medications/presentation/medication_entry_sheet.dart';
import 'package:medication_companion/features/medications/data/medication_setup_repository.dart';

Future<void> next(WidgetTester tester) async {
  await tester.tap(find.text('مرحله بعد'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('base-unit categories filter choices and show canonical volume equivalents',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => FilledButton(
        onPressed: () => showMedicationEntrySheet(context, profileName: 'بیمار'),
        child: const Text('باز کردن فرم'),
      )))));
    await tester.tap(find.text('باز کردن فرم'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dose-unit-category-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('میلی‌لیتر (سی‌سی)'));
    await tester.pumpAndSettle();
    expect(find.text(MedicationUnits.displayLabels[MedicationUnits.teaSpoon]!), findsOneWidget);
    expect(find.text(MedicationUnits.displayLabels[MedicationUnits.tableSpoon]!), findsOneWidget);
    expect(find.text('عدد'), findsNothing);
    await tester.tap(find.text(MedicationUnits.displayLabels[MedicationUnits.teaSpoon]!));
    await tester.pumpAndSettle();
    expect(find.text(MedicationUnits.displayLabels[MedicationUnits.teaSpoon]!), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wizard preserves quantities across back navigation and declines unavailable notification permission',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    MedicationDraft? draft;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) => FilledButton(
        onPressed: () async {
          draft = await showMedicationEntrySheet(context,
            profileName: 'بیمار',
            requestReminderPermission: ({bool fullScreen = false}) async => false);
        },
        child: const Text('باز کردن فرم'),
      ))),
    ));
    await tester.tap(find.text('باز کردن فرم'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('medication-wizard-progress')), findsOneWidget);
    expect(find.text('سوابق مصرف'), findsNothing);
    await tester.enterText(find.byKey(const Key('medication-name-field')), 'استامینوفن 500');
    expect(find.text('واحد پایه دارو'), findsOneWidget);
    await next(tester); // schedule
    expect(find.text('واحد مصرف'), findsNothing);
    await tester.enterText(find.byKey(const Key('med-dose-1')), '2');
    await next(tester); // stock
    expect(find.text('حجمی / مایع'), findsNothing);
    await tester.enterText(find.byKey(const Key('med-stock-1')), '40');
    await tester.ensureVisible(find.text('محاسبه تعداد از روی ورق قرص'));
    await tester.tap(find.text('محاسبه تعداد از روی ورق قرص'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('calculator-strip-count')), '5');
    await tester.enterText(
      find.byKey(const Key('calculator-per-strip')), '10');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('اعمال 50 عدد'));
    await tester.tap(find.text('اعمال 50 عدد'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('med-stock-1')))
      .controller?.text, '50');

    await tester.tap(find.text('قبلی')); // schedule
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('med-dose-1')))
      .controller?.text, '2');
    await next(tester); // stock
    expect(tester.widget<TextField>(find.byKey(const Key('med-stock-1')))
      .controller?.text, '50');
    await next(tester); // low-stock threshold
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('medication-low-stock-threshold')), '20');
    await next(tester); // reminders
    await tester.tap(find.text('اعلان یادآوری'));
    await tester.pumpAndSettle();
    expect(tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).first.value,
      isFalse);
    expect(find.text('متن هشدار (اختیاری)'), findsNothing);
    await tester.tap(find.text('ثبت دارو'));
    await tester.pumpAndSettle();

    expect(draft, isNotNull);
    expect(draft!.name, 'استامینوفن 500');
    expect(draft!.packages.single.initialMilliunits, 50000);
    expect(draft!.slots.single.quantity?.milliunits, 2000);
    expect(draft!.lowStockThresholdMilliunits, 20000);
    expect(draft!.notificationsEnabled, isFalse);
    expect(draft!.fullScreenAlert, isFalse);
    expect(tester.takeException(), isNull);
  });
}
