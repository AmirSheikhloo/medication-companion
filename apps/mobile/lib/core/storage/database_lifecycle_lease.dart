import 'package:flutter/services.dart';

/// A process/kernel-backed Android lease obtained BEFORE constructing Drift.
/// The native owner holds one shared file lock until the last issued session
/// token has been released, and rejects admission on pending restore markers.
/// Background engines without this channel must fail closed.
final class DatabaseLifecycleLease {
  static const MethodChannel _defaultChannel =
      MethodChannel('medication_companion/secure_backup');

  final MethodChannel _channel;
  final String _token;
  bool _released = false;

  DatabaseLifecycleLease._(this._channel, this._token);

  static Future<DatabaseLifecycleLease> acquire({MethodChannel? channel}) async {
    final bridge = channel ?? _defaultChannel;
    final token = await bridge.invokeMethod<String>('acquireDatabaseLease');
    if (token == null || token.isEmpty) {
      throw StateError('Native DB lease was denied; database must remain closed');
    }
    return DatabaseLifecycleLease._(bridge, token);
  }

  Future<void> release() async {
    if (_released) return;
    final released = await _channel.invokeMethod<bool>(
      'releaseDatabaseLease',
      {'token': _token},
    );
    if (released != true) {
      throw StateError('Native DB lease release was not acknowledged');
    }
    _released = true;
  }
}
