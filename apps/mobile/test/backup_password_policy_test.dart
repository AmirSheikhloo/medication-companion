import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/features/backup/domain/backup_password_policy.dart';

void main() {
  group('M4-01B password validation', () {
    test('accepts 12 Persian scalar values without normalization', () {
      const raw = 'رمزپشتیبانقوی';
      expect(raw.runes.length, greaterThanOrEqualTo(12));
      expect(backupPasswordError(raw, raw), isNull);
    });

    test('counts emojis as scalar values and permits embedded spaces', () {
      const raw = '🌷🌷🌷🌷🌷🌷🌷🌷🌷🌷🌷🌷';
      expect(backupPasswordError(raw, raw), isNull);
      const spaced = 'عبارت امن با فاصله 🌷';
      expect(backupPasswordError(spaced, spaced), isNull);
    });

    test('rejects too short, all-whitespace, mismatch', () {
      expect(backupPasswordError('abc123', 'abc123'), isNotNull);
      expect(backupPasswordError('               ', '               '), isNotNull);
      expect(backupPasswordError('abcdefghijklm', 'abcdefghijkln'), isNotNull);
    });

    test('rejects isolated surrogates and does not trim comparison', () {
      const isolated = 'abcdefghijk\uD800';
      expect(backupPasswordError(isolated, isolated), isNotNull);
      expect(backupPasswordError('abcdefghijklm ', 'abcdefghijklm'), isNotNull);
    });
  });
}
