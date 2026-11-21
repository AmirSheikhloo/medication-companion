import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/inventory/data/inventory_repository.dart';
import 'package:medication_companion/features/inventory/presentation/stock_management_sheet.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';

void main() {
  testWidgets('threshold save is confirmed and package ledger can be viewed',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final profiles = ProfileRepository(db);
    final medicationRepository = MedicationRepository(db);
    final inventory = InventoryRepository(db);

    final profile = await profiles.createGuestProfile(forSelf: true);
    final medId = await medicationRepository.addDailyMedication(
      profileId: profile.id,
      name: 'داروی نمونه',
      doseText: 'فقط آزمایشی',
      time: const TimeOfDayValue(8, 0),
    );
    await inventory.addPackage(
      profileId: profile.id,
      medicationId: medId,
      label: 'جعبه A',
      unit: 'عدد',
      initialMilliunits: 4000,
      selectForUse: true,
    );
    final medication =
        (await medicationRepository.medicationsFor(profile.id)).single;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => FilledButton(
          onPressed: () => showStockManagementSheet(
            context,
            repository: inventory,
            medication: medication,
            profileId: profile.id,
          ),
          child: const Text('باز کردن موجودی'),
        )),
      ),
    ));
    await tester.tap(find.text('باز کردن موجودی'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '3');
    await tester.ensureVisible(find.text('ذخیره حد هشدار'));
    await tester.tap(find.text('ذخیره حد هشدار'));
    await tester.pumpAndSettle();
    expect(find.text('حد هشدار با موفقیت ذخیره شد.'), findsWidgets);
    expect(find.textContaining('موجودی فعلی بالاتر از حد هشدار است.'),
        findsOneWidget);

    await tester.ensureVisible(find.text('تاریخچه موجودی'));
    await tester.tap(find.text('تاریخچه موجودی'));
    await tester.pumpAndSettle();
    expect(find.text('تاریخچه تغییرات این بسته'), findsOneWidget);
    expect(find.text('موجودی اولیه'), findsOneWidget);
    expect(find.text('+۴ عدد'), findsOneWidget);
    final history = await inventory.movementsForPackage(
      profileId: profile.id,
      medicationId: medId,
      packageId: (await inventory.summary(profile.id, medId)).selectedPackageId!,
    );
    expect(history, hasLength(1));
    expect(history.single.kind, 'initial');
    expect(tester.takeException(), isNull);
  });
}
