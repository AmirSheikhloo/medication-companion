import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/medications/data/medication_repository.dart';
import 'package:medication_companion/features/medications/presentation/medication_home.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';
import 'package:medication_companion/features/reminders/data/android_reminder_port.dart';
import 'package:medication_companion/features/reminders/data/reminder_coordinator.dart';
import 'package:medication_companion/features/reminders/domain/reminder_plan.dart';

class WidgetReminderPort implements ReminderNotificationPort {
  int tests = 0;
  int replacements = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<bool> requestFullScreenPermission() async => true;

  @override
  Future<bool> hasPermissions() async => true;

  @override
  Future<void> replaceManaged(List<ReminderJob> jobs) async {
    replacements++;
  }

  @override
  Future<void> scheduleDemo() async {
    tests++;
  }
}

void main() {
  testWidgets('More tab explicitly enables, tests and disables reminders',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final meds = MedicationRepository(database);
    final profiles = ProfileRepository(database);
    final port = WidgetReminderPort();
    final reminder = ReminderCoordinator(
      database: database,
      medications: meds,
      profiles: profiles,
      notifications: port,
    );
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MedicationHome(
          repository: meds,
          profileRepository: profiles,
          reminderCoordinator: reminder,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('ورود به عنوان مهمان'));
    await tester.tap(find.text('ورود به عنوان مهمان'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بیشتر'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('یادآوری‌ها'));
    await tester.pumpAndSettle();

    expect(await reminder.isEnabled(), isFalse);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(await reminder.isEnabled(), isTrue);
    expect(find.text('تست اعلان — 5 ثانیه دیگر'), findsOneWidget);
    await tester.ensureVisible(find.text('تست اعلان — 5 ثانیه دیگر'));
    await tester.tap(find.text('تست اعلان — 5 ثانیه دیگر'));
    await tester.pumpAndSettle();
    expect(port.tests, 1);

    await tester.ensureVisible(find.text('خاموش کردن یادآورها'));
    await tester.tap(find.text('خاموش کردن یادآورها'));
    await tester.pumpAndSettle();
    expect(await reminder.isEnabled(), isFalse);
    expect(find.text('مجوز اعلان‌ها: غیرفعال'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
