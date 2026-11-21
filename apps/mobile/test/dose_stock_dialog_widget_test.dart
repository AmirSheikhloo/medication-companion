import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/inventory/data/inventory_repository.dart';
import 'package:medication_companion/features/inventory/presentation/dose_stock_dialog.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';

void main() {
  testWidgets('typed Persian debit rejects overdraw and accepts fractions',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profile = await ProfileRepository(db).createGuestProfile(forSelf: true);
    final medId = await MedicationRepository(db).addDailyMedication(
      profileId: profile.id, name: 'داروی آزمایشی', doseText: 'تستی',
      time: const TimeOfDayValue(8, 0),
    );
    final inventory = InventoryRepository(db);
    await inventory.addPackage(
      profileId: profile.id, medicationId: medId, unit: 'عدد',
      initialMilliunits: 5000, selectForUse: true,
    );
    await inventory.setDoseDebitPreset(
      profileId: profile.id, medicationId: medId,
      unit: 'عدد', quantityMilliunits: 1000,
    );
    final summary = await inventory.summary(profile.id, medId);
    DoseStockChoice? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) => FilledButton(
        onPressed: () async {
          selected = await askDoseStockChoice(context,
              medicationName: 'داروی آزمایشی', stock: summary);
        },
        child: const Text('ثبت مصرف آزمایشی'),
      ))),
    ));
    await tester.tap(find.text('ثبت مصرف آزمایشی'));
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('dose-debit-quantity-input'));
    expect(tester.widget<TextField>(field).keyboardType,
        const TextInputType.numberWithOptions(decimal: true));
    expect(tester.widget<TextField>(field).controller?.text, '۱');
    await tester.enterText(field, '6');
    await tester.tap(find.text('ثبت و کسر موجودی'));
    await tester.pumpAndSettle();
    expect(find.textContaining('موجودی این بسته کافی نیست'), findsOneWidget);
    expect(selected, isNull);

    await tester.enterText(field, '٢٫٥');
    expect(tester.widget<TextField>(field).controller?.text, '۲٫۵');
    await tester.tap(find.text('ثبت و کسر موجودی'));
    await tester.pumpAndSettle();
    expect(selected?.quantityMilliunits, 2500);
    expect(tester.takeException(), isNull);
  });
}
