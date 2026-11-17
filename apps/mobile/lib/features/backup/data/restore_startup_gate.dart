import 'package:flutter/services.dart';

/// Guard every real SQLite connection behind the Android recovery admission
/// check. A missing plugin or uncertain recovery state is always a hard stop;
/// this phase intentionally does not perform any destructive replacement.
final class RestoreStartupGate {
  static const MethodChannel _channel =
      MethodChannel('medication_companion/secure_backup');

  static Future<bool> runBeforeAppStart() async {
    try {
      return await _channel.invokeMethod<bool>('bootstrapRecovery') == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
