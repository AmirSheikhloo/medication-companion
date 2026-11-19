import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/features/backup/data/restore_startup_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('medication_companion/secure_backup');
  final messenger = TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('startup is admitted only on an explicit native true', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'bootstrapRecovery');
      return true;
    });
    expect(await RestoreStartupGate.runBeforeAppStart(), isTrue);
  });

  test('native refusal blocks all normal SQLite startup', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    expect(await RestoreStartupGate.runBeforeAppStart(), isFalse);
  });

  test('missing native channel cannot bypass recovery guard', () async {
    expect(await RestoreStartupGate.runBeforeAppStart(), isFalse);
  });

  test('platform exception also fails closed', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'RECOVERY_UNCERTAIN');
    });
    expect(await RestoreStartupGate.runBeforeAppStart(), isFalse);
  });
}
