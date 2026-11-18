import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/core/storage/database_lifecycle_lease.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('m4_lease_test');
  final messenger = TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('holds a native session until explicit acknowledged close', () async {
    final seen = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      seen.add(call.method);
      if (call.method == 'acquireDatabaseLease') return 'nonempty-token';
      if (call.method == 'releaseDatabaseLease') {
        expect(call.arguments, {'token': 'nonempty-token'});
        return true;
      }
      throw MissingPluginException();
    });
    final lease = await DatabaseLifecycleLease.acquire(channel: channel);
    expect(seen, ['acquireDatabaseLease']);
    await lease.release();
    await lease.release();
    expect(seen, ['acquireDatabaseLease', 'releaseDatabaseLease']);
  });

  test('denied or blank native lease fails closed', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await expectLater(DatabaseLifecycleLease.acquire(channel: channel),
        throwsStateError);
    messenger.setMockMethodCallHandler(channel, (_) async => '');
    await expectLater(DatabaseLifecycleLease.acquire(channel: channel),
        throwsStateError);
  });

  test('missing channel cannot construct an unguarded session', () async {
    await expectLater(DatabaseLifecycleLease.acquire(channel: channel),
        throwsA(isA<MissingPluginException>()));
  });

  test('unacknowledged release is never treated as success', () async {
    var releaseAttempts = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'acquireDatabaseLease') return 'lease-b';
      releaseAttempts++;
      return releaseAttempts > 1;
    });
    final lease = await DatabaseLifecycleLease.acquire(channel: channel);
    await expectLater(lease.release(), throwsStateError);
    await lease.release();
    expect(releaseAttempts, 2);
  });

  test('native errors propagate before access to Drift is possible', () async {
    messenger.setMockMethodCallHandler(channel, (_) async =>
        throw PlatformException(code: 'RECOVERY_PENDING'));
    await expectLater(DatabaseLifecycleLease.acquire(channel: channel),
        throwsA(isA<PlatformException>()));
  });
}
