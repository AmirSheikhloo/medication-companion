import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/m0/test_timings.dart';

void main() {
  test('M0 notification test uses a five-second delay', () {
    expect(m0NormalNotificationDelay, const Duration(seconds: 5));
  });

  test('M0 full-screen test uses a ten-second delay', () {
    expect(m0FullScreenNotificationDelay, const Duration(seconds: 10));
  });
}
